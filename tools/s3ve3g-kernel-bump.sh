#!/bin/sh
# Samsung Galaxy S III Neo: move the kernel recipe (overlay linux-postmarketos-qcom-msm8226) to
# another kernel.org release, keeping our patches and config: pkgver and the tarball's checksum.
# Whether the patches still apply and the kernel builds shows the build (pmbootstrap, or the
# workflow s3ve3g-kernel-watch.yml, which runs this for each newer release).
#
# Usage: tools/s3ve3g-kernel-bump.sh VERSION      (e.g. 7.3.5 or 7.4; a full kernel.org release)
set -eu

version=$1
recipe=overlays/s3ve3g/device/testing/linux-postmarketos-qcom-msm8226/APKBUILD
[ -f "$recipe" ] || { echo "run from the repository's top directory ($recipe)" >&2; exit 1; }

old=$(sed -n 's/^pkgver=//p' "$recipe")
[ "$old" != "$version" ] || { echo "already $version"; exit 0; }

url="https://cdn.kernel.org/pub/linux/kernel/v${version%%.*}.x/linux-$version.tar.xz"
echo "linux-$version.tar.xz: checksum from $url"
sum=$(curl -fsSL "$url" | sha512sum | cut -d' ' -f1)
# sha512sum of nothing, if curl failed in the pipe
[ "$sum" != "cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e" ] ||
	{ echo "download failed" >&2; exit 1; }

sed -i -e "s/^pkgver=.*/pkgver=$version/" \
	-e "s/^[0-9a-f]\{128\}  linux-$old\.tar\.xz\$/$sum  linux-$version.tar.xz/" "$recipe"
grep -q "^$sum  linux-$version.tar.xz\$" "$recipe" ||
	{ echo "no checksum line for linux-$old.tar.xz in $recipe" >&2; exit 1; }
echo "$recipe: $old -> $version"
