#!/bin/sh
# Samsung Galaxy S III Neo: the power key switches the screen off and on. The panel through its
# backlight device (bl_power: display off and sleep in, without DRM master, so also while a Qt
# eglfs application owns the display); the touchscreen inhibited while dark (no events to anyone).
# Run as root (OpenRC service s3ve3g-powerkey); elogind must ignore the key (logind.conf.d).
find_input() {	# input device directory by name
	for d in /sys/class/input/input*; do
		[ "$(cat "$d/name" 2>/dev/null)" = "$1" ] && { echo "$d"; return 0; }
	done
	return 1
}
key=$(find_input pm8941_pwrkey) || { echo "no pm8941_pwrkey"; exit 1; }
touch=$(find_input "MELFAS MMS114 Touchscreen")
ev=/dev/input/$(basename "$key"/event*)
bl=$(ls -d /sys/class/backlight/* | head -n 1)

screen() {	# on|off
	if [ "$1" = off ]; then
		[ -n "$touch" ] && echo 1 > "$touch/inhibited"
		echo 4 > "$bl/bl_power"
	else
		echo 0 > "$bl/bl_power"
		[ -n "$touch" ] && echo 0 > "$touch/inhibited"
	fi
	logger -t s3ve3g-powerkey "screen $1"
}

# struct input_event on armv7: 8 bytes time, u16 type, u16 code, s32 value; EV_KEY 1, KEY_POWER 116
exec 3< "$ev"
while :; do
	set -- $(dd bs=16 count=1 <&3 2>/dev/null | od -An -tu2 -w16)
	[ $# -ge 8 ] || continue
	# fields (u16): time 1-4, type 5, code 6, value 7 (low half)
	[ "$5" = 1 ] && [ "$6" = 116 ] && [ "$7" = 1 ] || continue
	if [ "$(cat "$bl/bl_power")" = 0 ]; then screen off; else screen on; fi
done
