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
# The device's extra packages (targets: EXTRA_PACKAGES_<device, - as _>), e.g. zynthian-hw
eval "extra=\${EXTRA_PACKAGES_$(echo "$device" | tr - _):-}"
# shellcheck disable=SC2154 # set by eval
pmb config extra_packages "${extra:-none}"
pmb install --password "${NURA_PASSWORD:-147147}"

img="$NURA_WORK/chroot_native/home/pmos/rootfs/$device.img"
[ -f "$img" ] || { echo "no image at $img" >&2; exit 1; }
mkdir -p "$NURA_OUT"
sudo zstd -T0 -10 -q -f "$img" -o "$NURA_OUT/$TARGET-$device.img.zst"
sudo chown "$(id -u):$(id -g)" "$NURA_OUT/$TARGET-$device.img.zst"
ls -la "$NURA_OUT/$TARGET-$device.img.zst"
