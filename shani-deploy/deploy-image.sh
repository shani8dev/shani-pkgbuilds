#!/bin/bash
# deploy-image.sh – Safely update the candidate system subvolume (@blue or @green)
#
# This script:
#   1. Reads the current build version and profile from /etc/shani-version and /etc/shani-profile.
#   2. Constructs IMAGE_NAME as "${OS_NAME}-${VERSION}-${PROFILE}.zst" and checks against latest.txt
#      (stored in the shared @data subvolume, mounted at /data).
#   3. If a new image is available, downloads and verifies it.
#   4. Mounts the Btrfs top-level (using subvolid=5) to access the shared @data subvolume,
#      determines the active slot, and calculates the candidate slot.
#   5. Backs up the candidate subvolume (via snapshot) before deleting it.
#   6. Receives the update image (containing shanios_base) into a temporary subvolume and
#      snapshots it as the new candidate.
#   7. Calls gen-efi.sh (via arch-chroot) to regenerate the Secure Boot UKI.
#   8. Updates the slot marker files only after the new candidate is successfully prepared.
#
# (Run from the installed system.)
 
set -Eeuo pipefail
IFS=$'\n\t'
trap 'echo "$(date "+%Y-%m-%d %H:%M:%S") [DEPLOY][ERROR] Error at ${BASH_SOURCE[0]} line ${LINENO}: ${BASH_COMMAND}" >&2; exit 1' ERR

log() {
    echo "$(date "+%Y-%m-%d %H:%M:%S") [DEPLOY] $*"
}

##############################
# Configuration
##############################
OS_NAME="shanios"

# Read installed build version and profile.
VERSION=$(cat /etc/shani-version)
PROFILE=$(cat /etc/shani-profile)
IMAGE_NAME="${OS_NAME}-${VERSION}-${PROFILE}.zst"

# Shared @data subvolume (mounted at /data) holds downloads and marker files.
DOWNLOAD_DIR="/data/downloads"
ZSYNC_CACHE_DIR="${DOWNLOAD_DIR}/zsync_cache"

# Temporary mount point for Btrfs top-level.
MOUNT_DIR="/mnt"
ROOTLABEL="shani_root"
ROOT_DEV="/dev/disk/by-label/${ROOTLABEL}"

LATEST_URL="https://example.com/path/to/latest.txt"
IMAGE_BASE_URL="https://example.com/path/to"
IMAGE_URL="${IMAGE_BASE_URL}/${IMAGE_NAME}.zsync"

MIN_FREE_SPACE_MB=10240

# Marker files (in @data)
CURRENT_SLOT_FILE="/data/current-slot"
PREVIOUS_SLOT_FILE="/data/previous-slot"

# Path to the UKI regeneration script.
GENEFI_SCRIPT="/usr/local/bin/gen-efi.sh"

##############################
# Step 1: Pre-update check
##############################
log "Checking disk space on /data..."
free_space_mb=$(df --output=avail "/data" | tail -n1)
free_space_mb=$(( free_space_mb / 1024 ))
if [ "$free_space_mb" -lt "$MIN_FREE_SPACE_MB" ]; then
    log "Not enough disk space: ${free_space_mb} MB available; ${MIN_FREE_SPACE_MB} MB required."
    exit 1
fi
log "Disk space OK."

log "Preparing download environment..."
mkdir -p "$ZSYNC_CACHE_DIR"

LATEST_FILE="$DOWNLOAD_DIR/latest.txt"
if [ -f "$LATEST_FILE" ]; then
    LATEST_IMAGE=$(cat "$LATEST_FILE")
else
    LATEST_IMAGE=""
fi

if [ "$LATEST_IMAGE" = "$IMAGE_NAME" ]; then
    log "Latest image ($IMAGE_NAME) already deployed. Skipping update."
    exit 0
fi
echo "$IMAGE_NAME" > "$LATEST_FILE"

##############################
# Step 2: Download & verify image
##############################
log "Downloading update image info..."
cd "$DOWNLOAD_DIR" || exit 1
old_image=""
[ -f "$DOWNLOAD_DIR/old.txt" ] && old_image=$(cat "$DOWNLOAD_DIR/old.txt")
if [[ -n "$old_image" && -f "$DOWNLOAD_DIR/$old_image" ]]; then
    zsync --cache-dir="$ZSYNC_CACHE_DIR" -i "$DOWNLOAD_DIR/$old_image" "$IMAGE_URL"
else
    zsync --cache-dir="$ZSYNC_CACHE_DIR" "$IMAGE_URL"
fi
wget -q "${IMAGE_URL}.sha256" -O "${IMAGE_NAME}.sha256"
wget -q "${IMAGE_URL}.asc" -O "${IMAGE_NAME}.asc"

log "Verifying image integrity..."
sha256sum -c "${IMAGE_NAME}.sha256" || { log "SHA256 verification failed"; exit 1; }
gpg --verify "${IMAGE_NAME}.asc" "$IMAGE_NAME" || { log "PGP verification failed"; exit 1; }
log "Image verification successful."

##############################
# Step 3: Mount Btrfs top-level & determine slot
##############################
log "Mounting Btrfs top-level..."
mkdir -p "$MOUNT_DIR"
mount -o subvolid=5 "$ROOT_DEV" "$MOUNT_DIR" || { log "Mount failed"; exit 1; }

if [ -f "$MOUNT_DIR/@data/current-slot" ]; then
    ACTIVE_SLOT=$(cat "$MOUNT_DIR/@data/current-slot")
else
    ACTIVE_SLOT="blue"
    echo "$ACTIVE_SLOT" > "$MOUNT_DIR/@data/current-slot"
fi
if [ "$ACTIVE_SLOT" = "blue" ]; then
    CANDIDATE_SLOT="green"
else
    CANDIDATE_SLOT="blue"
fi
log "Active slot: $ACTIVE_SLOT; Candidate slot: $CANDIDATE_SLOT."

##############################
# Step 4: Update candidate subvolume
##############################
CANDIDATE_PATH="$MOUNT_DIR/@${CANDIDATE_SLOT}"
# Backup candidate subvolume if it exists.
if btrfs subvolume list "$MOUNT_DIR" | grep -q "path @${CANDIDATE_SLOT}\$"; then
    BACKUP_NAME="${CANDIDATE_SLOT}_backup_$(date +%Y%m%d%H%M)"
    btrfs subvolume snapshot "$CANDIDATE_PATH" "$MOUNT_DIR/@${BACKUP_NAME}" \
        || { log "Candidate backup snapshot failed"; exit 1; }
    log "Candidate backup created: $BACKUP_NAME"
    btrfs property set -f -ts "$CANDIDATE_PATH" ro false || { log "Failed to clear candidate RO property"; exit 1; }
    btrfs subvolume delete "$CANDIDATE_PATH" || { log "Failed to delete candidate slot"; exit 1; }
fi

# Create temporary subvolume for update image.
TEMP_SUBVOL="$MOUNT_DIR/temp_update"
btrfs subvolume create "$TEMP_SUBVOL" || { log "Failed to create temporary subvolume"; exit 1; }

log "Receiving update image into temporary subvolume..."
zstd -d --long=31 -T0 "$DOWNLOAD_DIR/$IMAGE_NAME" -c | btrfs receive "$TEMP_SUBVOL" \
    || { log "Image extraction failed"; exit 1; }

log "Creating candidate slot snapshot..."
btrfs subvolume snapshot "$TEMP_SUBVOL/shanios_base" "$CANDIDATE_PATH" \
    || { log "Snapshot creation for candidate slot failed"; exit 1; }
btrfs property set -f -ts "$CANDIDATE_PATH" ro true || { log "Failed to set candidate read-only"; exit 1; }
btrfs subvolume delete "$TEMP_SUBVOL" || { log "Failed to delete temporary subvolume"; exit 1; }
umount -R "$MOUNT_DIR" || { log "Unmount failed"; exit 1; }
log "Candidate slot update complete."

##############################
# Step 5: Regenerate Secure Boot UKI
##############################
log "Updating Secure Boot configuration..."
mkdir -p "$MOUNT_DIR"
mount -o "subvol=@${CANDIDATE_SLOT}" "$ROOT_DEV" "$MOUNT_DIR" \
    || { log "Mounting candidate slot failed"; exit 1; }
mount --mkdir -o ro LABEL=shani_boot "$MOUNT_DIR/boot/efi" \
    || { log "Mounting EFI partition failed"; exit 1; }
if [[ -x "$GENEFI_SCRIPT" ]]; then
    arch-chroot "$MOUNT_DIR" "$GENEFI_SCRIPT" configure "$CANDIDATE_SLOT" \
        || { log "UKI generation failed"; exit 1; }
fi
umount -R "$MOUNT_DIR"

##############################
# Step 6: Switch active slot marker
##############################
log "Remounting top-level to update slot markers..."
mkdir -p "$MOUNT_DIR"
mount -o subvolid=5 "$ROOT_DEV" "$MOUNT_DIR" || { log "Mount failed"; exit 1; }
log "Switching active slot..."
echo "$ACTIVE_SLOT" > "$MOUNT_DIR/@data/previous-slot"
echo "$CANDIDATE_SLOT" > "$MOUNT_DIR/@data/current-slot"
umount -R "$MOUNT_DIR"

log "Deployment complete. Next boot will use slot: $CANDIDATE_SLOT"

