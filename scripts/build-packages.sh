#!/bin/sh
# Build packages by name (forced: also when the repository already has their version), with their
# missing or outdated dependencies. For trying single recipes (.github/workflows/packages.yml).
#
# Usage: build-packages.sh PKGNAME[=@REPO]...      (scripts/setup.sh first)
# PKGNAME=@REPO builds the package from the checkout of a source repository (pmbootstrap --src, as
# the stages do), e.g. zyncoder=@zyncoder.
. "$(dirname "$0")/common.sh"

[ $# -gt 0 ] || { echo "usage: $0 PKGNAME..." >&2; exit 1; }
for pkg in "$@"; do
	case $pkg in
		*=@*) case ${pkg%%=@*}${pkg#*=@} in *[!a-z0-9._+-]*) echo "not a package name: $pkg" >&2; exit 1 ;; esac ;;
		*[!a-z0-9._+-]*) echo "not a package name: $pkg" >&2; exit 1 ;;
	esac
done
for pkg in "$@"; do
	echo "::group::pmbootstrap build --force $pkg"
	case $pkg in
		*=@*) pmb build --arch "$ARCH" --force --src="$(resolve "@${pkg#*=@}")" "${pkg%%=@*}" ;;
		*) pmb build --arch "$ARCH" --force "$pkg" ;;
	esac
	echo "::endgroup::"
done
