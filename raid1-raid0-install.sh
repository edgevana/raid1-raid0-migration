#!/bin/bash

##########################################################
#                                                        #                                                    #
# Organization: Edgevana                                 #
#                                                        #
# Purpose: Migrate RAID1 installations to RAID0          #
# for Solana validator nodes.                            #
#                                                        #
# DISCLAIMER:                                            #
# This script is provided "AS IS" without warranty of    #
# any kind. Use at your own risk. The author or          #
# Edgevana are not responsible for any data loss or      #
# damage that may occur through the use of this script.  #
# Users are advised to understand and verify the         #
# commands being executed.                               #
#                                                        #
# INSTRUCTIONS:                                          #
# This script is intended to be run in recovery mode     #
# on Vultr servers. Before running, ensure that your     #
# data is backed up and the server is in recovery mode.  #
# Follow the steps provided by Vultr to enter recovery   #
# mode, then execute this script.                        #
#                                                        #
# For support or queries, contact:                       #
# tsmith@edgevana.com                                    #
#                                                        #
##########################################################

# Speed up all raid operations within the recovery ISO so things dont take as long
echo 5000000 > /proc/sys/dev/raid/speed_limit_max

# Checks if there is any raid syncing,recoverying, or reshaping
hold_until_raid_in_sync() {

  echo "Checking if raid is in sync..."

  # Loop indefinitely until the RAID is in sync
  while true; do
    # Extract the current status of the RAID
    local status=$(cat /proc/mdstat)

    # Check for the presence of 'recovery' or 'resync'
    if echo "$status" | grep -E 'recovery|resync|reshape'; then
      # If the RAID is resyncing, print the status and sleep for a bit
      echo "$status"
      echo "RAID  is resyncing. Waiting..."
      sleep 5 # wait for 30 seconds before checking again
    else
      # If there's no 'recovery' or 'resync', the RAID should be in sync
      if echo "$status" | grep -q 'active\|clean'; then
        echo "RAID  is in sync. Proceeding..."
        break # exit the loop
      else
        echo "RAID status is unknown. Please check manually."
        exit 2 # exit with an error code
      fi
    fi
  done

  # Notify that the RAID is now in sync
  echo "The RAID is now in sync. You can continue with other operations."
}

# Checking to make sure in sync before we start
hold_until_raid_in_sync

# We stop it here because its in read-only mode
mdadm --stop /dev/md127

# Putting it back together now to get out of read only mode
mdadm -A -s

# Making sure its still in sync
hold_until_raid_in_sync

# Going to fail a disk and then remove it in prep to turn into raid0
mdadm --manage /dev/md127 --fail /dev/sdb2
mdadm --manage /dev/md127 --remove /dev/sdb2

# We check the filesystem to make sure its good to go
e2fsck -fy /dev/md127

# Resize filesystem to make sure we can fit it all on a new disk with a dd command, also makes this a quicker process
resize2fs /dev/md127 50G

# Wipes the second disk for a raid0
wipefs -a /dev/sdb2

# Create the raid0
mdadm --create --verbose /dev/md0 --level=0 --raid-devices=1 /dev/sdb2 --force

# We copy over the existing installation.
dd if=/dev/md127 of=/dev/md0 bs=1G count=55 status=progress

# Stopping the raid1, no longer needed
mdadm --stop /dev/md127

# Wipe it
wipefs -a /dev/sda2

# Add it to the raid0, this will take a while. It will also turn into a raid4 which is normal for this expansion process
mdadm --grow /dev/md0 --level=0 --raid-devices=2 --add /dev/sda2

# Wait untill this raid0 creation is fully done
hold_until_raid_in_sync

# We check the filesystem to make sure its good to go
e2fsck -fy /dev/md0

# Make the filesystem max size
resize2fs /dev/md0

# Reboot
echo "System is ready for a reboot. RAID-0 has been created."
echo "Run 'reboot'"

