#!/bin/bash
# deploy-image.sh – Combined Deployment and Rollback for Blue/Green Btrfs Systems
# with Update Channel Selection, Boot Failure Detection, Overlay Mount for /etc,
# UKI Generation, and Cleanup of Old Backups and Downloads.
#
# Deployment (default):
#   - Validates the booted subvolume vs. expected slot (/data/current-slot).
#   - Checks for the boot-success marker (/data/boot-ok). If missing (or /data/boot_failure exists),
#     triggers rollback.
#   - Uses update channel ("stable" or "latest") to download and verify a new image.
#   - Creates a backup of the candidate slot (if one exists) using Btrfs snapshots.
#   - Deploys the update into the candidate slot.
#   - Mounts the candidate subvolume with an overlay for /etc (upper layer in /data/overlay/etc),
#     then calls gen-efi.sh via arch-chroot to generate a new UKI.
#   - Updates /data/current-slot and /data/previous-slot.
#   - Cleans up old backups (keeping at least one per slot) and downloaded images (keeping at least one).
#
# Rollback (when run with "rollback" or boot failure detected):
#   - Mounts the Btrfs top-level, identifies the failing slot (blue/green) by reading /data/current-slot,
#     and restores it from its latest backup.
#   - Updates slot markers and reboots.
#
# Usage:
#   deploy-image.sh              # Deploy update (default: latest channel)
#   deploy-image.sh latest       # Deploy update from latest channel
#   deploy-image.sh stable       # Deploy update from stable channel
#   deploy-image.sh rollback     # Force a rollback
#
# (Run as root.)

set -Eeuo pipefail
IFS=$'\n\t'

# --- Configuration ---
OS_NAME="shanios"
LOCAL_VERSION=$(cat /etc/shani-version)
LOCAL_PROFILE=$(cat /etc/shani-profile)
DOWNLOAD_DIR="/data/downloads"
ZSYNC_CACHE_DIR="${DOWNLOAD_DIR}/zsync_cache"
MOUNT_DIR="/mnt"
ROOTLABEL="shani_root"
ROOT_DEV="/dev/disk/by-label/${ROOTLABEL}"
MIN_FREE_SPACE_MB=10240
GENEFI_SCRIPT="/usr/local/bin/gen-efi.sh"  # Ensure this script is present

declare -g BACKUP_NAME=""
declare -g CURRENT_SLOT=""
declare -g CANDIDATE_SLOT=""
declare -g REMOTE_VERSION=""
declare -g REMOTE_PROFILE=""
declare -g IMAGE_NAME=""
declare -g UPDATE_CHANNEL="latest"  # Default channel

# --- Parameter Parsing ---
if [[ "${1:-}" == "rollback" ]]; then
    rollback_mode="yes"
else
    rollback_mode="no"
    if [[ "${1:-}" == "stable" ]]; then
        UPDATE_CHANNEL="stable"
    elif [[ "${1:-}" == "latest" ]]; then
        UPDATE_CHANNEL="latest"
    fi
fi

# --- Common Functions ---
log() {
    echo "$(date "+%Y-%m-%d %H:%M:%S") [DEPLOY] $*"
}

die() {
    echo "$(date "+%Y-%m-%d %H:%M:%S") [FATAL] $*" >&2
    exit 1
}

safe_mount() {
    local src=$1 tgt=$2 opts=$3
    if ! findmnt -M "$tgt" >/dev/null; then
        mount -o "$opts" "$src" "$tgt" || die "Mount failed: $src → $tgt"
        log "Mounted $tgt ($opts)"
    fi
}

safe_umount() {
    local tgt=$1
    if findmnt -M "$tgt" >/dev/null; then
        umount -R "$tgt" && log "Unmounted $tgt"
    fi
}

get_booted_subvol() {
    local rootflags subvol
    rootflags=$(grep -o 'rootflags=[^ ]*' /proc/cmdline | cut -d= -f2-)
    subvol=$(awk -F'subvol=' '{print $2}' <<<"$rootflags" | cut -d, -f1)
    subvol="${subvol#@}"
    [[ -z "$subvol" ]] && subvol=$(btrfs subvolume get-default / 2>/dev/null | awk '{gsub(/@/,""); print $NF}')
    echo "${subvol:-blue}"
}

cleanup_old_backups() {
    # For each slot, keep at least one backup and delete older ones.
    for slot in blue green; do
        local backup_list count retention to_remove backup
        backup_list=$(btrfs subvolume list "$MOUNT_DIR" | awk -v slot="$slot" '$0 ~ slot"_backup" {print $NF}' | sort)
        count=$(echo "$backup_list" | wc -l)
        retention=1
        if [ "$count" -gt "$retention" ]; then
            to_remove=$(echo "$backup_list" | head -n $(($count - $retention)))
            for backup in $to_remove; do
                btrfs subvolume delete "$MOUNT_DIR/@${backup}" && log "Deleted old backup: @${backup}"
            done
        fi
    done
}

cleanup_downloads() {
    # Remove downloaded image files older than 7 days, but keep at least one.
    local count
    count=$(find "$DOWNLOAD_DIR" -maxdepth 1 -type f -name "shanios-*.zst" | wc -l)
    if [ "$count" -gt 1 ]; then
        find "$DOWNLOAD_DIR" -maxdepth 1 -type f -name "shanios-*.zst" -mtime +7 -exec rm -f {} \;
        log "Cleaned up downloaded images older than 7 days."
    else
        log "Only one downloaded image remains; skipping downloads cleanup."
    fi
}

# --- Deployment Error Rollback ---
restore_candidate() {
    log "Error encountered. Initiating candidate rollback..."
    (
        set +e
        safe_mount "$ROOT_DEV" "$MOUNT_DIR" "subvolid=5"
        if [[ -n "$BACKUP_NAME" ]] && btrfs subvolume show "$MOUNT_DIR/@${BACKUP_NAME}" &>/dev/null; then
            log "Restoring candidate slot @${CANDIDATE_SLOT} from backup @${BACKUP_NAME}"
            btrfs property set -ts "$MOUNT_DIR/@${CANDIDATE_SLOT}" ro false &>/dev/null || true
            btrfs subvolume delete "$MOUNT_DIR/@${CANDIDATE_SLOT}" &>/dev/null || true
            btrfs subvolume snapshot "$MOUNT_DIR/@${BACKUP_NAME}" "$MOUNT_DIR/@${CANDIDATE_SLOT}"
            btrfs property set -ts "$MOUNT_DIR/@${CANDIDATE_SLOT}" ro true
        fi
        if btrfs subvolume list "$MOUNT_DIR" | grep -q "@temp_update"; then
            btrfs subvolume delete "$MOUNT_DIR/@temp_update" &>/dev/null
        fi
        safe_umount "$MOUNT_DIR"
    ) || log "Candidate rollback incomplete – manual intervention may be required"
    exit 1
}
trap 'restore_candidate' ERR

# --- Rollback Functionality ---
rollback_system() {
    log "Initiating full system rollback..."
    mkdir -p "$MOUNT_DIR"
    safe_mount "$ROOT_DEV" "$MOUNT_DIR" "subvolid=5"
    if [ -f "$MOUNT_DIR/@data/current-slot" ]; then
        FAILED_SLOT=$(cat "$MOUNT_DIR/@data/current-slot")
    else
        die "Current slot marker not found. Cannot rollback."
    fi
    if [ -f "$MOUNT_DIR/@data/previous-slot" ]; then
        PREVIOUS_SLOT=$(cat "$MOUNT_DIR/@data/previous-slot")
    else
        if [ "$FAILED_SLOT" = "blue" ]; then
            PREVIOUS_SLOT="green"
        else
            PREVIOUS_SLOT="blue"
        fi
    fi
    log "Detected failing slot: ${FAILED_SLOT}. Previous working slot: ${PREVIOUS_SLOT}."
    BACKUP_NAME=$(btrfs subvolume list "$MOUNT_DIR" | awk -v slot="${FAILED_SLOT}" '$0 ~ slot"_backup" {print $NF}' | sort | tail -n 1)
    if [ -z "$BACKUP_NAME" ]; then
        die "No backup found for slot ${FAILED_SLOT}. Cannot rollback."
    fi
    log "Restoring slot ${FAILED_SLOT} from backup ${BACKUP_NAME}..."
    FAILED_PATH="$MOUNT_DIR/@${FAILED_SLOT}"
    BACKUP_PATH="$MOUNT_DIR/${BACKUP_NAME}"
    btrfs subvolume delete "$FAILED_PATH" || die "Failed to delete failed slot"
    btrfs subvolume snapshot "$BACKUP_PATH" "$FAILED_PATH" || die "Failed to restore from backup"
    log "Switching active slot to previous working slot: ${PREVIOUS_SLOT}..."
    echo "$PREVIOUS_SLOT" > "$MOUNT_DIR/@data/current-slot"
    bootctl set-default "shanios-${PREVIOUS_SLOT}.conf" || log "bootctl update failed (please verify manually)"
    safe_umount "$MOUNT_DIR"
    log "Rollback complete. Rebooting..."
    reboot
}

# --- Boot Failure Check ---
# If the boot-success marker (/data/boot-ok) is missing, assume boot failure.
if [ ! -f /data/boot-ok ]; then
    log "Boot failure detected: /data/boot-ok marker missing. Initiating rollback..."
    rollback_system
fi

# --- Main Execution (Deployment) ---
if [[ "${rollback_mode}" == "yes" ]]; then
    rollback_system
    exit 0
fi

log "Starting deployment procedure..."
log "Deploying update from channel: ${UPDATE_CHANNEL}"
CHANNEL_URL="https://sourceforge.net/projects/shanios/files/${LOCAL_PROFILE}/${UPDATE_CHANNEL}.txt"

# Phase 1: Boot Validation & Candidate Selection
CURRENT_SLOT=$(cat /data/current-slot 2>/dev/null || echo "blue")
BOOTED_SLOT=$(get_booted_subvol)
if [[ "$BOOTED_SLOT" != "$CURRENT_SLOT" ]]; then
    die "System booted @${BOOTED_SLOT} but expected slot is @${CURRENT_SLOT}. Reboot into the correct slot first."
fi
if [[ "$CURRENT_SLOT" == "blue" ]]; then
    CANDIDATE_SLOT="green"
else
    CANDIDATE_SLOT="blue"
fi
log "System booted from @${CURRENT_SLOT}. Preparing deployment to candidate slot @${CANDIDATE_SLOT}."

# Phase 2: Pre-update Checks
log "Checking available disk space on /data..."
free_space_mb=$(df --output=avail "/data" | tail -n1)
free_space_mb=$(( free_space_mb / 1024 ))
if [ "$free_space_mb" -lt "$MIN_FREE_SPACE_MB" ]; then
    die "Not enough disk space: ${free_space_mb} MB available; ${MIN_FREE_SPACE_MB} MB required."
fi
log "Disk space is sufficient."
mkdir -p "$DOWNLOAD_DIR" "$ZSYNC_CACHE_DIR"

# Phase 3: Update Check & Download
log "Fetching ${UPDATE_CHANNEL} image info from ${CHANNEL_URL}..."
IMAGE_NAME=$(wget -qO- "$CHANNEL_URL" | tr -d '[:space:]')
if [[ "$IMAGE_NAME" =~ ^shanios-([0-9]+)-([a-zA-Z]+)\.zst$ ]]; then
    REMOTE_VERSION="${BASH_REMATCH[1]}"
    REMOTE_PROFILE="${BASH_REMATCH[2]}"
    log "New image found: $IMAGE_NAME (version: $REMOTE_VERSION, profile: $REMOTE_PROFILE)"
else
    die "Unexpected format in ${UPDATE_CHANNEL}.txt: $IMAGE_NAME"
fi
if [[ "$LOCAL_VERSION" == "$REMOTE_VERSION" && "$LOCAL_PROFILE" == "$REMOTE_PROFILE" ]]; then
    log "System is already up-to-date (v${REMOTE_VERSION})."
    exit 0
fi
IMAGE_BASE_URL="https://sourceforge.net/projects/shanios/files/${REMOTE_PROFILE}/version"
IMAGE_URL="${IMAGE_BASE_URL}/${IMAGE_NAME}.zsync"
echo "$IMAGE_NAME" > "$DOWNLOAD_DIR/${UPDATE_CHANNEL}.txt"
log "Downloading update image..."
cd "$DOWNLOAD_DIR" || die "Failed to access download directory"
old_image=""
[ -f "old.txt" ] && old_image=$(cat "old.txt")
if [[ -n "$old_image" && -f "$old_image" ]]; then
    zsync --cache-dir="$ZSYNC_CACHE_DIR" -i "$old_image" "$IMAGE_URL" || die "Zsync download failed"
else
    zsync --cache-dir="$ZSYNC_CACHE_DIR" "$IMAGE_URL" || die "Zsync download failed"
fi
wget -q "${IMAGE_URL}.sha256" -O "${IMAGE_NAME}.sha256" || die "Failed to download SHA256 file"
wget -q "${IMAGE_URL}.asc" -O "${IMAGE_NAME}.asc" || die "Failed to download PGP signature file"
log "Verifying image integrity..."
sha256sum -c "${IMAGE_NAME}.sha256" || die "SHA256 checksum verification failed"
gpg --verify "${IMAGE_NAME}.asc" "$IMAGE_NAME" || die "PGP signature verification failed"
log "Image verified successfully."

# Phase 4: Btrfs Deployment
log "Mounting Btrfs top-level..."
mkdir -p "$MOUNT_DIR"
safe_mount "$ROOT_DEV" "$MOUNT_DIR" "subvolid=5"
if mountpoint -q "$MOUNT_DIR/@${CANDIDATE_SLOT}"; then
    safe_umount "$MOUNT_DIR"
    die "Candidate slot @${CANDIDATE_SLOT} is mounted – aborting deployment."
fi
if btrfs subvolume list "$MOUNT_DIR" | grep -q "path @${CANDIDATE_SLOT}\$"; then
    BACKUP_NAME="${CANDIDATE_SLOT}_backup_$(date +%Y%m%d%H%M)"
    log "Creating backup of candidate slot @${CANDIDATE_SLOT} as @${BACKUP_NAME}"
    btrfs subvolume snapshot "$MOUNT_DIR/@${CANDIDATE_SLOT}" "$MOUNT_DIR/@${BACKUP_NAME}" || die "Candidate backup snapshot failed"
    btrfs property set -f -ts "$MOUNT_DIR/@${CANDIDATE_SLOT}" ro false || die "Failed to clear read-only property on candidate slot"
    btrfs subvolume delete "$MOUNT_DIR/@${CANDIDATE_SLOT}" || die "Failed to delete candidate slot"
fi
TEMP_SUBVOL="$MOUNT_DIR/temp_update"
btrfs subvolume create "$TEMP_SUBVOL" || die "Failed to create temporary subvolume"
log "Receiving update image into temporary subvolume..."
zstd -d --long=31 -T0 "$DOWNLOAD_DIR/$IMAGE_NAME" -c | btrfs receive "$TEMP_SUBVOL" || die "Image extraction failed"
log "Creating candidate snapshot from update image..."
btrfs subvolume snapshot "$TEMP_SUBVOL/shanios_base" "$MOUNT_DIR/@${CANDIDATE_SLOT}" || die "Snapshot creation for candidate slot failed"
btrfs property set -f -ts "$MOUNT_DIR/@${CANDIDATE_SLOT}" ro true || die "Failed to set candidate slot to read-only"
btrfs subvolume delete "$TEMP_SUBVOL" || die "Failed to delete temporary subvolume"
safe_umount "$MOUNT_DIR"
log "Candidate slot update complete."

# Phase 5: UKI Generation with Overlay Support
log "Mounting candidate subvolume for UKI update..."
mkdir -p "$MOUNT_DIR"
safe_mount "$ROOT_DEV" "$MOUNT_DIR" "subvol=@${CANDIDATE_SLOT}"
safe_mount "LABEL=shani_boot" "$MOUNT_DIR/boot/efi" "ro"
mount --bind /data "$MOUNT_DIR/data" || die "Data bind mount failed"
log "Setting up overlay for /etc..."
mkdir -p "$MOUNT_DIR/data/overlay/etc/upper" "$MOUNT_DIR/data/overlay/etc/work"
mount -t overlay overlay -o "lowerdir=$MOUNT_DIR/etc,upperdir=$MOUNT_DIR/data/overlay/etc/upper,workdir=$MOUNT_DIR/data/overlay/etc/work" "$MOUNT_DIR/etc" || die "Overlay mount failed"
log "Regenerating Secure Boot UKI..."
arch-chroot "$MOUNT_DIR" "$GENEFI_SCRIPT" configure "$CANDIDATE_SLOT" || { 
    safe_umount "$MOUNT_DIR/etc"; 
    safe_umount "$MOUNT_DIR/data"; 
    safe_umount "$MOUNT_DIR/boot/efi"; 
    safe_umount "$MOUNT_DIR"; 
    die "UKI generation failed"; 
}
safe_umount "$MOUNT_DIR/etc"
safe_umount "$MOUNT_DIR/data"
safe_umount "$MOUNT_DIR/boot/efi"
safe_umount "$MOUNT_DIR"

# Phase 6: Finalization & Cleanup
log "Updating slot markers..."
echo "$CURRENT_SLOT" > "/data/previous-slot"
echo "$CANDIDATE_SLOT" > "/data/current-slot"
safe_mount "$ROOT_DEV" "$MOUNT_DIR" "subvolid=5"
if [[ -n "$BACKUP_NAME" ]]; then
    btrfs subvolume delete "$MOUNT_DIR/@${BACKUP_NAME}" &>/dev/null && log "Deleted backup @${BACKUP_NAME}"
fi
cleanup_old_backups
safe_umount "$MOUNT_DIR"
echo "$IMAGE_NAME" > "$DOWNLOAD_DIR/old.txt"
cleanup_downloads
log "Deployment successful! Next boot will use @${CANDIDATE_SLOT} (version: ${REMOTE_VERSION})"

