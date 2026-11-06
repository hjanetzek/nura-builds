#!/bin/sh
# Publish a build as GitHub releases of this repository (gh, GH_TOKEN with contents: write):
#
# - the package repository: release "aarch64". apk asks for <repository>/aarch64/APKINDEX.tar.gz,
#   and release files are at .../releases/download/<tag>/<file>, so with the tag "aarch64" the
#   repository is https://github.com/<owner>/<repo>/releases/download. Uploads the packages the
#   release doesn't have yet or has as another file (same version, rebuilt), then the index, then deletes packages the index no longer has (in
#   that order, so the published index never points to a missing file).
# - images: release "<target>-latest", the images replaced by each build.
#
# Usage: publish.sh TARGET PACKAGES_TAR [IMAGE...]
set -eu

target=$1
tar=$2
shift 2
repo_tag=aarch64
image_tag=$target-latest
run_url="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-}/actions/runs/${GITHUB_RUN_ID:-}"
repository_url="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-}/releases/download"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Packages of the local repository (packages/<channel>/aarch64/)
tar -C "$tmp" -xf "$tar" --wildcards --no-anchored "*/aarch64/*.apk" "*/aarch64/APKINDEX.tar.gz"
dir=$(dirname "$(find "$tmp" -name APKINDEX.tar.gz | head -n 1)")
[ -f "$dir/APKINDEX.tar.gz" ] || { echo "no APKINDEX.tar.gz in $tar" >&2; exit 1; }
echo "packages: $(find "$dir" -name '*.apk' | wc -l) in $dir"

notes="Package repository of nura-builds (aarch64, Nura edge), signed with keys/nura-builds-ci.rsa.pub.

On a device (as root):

    wget -O /etc/apk/keys/nura-builds-ci.rsa.pub https://raw.githubusercontent.com/${GITHUB_REPOSITORY:-}/main/keys/nura-builds-ci.rsa.pub
    echo $repository_url >> /etc/apk/repositories
    apk update && apk upgrade

Updated by $run_url"
gh release view "$repo_tag" >/dev/null 2>&1 ||
	gh release create "$repo_tag" --prerelease --title "Package repository (aarch64)" --notes "$notes"

# Published packages with their sha256 ("name sha256:..."). A package rebuilt with the same version
# (the zynthian stage rebuilds the kiosk package every run; full rebuilds after cache changes) is
# another file under the same name: the index has its checksum, so the old file must be replaced,
# or apk fails with "package integrity error".
release_id=$(gh api "repos/{owner}/{repo}/releases/tags/$repo_tag" --jq .id)
assets=$(gh api "repos/{owner}/{repo}/releases/$release_id/assets?per_page=100" --paginate \
	--jq '.[] | "\(.name) \(.digest // "")"')
new=
for f in "$dir"/*.apk; do
	name=$(basename "$f")
	sum="sha256:$(sha256sum "$f" | cut -d' ' -f1)"
	echo "$assets" | grep -qxF "$name $sum" || new="$new $f"
done
# In a function: its own positional parameters (the script's are the images)
upload_packages() {
	echo "uploading $# new or changed packages"
	gh release upload "$repo_tag" "$@" --clobber
}
# shellcheck disable=SC2086 # a list of files
[ -z "$new" ] || upload_packages $new
gh release upload "$repo_tag" "$dir/APKINDEX.tar.gz" --clobber
echo "$assets" | while read -r name _; do
	case $name in *.apk) ;; *) continue ;; esac
	[ -f "$dir/$name" ] || { echo "deleting $name"; gh release delete-asset "$repo_tag" "$name" -y; }
done
gh release edit "$repo_tag" --notes "$notes"

# Images
[ $# -gt 0 ] || exit 0
image_notes="$target images built by nura-builds ($run_url). Write to a USB stick or SD card:
zstd -d < <file>.img.zst | sudo dd of=/dev/sdX bs=4M status=progress
Packages for updates: release \"$repo_tag\" (see its notes)."
gh release view "$image_tag" >/dev/null 2>&1 ||
	gh release create "$image_tag" --title "$target (latest build)" --notes "$image_notes"
gh release upload "$image_tag" "$@" --clobber
gh release edit "$image_tag" --notes "$image_notes"
