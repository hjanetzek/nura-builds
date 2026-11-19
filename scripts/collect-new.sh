#!/bin/sh
# After a build: the packages it added or changed (compared with fetch-released.sh's list), with
# an index of only those, to publish (publish.sh) or to hand to the next job, in
# $NURA_OUT/new/<name>/: *.apk, APKINDEX.tar.gz (unsigned), plan.json (the plan, for the manifest).
#
# Usage: collect-new.sh NAME [PLAN_JSON]
. "$(dirname "$0")/common.sh"

name=$1
dest="$NURA_OUT/new/$name"
rm -rf "$dest"
mkdir -p "$dest"
dir="$(packages_dir)/edge/$ARCH"
fetched="$NURA_OUT/released/fetched.txt"
[ -f "$fetched" ] || : > "$fetched"
n=0
for f in "$dir"/*.apk; do
	[ -f "$f" ] || continue
	sum=$(sudo sha256sum "$f" | cut -d' ' -f1)
	grep -qx "$sum  $(basename "$f")" "$fetched" && continue
	sudo cp "$f" "$dest/"
	n=$((n + 1))
done
sudo chown -R "$(id -u):$(id -g)" "$dest"
[ -z "${2:-}" ] || cp "$2" "$dest/plan.json"
if [ "$n" -gt 0 ]; then
	python3 "$here/scripts/apkindex.py" filter "$dir/APKINDEX.tar.gz" "$dest/APKINDEX.tar.gz" "$dest"/*.apk
fi
echo "$name: $n new or changed packages in $dest"
