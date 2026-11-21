#!/bin/sh
# Pin pmbootstrap's apk.static (the apk that installs packages into the build chroots) to an older
# apk-tools while a newer one can't install a package pmbootstrap needs.
#
# Now: apk-tools 3.0.10 (Alpine edge since 2026-11-19) fails on postmarketOS' systemd 262.2-r0,
# which ships sbin/init and usr/sbin/init, bin/udevadm and usr/bin/udevadm; under usr-merge each
# pair is one path ("failed to commit usr/sbin/init: No such file or directory", apk-tools
# #11231; apk-tools master now reports it as APKE_DIR_ALIAS). 3.0.9 lets the last one win (the
# same file). Every aarch64/x86_64 build chroot that pulls systemd (udev) failed. Remove this
# (APK_STATIC_PIN="") once pmaports' systemd stops shipping both paths.
#
# Puts the signed apk-tools-static of an Alpine release (verified as pmbootstrap does it, with
# the Alpine keys pmbootstrap ships) into $NURA_WORK/apk.static and makes pmbootstrap keep it:
# its apk_static.init() replaces apk.static with edge's newest whenever it creates a chroot, so
# the installed pmbootstrap gets two lines that return early while $NURA_WORK/apk.static.pinned
# exists (a file: the CI steps run pmbootstrap in separate processes).
#
# Usage: apk-static-pin.sh WORK_DIR    (after pmbootstrap init)
set -eu

work=${1:?usage: $0 WORK_DIR}
APK_STATIC_PIN=${APK_STATIC_PIN-3.0.9-r0}
APK_STATIC_RELEASE=${APK_STATIC_RELEASE:-v3.23}
marker=$work/apk.static.pinned

if [ -z "$APK_STATIC_PIN" ]; then
	rm -f "$marker"
	exit 0
fi

# The installed pmbootstrap: keep a pinned apk.static
pmb=$(python3 -c 'import os, pmb; print(os.path.dirname(pmb.__file__))')
f=$pmb/helpers/apk_static.py
if ! grep -q 'apk.static.pinned' "$f"; then
	sudo=""
	[ -w "$f" ] || sudo=sudo
	$sudo python3 - "$f" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
head = 'def init() -> None:\n    """Download, verify, extract $WORK/apk.static."""\n'
assert s.count(head) == 1, "pmbootstrap's apk_static.init() changed: check scripts/apk-static-pin.sh"
s = s.replace(head, head +
    '    # nura-builds (scripts/apk-static-pin.sh): keep a pinned apk.static\n'
    '    if (get_context().config.work / "apk.static.pinned").exists() and (get_context().config.work / "apk.static").exists():\n'
    '        return\n', 1)
open(p, "w").write(s)
PY
	echo "pmbootstrap ($f): keeps a pinned apk.static"
fi

# The apk.static, if not there already
if [ "$(cat "$marker" 2>/dev/null)" = "$APK_STATIC_PIN" ] && [ -x "$work/apk.static" ]; then
	echo "apk.static: pinned to $APK_STATIC_PIN already"
	exit 0
fi
case $(uname -m) in
	x86_64) arch=x86_64 ;;
	aarch64 | arm64) arch=aarch64 ;;
	*) echo "apk-static-pin: no rule for $(uname -m)" >&2; exit 1 ;;
esac
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
apk=apk-tools-static-$APK_STATIC_PIN.apk
curl -sfL "https://dl-cdn.alpinelinux.org/alpine/$APK_STATIC_RELEASE/main/$arch/$apk" -o "$tmp/$apk" ||
	{ echo "apk-static-pin: can't download $APK_STATIC_RELEASE/main/$arch/$apk" >&2; exit 1; }
tar -xzf "$tmp/$apk" -C "$tmp" sbin 2>/dev/null
sig=$(cd "$tmp/sbin" && ls apk.static.SIGN.RSA.sha256.* | head -n 1)
key=${sig#apk.static.SIGN.RSA.sha256.}
[ -f "$pmb/data/keys/$key" ] || { echo "apk-static-pin: unknown key $key" >&2; exit 1; }
openssl dgst -sha256 -verify "$pmb/data/keys/$key" -signature "$tmp/sbin/$sig" "$tmp/sbin/apk.static" >/dev/null ||
	{ echo "apk-static-pin: bad signature on $apk" >&2; exit 1; }
"$tmp/sbin/apk.static" --version | grep -q "${APK_STATIC_PIN%-r*}" ||
	{ echo "apk-static-pin: $apk reports another version" >&2; exit 1; }
sudo install -m 755 "$tmp/sbin/apk.static" "$work/apk.static"
echo "$APK_STATIC_PIN" | sudo tee "$marker" >/dev/null
echo "apk.static: $("$work/apk.static" --version | head -n 1) (pinned, $APK_STATIC_RELEASE; edge has a newer one)"
