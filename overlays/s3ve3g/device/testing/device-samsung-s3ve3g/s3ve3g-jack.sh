# JACK on the Samsung Galaxy S III Neo's sound card, for the session launchers (s3ve3g-zynthian,
# s3ve3g-mdt): sourced, then "s3ve3g_jack_start" (returns non-zero when jackd doesn't come up).
# Installed as /usr/share/s3ve3g/jack.sh by device-samsung-s3ve3g.
#
# An already running jackd is kept; otherwise jackd on the card "Neo" (WCD9306), 48 kHz, JACK_PERIOD
# frames (default 480: q6asm takes multiples of 480 (10 ms) since 6.18; 256 gave xruns on 6.16),
# 2 periods, 16 bit, real-time priority 70; the dummy backend without the card. Alpine's jackd
# 1.9.22 on armv7 reads option values only when attached (-r48000; "-r 48000" gives 0 Hz), and needs
# JACK_NO_AUDIO_RESERVATION=1 without a D-Bus session. The output (speaker or headphones):
# s3ve3g-audio restore, if installed and sudo allows it without a password.
# jackd is checked and started again when its ALSA driver doesn't come up: on 7.3.4 the first start
# after boot can fail ("could not start playback (Broken pipe)", q6asm "Error queuing playback
# buffer -11"); jackd then keeps running without a driver and refuses clients.
# Log: /tmp/jackd.log

# A jackd whose driver failed (see above) is no use: stopped, and started again
jack_failed() {
	grep -qE "could not start playback|Cannot initialize driver|Driver is not running" /tmp/jackd.log 2>/dev/null
}

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

s3ve3g_jack_start() {
	local period=${JACK_PERIOD:-480} try=0 p
	if pgrep -x jackd >/dev/null && jack_failed; then
		for p in $(pgrep -x jackd); do kill "$p"; done
		sleep 2
	fi
	while ! pgrep -x jackd >/dev/null; do
		try=$((try + 1))
		[ $try -le 3 ] || { echo "jackd didn't start, see /tmp/jackd.log" >&2; return 1; }
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
}
