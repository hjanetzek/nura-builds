#!/bin/sh
# Build the packages the plan (plan-packages.py --json) lists for a set, one pmbootstrap build each
# in the plan's order (--force where the version is published already), on top of the published
# repository (fetch-released.sh). KEEPGOING (set file): a failure doesn't stop the others; the
# failures are listed in $NURA_OUT/failed-<set>.txt and the run's summary. Recipe directories of
# ADD_ARCH_<arch> get the architecture added to arch= for the build.
#
# Usage: build-set.sh SET PLAN_JSON      (setup.sh and fetch-released.sh first)
. "$(dirname "$0")/common.sh"

set=$1
plan=$2
setfile="$here/sets/$set.sh"
[ -f "$setfile" ] || { echo "no set $set (sets/$set.sh)" >&2; exit 1; }
# Only the set's ADD_ARCH_<arch>, not the target file's (common.sh sources it: recipes of other
# repositories, not checked out for sets)
unset "ADD_ARCH_$ARCH"
KEEPGOING= ; eval "$(sed -n 's/^\(KEEPGOING\|ADD_ARCH_[a-z0-9_]*\)=/\1=/p' "$setfile")"
eval "add_arch=\${ADD_ARCH_$ARCH:-}"
for p in $add_arch; do
	f=$here/$p/APKBUILD
	grep -Eq "^arch=\"(.* )?($ARCH|all)( .*)?\"" "$f" ||
		{ sed -i "s/^arch=\"\(.*\)\"/arch=\"\1 $ARCH\"/" "$f"; echo "$p: $ARCH added to arch="; }
done

failed="$NURA_OUT/failed-$set.txt"
: > "$failed"
python3 -c 'import json,sys; [print(t["pkg"], int(t["force"])) for t in json.load(open(sys.argv[1]))["sets"].get(sys.argv[2], [])]' \
	"$plan" "$set" > "$NURA_OUT/todo-$set.txt"
status=0
while read -r pkg force; do
	[ "$force" = 1 ] && f=--force || f=
	echo "::group::$set: pmbootstrap build $f $pkg"
	if pmb build --arch "$ARCH" $f "$pkg" < /dev/null; then
		echo "::endgroup::"
	else
		echo "::endgroup::"
		echo "$pkg" >> "$failed"
		echo "::warning::$set: $pkg failed on $ARCH"
		# the build's output (the job doesn't fail with KEEPGOING, so the workflow's log step skips it)
		echo "::group::$set: $pkg: the end of pmbootstrap's log"
		sudo tail -n 80 "$NURA_WORK/log.txt" 2>/dev/null || tail -n 80 "$NURA_WORK/log.txt" || true
		echo "::endgroup::"
		[ -n "$KEEPGOING" ] || { status=1; break; }
	fi
done < "$NURA_OUT/todo-$set.txt"

if [ -s "$failed" ]; then
	[ -z "${GITHUB_STEP_SUMMARY:-}" ] || { echo "### $set: failed on $ARCH"; sed 's/^/- /' "$failed"; } >> "$GITHUB_STEP_SUMMARY"
	[ -n "$KEEPGOING" ] || status=1
fi
# Undo the arch additions (the checkout stays as committed)
for p in $add_arch; do git -C "$here" checkout -q -- "$p/APKBUILD" 2>/dev/null || true; done
exit $status
