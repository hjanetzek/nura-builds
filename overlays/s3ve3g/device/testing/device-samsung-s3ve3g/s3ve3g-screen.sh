#!/bin/sh
# Samsung Galaxy S III Neo: the screen on or off. Without a panel driver there is no brightness
# control (the screen is the bootloader's framebuffer, simpledrm); an AMOLED's black pixels are
# off, so "off" detaches the text console from the framebuffer and clears it to black (no burn-in).
# "on" binds the console again (it redraws). Programs drawing on the framebuffer themselves
# (buffyboard) keep drawing.
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

case "${1:-}" in
off)
	fbcon 0
	dd if=/dev/zero of=/dev/fb0 bs=1M status=none 2>/dev/null || true
	;;
on)
	fbcon 1
	;;
*)
	echo "usage: s3ve3g-screen on|off" >&2
	exit 1
	;;
esac
