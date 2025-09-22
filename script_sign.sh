#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# Check if the script is run with sudo
if [ "$EUID" -ne 0 ]; then
    echo "Please run this script with sudo."
    exit 1
fi

# Automatically detect current kernel version
KERNEL_VERSION="$(uname -r)"

# Configuration paths
KEY_DIR="/etc/pki/virtualbox-signing"
PRIVATE_KEY="$KEY_DIR/MOK.priv"
PUBLIC_CERT="$KEY_DIR/MOK.der"
SIGN_TOOL="/lib/modules/$KERNEL_VERSION/build/scripts/sign-file"

SOURCE_DIR="/lib/modules/$KERNEL_VERSION/extra/VirtualBox"
TARGET_DIR="/usr/local/lib/modules/$KERNEL_VERSION/extra/VirtualBox"
MODULES=("vboxdrv" "vboxnetflt" "vboxnetadp")
BLACKLIST_FILE="/etc/modprobe.d/blacklist-vbox.conf"

# Check if the signed modules already exist.
if [[ -f "$TARGET_DIR/vboxdrv.ko" && -f "$TARGET_DIR/vboxnetflt.ko" && -f "$TARGET_DIR/vboxnetadp.ko" ]]; then
    echo "Signed modules already exist. Skipping signing process."
else
    # Check for key files
    if [[ ! -f "$PRIVATE_KEY" || ! -f "$PUBLIC_CERT" ]]; then
        echo "Error: MOK.priv or MOK.der not found in $KEY_DIR. Make sure your signing keys are in place."
        exit 1
    fi

    # Check for the signing tool
    if [[ ! -x "$SIGN_TOOL" ]]; then
        SIGN_TOOL="/usr/src/kernels/$KERNEL_VERSION/scripts/sign-file"
        if [[ ! -x "$SIGN_TOOL" ]]; then
            echo "Error: sign-file tool not found at $SIGN_TOOL or /usr/src/kernels/$KERNEL_VERSION/scripts/sign-file"
            exit 1
        fi
    fi

    # Blacklist the original unsigned modules
    if [[ -s "$BLACKLIST_FILE" ]]; then
        echo "Blacklist file already exists and is not empty. Skipping creation."
    else
        echo "Blacklisting original VirtualBox modules..."
        cat > "$BLACKLIST_FILE" << EOF
blacklist vboxdrv
blacklist vboxnetflt
blacklist vboxnetadp
EOF
    fi

    # Prepare target directory
    echo "Creating target directory: $TARGET_DIR"
    mkdir -p "$TARGET_DIR"

    # Copy, sign, and store modules
    echo "Copying, signing, and storing modules..."
    for mod in "${MODULES[@]}"; do
        SRC="$SOURCE_DIR/${mod}.ko.xz"

        if [[ ! -f "$SRC" ]]; then
            echo "Warning: Module $mod not found at $SRC. Skipping..."
            continue
        fi

        TEMP_DIR=$(mktemp -d)
        TEMP_FILE="$TEMP_DIR/${mod}.ko"

        echo "Processing $mod..."
        if ! unxz -c "$SRC" > "$TEMP_FILE"; then
            echo "Error: Failed to decompress $mod. Skipping..."
            rm -rf "$TEMP_DIR"
            continue
        fi

        if ! "$SIGN_TOOL" sha256 "$PRIVATE_KEY" "$PUBLIC_CERT" "$TEMP_FILE"; then
            echo "Error: Failed to sign $mod. Skipping..."
            rm -rf "$TEMP_DIR"
            continue
        fi

        cp "$TEMP_FILE" "$TARGET_DIR/"
        rm -rf "$TEMP_DIR"
    done
fi

# Check if any modules were signed successfully or already existed before loading
if [[ $(ls -A "$TARGET_DIR") ]]; then
    echo "Loading modules into the kernel..."

    # Load each module and check for errors
    for mod in "${MODULES[@]}"; do
        if ! insmod "$TARGET_DIR/${mod}.ko"; then
            echo "Error: Failed to load module $mod. Aborting."
            exit 1
        fi
    done

    #Verification
    echo "Verifying modules are loaded..."
    if lsmod | grep -q 'vboxdrv'; then
        echo "Success: VirtualBox modules are loaded and ready."
    else
        echo "Error: VirtualBox modules are not loaded. Check the logs above for issues."
        exit 1
    fi
else
    echo "No modules were found to load. Check the previous logs."
    exit 1
fi
