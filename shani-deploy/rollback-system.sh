#!/bin/bash
# rollback-system.sh – Rollback the active slot using its backup and revert to the previous slot.
set -e
DEPLOYMENT_DIR="/deployment"
MOUNT_DIR="/mnt"
CURRENT_SLOT_FILE="${DEPLOYMENT_DIR}/current-slot"

echo "[ROLLBACK] Boot failure detected. Initiating rollback..."
mount -o subvolid=5 "$DEPLOYMENT_DIR" "$MOUNT_DIR" || { echo "[ROLLBACK] Failed to mount deployment"; exit 1; }

if [ -f "$CURRENT_SLOT_FILE" ]; then
  FAILED_SLOT=$(cat "$CURRENT_SLOT_FILE")
  ORIGINAL_SLOT=$([ "$FAILED_SLOT" = "blue" ] && echo "green" || echo "blue")
else
  echo "[ROLLBACK] Current slot record not found. Cannot rollback."
  exit 1
fi

# Find the latest backup snapshot for the failed slot.
LATEST_BACKUP=$(btrfs subvolume list "$MOUNT_DIR" | awk '/system\/'"${FAILED_SLOT}"'_backup/ {print $NF}' | sort | tail -n 1)
if [ -z "$LATEST_BACKUP" ]; then
  echo "[ROLLBACK] No backup found for slot ${FAILED_SLOT}. Cannot rollback."
  exit 1
fi

echo "[ROLLBACK] Restoring ${FAILED_SLOT} from backup ${LATEST_BACKUP}..."
btrfs subvolume delete "$MOUNT_DIR/system/${FAILED_SLOT}" || { echo "[ROLLBACK] Failed to delete failed slot"; exit 1; }
btrfs subvolume snapshot "$MOUNT_DIR/system/$LATEST_BACKUP" "$MOUNT_DIR/system/${FAILED_SLOT}" || { echo "[ROLLBACK] Failed to restore from backup"; exit 1; }

echo "[ROLLBACK] Reverting to original slot: ${ORIGINAL_SLOT}..."
echo "$ORIGINAL_SLOT" > "$CURRENT_SLOT_FILE"
bootctl set-default "shanios-${ORIGINAL_SLOT}.conf"

umount -R "$MOUNT_DIR"
echo "[ROLLBACK] Rollback complete. Rebooting..."
reboot
