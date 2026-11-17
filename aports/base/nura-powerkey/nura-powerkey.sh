#!/bin/sh
# The power key switches the screen off and on, for phones and tablets running zynthian (or any
# full-screen application) without a desktop: the panel through its backlight device (bl_power:
# display off, without DRM master, so also while the application owns the display), the
# touchscreen inhibited while dark (no events to anyone). From the Galaxy S III Neo's handler
# (device-samsung-s3ve3g), with the devices found by their capabilities:
# - power key: the first input device with KEY_POWER (code 116), devices named like a power button
#   (pwrkey, power, button) first, so that a keyboard with a power key isn't taken
# - touchscreen: input devices with INPUT_PROP_DIRECT
# - backlight: the first in /sys/class/backlight
# Overrides in /etc/default/nura-powerkey: POWERKEY_NAME, TOUCH_NAMES (|-separated), BACKLIGHT.
# Run as root (systemd: nura-powerkey.service; OpenRC: nura-powerkey); logind/elogind must ignore
# the key (logind.conf.d/50-nura-powerkey.conf).
[ -f /etc/default/nura-powerkey ] && . /etc/default/nura-powerkey

has_key_power() {	# input device dir: KEY_POWER in capabilities/key (64-bit words, highest first)
	set -- $(cat "$1/capabilities/key" 2>/dev/null)
	[ $# -ge 2 ] || return 1
	shift $(($# - 2))
	[ $(( 0x$1 >> 52 & 1 )) = 1 ]	# bit 116 = bit 52 of the second-lowest word
}

find_powerkey() {
	for d in /sys/class/input/input*; do
		n=$(cat "$d/name" 2>/dev/null)
		if [ -n "${POWERKEY_NAME:-}" ]; then
			[ "$n" = "$POWERKEY_NAME" ] && { echo "$d"; return 0; }
			continue
		fi
		case "$n" in *[Pp]wr*|*[Pp]ower*|*[Bb]utton*) has_key_power "$d" && { echo "$d"; return 0; } ;; esac
	done
	[ -n "${POWERKEY_NAME:-}" ] && return 1
	for d in /sys/class/input/input*; do
		has_key_power "$d" && { echo "$d"; return 0; }
	done
	return 1
}

find_touch() {
	for d in /sys/class/input/input*; do
		n=$(cat "$d/name" 2>/dev/null)
		if [ -n "${TOUCH_NAMES:-}" ]; then
			echo "|$TOUCH_NAMES|" | grep -qF "|$n|" && echo "$d"
		elif [ $(( 0x$(cat "$d/properties" 2>/dev/null || echo 0) & 2 )) = 2 ]; then
			echo "$d"
		fi
	done
}

key=$(find_powerkey) || { echo "nura-powerkey: no power key found" >&2; exit 1; }
touch=$(find_touch)
bl=${BACKLIGHT:-$(ls -d /sys/class/backlight/* 2>/dev/null | head -n 1)}
[ -n "$bl" ] && [ -e "$bl/bl_power" ] || { echo "nura-powerkey: no backlight" >&2; exit 1; }
ev=/dev/input/$(basename "$key"/event*)
logger -t nura-powerkey "key $(cat "$key/name") ($ev), backlight $bl, touch: $(for t in $touch; do cat "$t/name"; done | tr '\n' ',')"

screen() {	# on|off
	if [ "$1" = off ]; then
		for t in $touch; do echo 1 > "$t/inhibited"; done
		echo 4 > "$bl/bl_power"
	else
		echo 0 > "$bl/bl_power"
		for t in $touch; do echo 0 > "$t/inhibited"; done
	fi
	logger -t nura-powerkey "screen $1"
}

# struct input_event: struct timeval (2 longs), u16 type, u16 code, s32 value: 24 bytes on 64-bit,
# 16 on 32-bit; read as u16 words: type, code and the low half of value follow the time
if [ "$(getconf LONG_BIT 2>/dev/null || echo 32)" = 64 ]; then size=24 t=9; else size=16 t=5; fi
exec 3< "$ev"
while :; do
	set -- $(dd bs=$size count=1 <&3 2>/dev/null | od -An -tu2 -w$size)
	[ $# -ge $((t + 2)) ] || continue
	shift $((t - 1))
	# EV_KEY 1, KEY_POWER 116, press 1
	[ "$1" = 1 ] && [ "$2" = 116 ] && [ "$3" = 1 ] || continue
	if [ "$(cat "$bl/bl_power")" = 0 ]; then screen off; else screen on; fi
done
