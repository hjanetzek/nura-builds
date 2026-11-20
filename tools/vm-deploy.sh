#!/bin/sh
# Build packages from local checkouts (e.g. a zynthian-ui worktree) in the builder VM and install
# them on a device: no pmbootstrap and no sudo on this machine. The VM (zynthian-ui's
# tools/run_qemu.sh with the Nura amd64 image, set up with tools/qemu_setup.sh: key login,
# passwordless sudo) runs this repository's own CI scripts, so builds match CI's:
# scripts/setup.sh (pmbootstrap config: edge, systemd; the recipes of aports/ linked) once per
# architecture, the published packages of the architecture's release as the base (only what is
# missing is downloaded; pmbootstrap then builds just the named packages), and
# pmbootstrap build --src for the packages built from checkouts.
#
# Usage: tools/vm-deploy.sh -d DEVICE [options] [PACKAGE...]
#   -d DEVICE    duet, pi, pixel, s3 or vm (sets host, user, architecture and how zynthian restarts)
#   -H HOST -u USER -P PORT -a ARCH    override the device's settings
#   -U DIR       zynthian-ui checkout (default: ../zynthian-ui next to this repository)
#   -z DIR       zyncoder checkout (zyncoder, zyncoder-hw; default ../zyncoder)
#   -W DIR       zynthian-webconf checkout, nura branch (default ../zynthian-webconf-nura)
#   -j DIR       zynthian's jalv checkout (zynthian-jalv; default ../jalv)
#   -b           build only, don't install
#   -i           install only: the packages built last for the architecture
#   -R           don't restart zynthian afterwards
#   -t SECONDS   timeout of each step of the checked restart (default 120)
#   PACKAGE      default zynthian-ui; zynthian-ui, zyncoder(-hw), zynthian-webconf and zynthian-jalv
#                come from their checkouts (--src), anything else from this repository's recipes
# Environment: PORT (the VM's SSH port, default 2240).
#
# After installing zynthian-ui, zynthian restarts checked (zynthian-ui's tools/restart_ui.py on the
# device: waits until it is idle, RESTART_UI, a new process that answers idle); if zynthian
# isn't running, the session restarts. The device must trust the VM's package signing key: it is
# installed there the first time (/etc/apk/keys). The first build of an architecture sets up
# pmbootstrap in the VM and downloads the release (aarch64 ~2.3 GB, x86_64 ~1.9, armv7 ~0.7).
# The VM (agents: own directory and ports, headless, see zynthian-ui's docs/qemu-testing.md):
#   cd ~/bastel/github/zynthian-ui
#   tools/run_qemu.sh -d /mnt/ssd860/qemu/nura-builds-builder -s 32G -m 8G -c 16 -D none -A none \
#           -p 2240 -w 8100 < /dev/null > /mnt/ssd860/qemu/nura-builds-builder/run.log 2>&1 &
#   tools/qemu_setup.sh -p 2240
set -eu

here=$(cd "$(dirname "$0")/.." && pwd)
parent=$(cd "$here/.." && pwd)
PORT=${PORT:-2240}
# (the port separately: ssh takes -p, scp -P)
vm_opts="-o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
vm() {
	# shellcheck disable=SC2086 # options
	ssh -p "$PORT" $vm_opts user@127.0.0.1 "$@"
}
vm_rsync() {
	# shellcheck disable=SC2086
	rsync -a --delete --exclude .git --exclude __pycache__ --exclude out -e "ssh -p $PORT $vm_opts" "$@"
}
usage() { sed -n '2,/^set -eu/{/^set -eu/d;s/^# \{0,1\}//;p}' "$0"; exit "${1:-0}"; }

device='' host='' user='' dport='' arch='' build=1 install=1 restart=1 timeout=120
ui=$parent/zynthian-ui zyncoder=$parent/zyncoder jalv=$parent/jalv
webconf=$parent/zynthian-webconf-nura
[ -d "$webconf" ] || webconf=$parent/zynthian-webconf
while getopts d:H:u:P:a:U:z:W:j:biRt:h opt; do
	case $opt in
		d) device=$OPTARG ;;
		H) host=$OPTARG ;;
		u) user=$OPTARG ;;
		P) dport=$OPTARG ;;
		a) arch=$OPTARG ;;
		U) ui=$OPTARG ;;
		z) zyncoder=$OPTARG ;;
		W) webconf=$OPTARG ;;
		j) jalv=$OPTARG ;;
		b) install=0 ;;
		i) build=0 ;;
		R) restart=0 ;;
		t) timeout=$OPTARG ;;
		h) usage ;;
		*) usage 1 ;;
	esac
done
shift $((OPTIND - 1))
[ $# -gt 0 ] || set -- zynthian-ui

# Devices: host, user, architecture, ssh options, session restart (when zynthian isn't running)
dev_opts="-o BatchMode=yes"
session_restart="sudo systemctl restart tinydm"
case $device in
	duet) d_host=kick-duet.local d_user=jeff d_arch=aarch64 ;;
	pi) d_host=nura-zynthian.local d_user=user d_arch=aarch64 ;;
	pixel) d_host=pixel3.local d_user=jeff d_arch=aarch64 ;;
	# the S III Neo over USB networking; OpenRC, zynthian under its own launcher service
	s3) d_host=172.16.42.1 d_user=jeff d_arch=armv7 session_restart="sudo rc-service s3ve3g-zynthian restart" ;;
	# the Nura QEMU VM (zynthian-ui's run_qemu.sh; the Qt test VM's port)
	vm) d_host=127.0.0.1 d_user=user d_arch=x86_64 d_port=2252
		dev_opts="$dev_opts -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR" ;;
	"") [ -n "$host" ] && [ -n "$arch" ] || { echo "-d DEVICE, or -H HOST and -a ARCH" >&2; usage 1; } ;;
	*) echo "unknown device: $device" >&2; usage 1 ;;
esac
host=${host:-$d_host} user=${user:-${d_user:-$USER}} arch=${arch:-$d_arch} dport=${dport:-${d_port:-22}}
target=$user@$host
dev() {
	# shellcheck disable=SC2086
	ssh $dev_opts -p "$dport" "$target" "$@"
}

# In the VM: this repository, the checkouts for --src, the work dir (shared by the architectures)
vrepo=/home/user/nura-builds-vm-deploy
vsrc=/home/user/vm-deploy-src
venv="TARGET=zynthian NURA_ARCH=$arch NURA_WORK=/home/user/nura-work NURA_SRC=/home/user/nura-src NURA_OUT=/home/user/nura-out"
cfg=/home/user/.config/pmbootstrap-nura-zynthian.cfg
pkgdir=/home/user/nura-work/packages/edge/$arch

src_of() {	# package -> checkout for --src (empty: from the recipe)
	case $1 in
		zynthian-ui) echo "$ui" ;;
		zyncoder | zyncoder-hw) echo "$zyncoder" ;;
		zynthian-webconf) echo "$webconf" ;;
		zynthian-jalv) echo "$jalv" ;;
	esac
}

if [ $build = 1 ]; then
	vm true 2>/dev/null || { echo "builder VM not reachable on port $PORT (see the header)" >&2; exit 1; }
	# the image has neither: CI's scripts (pin-binary.sh) and the release download need curl
	vm "command -v curl >/dev/null && command -v rsync >/dev/null || sudo apk add -q curl rsync"
	vm_rsync "$here/" "user@127.0.0.1:$vrepo/"
	# pmbootstrap set up for the architecture (once): CI's setup.sh
	if ! vm "[ -f /home/user/nura-work/.vm-deploy-$arch ]"; then
		echo "== setting up pmbootstrap for $arch in the VM (scripts/setup.sh)"
		vm "cd $vrepo && $venv scripts/setup.sh && touch /home/user/nura-work/.vm-deploy-$arch"
	fi
	# The release of the architecture into the local repository: what is missing (public
	# downloads, no token), signed with CI's key, which the build chroots then trust
	echo "== release $arch: missing packages"
	vm "set -e; base=https://github.com/hjanetzek/nura-builds/releases/download/$arch
		t=\$(mktemp -d); trap 'rm -rf \$t' EXIT
		curl -sfL \$base/APKINDEX.tar.gz -o \$t/APKINDEX.tar.gz
		sudo mkdir -p $pkgdir
		tar -xzOf \$t/APKINDEX.tar.gz APKINDEX | awk -F: '/^P:/{p=\$2} /^V:/{print p \"-\" \$2 \".apk\"}' > \$t/files
		n=0; for f in \$(cat \$t/files); do
			[ -e $pkgdir/\$f ] && continue
			curl -sfL \$base/\$f -o \$t/\$f && sudo mv \$t/\$f $pkgdir/ && n=\$((n + 1)) || echo \"can't download \$f\"
		done
		echo \"\$n downloaded, \$(wc -l < \$t/files) in the release\"
		# (pmbootstrap creates its own key with the first build; it looks for abuild.conf, so
		# the directory may exist before)
		sudo mkdir -p /home/user/nura-work/config_abuild
		sudo cp $vrepo/keys/nura-builds-ci.rsa.pub /home/user/nura-work/config_abuild/
		sudo chown -R 12345:12345 /home/user/nura-work/config_abuild
		sudo chown -R 12345:12345 /home/user/nura-work/packages
		pmbootstrap -c $cfg -y index >/dev/null"
	vm "touch /tmp/vm-deploy-mark-$arch"
	for p in "$@"; do
		s=$(src_of "$p")
		if [ -n "$s" ]; then
			[ -d "$s" ] || { echo "$p: no checkout $s" >&2; exit 1; }
			echo "== $p from $s ($(git -C "$s" log -1 --format='%h %s' 2>/dev/null | cut -c1-60))"
			vm "mkdir -p $vsrc"
			vm_rsync "$s/" "user@127.0.0.1:$vsrc/$p/"
			[ "$p" = zynthian-ui ] && vm "cd $vrepo && sudo aports/zynthian/seed-distfiles.sh $cfg >/dev/null"
			vm "pmbootstrap -c $cfg -y build --arch $arch --force --src=$vsrc/$p $p"
		else
			echo "== $p from its recipe"
			vm "pmbootstrap -c $cfg -y build --arch $arch --force $p"
		fi
	done
fi

[ $install = 1 ] || exit 0

# The packages to install: built in this run (or with -i the newest of each name), without -dbg
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
if [ $build = 1 ]; then
	files=$(vm "cd $pkgdir && find . -maxdepth 1 -name '*.apk' -newer /tmp/vm-deploy-mark-$arch | sed 's|^\./||'")
else
	files=$(vm "cd $pkgdir && for p in $*; do ls -t \$p-[0-9]*.apk 2>/dev/null | head -n 1; done")
fi
files=$(echo "$files" | grep -vE -- '-(dbg|doc)-' || true)
[ -n "$files" ] || { echo "nothing built to install" >&2; exit 1; }
for f in $files; do
	# shellcheck disable=SC2086
	scp -q -P "$PORT" $vm_opts "user@127.0.0.1:$pkgdir/$f" "$tmp/"
done
echo "== installing on $target: $(echo $files)"

# The VM's signing key on the device (once)
key=$(vm "cd /home/user/nura-work/config_abuild && ls *.rsa.pub | grep -v '^nura-builds-ci'" | head -n 1)
if ! dev "[ -f /etc/apk/keys/$key ]"; then
	vm "cat /home/user/nura-work/config_abuild/$key" | dev "sudo tee /etc/apk/keys/$key >/dev/null"
	echo "the device trusts the VM's key now ($key)"
fi
dev "rm -rf /tmp/vm-deploy && mkdir -p /tmp/vm-deploy"
# shellcheck disable=SC2086
scp -q -P "$dport" $dev_opts "$tmp"/*.apk "$target:/tmp/vm-deploy/"
# These very files (a rebuild with the same version too), then by name, so that the world file
# doesn't stay pinned to these builds
names=$(for f in $files; do echo "$f" | sed -E 's/-[0-9][^-]*-r[0-9]+\.apk$//'; done | tr '\n' ' ')
dev "sudo apk add --no-interactive /tmp/vm-deploy/*.apk | grep -E '^\(|^OK|ERROR' ; sudo apk add --no-interactive $names >/dev/null; rm -rf /tmp/vm-deploy"

# zynthian restarted, checked
if [ $restart = 1 ] && echo " $names " | grep -qE ' (zynthian-ui|zyncoder|zynthian-jalv) '; then
	restart_py=$ui/tools/restart_ui.py
	rc=0
	if [ -f "$restart_py" ]; then
		dev "python3 - $timeout" < "$restart_py" || rc=$?
	else
		rc=10
	fi
	case $rc in
		0) ;;
		10) echo "zynthian not running (or no restart_ui.py): restarting the session"; dev "$session_restart" ;;
		*) echo "restart_ui.py: exit code $rc" >&2; exit "$rc" ;;
	esac
fi
