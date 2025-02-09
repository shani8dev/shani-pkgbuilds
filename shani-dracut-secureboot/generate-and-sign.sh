#!/bin/bash -e

# Define paths for keys and images
MOK_KEY="/usr/share/secureboot/keys/MOK.key"
MOK_CRT="/usr/share/secureboot/keys/MOK.crt"
MOK_DER="/usr/share/secureboot/keys/MOK.der"
SHANI_BOOT_DIR="/usr/lib/shani-boot"
KERNEL_IMAGE="$SHANI_BOOT_DIR/vmlinuz"
INITRAMFS_IMAGE="$SHANI_BOOT_DIR/initramfs.img"

# Define EFI files to be signed
EFI_FILES=(
    "/usr/lib/fwupd/efi/fwupdx64.efi"
    "/usr/lib/systemd/boot/efi/systemd-bootx64.efi"
)

mkdir -p "$SHANI_BOOT_DIR"

move_kernel_image() {
    echo "🚀 Moving kernel image..."
    for mod_dir in /usr/lib/modules/*; do
        [[ -f "$mod_dir/vmlinuz" ]] || continue
        install -Dm644 "$mod_dir/vmlinuz" "$KERNEL_IMAGE"
        echo "✅ Moved: $KERNEL_IMAGE"
        break # Only move the first detected kernel
    done
}

generate_initramfs() {
    echo "🛠️ Building initramfs image..."
    for mod_dir in /usr/lib/modules/*; do
        [[ -d "$mod_dir" ]] || continue
        dracut --force "$INITRAMFS_IMAGE" --kver "$(basename "$mod_dir")"
        echo "✅ Built: $INITRAMFS_IMAGE"
        break # Only generate for the first detected kernel
    done
}

# Generic function to sign files
sign_file() {
    local file="$1"
    [[ ! -f "$file" ]] && echo "❌ File missing: $file" && return 0
    echo "🔏 Signing: $file..."
    if sbsign --key "$MOK_KEY" --cert "$MOK_CRT" --output "${file}.signed" "$file"; then
        mv -f "${file}.signed" "$file"
        echo "✅ Signed: $file"
    else
        echo "❌ Signing failed: $file" >&2
    fi
}

# Sign kernel modules
sign_kernel_modules() {
    local modules_dir="/usr/lib/modules/$(uname -r)"
    [[ ! -d "$modules_dir" ]] && echo "❌ No kernel modules found: $modules_dir" && return 0
    echo "🔏 Signing kernel modules in: $modules_dir..."

    find "$modules_dir/kernel" "$modules_dir/extramodules" -type f \( -name '*.ko' -o -name '*.ko.zst' \) 2>/dev/null | while read -r module; do
        if [[ "$module" == *.ko.zst ]]; then
            zstd -d --rm "$module" -o "${module%.zst}"
            module="${module%.zst}"
        fi
        sign_file "$module"
        [[ -f "$module" ]] && zstd --rm "$module"
    done

    echo "✅ Kernel modules signed."
}

# Main execution
move_kernel_image
generate_initramfs
sign_file "$KERNEL_IMAGE"
sign_file "$INITRAMFS_IMAGE"
#sign_kernel_modules

# Sign EFI files
for efi_file in "${EFI_FILES[@]}"; do
    sign_file "$efi_file"
done

echo "✅ All files signed successfully."

