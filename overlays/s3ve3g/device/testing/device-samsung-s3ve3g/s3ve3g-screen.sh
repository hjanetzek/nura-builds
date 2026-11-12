#!/bin/sh
# Samsung Galaxy S III Neo: the screen on or off.
# With the msm display driver (fb0 "msmdrmfb"): DPMS, the panel powered down (display off, sleep in)
# and up again. With the bootloader's framebuffer only (simpledrm, no panel driver): no power
# control, so "off" detaches the text console from the framebuffer and clears it (an AMOLED's black
# pixels are off: no burn-in), "on" binds the console again (it redraws).
# Programs drawing on the framebuffer themselves (buffyboard) keep drawing.
#
# Usage: s3ve3g-screen on|off
set -eu

fbcon() {
	local v
	for v in /sys/class/vtconsole/vtcon*; do
		if grep -q "frame buffer" "$v/name" 2>/dev/null; then
			echo "$1" > "$v/bind"
		fi
	done
}

dpms() {
	[ "$(cat /sys/class/graphics/fb0/name 2>/dev/null)" = msmdrmfb ]
}

case "${1:-}" in
off)
	if dpms; then
		echo 4 > /sys/class/graphics/fb0/blank
		exit 0
	fi
	fbcon 0
	dd if=/dev/zero of=/dev/fb0 bs=1M status=none 2>/dev/null || true
	;;
on)
	if dpms; then
		fbcon 1
		echo 0 > /sys/class/graphics/fb0/blank
		exit 0
	fi
	fbcon 1
	# no console blanking: it would power the display down through DPMS, which crashes msm
	# on MSM8226 so far (and /etc/issue of postmarketos-release sets 5 minutes, ESC[9;5])
	printf '\033[9;0]' > /dev/tty1 2>/dev/null || true
	;;
*)
	echo "usage: s3ve3g-screen on|off" >&2
	exit 1
	;;
esac
