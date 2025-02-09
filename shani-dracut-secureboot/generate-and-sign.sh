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

# Ensure the directory for the keys exists
mkdir -p /usr/share/secureboot/keys

# Generate MOK keys if they do not exist
generate_keys() {
    if [[ ! -f "$MOK_KEY" || ! -f "$MOK_CRT" || ! -f "$MOK_DER" ]]; then
        echo "🔑 Generating new MOK keys..."
        openssl req -newkey rsa:4096 -nodes -keyout "$MOK_KEY" \
            -new -x509 -sha256 -days 3650 -out "$MOK_CRT" \
            -subj "/CN=Shani OS Secure Boot Key/"
        openssl x509 -in "$MOK_CRT" -outform DER -out "$MOK_DER"
        echo "✅ New MOK keys generated."
    else
        echo "🔑 MOK keys already exist. Skipping key generation."
    fi
}

# Ensure Secure Boot keys are ready
generate_keys
echo "✅ Secure Boot keys are ready."

# Move vmlinuz to shani-boot
move_kernel_image() {
    local src_vmlinuz="/usr/lib/modules/$(uname -r)/vmlinuz"
    local dest_vmlinuz="$SHANI_BOOT_DIR/vmlinuz"

    if [[ -f "$src_vmlinuz" ]]; then
        echo "🚀 Moving kernel image to $SHANI_BOOT_DIR..."
        mkdir -p "$SHANI_BOOT_DIR"
        mv -f "$src_vmlinuz" "$dest_vmlinuz"
        echo "✅ Kernel image moved."
    else
        echo "⚠️ Kernel image not found at $src_vmlinuz. Skipping move."
    fi
}

# Generate initramfs images in /usr/lib/shani-boot
generate_initramfs() {
    echo ":: Building initramfs for kernel $(uname -r)..."
    mkdir -p "$SHANI_BOOT_DIR"
    if command -v dracut &>/dev/null; then
        dracut --force "$INITRAMFS_IMAGE" "$(uname -r)"
    else
        echo "❌ Dracut not found. Skipping initramfs generation."
    fi
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

