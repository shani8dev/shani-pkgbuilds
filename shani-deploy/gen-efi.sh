#!/usr/bin/env bash
# gen-efi.sh – Generate and update the Unified Kernel Image (UKI) for Secure Boot.
# Usage: ./gen-efi.sh configure <target_slot>
set -Eeuo pipefail
IFS=$'\n\t'

if [[ $EUID -ne 0 ]]; then
  echo "[ERROR] Must run as root." >&2
  exit 1
fi

### Configuration
OS_NAME="shanios"
BUILD_VERSION="$(date +%Y%m%d)"
ESP="/boot/efi"
EFI_DIR="$ESP/EFI/${OS_NAME}"
UKI_BOOT_ENTRY="$ESP/loader/entries"
CMDLINE_FILE="/etc/kernel/deploy_cmdline_$2"
MOK_KEY="/usr/share/secureboot/keys/MOK.key"
MOK_CRT="/usr/share/secureboot/keys/MOK.crt"
ROOTLABEL="shani_root"

mkdir -p "$ESP" "$EFI_DIR" "$UKI_BOOT_ENTRY"

sign_efi_binary() {
  sbsign --key "$MOK_KEY" --cert "$MOK_CRT" --output "$1" "$1"
  sbverify --cert "$MOK_CRT" "$1"
}

get_kernel_version() {
  ls -1 /usr/lib/modules/ | grep -E '^[0-9]+\.[0-9]+\.[0-9]+' | sort -V | tail -n 1
}

generate_cmdline() {
  local target_slot="$1"
  local cmdline="quiet splash rootflags=subvol=deployment/system/${target_slot}"
  if [ -e "/dev/mapper/${ROOTLABEL}" ]; then
    local luks_uuid
    luks_uuid=$(blkid -s UUID -o value "/dev/mapper/${ROOTLABEL}")
    cmdline+=" rd.luks.uuid=${luks_uuid} rd.luks.options=${luks_uuid}=tpm2-device=auto"
  fi
  if [ -f "/deployment/data/swap/swapfile" ]; then
    local root_uuid swap_offset
    root_uuid=$(blkid -s UUID -o value /dev/disk/by-label/"$ROOTLABEL")
    swap_offset=$(btrfs inspect-internal map-swapfile -r /deployment/data/swap/swapfile | awk '{print $NF}')
    cmdline+=" resume=UUID=${root_uuid} resume_offset=${swap_offset}"
  fi
  echo "$cmdline" > "$CMDLINE_FILE"
  chmod 0644 "$CMDLINE_FILE"
  echo "[DEPLOY] Kernel cmdline generated for ${target_slot} (saved in ${CMDLINE_FILE})"
}

generate_uki() {
  local slot="$1"
  local kernel_version uki_path
  kernel_version=$(get_kernel_version)
  uki_path="$EFI_DIR/shanios-${slot}.efi"
  
  generate_cmdline "$slot"
  dracut --force --uefi --kver "$kernel_version" --cmdline "$(cat "$CMDLINE_FILE")" "$uki_path"
  sign_efi_binary "$uki_path"
  
  cat > "$UKI_BOOT_ENTRY/shanios-${slot}.conf" <<EOF
title   shanios-${slot} (${BUILD_VERSION})
efi     /EFI/${OS_NAME}/${OS_NAME}-${slot}.efi
EOF
  bootctl set-default "shanios-${slot}.conf"
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

