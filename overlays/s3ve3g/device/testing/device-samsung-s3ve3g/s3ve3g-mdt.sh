#!/bin/sh
# MicroDexed-touch (package microdexed-touch) as the Samsung Galaxy S III Neo's session instead of
# zynthian, with JACK on the phone's sound card, as the logged-in user. Installed as
# /usr/bin/s3ve3g-mdt by device-samsung-s3ve3g, started by its service s3ve3g-mdt (OpenRC); the
# session is chosen with s3ve3g-session (zynthian or mdt).
#
# - headless with audio by default (MDT_ARGS="--headless --audio"): the phone has no compositor, and
#   its panel is portrait while MDT draws a 480x320 landscape window; the screen stays off
#   (s3ve3g-screen-off). Played through a controller (Maschine JAM over hidraw), MIDI (ALSA
#   sequencer) or MDT's control port (127.0.0.1:5000); the phone's keys are to follow
# - JACK: /usr/share/s3ve3g/jack.sh, as for zynthian (48 kHz, JACK_PERIOD, default 480 frames);
#   MDT's audio through SDL's JACK driver (microdexed-touch's launcher sets SDL_AUDIODRIVER=jack)
# - its SD card image in the user's data directory, made on the first start (microdexed-touch)
# Log: /tmp/mdt.log (jackd: /tmp/jackd.log)

# The boot splash first (it holds DRM master; MDT may draw later): told to quit, waited for (60 s)
if pgrep -x plymouthd >/dev/null; then
	sudo -n plymouth quit --retain-splash >/dev/null 2>&1 || true
fi
i=0
while pgrep -x plymouthd >/dev/null && [ $i -lt 600 ]; do
	sleep 0.1; i=$((i + 1))
done

# Another MDT (a session started before): stopped
for p in $(pgrep -x mdt); do kill "$p"; done

. /usr/share/s3ve3g/jack.sh
s3ve3g_jack_start || exit 1

# shellcheck disable=SC2086 # MDT_ARGS: several options
exec microdexed-touch ${MDT_ARGS:---headless --audio} > /tmp/mdt.log 2>&1
