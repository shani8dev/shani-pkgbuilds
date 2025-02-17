#!/bin/bash
# deploy-image.sh – Update the candidate slot (blue–green deployment).
# Determines the active slot from /deployment/current-slot and updates the alternate (candidate) slot.
# Backs up the candidate slot before updating, applies the update transactionally using a temporary staging subvolume,
# and regenerates UKI entries so that systemd-boot will boot the candidate on next reboot.
# Updates /deployment/current-slot to mark the candidate as active.
# Usage: ./deploy-image.sh
set -Eeuo pipefail
IFS=$'\n\t'
trap 'echo "[ERROR] Error at ${BASH_SOURCE[0]} line ${LINENO}: ${BASH_COMMAND}" >&2; exit 1' ERR

### Configuration
OS_NAME="shanios"
BUILD_VERSION="$(date +%Y%m%d)"
OUTPUT_DIR="./cache/output"
DEPLOYMENT_DIR="/deployment"   # Contains both data and system subvolumes.
LATEST_URL="https://example.com/path/to/latest.txt"
IMAGE_BASE_URL="https://example.com/path/to"
PROFILE="default"
IMAGE_NAME="${OS_NAME}-${BUILD_VERSION}-${PROFILE}.zst"
IMAGE_URL="${IMAGE_BASE_URL}/${IMAGE_NAME}.zsync"
DOWNLOAD_DIR="${DEPLOYMENT_DIR}/downloads"
ZSYNC_CACHE_DIR="${DOWNLOAD_DIR}/zsync_cache"
MOUNT_DIR="/mnt"
GENEFI_SCRIPT="/usr/local/bin/gen-efi.sh"

MIN_FREE_SPACE_MB=10240
MIN_METADATA_FREE_MB=512
LATEST_FILE="${DOWNLOAD_DIR}/latest.txt"
OLD_LATEST_FILE="${DOWNLOAD_DIR}/old.txt"
CURRENT_SLOT_FILE="${DEPLOYMENT_DIR}/current-slot"  # Contains "blue" or "green"
PREVIOUS_SLOT_FILE="${DEPLOYMENT_DIR}/previous-slot"


echo "[DEPLOY] Checking disk space on ${DEPLOYMENT_DIR}..."
free_space_mb=$(df --output=avail "$DEPLOYMENT_DIR" | tail -n1)
free_space_mb=$(( free_space_mb / 1024 ))
[ "$free_space_mb" -lt "$MIN_FREE_SPACE_MB" ] && { echo "[DEPLOY] Not enough disk space"; exit 1; }
echo "[DEPLOY] Disk space OK."

echo "[DEPLOY] Preparing download environment..."
if ! btrfs subvolume list "$DEPLOYMENT_DIR" | grep -q "downloads\$"; then
  btrfs subvolume create "$DOWNLOAD_DIR" || { echo "[DEPLOY] Failed to create downloads subvolume"; exit 1; }
fi
mkdir -p "$ZSYNC_CACHE_DIR"

echo "[DEPLOY] Downloading latest image info..."
[ -f "$LATEST_FILE" ] && mv "$LATEST_FILE" "$OLD_LATEST_FILE"
wget -q "$LATEST_URL" -O "$LATEST_FILE" || { [ -f "$OLD_LATEST_FILE" ] && mv "$OLD_LATEST_FILE" "$LATEST_FILE"; }
cd "$DOWNLOAD_DIR" || exit 1
old_image=""
[ -f "$OLD_LATEST_FILE" ] && old_image=$(cat "$OLD_LATEST_FILE")
if [[ -n "$old_image" && -f "$DOWNLOAD_DIR/$old_image" ]]; then
  zsync --cache-dir="$ZSYNC_CACHE_DIR" -i "$DOWNLOAD_DIR/$old_image" "$IMAGE_URL"
else
  zsync --cache-dir="$ZSYNC_CACHE_DIR" "$IMAGE_URL"
fi
echo "$IMAGE_NAME" > "$LATEST_FILE"
wget -q "${IMAGE_URL}.sha256" -O "${IMAGE_NAME}.sha256"
wget -q "${IMAGE_URL}.asc" -O "${IMAGE_NAME}.asc"

echo "[DEPLOY] Verifying image integrity..."
sha256sum -c "${IMAGE_NAME}.sha256" || { echo "[DEPLOY] SHA256 verification failed"; exit 1; }
gpg --verify "${IMAGE_NAME}.asc" "$IMAGE_NAME" || { echo "[DEPLOY] PGP verification failed"; exit 1; }
echo "[DEPLOY] Image verification successful."

NEW_VERSION=$(echo "$IMAGE_NAME" | cut -d '-' -f2)
if [ -f "$CURRENT_SLOT_FILE" ]; then
    ACTIVE_SLOT=$(cat "$CURRENT_SLOT_FILE")
else
    ACTIVE_SLOT="blue"
    echo "$ACTIVE_SLOT" > "$CURRENT_SLOT_FILE"
fi
if [ "$ACTIVE_SLOT" = "blue" ]; then
    CANDIDATE_SLOT="green"
else
    CANDIDATE_SLOT="blue"
fi
echo "[DEPLOY] Active slot: ${ACTIVE_SLOT}; Candidate slot: ${CANDIDATE_SLOT}"

CURRENT_VERSION=$(cat "${DEPLOYMENT_DIR}/system/${ACTIVE_SLOT}/etc/shani-version" 2>/dev/null || echo "none")
if [ "$NEW_VERSION" = "$CURRENT_VERSION" ]; then
  echo "[DEPLOY] Deployed version ($CURRENT_VERSION) matches new image. Skipping update."
  exit 0
fi

# Mount deployment top-level.
mkdir -p "$MOUNT_DIR"
mount -o subvolid=5 "$DEPLOYMENT_DIR" "$MOUNT_DIR" || { echo "[DEPLOY] Mounting failed"; exit 1; }

# Backup the candidate slot.
if btrfs subvolume list "$MOUNT_DIR" | grep -q "system/${CANDIDATE_SLOT}\$"; then
  CANDIDATE_BACKUP="${CANDIDATE_SLOT}_backup_$(date +%Y%m%d%H%M)"
  btrfs subvolume snapshot "$MOUNT_DIR/system/${CANDIDATE_SLOT}" "$MOUNT_DIR/system/$CANDIDATE_BACKUP" || { echo "[DEPLOY] Candidate backup snapshot failed"; exit 1; }
  echo "[DEPLOY] Created candidate backup: $CANDIDATE_BACKUP"
fi

# Update candidate slot.
btrfs property set -f -ts "$MOUNT_DIR/system/$CANDIDATE_SLOT" ro false || { echo "[DEPLOY] Failed to clear candidate read-only property"; exit 1; }
TEMP_SUBVOL="temp_update"
btrfs subvolume create "$MOUNT_DIR/$TEMP_SUBVOL" || { echo "[DEPLOY] Temporary subvolume creation failed"; exit 1; }
if [ -n "$CANDIDATE_BACKUP" ]; then
  echo "[DEPLOY] Performing incremental update on candidate slot..."
  btrfs send -p "$MOUNT_DIR/system/$CANDIDATE_BACKUP" "$MOUNT_DIR/$TEMP_SUBVOL" | btrfs receive "$MOUNT_DIR/system/$CANDIDATE_SLOT" || {
    echo "[DEPLOY] Incremental update failed; rolling back candidate..."
    btrfs subvolume delete "$MOUNT_DIR/system/$CANDIDATE_SLOT"
    btrfs subvolume snapshot "$MOUNT_DIR/system/$CANDIDATE_BACKUP" "$MOUNT_DIR/system/$CANDIDATE_SLOT"
    exit 1
  }
else
  echo "[DEPLOY] No candidate backup found. Performing full update on candidate slot..."
  zstd -d --long -T0 "$DOWNLOAD_DIR/$IMAGE_NAME" -c | btrfs receive "$MOUNT_DIR/$TEMP_SUBVOL" || { echo "[DEPLOY] Image extraction failed"; exit 1; }
  btrfs subvolume snapshot "$MOUNT_DIR/$TEMP_SUBVOL" "$MOUNT_DIR/system/$CANDIDATE_SLOT" || { echo "[DEPLOY] Snapshot swap failed"; exit 1; }
fi

btrfs property set -f -ts "$MOUNT_DIR/system/$CANDIDATE_SLOT" ro true || { echo "[DEPLOY] Failed to set candidate as read-only"; exit 1; }
btrfs subvolume delete "$MOUNT_DIR/$TEMP_SUBVOL" || { echo "[DEPLOY] Deleting temporary subvolume failed"; exit 1; }
umount -R "$MOUNT_DIR" || { echo "[DEPLOY] Unmounting failed"; exit 1; }
echo "[DEPLOY] Candidate slot update complete."

echo "[DEPLOY] Updating Secure Boot configuration..."
mkdir -p "$MOUNT_DIR"
mount -o subvol="system/${CANDIDATE_SLOT}" "$DEPLOYMENT_DIR" "$MOUNT_DIR" || { echo "[DEPLOY] Mounting updated candidate failed"; exit 1; }
mount LABEL=shani_boot "$MOUNT_DIR/boot/efi" || { echo "[DEPLOY] Mounting EFI failed"; exit 1; }
if [[ -x "$GENEFI_SCRIPT" ]]; then
  arch-chroot "$MOUNT_DIR" "$GENEFI_SCRIPT" configure "$CANDIDATE_SLOT" || { echo "[DEPLOY] UKI generation failed"; exit 1; }
fi
umount -R "$MOUNT_DIR"

# Switch active slot by updating the current-slot record.
# In deploy-image.sh after determining ACTIVE_SLOT and CANDIDATE_SLOT:
echo "$ACTIVE_SLOT" > "$PREVIOUS_SLOT_FILE"
echo "$CANDIDATE_SLOT" > "$CURRENT_SLOT_FILE"
echo "[DEPLOY] Deployment finished successfully. Next boot will use slot: ${CANDIDATE_SLOT}"

