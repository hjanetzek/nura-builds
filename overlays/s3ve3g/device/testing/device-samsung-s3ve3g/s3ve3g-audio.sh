#!/bin/sh
# Samsung Galaxy S III Neo: choose the audio output (ALSA UCM profile "HiFi" of the card
# "Samsung Galaxy S III Neo"), and remember it for the next boot.
# Usage: s3ve3g-audio speaker|headphones   switch (run as root)
#        s3ve3g-audio restore              the saved output (boot), speaker by default
#        s3ve3g-audio follow               follow the headphone jack: headphones while a plug is
#                                          in, the speaker otherwise (the boot service)
#        s3ve3g-audio                      show the current output
# Without an audio server, play on plughw:CARD=Neo (or hw:CARD=Neo,0: 48 kHz, 16/24 bit).
state=/var/lib/s3ve3g/audio-output
card=hw:CARD=Neo

ucm_device() {	# speaker -> Speaker, headphones -> Headphones
	case $1 in
	speaker) echo Speaker ;;
	headphones) echo Headphones ;;
	*) return 1 ;;
	esac
}

# The codec (WCD9306) doesn't bring up a newly routed output while a stream runs: switched during
# playback, the speaker or the headphones stay silent (all DAPM widgets on) until the next stream
# start. A running PipeWire (the sessions' audio server: s3ve3g_pipewire_start, as the phone's user
# in /tmp/runtime-USER) gets its card output node suspended: PipeWire closes the PCM and opens it
# again for its clients at once (a few xruns). jackd keeps the PCM running: no fix there.
restart_streams() {
	command -v pw-cli >/dev/null || return 0
	local sock dir id
	# after the codec has settled the new path: right after alsaucm the restart came too early (the
	# output stayed silent), 0.5 s later it was enough for the speaker but not the headphones (charge
	# pump, class H, the PA ramp); 2 s (the output is silent meanwhile anyway)
	sleep 2
	for sock in /tmp/runtime-*/pipewire-0 /run/user/*/pipewire-0; do
		[ -S "$sock" ] || continue
		dir=${sock%/pipewire-0}
		for id in $(PIPEWIRE_RUNTIME_DIR=$dir timeout 4 pw-cli ls Node </dev/null 2>/dev/null |
				awk '$1 == "id" { id = $2; sub(",", "", id) } /node.name = "alsa_output/ { print id }'); do
			PIPEWIRE_RUNTIME_DIR=$dir timeout 4 pw-cli send-command "$id" Suspend '{}' </dev/null >/dev/null 2>&1
		done
	done
	return 0
}

switch() {
	new=$(ucm_device "$1") || { echo "unknown output: $1" >&2; exit 1; }
	case $new in Speaker) old=Headphones ;; *) old=Speaker ;; esac
	# alsaucm forgets its state between runs: the other device is enabled and disabled again so
	# that its disable sequence runs (only mixer controls; nothing powers up without a stream)
	alsaucm -c "$card" set _verb HiFi set _enadev "$old" set _disdev "$old" \
		set _enadev "$new" >/dev/null || exit 1
	restart_streams
	mkdir -p "${state%/*}" && echo "$1" > "$state"
	echo "$1"
}

wait_card() {	# the card comes up with the codec's module, after the ADSP has booted
	i=0
	until [ -e /proc/asound/Neo ]; do
		i=$((i + 1)); [ $i -gt 60 ] && { echo "s3ve3g-audio: no sound card" >&2; exit 1; }
		sleep 1
	done
}

jack_plugged() {	# the codec driver's ALSA jack control
	amixer -c Neo cget iface=CARD,name='Headphone Jack' 2>/dev/null | grep -q ': values=on'
}

jack_input() {	# the jack's input device (EV_SW, SW_HEADPHONE_INSERT)
	for d in /sys/class/input/input*; do
		case $(cat "$d/name" 2>/dev/null) in
		*"Headphone Jack"*) echo "/dev/input/$(basename "$d"/event*)"; return 0 ;;
		esac
	done
	return 1
}

case ${1:-} in
speaker|headphones) switch "$1" ;;
restore)
	wait_card
	out=$(cat "$state" 2>/dev/null)
	switch "${out:-speaker}"
	;;
follow)
	wait_card
	ev=$(jack_input) || { echo "s3ve3g-audio: no headphone jack input" >&2; exit 1; }
	if jack_plugged; then switch headphones; else switch speaker; fi
	# struct input_event on armv7: 8 bytes time, u16 type, u16 code, s32 value;
	# EV_SW 5, SW_HEADPHONE_INSERT 2
	exec 3< "$ev"
	while :; do
		set -- $(dd bs=16 count=1 <&3 2>/dev/null | od -An -tu2 -w16)
		[ $# -ge 7 ] || continue
		[ "$5" = 5 ] && [ "$6" = 2 ] || continue
		if [ "$7" = 1 ]; then switch headphones; else switch speaker; fi
	done
	;;
"")
	if amixer -c Neo cget name='SPK DAC Switch' 2>/dev/null | grep -q ': values=on'; then
		echo speaker
	elif amixer -c Neo cget name='HPHL DAC Switch' 2>/dev/null | grep -q ': values=on'; then
		echo headphones
	else
		echo none
	fi
	;;
*) echo "usage: s3ve3g-audio [speaker|headphones|restore|follow]" >&2; exit 1 ;;
esac
