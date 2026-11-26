#!/bin/sh
# MicroDexed-touch (package microdexed-touch) as the Samsung Galaxy S III Neo's session instead of
# zynthian, with JACK on the phone's sound card, as the logged-in user. Installed as
# /usr/bin/s3ve3g-mdt by device-samsung-s3ve3g, started by its service s3ve3g-mdt (OpenRC); the
# session is chosen with s3ve3g-session (zynthian or mdt).
#
# - headless with audio by default (MDT_ARGS="--headless --audio"): the phone has no compositor, and
#   its panel is portrait while MDT draws a 480x320 landscape window; the screen stays off
#   (s3ve3g-screen-off). Played through a controller (Maschine JAM over hidraw), MIDI (ALSA
#   sequencer) or MDT's control port (127.0.0.1:5000); the phone's keys through that port
#   (s3ve3g-mdt-keys: volume = encoder, home = enter/back, back, menu = S1/sequencer start-stop)
# - audio (MDT_AUDIO): "pipewire" by default: PipeWire and WirePlumber as the user, without a D-Bus
#   session (their D-Bus errors are harmless), the card's Pro Audio profile (s3ve3g-wireplumber.conf),
#   48 kHz with a quantum of 480 (s3ve3g-pipewire.conf, and forced: WirePlumber's sink otherwise
#   runs at 256), MDT through PipeWire's JACK (pw-jack; package pipewire-jack). "jackd": jackd as
#   for zynthian (/usr/share/s3ve3g/jack.sh); MDT's SDL JACK output fails on jackd 1.9.22 (it
#   connects its ports before activating), so this is for a later MDT. SDL's ALSA output fails
#   here ("Host is down", as for ALSA's default device)
#   (microdexed-touch's launcher sets SDL_AUDIODRIVER=jack)
# - its SD card image in the user's data directory, made on the first start (microdexed-touch)
# Log: /tmp/mdt.log (/tmp/mdt-pipewire.log, /tmp/mdt-wireplumber.log or /tmp/jackd.log, keys:
# /tmp/mdt-keys.log)

# The boot splash first (it holds DRM master; MDT may draw later): told to quit, waited for (60 s)
if pgrep -x plymouthd >/dev/null; then
	sudo -n plymouth quit --retain-splash >/dev/null 2>&1 || true
fi
i=0
while pgrep -x plymouthd >/dev/null && [ $i -lt 600 ]; do
	sleep 0.1; i=$((i + 1))
done

# Another MDT and its key relay (a session started before): stopped (MDT ignores SIGTERM)
for p in $(pgrep -x mdt) $(pgrep -x s3ve3g-mdt-keys); do kill -9 "$p"; done

audio=${MDT_AUDIO:-pipewire}
period=${JACK_PERIOD:-480}
wrap=
case $audio in
pipewire)
	command -v pw-jack >/dev/null || { echo "pw-jack missing (apk add pipewire-jack)" >&2; exit 1; }
	# jackd (zynthian's session) and an earlier PipeWire of this session: stopped
	for p in $(pgrep -x jackd) $(pgrep -x wireplumber) $(pgrep -x pipewire); do kill "$p"; done
	sleep 1
	if command -v s3ve3g-audio >/dev/null; then
		sudo -n s3ve3g-audio restore >/dev/null 2>&1 || true
	fi
	rm -f "$XDG_RUNTIME_DIR"/pipewire-0 "$XDG_RUNTIME_DIR"/pipewire-0.lock \
		"$XDG_RUNTIME_DIR"/pipewire-0-manager "$XDG_RUNTIME_DIR"/pipewire-0-manager.lock
	pipewire </dev/null >/tmp/mdt-pipewire.log 2>&1 &
	i=0
	while [ ! -S "$XDG_RUNTIME_DIR/pipewire-0" ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
	wireplumber </dev/null >/tmp/mdt-wireplumber.log 2>&1 &
	# until WirePlumber has made the card's sink (at most 10 s)
	i=0
	until timeout 3 wpctl inspect @DEFAULT_AUDIO_SINK@ </dev/null >/dev/null 2>&1 || [ $i -ge 20 ]; do
		sleep 0.5; i=$((i + 1))
	done
	timeout 3 pw-metadata -n settings 0 clock.force-quantum "$period" </dev/null >/dev/null 2>&1
	wrap=pw-jack
	;;
jackd)
	. /usr/share/s3ve3g/jack.sh
	s3ve3g_jack_start || exit 1
	;;
*) echo "MDT_AUDIO: pipewire or jackd, not $audio" >&2; exit 1 ;;
esac

# the phone's keys to MDT's control port (stopped by the service's stop, or the next start)
# (python3, not a dependency of the device package: without it, no relay)
if command -v python3 >/dev/null; then
	s3ve3g-mdt-keys > /tmp/mdt-keys.log 2>&1 &
else
	echo "no python3: the phone's keys aren't relayed to MDT" >&2
fi

# shellcheck disable=SC2086 # MDT_ARGS: several options
exec $wrap microdexed-touch ${MDT_ARGS:---headless --audio} > /tmp/mdt.log 2>&1
