#!/bin/sh
# The end of pmbootstrap's log after a failed build, with its error lines first: apk's errors (an
# install script that failed, "failed to commit ...", "N errors") are often far above the tail,
# which then only shows the summary (systemd 262 vs apk-tools 3.0.10: "2 errors" and nothing else).
# From zynthian-arm7's 0f30c1c.
#
# Usage: show-log.sh [LINES]   (default 200; NURA_WORK: the pmbootstrap work dir)
n=${1:-200}
log=${NURA_WORK:-$HOME/nura-work}/log.txt
cat_log() { sudo cat "$log" 2>/dev/null || cat "$log" 2>/dev/null; }
echo "--- error lines of $log:"
cat_log | grep -nE "ERROR|error:|failed to|script exited|[0-9]+ errors?;" | grep -v "digest-mismatch" | tail -n 60
echo "--- the last $n lines:"
cat_log | tail -n "$n"
exit 0
