#!/bin/bash
# rollback-system.sh – Rollback the active slot using its backup and revert to the previous slot.
# This script rolls back the active (failing) slot by restoring its latest backup snapshot,
# then updates the current slot marker to the previous working slot.
#
# Usage: ./rollback-system.sh

set -e

# Configuration – aligns with install and deploy scripts.
DEPLOYMENT_DIR="deployment"    # The deployment subvolume (mounted as /mnt/deployment)
MOUNT_DIR="/mnt"
ROOTLABEL="shani_root"
ROOT_DEV="/dev/disk/by-label/${ROOTLABEL}"
CURRENT_SLOT_FILE="${DEPLOYMENT_DIR}/current-slot"
PREVIOUS_SLOT_FILE="${DEPLOYMENT_DIR}/previous-slot"

echo "[ROLLBACK] Boot failure detected. Initiating rollback..."

# Mount the Btrfs top-level so that the entire deployment hierarchy is accessible.
mount -o subvolid=5 "$ROOT_DEV" "$MOUNT_DIR" || { echo "[ROLLBACK] Failed to mount Btrfs top-level"; exit 1; }

# Read the current active slot from /mnt/deployment/current-slot.
if [ -f "$MOUNT_DIR/${CURRENT_SLOT_FILE}" ]; then
    FAILED_SLOT=$(cat "$MOUNT_DIR/${CURRENT_SLOT_FILE}")
else
    echo "[ROLLBACK] Current slot record not found. Cannot rollback."
    exit 1
fi

# Determine the previous (working) slot.
if [ -f "$MOUNT_DIR/${PREVIOUS_SLOT_FILE}" ]; then
    PREVIOUS_SLOT=$(cat "$MOUNT_DIR/${PREVIOUS_SLOT_FILE}")
else
    # Fallback: if previous-slot record is missing, use the alternate slot.
    if [ "$FAILED_SLOT" = "blue" ]; then
         PREVIOUS_SLOT="green"
    else
         PREVIOUS_SLOT="blue"
    fi
fi

echo "[ROLLBACK] Failed slot: ${FAILED_SLOT}. Previous working slot: ${PREVIOUS_SLOT}."

# Locate the latest backup snapshot for the failed slot.
# Backups are assumed to be stored under /mnt/deployment/system
# with names like "<slot>_backup_YYYYMMDDHHMM".
BACKUP_DIR="$MOUNT_DIR/${DEPLOYMENT_DIR}/system"
LATEST_BACKUP=$(btrfs subvolume list "$BACKUP_DIR" | awk -v slot="${FAILED_SLOT}" '$0 ~ slot"_backup" {print $NF}' | sort | tail -n 1)
if [ -z "$LATEST_BACKUP" ]; then
  echo "[ROLLBACK] No backup found for slot ${FAILED_SLOT}. Cannot rollback."
  exit 1
fi

echo "[ROLLBACK] Restoring ${FAILED_SLOT} from backup ${LATEST_BACKUP}..."
# Delete the failed slot subvolume.
btrfs subvolume delete "$MOUNT_DIR/${DEPLOYMENT_DIR}/system/${FAILED_SLOT}" || { echo "[ROLLBACK] Failed to delete failed slot"; exit 1; }
# Restore the backup snapshot as the new subvolume for the failed slot.
btrfs subvolume snapshot "$BACKUP_DIR/$LATEST_BACKUP" "$MOUNT_DIR/${DEPLOYMENT_DIR}/system/${FAILED_SLOT}" || { echo "[ROLLBACK] Failed to restore from backup"; exit 1; }

echo "[ROLLBACK] Reverting to previous working slot: ${PREVIOUS_SLOT}..."
# Update the current slot marker to the previous working slot.
echo "$PREVIOUS_SLOT" > "$MOUNT_DIR/${DEPLOYMENT_DIR}/current-slot"
bootctl set-default "shanios-${PREVIOUS_SLOT}.conf"

umount -R "$MOUNT_DIR"
echo "[ROLLBACK] Rollback complete. Rebooting..."
reboot

