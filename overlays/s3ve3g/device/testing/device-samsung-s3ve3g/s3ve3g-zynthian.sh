#!/bin/sh
# zynthian's Qt UI full-screen on the Samsung Galaxy S III Neo without a compositor (Qt's eglfs on
# KMS), with JACK on the phone's sound card, as the logged-in user (groups video, input, audio; the
# audio group's real-time limits). Installed as /usr/bin/s3ve3g-zynthian by device-samsung-s3ve3g,
# started at boot by its service s3ve3g-zynthian (OpenRC; systemd unit too); by hand:
# "rc-service s3ve3g-zynthian restart" (running this directly next to the service, the two fight).
#
# - waits for the boot splash to end (plymouthd holds DRM master until OpenRC's plymouth plugin
#   quits it at the end of the default runlevel)
# - zynthian's engine list rescanned when LV2 plugins were added or removed since (or zynthian's
#   defaults changed): zynthian enables new plugins only through that rescan ("zynthian_lv2.py
#   engines", which merges zynthian-sys's default engine config; upstream's update script runs
#   it), otherwise installed plugins stay disabled; ~10 s
# - stops a running zynthian first (zynthian_desktop.sh restarts zynthian when it exits, so the
#   launcher before its zynthian; two instances compete for DRM master and JACK)
# - JACK: /usr/share/s3ve3g/jack.sh (shared with s3ve3g-mdt): an already running jackd is kept,
#   otherwise jackd on the card "Neo", 48 kHz, JACK_PERIOD frames (default 480), restarted when its
#   ALSA driver doesn't come up
# - ZYNTHIAN_UI=qt: the Qt UI (without it zynthian_desktop.sh starts the Tk UI through XWayland)
# - eglfs_kms on the GPU's DRM device (/tmp/kms.json: { "device": "/dev/dri/card1" })
# - landscape by ZYNTHIAN_UI_ROTATION=90 (zynthian-ui 780cf605: the UI rotated in QML; eglfs doesn't
#   rotate Qt Quick, the MDP planes can't rotate by 90); scale 1.5: 853x480 logical pixels
# - touch through Qt's evdevtouch (QT_QPA_EGLFS_NO_LIBINPUT=1): raw panel coordinates, which the QML
#   rotation maps; libinput would apply the udev calibration matrix meant for cage
# - FD_MESA_DEBUG=inorder by default (FD_MESA_DEBUG= in the environment turns it off): even with
#   Mesa 26.2.6-r1 (the freedreno a3xx flicker fix, nura-builds armv7 repository) zynthian's UI
#   shows glitches on 6.16.12 and 7.3.4 alike, gone with inorder (no reordering/staging of busy
#   buffers in freedreno); a Mesa problem, not the kernel's
# Logs: /tmp/zyn-eglfs.log, /tmp/jackd.log
# The boot splash first: plymouthd keeps DRM master until it quits. Told to quit (keeping its last
# picture until zynthian draws) instead of waiting for OpenRC to quit it at the end of the boot
# (1.6 s on a boot); then waited for, at most 60 s
if pgrep -x plymouthd >/dev/null; then
	sudo -n plymouth quit --retain-splash >/dev/null 2>&1 || true
fi
i=0
while pgrep -x plymouthd >/dev/null && [ $i -lt 600 ]; do
	sleep 0.1; i=$((i + 1))
done

# A running zynthian: the launchers first (process name zynthian_deskto), then zynthian itself
for p in $(pgrep -x zynthian_deskto); do kill "$p"; done
for p in $(pgrep -x python3); do
	grep -q zynthian_qt_main "/proc/$p/cmdline" 2>/dev/null && kill "$p"
done
for p in $(pgrep -x aeolus); do kill "$p"; done
# Until the old zynthian has closed the display: the kernel makes only the first client of a DRM
# device without a master its master (the new zynthian otherwise gets "Could not set DRM mode ...
# Permission denied" and shows nothing); the user's own processes' descriptors are readable
i=0
while [ $i -lt 30 ]; do
	busy=
	for fd in /proc/[0-9]*/fd/*; do
		[ "$(readlink "$fd" 2>/dev/null)" = /dev/dri/card1 ] && { busy=1; break; }
	done
	[ -z "$busy" ] && break
	sleep 0.5; i=$((i + 1))
done

# The engine list: rescanned when a plugin directory or zynthian's defaults are newer than it
zdir=${ZYNTHIAN_DIR:-/usr/share/zynthian}
engines="${XDG_CONFIG_HOME:-$HOME/.config}/zynthian/engine_config.json"
rescan=
[ -f "$engines" ] || rescan=1
for d in /usr/lib/lv2 "${XDG_DATA_HOME:-$HOME/.local/share}/zynthian/plugins/lv2" \
		"$zdir/zynthian-sys/config/engine_config.json"; do
	[ -e "$d" ] && [ "$d" -nt "$engines" ] && rescan=1
done
if [ -n "$rescan" ]; then
	echo "rescanning zynthian's engines (LV2 plugins changed)" >&2
	# with zynthian's environment (ZYNTHIAN_CONFIG_DIR, ZYNTHIAN_SYS_DIR, ...: zynthian-ui's
	# desktop/zynthian_desktop_env.sh, as zynthian_desktop.sh sets it; bash): without it
	# zynthian_lv2.py looks in /zynthian/... and writes no engine list
	(cd "$zdir/zynthian-ui" && PYTHONPATH="$zdir/python${PYTHONPATH:+:$PYTHONPATH}" \
		bash -c '. desktop/zynthian_desktop_env.sh && exec python3 zyngine/zynthian_lv2.py engines' \
		> /tmp/zyn-rescan.log 2>&1) ||
		echo "rescan failed, see /tmp/zyn-rescan.log" >&2
fi

# JACK on the phone's card (shared with s3ve3g-mdt)
. /usr/share/s3ve3g/jack.sh
s3ve3g_jack_start || exit 1

[ -f /tmp/kms.json ] || echo '{ "device": "/dev/dri/card1" }' > /tmp/kms.json
export ZYNTHIAN_UI=qt ZYNTHIAN_FULLSCREEN=1 ZYNTHIAN_UI_SCALE=auto ZYNTHIAN_UI_ROTATION=${ZYNTHIAN_UI_ROTATION:-90}
export QT_QPA_PLATFORM=eglfs QT_QPA_EGLFS_INTEGRATION=eglfs_kms QT_QPA_EGLFS_KMS_CONFIG=/tmp/kms.json
export QT_QPA_EGLFS_NO_LIBINPUT=1 QT_SCALE_FACTOR=${QT_SCALE_FACTOR:-1.5} QT_QPA_EGLFS_HIDECURSOR=1
export FD_MESA_DEBUG=${FD_MESA_DEBUG-inorder}
exec zynthian > /tmp/zyn-eglfs.log 2>&1
