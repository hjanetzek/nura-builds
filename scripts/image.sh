#!/bin/sh
# Build the image of the target for a device from the packages in the local repository (restored
# by setup.sh), and write it to $NURA_OUT/<target>-<device>.img.zst.
#
# Usage: image.sh DEVICE
# Environment: NURA_PASSWORD (the user's password in the image, default "147147": change it on
# the device with passwd).
. "$(dirname "$0")/common.sh"

device=$1
pmb config device "$device"
pmb config ui "$UI"
# IMAGE_PACKAGES (target file, e.g. IMAGE_PACKAGES_armv7): packages installed besides the UI's
pmb install --password "${NURA_PASSWORD:-147147}" \
	${IMAGE_PACKAGES:+--add "$(echo $IMAGE_PACKAGES | tr ' ' ',')"}

img="$NURA_WORK/chroot_native/home/pmos/rootfs/$device.img"
[ -f "$img" ] || { echo "no image at $img" >&2; exit 1; }
mkdir -p "$NURA_OUT"
sudo zstd -T0 -10 -q -f "$img" -o "$NURA_OUT/$TARGET-$device.img.zst"
sudo chown "$(id -u):$(id -g)" "$NURA_OUT/$TARGET-$device.img.zst"
# Android boot image (devices flashed with heimdall or fastboot: kernel, initramfs, device tree),
# next to the image as <target>-<device>-boot.img.zst
bootimg="$NURA_WORK/chroot_rootfs_$device/boot/boot.img"
if sudo test -f "$bootimg"; then
	sudo zstd -q -f "$bootimg" -o "$NURA_OUT/$TARGET-$device-boot.img.zst"
	sudo chown "$(id -u):$(id -g)" "$NURA_OUT/$TARGET-$device-boot.img.zst"
fi
ls -la "$NURA_OUT/$TARGET-$device"*.img.zst
