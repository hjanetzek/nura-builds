#!/bin/sh
# Pin the device packages of the target's devices (device-<device> and those of its dependencies
# that have a recipe in pmaports: kernel, SoC and firmware packages) to the versions in
# postmarketOS's binary repository. When pmaports already has a newer recipe (e.g. a kernel
# pkgrel bump) than the published package, pmbootstrap would build it (the mt81 kernel: clang,
# Rust, BTF, 900 modules); instead, the recipe directory is checked out at the newest pmaports
# commit with the binary package's version, and pmbootstrap installs the published package.
# Packages whose binary version is in no commit of the recipe's history are left (and built).
#
# The index records no usable build commit (c:-dirty), so the commit is found by version.
# NURA_PIN_DRY=1: only print what would be pinned.
. "$(dirname "$0")/common.sh"

aports=$(pmbootstrap -c "$CFG" config aports)
mirror=${NURA_MIRROR:-http://mirror.postmarketos.org/postmarketos}
idx=$(mktemp)
trap 'rm -f "$idx"' EXIT
for repo in master extra-repos/systemd/master; do
	curl -sfL "$mirror/$repo/$ARCH/APKINDEX.tar.gz" | tar -xzO APKINDEX >> "$idx" 2>/dev/null || true
done
[ -s "$idx" ] || { echo "pin-binary: no binary index from $mirror, nothing pinned"; exit 0; }

# Version of a package in the binary index (first match: master before the systemd repository)
binary_version() {
	awk -v p="P:$1" '$0 == p {f = 1; next} f && /^V:/ {print substr($0, 3); exit} /^$/ {f = 0}' "$idx"
}

# Version of a recipe at a commit: pkgver-rpkgrel
recipe_version() {
	git -C "$aports" show "$1:$2/APKBUILD" 2>/dev/null |
		awk -F= '/^pkgver=/ {v = $2} /^pkgrel=/ {r = $2} END {if (v != "") print v "-r" r}'
}

# Recipe directory of a package in pmaports, relative to it (not the systemd overrides)
recipe_dir() {
	(cd "$aports" && find . -mindepth 2 -maxdepth 3 -type d -name "$1" ! -path "./.git/*" \
		! -path "./extra-repos/*" | sed 's|^\./||' | head -n 1)
}

pin() {
	pkg=$1
	dir=$(recipe_dir "$pkg")
	[ -n "$dir" ] || return 0
	bin=$(binary_version "$pkg")
	[ -n "$bin" ] || return 0
	cur=$(recipe_version HEAD "$dir")
	[ "$cur" != "$bin" ] || return 0
	for commit in $(git -C "$aports" log --format=%H -- "$dir"); do
		if [ "$(recipe_version "$commit" "$dir")" = "$bin" ]; then
			[ -n "${NURA_PIN_DRY:-}" ] || git -C "$aports" checkout -q "$commit" -- "$dir"
			echo "pin-binary: $pkg $cur -> $bin (pmaports $(echo "$commit" | cut -c1-10))${NURA_PIN_DRY:+ (dry run)}"
			return 0
		fi
	done
	echo "pin-binary: $pkg: pmaports $cur, binary $bin in no commit of $dir; it will be built"
}

for device in $DEVICES; do
	dir=$(recipe_dir "device-$device")
	[ -n "$dir" ] || { echo "pin-binary: no device-$device in pmaports" >&2; continue; }
	pin "device-$device"
	# depends="..." over one or more lines
	deps=$(awk '/^depends="/ {f = 1; sub(/^depends="/, "")}
		f {e = sub(/"$/, ""); print; if (e) exit}' "$aports/$dir/APKBUILD")
	for dep in $deps; do
		pin "$dep"
	done
done
