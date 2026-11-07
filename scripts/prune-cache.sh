#!/bin/sh
# Delete a stage's older cache entries after it saved its packages (stage.yml), so the repository
# stays under GitHub's 10 GB cache limit: entries are never overwritten, each change of a stage's
# inputs saves a new one (1-2 GB each, they hold the earlier stages' packages too), and only the
# newest is ever restored (the exact key, or the partial prefix: restore-keys picks the newest).
#
# Usage: scripts/prune-cache.sh KEEP_KEY
#   KEEP_KEY  the key the stage just saved (packages-<target>-<stage>-<signing key>-...)
# Deletes the entries of the same target and stage on the same branch (GITHUB_REF): older keys
# and the partial caches of failed attempts. Entries of other branches stay: a branch run can't
# restore main's entries anyway, but deleting them would cost main a full rebuild.
# Needs gh with GH_TOKEN (actions: write) and GH_REPO.
set -eu

keep=${1:?usage: $0 KEEP_KEY}
ref=${GITHUB_REF:?GITHUB_REF not set}
# packages-<target>-<stage>-: target and stage names contain no "-"
prefix=$(echo "$keep" | cut -d- -f1-3)-

gh cache list --ref "$ref" --key "$prefix" --limit 100 --json key --jq '.[].key' |
	while read -r key; do
		[ "$key" = "$keep" ] && continue
		echo "deleting cache $key"
		gh cache delete "$key" || echo "can't delete $key"
	done
