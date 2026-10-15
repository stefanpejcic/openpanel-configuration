#!/bin/bash
# enables the kernel io.cost controller on the disks behind /, /home and /var/lib/containers, so cgroup IOWeight is enforced
# the none/mq-deadline schedulers that NVMe and most VPS disks use ignore io.weight; io.cost works with any scheduler
# runs at boot from openpanel-iocost.service, the setting does not survive a reboot

QOS=/sys/fs/cgroup/io.cost.qos
[ -w "$QOS" ] || { echo "io.cost is not available in this kernel, IOWeight will not be enforced."; exit 0; }

# io.cost only attaches to whole disks, so walk from each mount's device (partition, lvm, raid) down to the disks under it
for path in / /home /var/lib/containers; do
    [ -e "$path" ] || continue
    src=$(findmnt -n -o SOURCE --target "$path" | sed 's/\[.*\]$//')
    [ -b "$src" ] || continue
    lsblk -s -n -r -o TYPE,MAJ:MIN "$src"
done | awk '$1 == "disk" {print $2}' | sort -u | while read -r dev; do
    if echo "$dev enable=1" > "$QOS" 2>/dev/null; then
        echo "io.cost enabled on $dev"
    else
        echo "Could not enable io.cost on $dev"
    fi
done
exit 0
