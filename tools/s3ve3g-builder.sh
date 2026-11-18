#!/bin/sh
# Build the Samsung Galaxy S III Neo's packages in a QEMU VM (zynthian-ui's nura/tools/run_qemu.sh
# with the Nura amd64 image, set up with nura/tools/qemu_setup.sh: key login, passwordless sudo),
# so that builds need no sudo on this machine: pmbootstrap runs in the VM, with its own work dir
# and the pmaports checkout at its default path, the overlays copied into it.
#
# Usage: tools/s3ve3g-builder.sh COMMAND [ARGS]
#   setup         once: pmbootstrap, a pmaports clone, the config (OpenRC, edge), pmbootstrap init
#   sync          this repository to the VM and the overlays into its pmaports (after changes)
#   build [PKG..] sync, then pmbootstrap build --force (default: the kernel and the device package)
#   fetch         the VM's armv7 repository to OUT (for tools/s3ve3g-deploy.sh: REPO=OUT)
#   key           install the VM's package signing key on the phone (once: apk trusts the packages)
#   ssh [CMD]     a shell or command in the VM
# Environment: PORT (the VM's SSH port, default 2240), PMB_WORK (this machine's pmbootstrap work dir,
# whose downloaded sources build copies to the VM, default ~/.local/var/pmbootstrap-s3ve3g), OUT (default ./out/s3ve3g/packages),
# PHONE (default jeff@172.16.42.1), KNOWN_HOSTS (the phone's ssh known_hosts file).
# The VM (agents: own directory and ports, headless, see zynthian-ui's docs/qemu-testing.md):
#   cd ~/bastel/github/zynthian-ui
#   nura/tools/run_qemu.sh -d /mnt/ssd860/qemu/nura-builds-builder -s 32G -m 8G -c 16 -D none -A none \
#           -p 2240 -w 8100 < /dev/null > /mnt/ssd860/qemu/nura-builds-builder/run.log 2>&1 &
#   nura/tools/qemu_setup.sh -p 2240
set -eu

here=$(cd "$(dirname "$0")/.." && pwd)
PORT=${PORT:-2240}
OUT=${OUT:-$here/out/s3ve3g/packages}
PHONE=${PHONE:-jeff@172.16.42.1}
commit=6b904fc480
vm_opts="-p $PORT -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
vm() {
	# shellcheck disable=SC2086 # options
	ssh $vm_opts user@127.0.0.1 "$@"
}
# In the VM
work=/home/user/pmb-work
cfg=/home/user/.config/pmbootstrap-s3ve3g.cfg
pmaports=$work/cache_git/pmaports

cmd=${1:-}
[ $# -gt 0 ] && shift
case $cmd in
setup)
	vm "sudo apk add -q pmbootstrap git openssl rsync"
	vm "mkdir -p /home/user/.config $work/cache_git
		[ -d $pmaports/.git ] || git clone -q --filter=blob:none https://gitlab.postmarketos.org/postmarketOS/pmaports.git $pmaports
		cat > $cfg <<CFG
[pmbootstrap]
aports = $pmaports
build_pkgs_on_install = False
device = samsung-s3ve3g
hostname = s3neo
is_default_channel = False
jobs = \$(nproc)
locale = C.UTF-8
service_manager = openrc
ssh_keys = False
timezone = Europe/Berlin
ui = console
user = user
work = $work

[providers]
postmarketos-base-ui-audio-backend = postmarketos-base-ui-audio-backend-pipewire

[mirrors]
CFG"
	"$0" sync
	vm "[ -f $work/version ] || { yes '' | timeout 900 pmbootstrap -c $cfg init >/dev/null 2>&1 || true; }
		[ -f $work/version ] && echo 'pmbootstrap: initialised' || { echo 'pmbootstrap init failed' >&2; exit 1; }
		pmbootstrap -c $cfg config aports"
	;;
sync)
	# shellcheck disable=SC2086
	rsync -a --delete --exclude .git --exclude out -e "ssh $vm_opts" "$here/" user@127.0.0.1:/home/user/nura-builds/
	vm "PMAPORTS=$pmaports WORKTREE=$pmaports /home/user/nura-builds/tools/s3ve3g-pmaports.sh $commit"
	;;
build)
	[ $# -gt 0 ] || set -- linux-postmarketos-qcom-msm8226 device-samsung-s3ve3g
	"$0" sync
	# sources this machine has already downloaded (GitHub rate-limits the VM's tarball downloads)
	dist=${PMB_WORK:-$HOME/.local/var/pmbootstrap-s3ve3g}/cache_distfiles
	if [ -d "$dist" ]; then
		# shellcheck disable=SC2086
		rsync -a --ignore-existing --chown=12345:12345 --rsync-path="sudo rsync" -e "ssh $vm_opts" \
			"$dist/" "user@127.0.0.1:$work/cache_distfiles/"
	fi
	vm "pmbootstrap -c $cfg build --force $*"
	;;
fetch)
	mkdir -p "$OUT"
	# shellcheck disable=SC2086
	rsync -a --delete -e "ssh $vm_opts" "user@127.0.0.1:$work/packages/edge/armv7/" "$OUT/armv7/"
	ls -l "$OUT/armv7" | grep -E 'samsung|msm8226|APKINDEX'
	;;
key)
	tmp=$(mktemp -d)
	trap 'rm -rf "$tmp"' EXIT
	vm "sudo sh -c 'cat $work/config_abuild/*.rsa.pub'" > "$tmp/key.pub"
	name=$(vm "sudo sh -c 'cd $work/config_abuild && ls *.rsa.pub'")
	[ -s "$tmp/key.pub" ] && [ -n "$name" ] || { echo "no signing key in the VM yet (build something first)" >&2; exit 1; }
	ssh_phone="ssh -o BatchMode=yes ${KNOWN_HOSTS:+-o UserKnownHostsFile=$KNOWN_HOSTS}"
	# shellcheck disable=SC2086
	$ssh_phone "$PHONE" "sudo tee /etc/apk/keys/$name >/dev/null" < "$tmp/key.pub"
	echo "phone trusts $name"
	;;
ssh)
	if [ $# -gt 0 ]; then vm "$@"; else
		# shellcheck disable=SC2086
		ssh -t $vm_opts user@127.0.0.1
	fi
	;;
*)
	sed -n '2,/^set -eu/{/^set -eu/d;s/^# \{0,1\}//;p}' "$0"
	exit 1
	;;
esac
