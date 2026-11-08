#!/bin/sh
# Run a Nura amd64 image (qemu-amd64 device) on this desktop in QEMU: KVM, OpenGL through virgl
# (virtio-vga-gl: the guest's Mesa renders on the desktop's GPU), PipeWire audio, SSH and webconf
# forwarded, USB devices (MIDI controllers) passed through.
#
#   tools/run-qemu.sh [options] [IMAGE]
#
# IMAGE: an .img or .img.zst. Default: the latest build of this repository (release
# "zynthian-latest", zynthian-qemu-amd64.img.zst), downloaded to the cache directory and
# unpacked once; later runs boot the same disk (state kept) until -r or -u.
#
#   -u          download the newest image (if the release has a newer one) and start from it
#   -r          start from a fresh copy of the downloaded image (discards the VM's changes)
#   -s SIZE     disk size of a fresh copy (default 8G; postmarketOS grows its root partition to the
#               disk at the first boot)
#   -m MEM      memory (default 4G)
#   -c CPUS     virtual CPUs (default: half of this machine's)
#   -D DISPLAY  gtk (default) or sdl
#   -n          no OpenGL (software rendering in the guest: slow, for checking a GL problem)
#   -A AUDIO    virtio (default: virtio-sound, QEMU 8.2+) or hda (emulated Intel HDA), none
#   -U VID:PID  pass a USB device through (repeatable), e.g. -U 17cc:1140 (Maschine Mk2). Needs
#               write access to its /dev/bus/usb node (a udev rule, or run as root)
#   -p PORT     host port for the VM's SSH (default 2222: ssh -p 2222 user@localhost)
#   -w PORT     host port for the VM's webconf (default 8080: http://localhost:8080)
#   -d DIR      cache directory (default ~/.cache/nura-builds)
#
# Needs qemu-system-x86_64 (with the virtio-vga-gl device: QEMU's GL/virglrenderer support),
# OVMF (edk2-ovmf / ovmf), zstd, curl; /dev/kvm for full speed (without it QEMU emulates, slowly).
set -eu

usage() { sed -n '2,/^set -eu/{/^set -eu/d;s/^# \{0,1\}//;p}' "$0"; exit "${1:-0}"; }

url=https://github.com/hjanetzek/nura-builds/releases/download/zynthian-latest/zynthian-qemu-amd64.img.zst
cache=${XDG_CACHE_HOME:-$HOME/.cache}/nura-builds
update=0 reset=0 size=8G mem=4G cpus= display=gtk gl=on audio=virtio usb= ssh_port=2222 web_port=8080
while getopts urs:m:c:D:nA:U:p:w:d:h opt; do
	case $opt in
		u) update=1 ;;
		r) reset=1 ;;
		s) size=$OPTARG ;;
		m) mem=$OPTARG ;;
		c) cpus=$OPTARG ;;
		D) display=$OPTARG ;;
		n) gl=off ;;
		A) audio=$OPTARG ;;
		U) usb="$usb $OPTARG" ;;
		p) ssh_port=$OPTARG ;;
		w) web_port=$OPTARG ;;
		d) cache=$OPTARG ;;
		h) usage ;;
		*) usage 1 ;;
	esac
done
shift $((OPTIND - 1))
[ $# -le 1 ] || usage 1

for cmd in qemu-system-x86_64 zstd; do
	command -v "$cmd" >/dev/null || { echo "$cmd not found" >&2; exit 1; }
done

# The disk: a given .img as it is; a .img.zst (given or downloaded) unpacked to the cache
mkdir -p "$cache"
if [ $# -eq 1 ] && [ "${1%.zst}" = "$1" ]; then
	disk=$1
else
	if [ $# -eq 1 ]; then
		zst=$1
	else
		zst=$cache/zynthian-qemu-amd64.img.zst
		if [ ! -f "$zst" ] || [ $update = 1 ]; then
			echo "downloading $url"
			old=$(stat -c %Y "$zst" 2>/dev/null || echo 0)
			# -z: only if the release's file is newer than the local copy; -R: keep its time
			if [ -f "$zst" ]; then
				set -- -z "$zst"
			else
				set --
			fi
			curl -fLR --progress-bar "$@" -o "$zst.part" "$url" || { rm -f "$zst.part"; exit 1; }
			set --
			if [ -s "$zst.part" ]; then
				mv "$zst.part" "$zst"
			else
				rm -f "$zst.part"
			fi
			[ "$(stat -c %Y "$zst")" = "$old" ] || reset=1
		fi
	fi
	disk=$cache/$(basename "${zst%.zst}")
	if [ ! -f "$disk" ] || [ $reset = 1 ]; then
		echo "unpacking $zst"
		zstd -d -q -f "$zst" -o "$disk"
		truncate -s ">$size" "$disk"
	fi
fi

# UEFI firmware (the image boots with systemd-boot)
ovmf=
for f in /usr/share/edk2/x64/OVMF.4m.fd /usr/share/edk2/x64/OVMF.fd /usr/share/OVMF/OVMF.fd \
	/usr/share/edk2/ovmf/OVMF.fd /usr/share/qemu/ovmf-x86_64.bin /usr/share/ovmf/OVMF.fd; do
	[ -f "$f" ] && { ovmf=$f; break; }
done
[ -n "$ovmf" ] || { echo "no OVMF firmware found: install edk2-ovmf (or ovmf)" >&2; exit 1; }

# QEMU's optional modules (distributions package them separately: on Arch qemu-hw-display-*,
# qemu-ui-*, qemu-audio-*, qemu-hw-usb-host; Debian/Ubuntu: qemu-system-gui, qemu-system-modules-*)
devices=$(qemu-system-x86_64 -device help 2>/dev/null)
audiodevs=$(qemu-system-x86_64 -audiodev help 2>/dev/null)
displays=$(qemu-system-x86_64 -display help 2>/dev/null)
missing=
has_device() { echo "$devices" | grep -q "name \"$1\""; }
if [ "$gl" = on ]; then
	has_device virtio-vga-gl || missing="$missing qemu-hw-display-virtio-vga-gl qemu-hw-display-virtio-gpu-gl qemu-ui-opengl"
else
	has_device virtio-vga || missing="$missing qemu-hw-display-virtio-vga qemu-hw-display-virtio-gpu"
fi
echo "$displays" | grep -qx "$display" || missing="$missing qemu-ui-$display"
if [ "$audio" != none ]; then
	echo "$audiodevs" | grep -qx -e pipewire -e pa || missing="$missing qemu-audio-pipewire"
fi
if [ -n "$usb" ]; then
	has_device usb-host || missing="$missing qemu-hw-usb-host"
fi
if [ -n "$missing" ]; then
	echo "QEMU lacks modules this needs; on Arch: sudo pacman -S$missing" >&2
	echo "(or -n for no OpenGL, -A none for no audio)" >&2
	exit 1
fi

[ -n "$cpus" ] || cpus=$(( $(nproc) / 2 ))
[ "$cpus" -ge 1 ] || cpus=1

set -- -nodefaults -machine q35 -smp "$cpus" -m "$mem" \
	-drive "if=pflash,format=raw,readonly=on,file=$ovmf" \
	-drive "file=$disk,format=raw,if=virtio" \
	-device virtio-tablet-pci -device virtio-keyboard-pci \
	-netdev "user,id=net,hostfwd=tcp:127.0.0.1:$ssh_port-:22,hostfwd=tcp:127.0.0.1:$web_port-:8080" \
	-device virtio-net-pci,netdev=net \
	-serial mon:stdio

if [ -w /dev/kvm ]; then
	set -- "$@" -enable-kvm -cpu host
else
	echo "warning: no access to /dev/kvm, QEMU emulates the CPU (slow)" >&2
fi

if [ "$gl" = on ]; then
	set -- "$@" -device virtio-vga-gl -display "$display,gl=on,show-cursor=on"
else
	set -- "$@" -device virtio-vga -display "$display,show-cursor=on"
fi

# Audio through the desktop's PipeWire (or PulseAudio)
if [ "$audio" != none ]; then
	if command -v pw-cli >/dev/null; then
		set -- "$@" -audiodev pipewire,id=snd
	else
		set -- "$@" -audiodev pa,id=snd
	fi
	case $audio in
		virtio) set -- "$@" -device virtio-sound-pci,audiodev=snd ;;
		hda) set -- "$@" -device intel-hda -device hda-duplex,audiodev=snd ;;
		*) echo "unknown audio $audio" >&2; exit 1 ;;
	esac
fi

# USB passthrough (xHCI)
if [ -n "$usb" ]; then
	set -- "$@" -device qemu-xhci,id=xhci
	for dev in $usb; do
		set -- "$@" -device "usb-host,bus=xhci.0,vendorid=0x${dev%%:*},productid=0x${dev#*:}"
	done
fi

echo "disk $disk; ssh -p $ssh_port <user>@localhost; webconf http://localhost:$web_port"
echo "serial console here (Ctrl-A x quits QEMU, Ctrl-A c the monitor)"
exec qemu-system-x86_64 "$@"
