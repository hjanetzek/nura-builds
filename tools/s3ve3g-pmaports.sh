#!/bin/sh
# A pmaports worktree for the Samsung Galaxy S III Neo (docs/samsung-s3ve3g.md): pmbootstrap's
# pmaports checkout at a commit, with this repository's overlays/s3ve3g copied over it as CI does
# (scripts/setup.sh): the mainline kernel with the s3ve3g device tree, the device package in
# device/testing, pmaports' archived device package removed. Leaves the main checkout alone.
# Run again after changing the overlays (it copies them anew).
#
# Usage: tools/s3ve3g-pmaports.sh [COMMIT]
#   COMMIT  pmaports commit (default: the one the overlays are based on, see their APKBUILDs)
# Environment: PMAPORTS (the main checkout, default pmbootstrap's), WORKTREE (default
# <PMAPORTS>-s3ve3g)
set -eu

here=$(cd "$(dirname "$0")/.." && pwd)
overlay=$here/overlays/s3ve3g
PMAPORTS=${PMAPORTS:-$HOME/.local/var/pmbootstrap/cache_git/pmaports}
WORKTREE=${WORKTREE:-$PMAPORTS-s3ve3g}
commit=${1:-6b904fc480}

git -C "$PMAPORTS" cat-file -e "$commit^{commit}" 2>/dev/null || git -C "$PMAPORTS" fetch -q origin main
if [ ! -d "$WORKTREE" ]; then
	git -C "$PMAPORTS" worktree add -q --detach "$WORKTREE" "$commit"
else
	git -C "$WORKTREE" checkout -q --detach "$commit"
	git -C "$WORKTREE" reset -q --hard
	git -C "$WORKTREE" clean -qfd
fi
echo "pmaports: $WORKTREE at $(git -C "$WORKTREE" log -1 --format='%h %cs %s')"

(cd "$overlay" && find . -name APKBUILD | sed 's|^\./||; s|/APKBUILD$||') | while read -r dir; do
	(cd "$WORKTREE" && find . -mindepth 2 -maxdepth 3 -type d -name "$(basename "$dir")" \
		! -path "./.git/*" ! -path "./extra-repos/*") | sed 's|^\./||' | while read -r other; do
		[ "$other" = "$dir" ] || { rm -rf "${WORKTREE:?}/$other"; echo "removed $other"; }
	done
	rm -rf "${WORKTREE:?}/$dir"
	mkdir -p "$WORKTREE/$(dirname "$dir")"
	cp -r "$overlay/$dir" "$WORKTREE/$dir"
	echo "overlay: $dir"
done
