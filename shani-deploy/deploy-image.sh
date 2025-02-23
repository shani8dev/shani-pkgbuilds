#!/bin/bash
# deploy-image.sh – Update the candidate slot (blue–green deployment).
#
# This script updates the candidate slot of a blue–green deployment.
# Although the running system is booted from one of the blue or green subvolumes,
# the update process mounts the Btrfs top-level (using subvolid=5) from the device
# so that the shared deployment subvolume (named "deployment") and its children can be accessed.
#
# The script then:
#   1. Downloads and verifies the new image.
#   2. Checks if the new version differs from the currently deployed version.
#   3. Backs up the candidate slot (if it exists), clears its read-only property,
#      and deletes it to prepare for the update.
#   4. Receives the full update image (which always contains a subvolume "shanios_base")
#      into a temporary subvolume, then snapshots it as the new candidate slot.
#   5. Regenerates UKI entries for Secure Boot.
#   6. Updates the slot marker files to switch the active slot.
#
# Usage: ./deploy-image.sh

set -Eeuo pipefail
IFS=$'\n\t'
trap 'echo "[DEPLOY][ERROR] Error at ${BASH_SOURCE[0]} line ${LINENO}: ${BASH_COMMAND}" >&2; exit 1' ERR

##############################
# Configuration
##############################
OS_NAME="shanios"
BUILD_VERSION="$(date +%Y%m%d)"
OUTPUT_DIR="./cache/output"
# The deployment subvolume created during install is named "deployment"
DEPLOYMENT_DIR="deployment"
LATEST_URL="https://example.com/path/to/latest.txt"
IMAGE_BASE_URL="https://example.com/path/to"
PROFILE="default"
IMAGE_NAME="${OS_NAME}-${BUILD_VERSION}-${PROFILE}.zst"
IMAGE_URL="${IMAGE_BASE_URL}/${IMAGE_NAME}.zsync"
# Downloads are stored under the data subvolume (already created during install)
DOWNLOAD_DIR="/deployment/data/downloads"
ZSYNC_CACHE_DIR="${DOWNLOAD_DIR}/zsync_cache"
# Temporary mount point for accessing the Btrfs top-level.
MOUNT_DIR="/mnt"
# Path to the UKI regeneration script.
GENEFI_SCRIPT="/usr/local/bin/gen-efi.sh"

# Minimum free space thresholds (in MB)
MIN_FREE_SPACE_MB=10240
MIN_METADATA_FREE_MB=512

LATEST_FILE="${DOWNLOAD_DIR}/latest.txt"
OLD_LATEST_FILE="${DOWNLOAD_DIR}/old.txt"

# Files for slot management are stored within the deployment subvolume.
# When mounted via the top-level, these reside at:
#   $MOUNT_DIR/deployment/current-slot and $MOUNT_DIR/deployment/previous-slot
ROOTLABEL="shani_root"
ROOT_DEV="/dev/disk/by-label/${ROOTLABEL}"

##############################
# Step 1: Download and verify the image
##############################
echo "[DEPLOY] Checking disk space on /deployment..."
free_space_mb=$(df --output=avail "/deployment" 2>/dev/null | tail -n1 || echo 0)
free_space_mb=$(( free_space_mb / 1024 ))
if [ "$free_space_mb" -lt "$MIN_FREE_SPACE_MB" ]; then
  echo "[DEPLOY] Not enough disk space (available: ${free_space_mb} MB, required: ${MIN_FREE_SPACE_MB} MB)"
  exit 1
fi
echo "[DEPLOY] Disk space OK."

echo "[DEPLOY] Preparing download environment..."
# The downloads subvolume is already created under /deployment/data/downloads.
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

##############################
# Step 2: Mount Btrfs top-level and determine active slot
##############################
echo "[DEPLOY] Mounting Btrfs top-level..."
mkdir -p "$MOUNT_DIR"
mount -o subvolid=5 "$ROOT_DEV" "$MOUNT_DIR" || { echo "[DEPLOY] Mounting failed"; exit 1; }

# Read active slot from the deployment subvolume.
ACTIVE_SLOT_FILE="$MOUNT_DIR/${DEPLOYMENT_DIR}/current-slot"
if [ -f "$ACTIVE_SLOT_FILE" ]; then
    ACTIVE_SLOT=$(cat "$ACTIVE_SLOT_FILE")
else
    ACTIVE_SLOT="blue"
    echo "$ACTIVE_SLOT" > "$ACTIVE_SLOT_FILE"
fi

if [ "$ACTIVE_SLOT" = "blue" ]; then
    CANDIDATE_SLOT="green"
else
    CANDIDATE_SLOT="blue"
fi
echo "[DEPLOY] Active slot: ${ACTIVE_SLOT}; Candidate slot: ${CANDIDATE_SLOT}"

# Check currently deployed version from the active slot.
CURRENT_VERSION=$(cat "$MOUNT_DIR/${DEPLOYMENT_DIR}/system/${ACTIVE_SLOT}/etc/shani-version" 2>/dev/null || echo "none")
if [ "$NEW_VERSION" = "$CURRENT_VERSION" ]; then
  echo "[DEPLOY] Deployed version ($CURRENT_VERSION) matches new image. Skipping update."
  umount -R "$MOUNT_DIR"
  exit 0
fi

##############################
# Step 3: Update candidate slot
##############################
# Define candidate slot path.
CANDIDATE_PATH="$MOUNT_DIR/${DEPLOYMENT_DIR}/system/${CANDIDATE_SLOT}"

# If candidate subvolume exists, back it up and delete it.
if btrfs subvolume list "$MOUNT_DIR" | grep -q "path ${DEPLOYMENT_DIR}/system/${CANDIDATE_SLOT}\$"; then
    CANDIDATE_BACKUP="${CANDIDATE_SLOT}_backup_$(date +%Y%m%d%H%M)"
    btrfs subvolume snapshot "$CANDIDATE_PATH" "$MOUNT_DIR/${DEPLOYMENT_DIR}/system/$CANDIDATE_BACKUP" \
      || { echo "[DEPLOY] Candidate backup snapshot failed"; exit 1; }
    echo "[DEPLOY] Created candidate backup: $CANDIDATE_BACKUP"
    # Clear read-only property and delete the existing candidate.
    btrfs property set -f -ts "$CANDIDATE_PATH" ro false || { echo "[DEPLOY] Failed to clear candidate read-only property"; exit 1; }
    btrfs subvolume delete "$CANDIDATE_PATH" || { echo "[DEPLOY] Failed to delete existing candidate slot"; exit 1; }
fi

# Create a temporary subvolume for the update.
TEMP_SUBVOL="$MOUNT_DIR/temp_update"
btrfs subvolume create "$TEMP_SUBVOL" || { echo "[DEPLOY] Temporary subvolume creation failed"; exit 1; }

echo "[DEPLOY] Receiving full update image into temporary subvolume..."
zstd -d --long=31 -T0 "$DOWNLOAD_DIR/$IMAGE_NAME" -c | btrfs receive "$TEMP_SUBVOL" \
    || { echo "[DEPLOY] Image extraction failed"; exit 1; }

# Verify that the received update contains the expected subvolume "shanios_base"
if [ -d "$TEMP_SUBVOL/shanios_base" ]; then
    echo "[DEPLOY] Found 'shanios_base' in update image. Creating candidate slot snapshot..."
    btrfs subvolume snapshot "$TEMP_SUBVOL/shanios_base" "$CANDIDATE_PATH" \
        || { echo "[DEPLOY] Snapshot swap failed"; exit 1; }
else
    echo "[DEPLOY] Received image does not contain expected 'shanios_base' subvolume"
    exit 1
fi

btrfs property set -f -ts "$CANDIDATE_PATH" ro true || { echo "[DEPLOY] Failed to set candidate as read-only"; exit 1; }
btrfs subvolume delete "$TEMP_SUBVOL" || { echo "[DEPLOY] Deleting temporary subvolume failed"; exit 1; }
umount -R "$MOUNT_DIR" || { echo "[DEPLOY] Unmounting failed"; exit 1; }
echo "[DEPLOY] Candidate slot update complete."

##############################
# Step 4: Update Secure Boot configuration
##############################
echo "[DEPLOY] Updating Secure Boot configuration..."
mkdir -p "$MOUNT_DIR"
# Mount the candidate system subvolume for UKI generation.
mount -o "subvol=${DEPLOYMENT_DIR}/system/${CANDIDATE_SLOT}" "$ROOT_DEV" "$MOUNT_DIR" \
    || { echo "[DEPLOY] Mounting updated candidate failed"; exit 1; }
mount --mkdir -o ro LABEL=shani_boot "$MOUNT_DIR/boot/efi" \
    || { echo "[DEPLOY] Mounting EFI failed"; exit 1; }
if [[ -x "$GENEFI_SCRIPT" ]]; then
  arch-chroot "$MOUNT_DIR" "$GENEFI_SCRIPT" configure "$CANDIDATE_SLOT" \
      || { echo "[DEPLOY] UKI generation failed"; exit 1; }
fi
umount -R "$MOUNT_DIR"

##############################
# Step 5: Switch active slot marker
##############################
echo "[DEPLOY] Remounting top-level to update slot marker files..."
mkdir -p "$MOUNT_DIR"
mount -o subvolid=5 "$ROOT_DEV" "$MOUNT_DIR" || { echo "[DEPLOY] Mounting failed"; exit 1; }
echo "[DEPLOY] Switching active slot..."
echo "$ACTIVE_SLOT" > "$MOUNT_DIR/${DEPLOYMENT_DIR}/previous-slot"
echo "$CANDIDATE_SLOT" > "$MOUNT_DIR/${DEPLOYMENT_DIR}/current-slot"
umount -R "$MOUNT_DIR"

echo "[DEPLOY] Deployment finished successfully. Next boot will use slot: ${CANDIDATE_SLOT}"

