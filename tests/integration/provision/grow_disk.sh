#!/usr/bin/env bash
#
# Grow the guest root partition and filesystem into the unallocated space
# already present on the disk.
#
# The boxes in the matrix ship a 20 GB disk but partition far less of it,
# leaving a root filesystem in the region of 9 GB. That is not enough for
# what the roles do: the mod_security role unpacks the ModSecurity source
# tree and the full nginx source tree under /tmp, compiles both, and installs
# a toolchain and a set of -devel packages on the way. This step extends the
# root partition and its filesystem over the rest of the disk so those builds
# have room.
#
# It only touches the in-guest partition table and filesystem; it does NOT
# resize the virtual disk. Vagrant's experimental disk feature does that, and
# on these boxes it corrupts the boot.
#
# Layout is detected at run time (package manager, partition number and
# filesystem type) so the same script serves every entry in the matrix. All
# operations are no-ops when there is nothing to grow, so re-running is safe.
set -euo pipefail

# growpart is not on either box out of the box, and the package that carries
# it is named differently per family: cloud-utils-growpart on Enterprise
# Linux, cloud-guest-utils on Debian and Ubuntu. The package manager is
# probed rather than the distribution, because that is the thing that
# actually differs here.
if ! command -v growpart >/dev/null 2>&1; then
    if command -v dnf >/dev/null 2>&1; then
        dnf install -y cloud-utils-growpart >/dev/null
    else
        apt-get update -qq
        apt-get install -y cloud-guest-utils >/dev/null
    fi
fi

# Identify the device, disk and partition backing the root mount
root_source="$(findmnt -no SOURCE /)"
root_fstype="$(findmnt -no FSTYPE /)"

# An LVM root is out of scope, and silently out of scope would be dangerous:
# the partition number below is derived from the trailing digits of the mount
# source, which on a logical volume are part of the volume name rather than a
# partition index. growpart would then be pointed at a partition this script
# never looked at. Neither box in the matrix uses LVM; a box that did would
# need the volume group walked instead, which is left undone rather than
# guessed.
case "$root_source" in
    /dev/mapper/* | /dev/dm-*)
        echo "grow_disk: root is on LVM ($root_source), leaving it alone"
        exit 0
        ;;
esac

whole_disk="/dev/$(lsblk -no PKNAME "$root_source" | head -1)"
partition_number="$(echo "$root_source" | grep -o '[0-9]*$')"

# Extend the partition into any free space that follows it. growpart exits
# non-zero when there is nothing to do (it reports NOCHANGE), which is a
# normal outcome on a box that already partitions its whole disk, so the
# failure is swallowed rather than allowed to abort the provisioner.
growpart "$whole_disk" "$partition_number" || true

# Grow the mounted filesystem to fill the enlarged partition. xfs is what the
# Enterprise Linux boxes format root as and it can only be grown by mount
# point; ext4 on the Ubuntu box is grown by device.
if [ "$root_fstype" = "xfs" ]; then
    xfs_growfs / >/dev/null
else
    resize2fs "$root_source" >/dev/null
fi

# Report the resulting size in the provisioning log
echo "grow_disk: root filesystem is now $(findmnt -no SIZE /)"
