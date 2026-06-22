#!/bin/bash
set -euo pipefail

modprobe zram

# only consumes physical RAM for compressed pages
echo 256M > /sys/block/zram0/disksize

mkswap /dev/zram0
swapon -p 100 /dev/zram0