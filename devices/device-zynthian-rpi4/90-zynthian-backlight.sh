#!/bin/sh
# initramfs hook (after the splash started): the kit panel's backlight on, so the boot animation is
# visible. The ZynScreen's gpio-backlight (piscreen2r-backlight) comes up powered down: the fbtft
# framebuffer can't unblank, and the text console is kept off the panel (fbcon=map:22). In the root
# filesystem 92-zynthian-backlight.rules does the same.
for b in /sys/class/backlight/*; do
	[ -e "$b/bl_power" ] && echo 0 > "$b/bl_power"
done
exit 0
