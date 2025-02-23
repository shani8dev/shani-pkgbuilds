#!/usr/bin/env bash
# gen-efi.sh – Generate and update the Unified Kernel Image (UKI) for Secure Boot.
# Usage: ./gen-efi.sh configure <target_slot>
#
# This script generates a kernel command-line file, creates a new UKI image using dracut,
# signs it with Secure Boot keys, and writes a boot entry so that systemd-boot will boot
# the specified target slot. The paths below match the deployment structure:
#   - The root subvolume is "deployment/system/<slot>"
#   - Swap is expected at "/deployment/data/swap/swapfile"
#   - The kernel command-line is stored at "/etc/kernel/install_cmdline_<target_slot>"
#
# Must be run as root.

set -Eeuo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "[ERROR] Must run as root." >&2
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

sign_efi_binary() {
  sbsign --key "$MOK_KEY" --cert "$MOK_CRT" --output "$1" "$1"
  sbverify --cert "$MOK_CRT" "$1"
}

get_kernel_version() {
  ls -1 /usr/lib/modules/ | grep -E '^[0-9]+\.[0-9]+\.[0-9]+' | sort -V | tail -n 1
}

generate_cmdline() {
  local slot="$1"
  local cmdline="quiet splash rootflags=subvol=deployment/system/${slot}"
  if [ -e "/dev/mapper/${ROOTLABEL}" ]; then
    cmdline+=" rd.luks.uuid=$(blkid -s UUID -o value /dev/mapper/${ROOTLABEL}) rd.luks.options=$(blkid -s UUID -o value /dev/mapper/${ROOTLABEL})=tpm2-device=auto"
  fi
  if [ -f "/deployment/data/swap/swapfile" ]; then
    local root_uuid=$(blkid -s UUID -o value /dev/disk/by-label/"$ROOTLABEL")
    local swap_offset=$(btrfs inspect-internal map-swapfile -r /deployment/data/swap/swapfile | awk '{print $NF}')
    cmdline+=" resume=UUID=${root_uuid} resume_offset=${swap_offset}"
  fi
  echo "$cmdline" > "$CMDLINE_FILE"
  chmod 0644 "$CMDLINE_FILE"
  echo "[DEPLOY] Kernel cmdline generated for ${slot} (saved in ${CMDLINE_FILE})"
}

generate_uki() {
  local slot="$1"
  local kernel_ver
  kernel_ver=$(get_kernel_version)
  # Align UKI path with configure.sh
  local uki_path="$EFI_DIR/${OS_NAME}-${slot}.efi"
  
  generate_cmdline "$slot"
  dracut --force --uefi --kver "$kernel_ver" --cmdline "$(cat "$CMDLINE_FILE")" "$uki_path"
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
      echo "[ERROR] Missing target slot. Usage: $0 configure <target_slot>" >&2
      exit 1
    fi
    generate_uki "$2"
    echo "[SUCCESS] UKI generated for $2"
    ;;
  *)
    echo "Usage: $0 configure <target_slot>"
    exit 1
    ;;
esac

