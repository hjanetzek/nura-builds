#!/bin/sh
# The published package repository of the architecture (release "<arch>", docs/ci-plan.md) into
# the local repository, before a build: pmbootstrap then builds only what is missing or outdated
# (or forced), and the repository the build leaves is the published one plus the new packages.
# Writes $NURA_OUT/released/ (APKINDEX.tar.gz, manifest.json as published; fetched.txt: the
# fetched files with their sha256, for collect-new.sh). Needs gh (GH_TOKEN) and setup.sh before.
#
# Usage: fetch-released.sh [--index-only]   (--index-only: the index and manifest, no packages)
. "$(dirname "$0")/common.sh"

out="$NURA_OUT/released"
rm -rf "$out"
mkdir -p "$out/apk"
repo=${NURA_RELEASE_REPO:-${GITHUB_REPOSITORY:-hjanetzek/nura-builds}}
# NURA_RELEASE_TAG: another release (tests)
tag=${NURA_RELEASE_TAG:-$ARCH}
if ! gh release view "$tag" -R "$repo" >/dev/null 2>&1; then
	echo "no release $tag in $repo yet: starting from an empty repository"
	: > "$out/fetched.txt"
	exit 0
fi
gh release download "$tag" -R "$repo" -D "$out" -p APKINDEX.tar.gz
gh release download "$tag" -R "$repo" -D "$out" -p manifest.json 2>/dev/null ||
	echo '{"packages": {}}' > "$out/manifest.json"
[ "${1:-}" != "--index-only" ] || exit 0

gh release download "$tag" -R "$repo" -D "$out/apk" -p '*.apk'
echo "fetched $(ls "$out/apk" | wc -l) packages ($(du -sh "$out/apk" | cut -f1)) of release $tag"
(cd "$out/apk" && sha256sum -- *.apk) > "$out/fetched.txt"

# Into pmbootstrap's local repository (owned by its build user, as packages it builds itself),
# without replacing files a previous step put there (artifacts of earlier sets of this run)
dir="$(packages_dir)/edge/$ARCH"
sudo mkdir -p "$dir"
sudo cp -n "$out/apk/"*.apk "$dir/"
sudo chown -R 12345:12345 "$(packages_dir)"
rm -rf "$out/apk"
pmb index
