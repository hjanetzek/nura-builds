#!/bin/sh
# Build the image of the target for a device from the packages in the local repository (restored
# by setup.sh), and write it to $NURA_OUT/<target>-<device>.img.zst.
# With IMAGE_KITS_<device, "-" as "_"> in the target file (e.g. IMAGE_KITS_zynthian_rpi4="V4 V5"):
# instead one image per zynthian kit, $NURA_OUT/<target>-<device>-<kit>.img.zst, the kit preset in
# zynthian.txt on the boot partition (zynthian-hw's zynthian-kit-boot sets it up at the first
# boot); written with mtools into the image file, without mounting it.
#
# Usage: image.sh DEVICE
# Environment: NURA_PASSWORD (the user's password in the image; default IMAGE_PASSWORD of the
# target file, else "147147": change it on the device with passwd).
. "$(dirname "$0")/common.sh"

device=$1
pmb config device "$device"
pmb config ui "$UI"
# The kernel of devices that offer a choice (device-<codename>-kernel-<name> subpackages):
# IMAGE_KERNEL_<device, "-" as "_"> in the target file (e.g. rpi or rpi-rt for zynthian-rpi4);
# pmbootstrap's default "stable" otherwise
eval "kernel=\${IMAGE_KERNEL_$(echo "$device" | tr - _):-stable}"
# shellcheck disable=SC2154 # set by eval
pmb config kernel "$kernel"
# IMAGE_PACKAGES (target file, e.g. IMAGE_PACKAGES_armv7) and the device's EXTRA_PACKAGES_<device,
# "-" as "_"> (e.g. zynthian-hw for zynthian-rpi4): packages installed besides the UI's
eval "extra=\${EXTRA_PACKAGES_$(echo "$device" | tr - _):-}"
# shellcheck disable=SC2154 # set by eval
add=$(echo $IMAGE_PACKAGES $extra | tr ' ' ',')
pmb install --password "${NURA_PASSWORD:-${IMAGE_PASSWORD:-147147}}" ${add:+--add "$add"}

img="$NURA_WORK/chroot_native/home/pmos/rootfs/$device.img"
[ -f "$img" ] || { echo "no image at $img" >&2; exit 1; }
mkdir -p "$NURA_OUT"
eval "kits=\${IMAGE_KITS_$(echo "$device" | tr - _):-}"
# shellcheck disable=SC2154 # set by eval
if [ -z "$kits" ]; then
	sudo zstd -T0 -10 -q -f "$img" -o "$NURA_OUT/$TARGET-$device.img.zst"
	sudo chown "$(id -u):$(id -g)" "$NURA_OUT/$TARGET-$device.img.zst"
	ls -la "$NURA_OUT/$TARGET-$device.img.zst"
	exit 0
fi
# The boot partition (the first one, FAT) in the image, for mtools ("image@@offset")
command -v mcopy >/dev/null || { echo "image.sh: IMAGE_KITS needs mtools (mcopy)" >&2; exit 1; }
start=$(sudo sfdisk -J "$img" | python3 -c 'import json,sys; print(json.load(sys.stdin)["partitiontable"]["partitions"][0]["start"])')
for kit in $kits; do
	out=$NURA_OUT/$TARGET-$device-$kit.img
	sudo cp "$img" "$out"
	sudo chown "$(id -u):$(id -g)" "$out"
	mcopy -n -i "$out@@$((start * 512))" ::zynthian.txt "$NURA_OUT/zynthian.txt" 2>/dev/null ||
		printf '# zynthian on a Raspberry Pi: your zynthian kit\n' > "$NURA_OUT/zynthian.txt"
	{
		grep -v '^[[:space:]]*kit[[:space:]]*=' "$NURA_OUT/zynthian.txt"
		echo "# This image is for the zynthian $kit kit (another kit: change the line below)"
		echo "kit=$kit"
	} > "$NURA_OUT/zynthian-$kit.txt"
	mcopy -o -i "$out@@$((start * 512))" "$NURA_OUT/zynthian-$kit.txt" ::zynthian.txt
	echo "$out: kit=$kit in zynthian.txt"
	zstd -T0 -10 -q -f --rm "$out" -o "$out.zst"
	rm -f "$NURA_OUT/zynthian.txt" "$NURA_OUT/zynthian-$kit.txt"
	ls -la "$out.zst"
done
