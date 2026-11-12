#!/bin/sh
# Samsung Galaxy S III Neo: copy the firmware the device needs from the stock partitions into
# /lib/firmware, once (instead of msm-firmware-loader, which mounted and scanned all firmware
# partitions on every boot, 4 s at 787 MHz, before udev):
# - the Wi-Fi core's firmware (wcnss.mdt, wcnss.b*) from apnhlos/image (the only remote processor
#   the device tree enables: no modem, ADSP or video core yet)
# - the Wi-Fi NV calibration file (per device) from system/etc/firmware/wlan/prima
# Runs before udev (the Wi-Fi driver asks for its firmware once, when it probes); does nothing
# when the files are there.
set -u
fw=/lib/firmware
nv=$fw/wlan/prima/WCNSS_qcom_wlan_nv.bin
[ -e "$fw/wcnss.mdt" ] && [ -e "$nv" ] && exit 0

# /dev/disk/by-partlabel doesn't exist yet (before udev): partition names from sysfs
partition() {
	for p in /sys/block/mmcblk*/mmcblk*p*; do
		if grep -qx "PARTNAME=$1" "$p/uevent" 2>/dev/null; then
			echo "/dev/${p##*/}"
			return
		fi
	done
}

# $1: partition name, $2: directory below it, $3...: files (globs) to copy into $fw/$dest
copy_from() {
	part=$1 dir=$2 dest=$3
	shift 3
	dev=$(partition "$part")
	[ -n "$dev" ] || { echo "s3ve3g-firmware: no $part partition"; return; }
	mnt=$(mktemp -d -p /run) || return
	if ! mount -o ro,nodev,noexec,nosuid "$dev" "$mnt" 2>/dev/null; then
		# e.g. system overwritten by a rootfs image (flash_rootfs with another device package)
		echo "s3ve3g-firmware: can't mount $part ($dev); missing: $*"
	else
		mkdir -p "$fw/$dest"
		for pattern in "$@"; do
			for f in "$mnt/$dir"/$pattern; do
				[ -f "$f" ] || continue
				install -m644 "$f" "$fw/$dest/" && echo "s3ve3g-firmware: $fw/$dest/${f##*/} from $part"
			done
		done
		umount "$mnt"
	fi
	for pattern in "$@"; do
		case $pattern in *'['*) continue ;; esac
		[ -e "$fw/$dest/$pattern" ] || echo "s3ve3g-firmware: no $pattern in $part:/$dir (see docs/samsung-s3ve3g.md)"
	done
	rmdir "$mnt"
}

[ -e "$fw/wcnss.mdt" ] || copy_from apnhlos image . 'wcnss.mdt' 'wcnss.b[0-9][0-9]'
[ -e "$nv" ] || copy_from system etc/firmware/wlan/prima wlan/prima WCNSS_qcom_wlan_nv.bin
exit 0
