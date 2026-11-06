#!/bin/sh
# Plan a CI run: for each stage of the target (in order), its package cache key and whether its
# job has to run, as GitHub Actions outputs (key_<stage>, run_<stage>, rebuild_<stage>).
#
# A stage is skipped when its packages are in the Actions cache under its exact key and no earlier
# stage runs; after a stage that runs, the later ones run too (their cached packages are merged with
# the new ones, see merge-cached.sh). With REBUILD=true the stages in REBUILD_STAGES (target file)
# run from scratch. Stages without INPUTS_<stage>, or with inputs from other repositories (@repo),
# always run. The key is the one stage.yml uses:
#   packages-<target>-<stage>-<signing key>-<previous stage's key>-<this stage's hash>
#
# Environment: NURA_ABUILD_KEY, REBUILD, GH_TOKEN/GH_REPO (gh cache list; actions: read);
# NURA_PLAN_OFFLINE=1: don't ask GitHub (every cacheable stage counts as cached).
. "$(dirname "$0")/common.sh"

out=${GITHUB_OUTPUT:-/dev/stdout}
kfp=$(printf '%s\n' "${NURA_ABUILD_KEY:-}" | openssl rsa -pubout 2>/dev/null | sha256sum | cut -c1-8)

cached() {
	[ -z "${NURA_PLAN_OFFLINE:-}" ] || return 0
	gh cache list --key "$1" --limit 100 --json key --jq '.[].key' | grep -qxF "$1"
}

prev_key=
running=false
for stage in $STAGES; do
	eval "inputs=\${INPUTS_$stage:-}"
	# shellcheck disable=SC2154 # set by eval
	if [ -n "$inputs" ] && ! echo "$inputs" | grep -q '@'; then
		prev=$(echo "$prev_key" | sha256sum | cut -c1-8)
		key="packages-$TARGET-$stage-$kfp-$prev-$(stage_hash "$stage")"
	else
		key=
	fi
	rebuild=false
	case " ${REBUILD_STAGES:-} " in
		*" $stage "*) [ "${REBUILD:-false}" != true ] || rebuild=true ;;
	esac
	if [ -z "$key" ]; then
		run=true why="not cacheable"
	elif [ $rebuild = true ]; then
		run=true why="rebuild"
	elif [ $running = true ]; then
		run=true why="an earlier stage runs"
	elif cached "$key"; then
		run=false why="cached"
	else
		run=true why="not cached"
	fi
	[ $run = false ] || running=true
	echo "$stage: $([ $run = true ] && echo run || echo skip) ($why) $key" >&2
	{
		echo "key_$stage=$key"
		echo "run_$stage=$run"
		echo "rebuild_$stage=$rebuild"
	} >> "$out"
	prev_key=$key
done
