#!/bin/bash

# Bluefin Linux System Update Script
# Handles: rpm-ostree, flatpak, and firmware updates

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

print_note() {
    echo -e "${BLUE}[NOTE]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root"
   exit 1
fi

# 1. rpm-ostree Update
print_status "Starting rpm-ostree update..."
if rpm-ostree upgrade; then
    print_status "rpm-ostree update completed successfully"
    REBOOT_NEEDED=true
else
    print_error "rpm-ostree update failed"
    exit 1
fi

# 2. Flatpak Updates
print_status "Starting Flatpak updates..."
if command -v flatpak &> /dev/null; then
    # Update system-wide flatpaks
    if flatpak update --system -y; then
        print_status "System Flatpak updates completed"
    else
        print_warning "System Flatpak update failed"
    fi

    # Update user flatpaks (if any users exist)
    for userdir in /home/*; do
        if [ -d "$userdir/.local/share/flatpak" ]; then
            username=$(basename "$userdir")
            print_status "Updating Flatpaks for user: $username"
            # Use runuser instead of sudo for user operations
            if ! runuser -u "$username" -- flatpak update --user -y; then
                print_warning "User Flatpak update failed for $username"
            fi
        fi
    done
else
    print_warning "Flatpak not installed, skipping"
fi

# 3. Firmware Updates
print_status "Starting firmware updates..."
if command -v fwupdmgr &> /dev/null; then
    # Check if system is UEFI
    if [ -d /sys/firmware/efi ]; then
        print_note "System is running in UEFI mode"
    else
        print_warning "System is not running in UEFI mode. Firmware updates may be limited."
    fi

    print_note "Note: Some firmware updates require UEFI capsule support. If you see a warning about UEFI capsule updates, it may be normal for your system."

    # Refresh firmware metadata
    print_status "Refreshing firmware metadata..."
    if fwupdmgr refresh --force; then
        print_status "Firmware metadata refreshed"
    else
        print_warning "Failed to refresh firmware metadata"
    fi

    # Get updates
    print_status "Checking for firmware updates..."
    if fwupdmgr get-updates; then
        print_status "Checking for firmware updates completed"
        
        # Install updates if available
        print_status "Installing firmware updates..."
        if fwupdmgr update -y; then
            print_status "Firmware updates installed successfully"
            FIRMWARE_REBOOT=true
        else
            print_warning "No firmware updates available or installation failed"
        fi
    else
        print_warning "Failed to check for firmware updates"
    fi
else
    print_warning "fwupdmgr not found, skipping firmware updates"
fi

# Summary
print_status "Update process completed!"
if [ "${REBOOT_NEEDED:-false}" = true ] || [ "${FIRMWARE_REBOOT:-false}" = true ]; then
    print_warning "A system reboot is required to complete all updates"
    read -p "Reboot now? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        reboot
    else
        print_status "Remember to reboot your system later"
    fi
else
    print_status "No reboot required at this time"
fi

exit 0
