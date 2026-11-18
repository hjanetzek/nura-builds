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
# - JACK: an already running jackd is kept; otherwise jackd on the card "Neo" (WCD9306), 48 kHz,
#   JACK_PERIOD frames (default 480: q6asm takes multiples of 480 (10 ms) since 6.18; 256 gave xruns on 6.16), 2 periods, 16 bit,
#   real-time priority 70; the dummy backend without the card. Alpine's jackd 1.9.22 on armv7 reads
#   option values only when attached (-r48000; "-r 48000" gives 0 Hz), and needs
#   JACK_NO_AUDIO_RESERVATION=1 without a D-Bus session. The output (speaker or headphones):
#   s3ve3g-audio restore, if installed and sudo allows it without a password.
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
# - jackd is checked and started again when its ALSA driver doesn't come up: on 7.3.4 the first
#   start after boot can fail ("could not start playback (Broken pipe)", q6asm "Error queuing
#   playback buffer -11"); jackd then keeps running without a driver and refuses clients
# Logs: /tmp/zyn-eglfs.log, /tmp/jackd.log
period=${JACK_PERIOD:-480}

# The boot splash first: plymouthd keeps DRM master until it quits (up to 60 s)
i=0
while pgrep -x plymouthd >/dev/null && [ $i -lt 120 ]; do
	sleep 0.5; i=$((i + 1))
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
	(cd "$zdir/zynthian-ui" && PYTHONPATH="$zdir/python${PYTHONPATH:+:$PYTHONPATH}" \
		python3 zyngine/zynthian_lv2.py engines > /tmp/zyn-rescan.log 2>&1) ||
		echo "rescan failed, see /tmp/zyn-rescan.log" >&2
fi

# A jackd whose driver failed (see above) is no use: stopped, and started again below
jack_failed() {
	grep -qE "could not start playback|Cannot initialize driver|Driver is not running" /tmp/jackd.log 2>/dev/null
}
if pgrep -x jackd >/dev/null && jack_failed; then
	for p in $(pgrep -x jackd); do kill "$p"; done
	sleep 2
fi

# Until the new jackd serves clients (its socket in /dev/shm and, with the ALSA driver, the driver
# configured: "ALSA: use N periods for playback" in its log) or its driver failed, at most 5 s;
# instead of a fixed 3 s (Alpine's jack has no jack_wait: no example clients)
jack_wait_ready() {
	local i=0 sock="/dev/shm/jack_default_$(id -u)_0"
	while [ $i -lt 50 ]; do
		jack_failed && return
		if [ -S "$sock" ] && pgrep -x jackd >/dev/null; then
			grep -q "ALSA: use .* periods for playback" /tmp/jackd.log 2>/dev/null && return
			grep -q "creating alsa driver" /tmp/jackd.log 2>/dev/null || return   # the dummy driver
		fi
		sleep 0.1
		i=$((i + 1))
	done
}

try=0
while ! pgrep -x jackd >/dev/null; do
	try=$((try + 1))
	[ $try -le 3 ] || { echo "jackd didn't start, see /tmp/jackd.log" >&2; exit 1; }
	if [ -e /proc/asound/Neo ]; then
		if command -v s3ve3g-audio >/dev/null; then
			sudo -n s3ve3g-audio restore >/dev/null 2>&1 || true
		fi
		JACK_NO_AUDIO_RESERVATION=1 jackd -R -P70 -d alsa -d hw:CARD=Neo,0 -r48000 "-p$period" -n2 -S -P \
			> /tmp/jackd.log 2>&1 &
	else
		jackd -R -d dummy -r48000 "-p$period" > /tmp/jackd.log 2>&1 &
	fi
	jack_wait_ready
	if jack_failed; then
		echo "jackd's driver didn't start (try $try), starting it again" >&2
		for p in $(pgrep -x jackd); do kill "$p"; done
		sleep 2
	fi
done

[ -f /tmp/kms.json ] || echo '{ "device": "/dev/dri/card1" }' > /tmp/kms.json
export ZYNTHIAN_UI=qt ZYNTHIAN_FULLSCREEN=1 ZYNTHIAN_UI_SCALE=auto ZYNTHIAN_UI_ROTATION=${ZYNTHIAN_UI_ROTATION:-90}
export QT_QPA_PLATFORM=eglfs QT_QPA_EGLFS_INTEGRATION=eglfs_kms QT_QPA_EGLFS_KMS_CONFIG=/tmp/kms.json
export QT_QPA_EGLFS_NO_LIBINPUT=1 QT_SCALE_FACTOR=${QT_SCALE_FACTOR:-1.5} QT_QPA_EGLFS_HIDECURSOR=1
export FD_MESA_DEBUG=${FD_MESA_DEBUG-inorder}
exec zynthian > /tmp/zyn-eglfs.log 2>&1
