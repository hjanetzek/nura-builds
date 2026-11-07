#!/bin/sh
# Move a zynthian-ui-<branch> recipe (aports/zynthian-upstream) to a newer upstream commit: apply its
# port patches there (git am -3), write them back (git format-patch), set _commit, pkgver and the
# checksums. On a conflict it stops in the work tree; resolve, "git am --continue", run it again
# with -k (keep the work tree).
#
# Usage: tools/update-zynthian-upstream.sh [-k] BRANCH [COMMIT]
#   BRANCH  vangelis or tomita (the recipe zynthian-ui-BRANCH)
#   COMMIT  upstream commit (default: the branch's head on github.com/zynthian/zynthian-ui)
#   -k      continue in the existing work tree (after resolving a conflict)
# Work tree: ${TMPDIR:-/tmp}/zynthian-upstream-BRANCH. Needs git, curl, sha512sum.
set -eu

keep=0
[ "${1:-}" = -k ] && { keep=1; shift; }
branch=${1:?usage: $0 [-k] BRANCH [COMMIT]}
here=$(cd "$(dirname "$0")/.." && pwd)
aport=$here/aports/zynthian-upstream/zynthian-ui-$branch
[ -f "$aport/APKBUILD" ] || { echo "no recipe $aport" >&2; exit 1; }
work=${TMPDIR:-/tmp}/zynthian-upstream-$branch
url=https://github.com/zynthian/zynthian-ui

if [ $keep = 0 ]; then
	rm -rf "$work"
	git clone -q --filter=blob:none --branch "$branch" "$url" "$work"
	commit=$(git -C "$work" rev-parse "${2:-HEAD}")
	git -C "$work" checkout -q --detach "$commit"
	git -C "$work" tag nura-base
	git -C "$work" -c user.name=nura-builds -c user.email=nura-builds@localhost \
		am -q -3 --committer-date-is-author-date "$aport"/*.patch || {
		echo "conflict: resolve in $work, git am --continue, then: $0 -k $branch" >&2
		exit 1
	}
else
	commit=$(git -C "$work" rev-parse nura-base)
fi

rm -f "$aport"/*.patch
git -C "$work" format-patch -q --no-signature --zero-commit --no-numbered nura-base..HEAD -o "$aport"

date=$(git -C "$work" show -s --format=%cd --date=format:%Y%m%d "$commit")
tarball=zynthian-ui-$commit.tar.gz
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
curl -fsSL -o "$tmp/$tarball" "$url/archive/$commit.tar.gz"

old=$(sed -n 's/^_commit=//p' "$aport/APKBUILD")
# Patch list in source=, checksums: the tarball, the Python files (unchanged), the patches
awk -v patches="$(cd "$aport" && ls ./*.patch | sed 's|^\./||')" '
	/^\t[^\t]*\.patch$/ { next }
	/^source="/ { insrc = 1 }
	insrc && /^\t"$/ { n = split(patches, p, "\n"); for (i = 1; i <= n; i++) print "\t" p[i]; insrc = 0 }
	/^sha512sums="/ { print; insum = 1; next }
	insum && /\.patch$/ { next }
	insum && /\.tar\.gz$/ && /zynthian-ui-/ { next }
	insum && /^"$/ { insum = 0 }
	{ print }
' "$aport/APKBUILD" > "$tmp/APKBUILD"
sed -i -e "s/^_commit=.*/_commit=$commit/" -e "s/^pkgver=.*/pkgver=0_git$date/" \
	-e "s/^pkgrel=.*/pkgrel=0/" "$tmp/APKBUILD"
{
	sed '/^sha512sums="/,$d' "$tmp/APKBUILD"
	echo 'sha512sums="'
	(cd "$tmp" && sha512sum "$tarball")
	sed -n '/^sha512sums="/,/^"$/{/^sha512sums="/d;/^"$/d;p}' "$tmp/APKBUILD"
	(cd "$aport" && sha512sum ./*.patch | sed 's|  \./|  |')
	echo '"'
} > "$aport/APKBUILD"

echo "zynthian-ui-$branch: $old -> $commit ($(ls "$aport"/*.patch | wc -l) patches)"
