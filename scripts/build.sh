#!/bin/sh
# Build one stage of the target (targets/<target>.sh: STAGE_<name>), then save the local package
# repository to $NURA_OUT/packages.tar and remove the build chroots (disk space on CI runners).
# The packages are saved also when a build fails (exit status 1): CI caches them as a partial
# result, so the next attempt builds only what is still missing.
#
# Usage: build.sh STAGE      (scripts/setup.sh first)
#        build.sh --hash STAGE   print the hash of the stage's inputs (cache key)
. "$(dirname "$0")/common.sh"

if [ "${1:-}" = "--hash" ]; then
	stage_hash "$2"
	exit 0
fi
stage=$1
eval "builds=\${STAGE_$stage:-}"
# shellcheck disable=SC2154 # set by eval
[ -n "$builds" ] || { echo "no stage $stage in targets/$TARGET.sh" >&2; exit 1; }

eval "seed=\${SEED_$stage:-}"
# shellcheck disable=SC2154
if [ -n "$seed" ]; then
	"$(resolve "$seed")" "$CFG"
fi

status=0
echo "$builds" | tr ';' '\n' | while read -r args; do
	[ -n "$args" ] || continue
	set --
	for a in $args; do
		case $a in
			--src=@*) set -- "$@" "--src=$(resolve "${a#--src=}")" ;;
			*) set -- "$@" "$a" ;;
		esac
	done
	echo "::group::pmbootstrap build $*"
	pmb build --arch "$ARCH" "$@" || exit 1
	echo "::endgroup::"
done || status=1

save_packages
# The build chroots and the HTTP cache, not the packages or distfiles
pmb zap -hc || true
exit $status
