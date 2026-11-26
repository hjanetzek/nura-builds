# JACK on the Samsung Galaxy S III Neo's sound card, for the session launchers (s3ve3g-zynthian,
# s3ve3g-mdt): sourced, then "s3ve3g_jack_start" (jackd) or "s3ve3g_pipewire_start" (PipeWire,
# below); both return non-zero when the server doesn't come up.
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
	# PipeWire (s3ve3g_pipewire_start, an earlier session) holds the card: stopped
	if pgrep -x pipewire >/dev/null; then
		for p in $(pgrep -x wireplumber) $(pgrep -x pipewire); do kill "$p"; done
		sleep 1
	fi
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

# PipeWire instead of jackd (s3ve3g_pipewire_start; the clients then through pw-jack, package
# pipewire-jack): PipeWire and WirePlumber as the user, without a D-Bus session (their D-Bus errors
# are harmless), the card's Pro Audio profile (/usr/share/wireplumber/wireplumber.conf.d/
# 50-s3ve3g.conf), 48 kHz with a quantum of JACK_PERIOD (480; 50-s3ve3g.conf in pipewire.conf.d,
# and forced: WirePlumber's sink otherwise runs at 256). A running jackd is stopped.
# Logs: /tmp/pipewire.log, /tmp/wireplumber.log
s3ve3g_pipewire_start() {
	local period=${JACK_PERIOD:-480} i p
	command -v pw-jack >/dev/null || { echo "pw-jack missing (apk add pipewire-jack)" >&2; return 1; }
	# jackd (zynthian's session) and an earlier PipeWire of this session: stopped
	for p in $(pgrep -x jackd) $(pgrep -x wireplumber) $(pgrep -x pipewire); do kill "$p"; done
	sleep 1
	if command -v s3ve3g-audio >/dev/null; then
		sudo -n s3ve3g-audio restore >/dev/null 2>&1 || true
	fi
	rm -f "$XDG_RUNTIME_DIR"/pipewire-0 "$XDG_RUNTIME_DIR"/pipewire-0.lock \
		"$XDG_RUNTIME_DIR"/pipewire-0-manager "$XDG_RUNTIME_DIR"/pipewire-0-manager.lock
	pipewire </dev/null >/tmp/pipewire.log 2>&1 &
	i=0
	while [ ! -S "$XDG_RUNTIME_DIR/pipewire-0" ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
	wireplumber </dev/null >/tmp/wireplumber.log 2>&1 &
	# until WirePlumber has made the card's sink (at most 10 s)
	i=0
	until timeout 3 wpctl inspect @DEFAULT_AUDIO_SINK@ </dev/null >/dev/null 2>&1 || [ $i -ge 20 ]; do
		sleep 0.5; i=$((i + 1))
	done
	timeout 3 pw-metadata -n settings 0 clock.force-quantum "$period" </dev/null >/dev/null 2>&1
}
