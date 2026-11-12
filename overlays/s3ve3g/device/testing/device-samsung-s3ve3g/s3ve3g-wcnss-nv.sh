#!/bin/sh
# Samsung Galaxy S III Neo: copy the Wi-Fi NV calibration file (WCNSS_qcom_wlan_nv.bin, per device,
# not redistributable) from the stock system partition into /lib/firmware, where wcn36xx asks for
# it. msm-firmware-loader doesn't find it: it looks in image/ and firmware/ of the firmware
# partitions, and in system only on devices with dynamic partitions. Runs before it, once.
set -u
target=/lib/firmware/wlan/prima/WCNSS_qcom_wlan_nv.bin
[ -e "$target" ] && exit 0

# /dev/disk/by-partlabel doesn't exist yet (before udev): the partition name from sysfs
dev=
for p in /sys/block/mmcblk*/mmcblk*p*; do
	if grep -qx 'PARTNAME=system' "$p/uevent" 2>/dev/null; then
		dev=/dev/${p##*/}
		break
	fi
done
[ -n "$dev" ] || { echo "s3ve3g-wcnss-nv: no system partition"; exit 0; }

mnt=$(mktemp -d -p /run) || exit 0
if mount -o ro,nodev,noexec,nosuid "$dev" "$mnt"; then
	src="$mnt/etc/firmware/wlan/prima/WCNSS_qcom_wlan_nv.bin"
	if [ -f "$src" ]; then
		install -Dm644 "$src" "$target" && echo "s3ve3g-wcnss-nv: $target from $dev"
	else
		echo "s3ve3g-wcnss-nv: no $src"
	fi
	umount "$mnt"
fi
rmdir "$mnt"
exit 0
