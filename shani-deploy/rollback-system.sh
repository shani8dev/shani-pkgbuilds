#!/bin/bash
# rollback-system.sh – Rollback the active slot using its backup and revert to the previous slot.
#
# This script restores the latest backup snapshot of the failing system subvolume
# (either @blue or @green) and then updates the slot marker file in the shared @data subvolume.
# It assumes backup snapshots are named with the pattern "<slot>_backup_YYYYMMDDHHMM".
#
# (Run from the installed system.)

set -e
IFS=$'\n\t'

log() {
    echo "$(date "+%Y-%m-%d %H:%M:%S") [ROLLBACK] $*"
}

ROOTLABEL="shani_root"
ROOT_DEV="/dev/disk/by-label/${ROOTLABEL}"
# Marker files reside in the shared @data subvolume (mounted at /data).
CURRENT_SLOT_FILE="/data/current-slot"
PREVIOUS_SLOT_FILE="/data/previous-slot"
MOUNT_DIR="/mnt"

log "Initiating rollback..."

mkdir -p "$MOUNT_DIR"
mount -o subvolid=5 "$ROOT_DEV" "$MOUNT_DIR" || { log "Failed to mount Btrfs top-level"; exit 1; }

if [ -f "$MOUNT_DIR/@data/current-slot" ]; then
    FAILED_SLOT=$(cat "$MOUNT_DIR/@data/current-slot")
else
    log "Current slot marker not found. Cannot rollback."
    exit 1
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

log "Failed slot: ${FAILED_SLOT}. Previous working slot: ${PREVIOUS_SLOT}."

# Locate the latest backup snapshot for the failed slot.
BACKUP_NAME=$(btrfs subvolume list "$MOUNT_DIR" | awk -v slot="${FAILED_SLOT}" '$0 ~ slot"_backup" {print $NF}' | sort | tail -n 1)
if [ -z "$BACKUP_NAME" ]; then
    log "No backup found for slot ${FAILED_SLOT}. Cannot rollback."
    exit 1
fi

log "Restoring slot ${FAILED_SLOT} from backup ${BACKUP_NAME}..."
FAILED_PATH="$MOUNT_DIR/@${FAILED_SLOT}"
BACKUP_PATH="$MOUNT_DIR/${BACKUP_NAME}"
btrfs subvolume delete "$FAILED_PATH" || { log "Failed to delete failed slot"; exit 1; }
btrfs subvolume snapshot "$BACKUP_PATH" "$FAILED_PATH" || { log "Failed to restore from backup"; exit 1; }

log "Reverting to previous working slot: ${PREVIOUS_SLOT}..."
echo "$PREVIOUS_SLOT" > "$MOUNT_DIR/@data/current-slot"
bootctl set-default "shanios-${PREVIOUS_SLOT}.conf"

umount -R "$MOUNT_DIR"
log "Rollback complete. Rebooting..."
reboot

