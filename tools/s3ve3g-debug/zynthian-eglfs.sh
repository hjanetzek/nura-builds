#!/bin/sh
# zynthian's Qt UI full-screen on the Samsung Galaxy S III Neo without a compositor (Qt's eglfs on
# KMS), with JACK on the phone's sound card, as the logged-in user (groups video, input, audio; the
# audio group's real-time limits). Copy to the phone and run there.
#
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
# - Mesa 26.2.6-r1 (nura-builds armv7 repository) fixes the freedreno a3xx flicker; with Alpine's
#   26.2.6-r0 set FD_MESA_DEBUG=inorder
# Logs: /tmp/zyn-eglfs.log, /tmp/jackd.log
period=${JACK_PERIOD:-480}

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

if ! pgrep -x jackd >/dev/null; then
	if [ -e /proc/asound/Neo ]; then
		if command -v s3ve3g-audio >/dev/null; then
			sudo -n s3ve3g-audio restore >/dev/null 2>&1 || true
		fi
		JACK_NO_AUDIO_RESERVATION=1 jackd -R -P70 -d alsa -d hw:CARD=Neo,0 -r48000 "-p$period" -n2 -S -P \
			> /tmp/jackd.log 2>&1 &
	else
		jackd -R -d dummy -r48000 "-p$period" > /tmp/jackd.log 2>&1 &
	fi
	sleep 3   # (no jack_wait: Alpine's jack has no example clients)
	pgrep -x jackd >/dev/null || { echo "jackd didn't start, see /tmp/jackd.log" >&2; exit 1; }
fi

[ -f /tmp/kms.json ] || echo '{ "device": "/dev/dri/card1" }' > /tmp/kms.json
export ZYNTHIAN_UI=qt ZYNTHIAN_FULLSCREEN=1 ZYNTHIAN_UI_SCALE=auto ZYNTHIAN_UI_ROTATION=${ZYNTHIAN_UI_ROTATION:-90}
export QT_QPA_PLATFORM=eglfs QT_QPA_EGLFS_INTEGRATION=eglfs_kms QT_QPA_EGLFS_KMS_CONFIG=/tmp/kms.json
export QT_QPA_EGLFS_NO_LIBINPUT=1 QT_SCALE_FACTOR=${QT_SCALE_FACTOR:-1.5} QT_QPA_EGLFS_HIDECURSOR=1
exec zynthian > /tmp/zyn-eglfs.log 2>&1
