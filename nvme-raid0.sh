#!/bin/bash

# Ensure the script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root"
    exit 1
fi

# Check if mdadm is installed
if ! command -v mdadm &> /dev/null; then
    echo "mdadm could not be found. Please install it."
    exit 1
fi

# Define devices
devices=("/dev/nvme0n1" "/dev/nvme1n1")

# Check if devices are valid
for device in "${devices[@]}"; do
    if [ ! -b "$device" ]; then
        echo "Device $device not found"
        exit 1
    fi

    # Check if devices are already part of another RAID array
    if mdadm --examine "$device" &> /dev/null; then
        echo "Device $device is already part of a RAID array"
        exit 1
    fi
done

# Create RAID0
if ! mdadm --create --verbose /dev/md0 --level=0 --raid-devices=2 "${devices[@]}"; then
    echo "Failed to create RAID-0"
    exit 1
fi

# Check if RAID array was successfully created
if [ ! -e /dev/md0 ]; then
    echo "RAID device /dev/md0 was not created"
    exit 1
fi

# Create Filesystem
if ! mkfs.ext4 /dev/md0; then
    echo "Failed to create filesystem on /dev/md0"
    exit 1
fi

# Define the mount point
mount_point="/data"

# Check and create mount point
if [ ! -d "$mount_point" ]; then
    mkdir -p "$mount_point"
fi

# Extract UUID
uuid=$(blkid -s UUID -o value /dev/md0)

# Check if UUID is extracted
if [ -z "$uuid" ]; then
    echo "Error: UUID not found for /dev/md0"
    exit 1
fi

# Backup fstab
cp /etc/fstab /etc/fstab.backup

# Add fstab entry
echo "UUID=$uuid $mount_point ext4 defaults 0 2" | tee -a /etc/fstab

# Verify fstab
if ! mount -a; then
    echo "Failed to mount devices. Check /etc/fstab"
    # Restore original fstab in case of failure
    cp /etc/fstab.backup /etc/fstab
    exit 1
fi

echo "Raid-0 Created"

