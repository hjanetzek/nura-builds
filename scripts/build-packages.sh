#!/bin/sh
# Build packages by name (forced: also when the repository already has their version), with their
# missing or outdated dependencies. For trying single recipes (.github/workflows/packages.yml).
#
# Usage: build-packages.sh PKGNAME...      (scripts/setup.sh first)
. "$(dirname "$0")/common.sh"

[ $# -gt 0 ] || { echo "usage: $0 PKGNAME..." >&2; exit 1; }
for pkg in "$@"; do
	case $pkg in
		*[!a-z0-9._+-]*) echo "not a package name: $pkg" >&2; exit 1 ;;
	esac
done
for pkg in "$@"; do
	echo "::group::pmbootstrap build --force $pkg"
	pmb build --arch "$ARCH" --force "$pkg"
	echo "::endgroup::"
done
