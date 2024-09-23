#!/bin/bash

# Function to print info messages
info_message() {
    echo -e "\e[32m[INFO]\e[0m $1"
}

# Function to print error messages
error_message() {
    echo -e "\e[31m[ERROR]\e[0m $1"
}

# Function to print warning messages
warning_message() {
    echo -e "\e[33m[WARNING]\e[0m $1"
}

# Check if the script is running as root
if [[ $EUID -ne 0 ]]; then
   error_message "This script must be run as root or using sudo."
   exit 1
fi

# Path to the virtual disk image and mount point
IMG_PATH="/srv/moosefs/virtual_disk.img"
MOUNT_POINT="/mnt/moosefs/virtual_disk"

# Step 1: Check if the image file exists
if [[ ! -f "$IMG_PATH" ]]; then
    error_message "The virtual disk image ($IMG_PATH) does not exist."
    exit 1
else
    info_message "Virtual disk image found: $IMG_PATH"
fi

# Step 2: Check if the mount point directory exists
if [[ ! -d "$MOUNT_POINT" ]]; then
    warning_message "Mount point directory ($MOUNT_POINT) does not exist. Creating it now..."
    mkdir -p "$MOUNT_POINT"
    if [[ $? -ne 0 ]]; then
        error_message "Failed to create mount point directory ($MOUNT_POINT)."
        exit 1
    fi
    info_message "Mount point directory created: $MOUNT_POINT"
else
    info_message "Mount point directory already exists: $MOUNT_POINT"
fi

# Step 3: Check the file system on the image (fsck)
info_message "Checking the file system on the virtual disk image..."
fsck_output=$(fsck -n "$IMG_PATH" 2>&1)
if [[ $? -ne 0 ]]; then
    error_message "File system check failed. Output: $fsck_output"
    exit 1
else
    info_message "File system check completed successfully."
fi

# Step 4: Try to manually mount the image
info_message "Attempting to mount the virtual disk image..."
mount_output=$(mount -o loop "$IMG_PATH" "$MOUNT_POINT" 2>&1)
if [[ $? -ne 0 ]]; then
    error_message "Failed to mount the virtual disk image. Output: $mount_output"
    exit 1
else
    info_message "Successfully mounted the virtual disk image at $MOUNT_POINT"
fi

# Step 5: Check if the mount is successful
if mountpoint -q "$MOUNT_POINT"; then
    info_message "Mount point $MOUNT_POINT is successfully mounted."
else
    error_message "Mount point $MOUNT_POINT is not mounted."
    exit 1
fi

# Step 6: Add mount entry to /etc/fstab if not already present
fstab_entry="$IMG_PATH $MOUNT_POINT ext4 loop,defaults 0 2"

if grep -qs "$IMG_PATH" /etc/fstab; then
    warning_message "An entry for $IMG_PATH already exists in /etc/fstab."
else
    info_message "Adding entry to /etc/fstab..."
    echo "$fstab_entry" >> /etc/fstab
    if [[ $? -ne 0 ]]; then
        error_message "Failed to add entry to /etc/fstab."
        exit 1
    else
        info_message "Entry added to /etc/fstab successfully."
    fi
fi

# Step 7: Apply mount changes from /etc/fstab
info_message "Applying mount changes from /etc/fstab..."
mount -a
if [[ $? -ne 0 ]]; then
    error_message "Error while applying mount changes from /etc/fstab."
    exit 1
else
    info_message "Mount changes applied successfully."
fi

info_message "Script completed successfully!"
