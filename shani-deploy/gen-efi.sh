#!/usr/bin/env bash
# gen-efi.sh – Generate and update the Unified Kernel Image (UKI) for Secure Boot.
#
# Usage: ./gen-efi.sh configure <target_slot>
#
# This script creates (or reuses) a kernel command-line file and uses dracut
# to generate a new UKI image, signing it for Secure Boot.
# The command line uses "rootflags=subvol=@<target_slot>" to boot the proper system snapshot.
#
# Must be run as root.

set -Eeuo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "$(date "+%Y-%m-%d %H:%M:%S") [GENEFI][ERROR] Must run as root." >&2
    exit 1
fi

# Configuration
OS_NAME="shanios"
ESP="/boot/efi"
EFI_DIR="$ESP/EFI/${OS_NAME}"
BOOT_ENTRIES="$ESP/loader/entries"
CMDLINE_FILE="/etc/kernel/install_cmdline_$2"
MOK_KEY="/usr/share/secureboot/keys/MOK.key"
MOK_CRT="/usr/share/secureboot/keys/MOK.crt"
ROOTLABEL="shani_root"

mkdir -p "$ESP" "$EFI_DIR" "$BOOT_ENTRIES"

log() {
    echo "$(date "+%Y-%m-%d %H:%M:%S") [GENEFI] $*"
}

sign_efi_binary() {
    sbsign --key "$MOK_KEY" --cert "$MOK_CRT" --output "$1" "$1"
    sbverify --cert "$MOK_CRT" "$1"
}

get_kernel_version() {
    ls -1 /usr/lib/modules/ | grep -E '^[0-9]+\.[0-9]+\.[0-9]+' | sort -V | tail -n 1
}

generate_cmdline() {
    local slot="$1"
    if [ -f "$CMDLINE_FILE" ]; then
        log "Reusing existing kernel cmdline from $CMDLINE_FILE"
    else
        local uuid
        uuid=$(blkid -s UUID -o value /dev/disk/by-label/"$ROOTLABEL")
        local cmdline="quiet splash root=UUID=${uuid} ro rootfstype=btrfs rootflags=subvol=@${slot},compress=zstd,space_cache=v2,autodefrag"
        if [ -e "/dev/mapper/${ROOTLABEL}" ]; then
		local luks_uuid
    		luks_uuid=$(blkid -s UUID -o value /dev/mapper/${ROOTLABEL})
            cmdline+=" rd.luks.uuid=${luks_uuid} rd.luks.options=${luks_uuid}=tpm2-device=auto"
        fi
        if [ -f "/data/swap/swapfile" ]; then
            local swap_offset
            swap_offset=$(btrfs inspect-internal map-swapfile -r /data/swap/swapfile | awk '{print $NF}')
            cmdline+=" resume=UUID=${uuid} resume_offset=${swap_offset}"
        fi
        echo "$cmdline" > "$CMDLINE_FILE"
        chmod 0644 "$CMDLINE_FILE"
        log "Kernel cmdline generated for ${slot} (saved in ${CMDLINE_FILE})"
    fi
}

generate_uki() {
    local slot="$1"
    local kernel_ver
    kernel_ver=$(get_kernel_version)
    local uki_path="$EFI_DIR/${OS_NAME}-${slot}.efi"
    generate_cmdline "$slot"
    dracut --force --uefi --kver "$kernel_ver" --kernel-cmdline "$(cat "$CMDLINE_FILE")" "$uki_path"
    sign_efi_binary "$uki_path"
    cat > "$BOOT_ENTRIES/${OS_NAME}-${slot}.conf" <<EOF
title   ${OS_NAME}-${slot}
efi     /EFI/${OS_NAME}/${OS_NAME}-${slot}.efi
EOF
    bootctl set-default "${OS_NAME}-${slot}.conf"
}

case "${1:-}" in
    configure)
        if [[ -z "${2:-}" ]]; then
            echo "$(date "+%Y-%m-%d %H:%M:%S") [GENEFI][ERROR] Missing target slot. Usage: $0 configure <target_slot>" >&2
            exit 1
        fi
        generate_uki "$2"
        log "UKI generated for $2"
        ;;
    *)
        echo "Usage: $0 configure <target_slot>"
        exit 1
        ;;
esac

