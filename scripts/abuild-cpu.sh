#!/bin/sh
# Write nura-builds' CPU baseline (scripts/abuild-cpu.conf) into a pmbootstrap work dir's
# config_abuild/abuild.conf, between markers: idempotent, the signing key's line stays. Run after
# pmbootstrap init (it may create the file with its own key). Owned by pmbootstrap's build user.
# Usage: abuild-cpu.sh WORKDIR [EXTRA]   (sudo for the file; SUDO= when run as root)
#   EXTRA: more C and C++ flags (a stage's CFLAGS_<stage>[_<arch>], scripts/build.sh); without
#   it the baseline alone
set -eu
conf=$(dirname "$0")/abuild-cpu.conf
f=$1/config_abuild/abuild.conf
SUDO=${SUDO-sudo}
$SUDO mkdir -p "$1/config_abuild"
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
{
	[ -f "$f" ] && $SUDO sed '/^# nura-builds cpu begin$/,/^# nura-builds cpu end$/d' "$f"
	echo "# nura-builds cpu begin"
	cat "$conf"
	if [ -n "${2:-}" ]; then
		echo "# the stage's flags (scripts/build.sh)"
		echo "export CFLAGS=\"\$CFLAGS $2\" CXXFLAGS=\"\$CXXFLAGS $2\""
	fi
	echo "# nura-builds cpu end"
} > "$tmp"
$SUDO cp "$tmp" "$f"
$SUDO chown 12345:12345 "$f" "$1/config_abuild"
echo "abuild CPU baseline: $f"
