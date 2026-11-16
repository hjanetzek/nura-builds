#!/bin/sh
# Publish packages and images as GitHub releases of this repository (gh, GH_TOKEN with
# contents: write), docs/ci-plan.md:
#
# - the package repository: release "<arch>" (NURA_ARCH: aarch64, default, x86_64, armv7). apk
#   asks for <repository>/<arch>/APKINDEX.tar.gz, and release files are at
#   .../releases/download/<tag>/<file>, so with the architecture as the tag the repository is
#   https://github.com/<owner>/<repo>/releases/download, the same for all architectures.
#   Merged, not replaced: the published index (fetched now, not at the build's start) keeps every
#   package this publication doesn't bring; a package it brings replaces the published one of the
#   same name. Several workflows publish to the same release, so callers serialize this per
#   architecture (concurrency group publish-<arch>). Order: the new packages, then the index, then
#   the manifest, then the files the index no longer has (the published index never points to a
#   missing file). The index is signed with the CI key (NURA_ABUILD_KEY, NURA_ABUILD_KEY_NAME).
# - manifest.json in the same release: per package the recipe hash, version and set (or target)
#   it was built for (plan-packages.py: what has to be rebuilt), and when and by which run.
# - images: release "<target>-latest" (NURA_IMAGE_TAG), the images replaced by each build.
#
# Usage: publish.sh TARGET NEW_DIR... [-- IMAGE...]
#   NEW_DIR: collect-new.sh's directories (*.apk, APKINDEX.tar.gz of those, plan.json)
set -eu

here=$(cd "$(dirname "$0")/.." && pwd)
target=$1
shift
dirs=
while [ $# -gt 0 ] && [ "$1" != "--" ]; do
	dirs="$dirs $1"
	shift
done
[ "${1:-}" != "--" ] || shift
arch=${NURA_ARCH:-aarch64}
# NURA_RELEASE_TAG: another release (tests)
repo_tag=${NURA_RELEASE_TAG:-$arch}
image_tag=${NURA_IMAGE_TAG:-$target-latest}
run_url="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-}/actions/runs/${GITHUB_RUN_ID:-}"
repository_url="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-}/releases/download"
apkindex="python3 $here/scripts/apkindex.py"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

notes="Package repository of nura-builds ($arch, Nura edge), signed with keys/nura-builds-ci.rsa.pub.

On a device (as root):

    wget -O /etc/apk/keys/nura-builds-ci.rsa.pub https://raw.githubusercontent.com/${GITHUB_REPOSITORY:-}/main/keys/nura-builds-ci.rsa.pub
    echo $repository_url >> /etc/apk/repositories
    apk update && apk upgrade

manifest.json: how each package was built (recipe hash, set or target, run).

Updated by $run_url"

# The new packages of all directories, with one index of them
mkdir -p "$tmp/new"
newindex=
plans=
for d in $dirs; do
	[ -f "$d/plan.json" ] && plans="$plans $d/plan.json"
	[ -f "$d/APKINDEX.tar.gz" ] || continue
	cp "$d"/*.apk "$tmp/new/"
	if [ -z "$newindex" ]; then
		newindex=$tmp/new.tar.gz
		cp "$d/APKINDEX.tar.gz" "$newindex"
	else
		$apkindex merge "$tmp/new2.tar.gz" "$newindex" "$d/APKINDEX.tar.gz" >/dev/null
		mv "$tmp/new2.tar.gz" "$newindex"
	fi
done
count=$(find "$tmp/new" -name '*.apk' | wc -l)
echo "publishing $count new or changed packages to release $repo_tag"

if [ "$count" -gt 0 ] || [ -n "$plans" ]; then
	gh release view "$repo_tag" >/dev/null 2>&1 ||
		gh release create "$repo_tag" --prerelease --title "Package repository ($arch)" --notes "$notes"
	# The published state, now (another workflow may have published since this build started)
	base=-
	if gh release download "$repo_tag" -D "$tmp/pub" -p APKINDEX.tar.gz 2>/dev/null; then
		base=$tmp/pub/APKINDEX.tar.gz
	fi
	gh release download "$repo_tag" -D "$tmp/pub" -p manifest.json 2>/dev/null ||
		echo '{"packages": {}}' > "$tmp/manifest.json.pub"
	[ -f "$tmp/pub/manifest.json" ] && mv "$tmp/pub/manifest.json" "$tmp/manifest.json.pub"

	release_id=$(gh api "repos/{owner}/{repo}/releases/tags/$repo_tag" --jq .id)
	assets=$(gh api "repos/{owner}/{repo}/releases/$release_id/assets?per_page=100" --paginate \
		--jq '.[] | "\(.name) \(.digest // "")"')

	if [ "$count" -gt 0 ]; then
		# Signing key for the index
		key=$tmp/key.rsa
		( umask 077; printf '%s\n' "${NURA_ABUILD_KEY:?NURA_ABUILD_KEY is not set}" > "$key" )
		$apkindex merge "$tmp/APKINDEX.tar.gz" "$base" "$newindex" \
			--key "$key" --key-name "${NURA_ABUILD_KEY_NAME:?}" --description "nura-builds $arch"
		rm -f "$key"

		# Upload what the release doesn't have as the same file (a rebuild with the same version is
		# another file under the same name: the index has its checksum, so the old one must go)
		new=
		for f in "$tmp/new"/*.apk; do
			sum="sha256:$(sha256sum "$f" | cut -d' ' -f1)"
			echo "$assets" | grep -qxF "$(basename "$f") $sum" || new="$new $f"
		done
		# shellcheck disable=SC2086 # a list of files
		[ -z "$new" ] || { echo "uploading$(echo $new | wc -w | sed 's/^/ /') packages"; gh release upload "$repo_tag" $new --clobber; }
		gh release upload "$repo_tag" "$tmp/APKINDEX.tar.gz" --clobber
	fi

	# The manifest: the built packages' entries (those now in the index), the adopted ones
	HERE=$here python3 - "$tmp/manifest.json.pub" "$tmp/manifest.json" "$run_url" "$target" "${newindex:--}" $plans <<'PY'
import datetime, json, os, sys
sys.path.insert(0, os.path.join(os.environ.get("HERE", "."), "scripts"))
pub, out, run, target, newindex, plans = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5], sys.argv[6:]
m = json.load(open(pub))
pk = m.setdefault("packages", {})
built = set()
if newindex != "-":
    import apkindex
    for b in apkindex.read_index(newindex)[1]:
        built.add(apkindex.field(b, "o") or apkindex.field(b, "P"))
now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%MZ")
n = a = 0
for p in plans:
    plan = json.load(open(p))
    for pkg, e in plan.get("hashes", {}).items():
        if pkg in built:
            pk[pkg] = dict(e, run=run, date=now, by=target)
            n += 1
    for pkg, e in plan.get("adopt", {}).items():
        if pkg not in pk:
            pk[pkg] = dict(e, run=None, date=now, by="adopted")
            a += 1
json.dump(m, open(out, "w"), indent=1, sort_keys=True)
print(f"manifest: {n} built, {a} adopted, {len(pk)} entries")
PY
	gh release upload "$repo_tag" "$tmp/manifest.json" --clobber

	# Files the index no longer has (replaced versions)
	if [ "$count" -gt 0 ]; then
		$apkindex list "$tmp/APKINDEX.tar.gz" | cut -d' ' -f3 > "$tmp/indexed.txt"
		echo "$assets" | while read -r name _; do
			case $name in *.apk) ;; *) continue ;; esac
			grep -qxF "$name" "$tmp/indexed.txt" || { echo "deleting $name"; gh release delete-asset "$repo_tag" "$name" -y; }
		done
	fi
	gh release edit "$repo_tag" --notes "$notes"
fi

# Images
[ $# -gt 0 ] || exit 0
image_notes="$target images built by nura-builds ($run_url). Write to a USB stick or SD card:
zstd -d < <file>.img.zst | sudo dd of=/dev/sdX bs=4M status=progress
Packages for updates: release \"$repo_tag\" (see its notes)."
gh release view "$image_tag" >/dev/null 2>&1 ||
	gh release create "$image_tag" --title "$target (latest build)" --notes "$image_notes"
gh release upload "$image_tag" "$@" --clobber
gh release edit "$image_tag" --notes "$image_notes"
