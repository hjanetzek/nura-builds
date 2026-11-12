#!/bin/sh
# Samsung Galaxy S III Neo: the screen on or off. Without a panel driver there is no brightness
# control (the screen is the bootloader's framebuffer, simpledrm); an AMOLED's black pixels are
# off, so "off" detaches the text console from the framebuffer and clears it to black (no burn-in).
# "on" binds the console again (it redraws) and turns console blanking off (DPMS off crashes the
# msm display driver for now; "off" is safe: the console doesn't reach the framebuffer then).
# Programs drawing on the framebuffer themselves
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
	# no console blanking: it would power the display down through DPMS, which crashes msm
	# on MSM8226 so far (and /etc/issue of postmarketos-release sets 5 minutes, ESC[9;5])
	printf '\033[9;0]' > /dev/tty1 2>/dev/null || true
	;;
*)
	echo "usage: s3ve3g-screen on|off" >&2
	exit 1
	;;
esac
