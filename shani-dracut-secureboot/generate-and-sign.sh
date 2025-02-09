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
    if [[ ! -f "$MOK_KEY" || ! -f "$MOK_CRT" ]]; then
        echo "🔑 Generating new MOK keys..."
        openssl req -newkey rsa:4096 -nodes -keyout "$MOK_KEY" \
            -new -x509 -sha256 -days 3650 -out "$MOK_CRT" \
            -subj "/CN=Shani OS Secure Boot Key/"
        openssl x509 -in "$MOK_CRT" -outform DER -out "$MOK_DER"
    else
        echo "🔑 Using existing MOK keys..."
    fi
}

# Ensure Secure Boot keys are ready
generate_keys
echo "✅ Secure Boot keys are ready."

# Generate initramfs images in /usr/lib/shani-boot
generate_initramfs() {
    echo ":: Building initramfs for kernel $(uname -r)..."
    # Ensure the boot directory exists
    mkdir -p "$SHANI_BOOT_DIR"
    dracut -L 1 --force --no-hostonly -o "network" "$INITRAMFS_IMAGE" "$(uname -r)"
}

# Generic function to sign files (kernel, initramfs, and EFI)
sign_file() {
    local file="$1"
    
    # Check if the file exists
    if [[ ! -f "$file" ]]; then
        echo "❌ File does not exist: ${file}. Skipping."
        return 0  # File doesn't exist, skipping without error
    fi
    
    echo "🔏 Signing file: ${file}..."
    if ! sbsign --key "$MOK_KEY" --cert "$MOK_CRT" --output "${file}.signed" "$file"; then
        echo "❌ Failed to sign file ${file}."
        exit 1
    fi
    mv -f "${file}.signed" "$file"
    echo "✅ Signed file: ${file}"
    return 0  # Success
}

# Sign kernel modules
sign_kernel_modules() {
    local modules_dir="/usr/lib/modules/$(uname -r)"
    echo "🔏 Signing kernel modules in: ${modules_dir}..."
    
    # Check if the directory exists
    if [[ ! -d "$modules_dir" ]]; then
        echo "❌ Kernel modules directory does not exist: ${modules_dir}. Skipping."
        return 0
    fi
    
    # Find and sign kernel modules
    find "$modules_dir" -type f -name '*.ko*' -exec sign_file "{}" \;
    echo "✅ Kernel modules signed."
}

# Main execution
generate_initramfs
sign_file "$KERNEL_IMAGE"
sign_file "$INITRAMFS_IMAGE"

# Sign kernel modules
sign_kernel_modules

# Sign the EFI files
for efi_file in "${EFI_FILES[@]}"; do
    sign_file "$efi_file"
done

echo "✅ All files signed successfully."

