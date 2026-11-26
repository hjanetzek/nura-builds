#!/bin/sh
# The Samsung Galaxy S III Neo's session: zynthian (s3ve3g-zynthian, the default) or MicroDexed-touch
# (s3ve3g-mdt). Switches the service started at boot and the running one (one at a time: both need
# the sound card and jackd). Installed as /usr/bin/s3ve3g-session by device-samsung-s3ve3g (OpenRC).
#
# Usage: s3ve3g-session [zynthian | mdt]   (without an argument: which one is set)
set -eu

current() {
	for s in s3ve3g-zynthian s3ve3g-mdt; do
		rc-update show default 2>/dev/null | grep -qw "$s" && echo "${s#s3ve3g-}"
	done
}

case ${1:-} in
	"") echo "session at boot: $(current | tr '\n' ' ')"; exit 0 ;;
	zynthian) want=s3ve3g-zynthian other=s3ve3g-mdt ;;
	mdt) want=s3ve3g-mdt other=s3ve3g-zynthian ;;
	*) echo "usage: $0 [zynthian | mdt]" >&2; exit 1 ;;
esac
[ "$(id -u)" = 0 ] || exec sudo "$0" "$@"

rc-update del "$other" default >/dev/null 2>&1 || true
rc-update add "$want" default >/dev/null
rc-service "$other" stop >/dev/null 2>&1 || true
rc-service "$want" start
echo "session: ${want#s3ve3g-}"
