#!/bin/sh
# Install packages built with pmbootstrap on the Samsung Galaxy S III Neo over SSH and flash its
# BOOT partition from the device itself (no heimdall, no download mode, no new rootfs): the
# packages go to the device as a local repository and are (re)installed with apk, so a rebuild
# with the same version (pmbootstrap build --force) is installed too, and kernel and modules
# stay in step; the device's mkinitfs/boot-deploy writes /boot/boot.img, which is checked
# (Android header, QCDT, size) and written to the "boot" partition. The previous BOOT contents are
# saved first, on this machine (BACKUP_DIR) and on the device (/boot/boot-partition.prev.img).
# (boot-deploy's deviceinfo_flash_kernel_on_update looks for the GPT label BOOT, heimdall's name;
# the GPT label here is "boot".)
#
# Usage: tools/s3ve3g-deploy.sh [-n] [PACKAGE...]
#   -n        don't reboot afterwards
#   PACKAGE   default: linux-postmarketos-qcom-msm8226 device-samsung-s3ve3g device-samsung-s3ve3g-openrc
# Environment: PMB_WORK (pmbootstrap work dir, default ~/.local/var/pmbootstrap-s3ve3g), REPO (an
# armv7 repository directory instead, e.g. from the builder VM: out/s3ve3g/packages/armv7),
# TARGET (ssh target, default jeff@172.16.42.1), KNOWN_HOSTS (ssh known_hosts file),
# BACKUP_DIR (where the old BOOT image goes on this machine, default ./out/s3ve3g)
set -eu

reboot=1
[ "${1:-}" = -n ] && { reboot=0; shift; }
[ $# -gt 0 ] || set -- linux-postmarketos-qcom-msm8226 device-samsung-s3ve3g device-samsung-s3ve3g-openrc
PMB_WORK=${PMB_WORK:-$HOME/.local/var/pmbootstrap-s3ve3g}
TARGET=${TARGET:-jeff@172.16.42.1}
BACKUP_DIR=${BACKUP_DIR:-$(cd "$(dirname "$0")/.." && pwd)/out/s3ve3g}
ssh_opts="-o BatchMode=yes"
[ -n "${KNOWN_HOSTS:-}" ] && ssh_opts="$ssh_opts -o UserKnownHostsFile=$KNOWN_HOSTS"

repo=${REPO:-$(find "$PMB_WORK/packages" -type d -name armv7 | head -n 1)}
[ -n "$repo" ] && [ -f "$repo/APKINDEX.tar.gz" ] || { echo "no armv7 repository in $PMB_WORK/packages" >&2; exit 1; }

# The newest .apk of each package (and the index, for apk's repository)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp "$repo/APKINDEX.tar.gz" "$tmp/"
for p in "$@"; do
	f=$(ls -t "$repo/$p"-[0-9]*.apk 2>/dev/null | head -n 1)
	[ -n "$f" ] || { echo "no $p in $repo" >&2; exit 1; }
	echo "package: $(basename "$f") ($(date -r "$f" +%H:%M))"
	cp "$f" "$tmp/"
done

# The current BOOT contents first, here and on the device: for heimdall if the new kernel
# doesn't boot
mkdir -p "$BACKUP_DIR"
backup="$BACKUP_DIR/boot-$(date +%Y%m%d-%H%M%S).img"
# shellcheck disable=SC2086 # options
ssh $ssh_opts "$TARGET" 'rm -rf /tmp/deploy && mkdir -p /tmp/deploy/armv7 &&
	sudo dd if="$(findfs PARTLABEL=boot)" of=/tmp/deploy/boot-partition.img bs=1M status=none &&
	sudo chown "$(id -u)" /tmp/deploy/boot-partition.img'
# shellcheck disable=SC2086
scp -q $ssh_opts "$TARGET:/tmp/deploy/boot-partition.img" "$backup"
echo "current BOOT saved: $backup (heimdall flash --BOOT $backup)"
# shellcheck disable=SC2086
scp -q $ssh_opts "$tmp"/* "$TARGET:/tmp/deploy/armv7/"

# shellcheck disable=SC2086
ssh $ssh_opts "$TARGET" "sh -s $reboot $*" <<'EOF'
set -eu
reboot=$1
shift
part=$(findfs PARTLABEL=boot)
psize=$(sudo blockdev --getsize64 "$part")
sudo cp /tmp/deploy/boot-partition.img /boot/boot-partition.prev.img

# Install these very files (a rebuild with the same version too: apk replaces it, where "fix"
# wants the installed build's checksum); triggers mkinitfs/boot-deploy. Then the names again, so
# that world doesn't stay pinned to these files' builds.
apk="sudo apk --no-network --no-interactive --repository /tmp/deploy"
files=
for p in "$@"; do
	files="$files $(ls /tmp/deploy/armv7/"$p"-[0-9]*.apk)"
done
# shellcheck disable=SC2086 # file list
out=$($apk add $files 2>&1) || { echo "$out" >&2; exit 1; }
echo "$out" | grep -E '^\(|^OK' || true
if ! echo "$out" | grep -qE 'Replacing|Upgrading|Installing|Downgrading'; then
	echo "apk: these packages are installed already; checking BOOT against /boot/boot.img"
fi
$apk add "$@" >/dev/null

img=/boot/boot.img
size=$(stat -c %s "$img")
[ "$(head -c 8 "$img")" = "ANDROID!" ] || { echo "$img: no Android boot image header" >&2; exit 1; }
[ "$size" -le "$psize" ] || { echo "$img: $size bytes, BOOT has $psize" >&2; exit 1; }
# the QCDT table follows kernel and ramdisk (page size 2048)
python3 - "$img" 2>/dev/null <<'PY' || { echo "$img: no QCDT" >&2; exit 1; }
import struct, sys
d = open(sys.argv[1], 'rb').read()
ks, ka, rs, ra, ss, sa, ta, ps, dt = struct.unpack('<9I', d[8:44])
pg = lambda n: (n + ps - 1) // ps * ps
o = ps + pg(ks) + pg(rs) + pg(ss)
assert dt and d[o:o + 4] == b'QCDT', 'no QCDT'
print(f"boot.img: kernel {ks}, ramdisk {rs}, dt.img {dt}, command line {len(d[64:576].rstrip(bytes(1)))} chars")
PY
# against the partition itself (it may hold another image, e.g. one flashed with heimdall)
if cmp -s -n "$size" "$img" /tmp/deploy/boot-partition.img; then
	echo "BOOT already holds this boot.img: not touched"
	exit 0
fi
echo "flashing $img ($size bytes) to $part ($psize bytes)"
sudo dd if="$img" of="$part" bs=1M conv=fsync status=none
sudo cmp -n "$size" "$img" "$part" && echo "BOOT written and verified"
if [ "$reboot" = 1 ]; then
	echo "rebooting"
	(sleep 1; sudo reboot) >/dev/null 2>&1 &
fi
EOF
