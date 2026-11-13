#!/bin/sh
# Samsung Galaxy S III Neo: choose the audio output (ALSA UCM profile "HiFi" of the card
# "Samsung Galaxy S III Neo"), and remember it for the next boot.
# Usage: s3ve3g-audio speaker|headphones   switch (run as root)
#        s3ve3g-audio restore              the saved output (boot), speaker by default
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

switch() {
	new=$(ucm_device "$1") || { echo "unknown output: $1" >&2; exit 1; }
	case $new in Speaker) old=Headphones ;; *) old=Speaker ;; esac
	# alsaucm forgets its state between runs: the other device is enabled and disabled again so
	# that its disable sequence runs (only mixer controls; nothing powers up without a stream)
	alsaucm -c "$card" set _verb HiFi set _enadev "$old" set _disdev "$old" \
		set _enadev "$new" >/dev/null || exit 1
	mkdir -p "${state%/*}" && echo "$1" > "$state"
	echo "$1"
}

case ${1:-} in
speaker|headphones) switch "$1" ;;
restore)
	# the card comes up with the codec's module, after the ADSP has booted
	i=0
	until [ -e /proc/asound/Neo ]; do
		i=$((i + 1)); [ $i -gt 60 ] && { echo "s3ve3g-audio: no sound card" >&2; exit 1; }
		sleep 1
	done
	out=$(cat "$state" 2>/dev/null)
	switch "${out:-speaker}"
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
*) echo "usage: s3ve3g-audio [speaker|headphones|restore]" >&2; exit 1 ;;
esac
