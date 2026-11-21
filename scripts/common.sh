# Shared by the scripts: paths, the pmbootstrap call, the target's settings.
# Environment: TARGET (default zynthian), NURA_WORK (pmbootstrap work dir, default
# ~/nura-work), NURA_SRC (checkouts of the source repositories, default ~/nura-src),
# NURA_OUT (packages and images to keep, default ./out), NURA_ARCH (aarch64, default, or x86_64).
set -eu

here=$(cd "$(dirname "$0")/.." && pwd)
TARGET=${TARGET:-zynthian}
. "$here/targets/$TARGET.sh"

NURA_WORK=${NURA_WORK:-$HOME/nura-work}
NURA_SRC=${NURA_SRC:-$HOME/nura-src}
NURA_OUT=${NURA_OUT:-$here/out}
CFG=${NURA_CFG:-$HOME/.config/pmbootstrap-nura-$TARGET.cfg}
# pmbootstrap's pmaports checkout (its default path; CI caches it)
PMAPORTS=${NURA_PMAPORTS:-$HOME/.local/var/pmbootstrap/cache_git/pmaports}
ARCH=${NURA_ARCH:-aarch64}
# The devices of the architecture (DEVICES_<arch> in the target file; DEVICES: aarch64's)
eval "DEVICES=\${DEVICES_$ARCH:-\${DEVICES:-}}"
# Other settings of the architecture (<VAR>_<arch> in the target file, e.g. STAGES_armv7)
eval "STAGES=\${STAGES_$ARCH:-\$STAGES} UI=\${UI_$ARCH:-\$UI}"
eval "IMAGE_PACKAGES=\${IMAGE_PACKAGES_$ARCH:-\${IMAGE_PACKAGES:-}} ADD_ARCH=\${ADD_ARCH_$ARCH:-}"
# pmbootstrap's service manager (SERVICE_MANAGER[_<arch>] in the target file, default systemd)
eval "SERVICE_MANAGER=\${SERVICE_MANAGER_$ARCH:-\${SERVICE_MANAGER:-systemd}}"
eval "OVERLAY=\${OVERLAY_$ARCH:-\${OVERLAY:-}}"
# Target name in cache keys: as before for aarch64, <target>_<arch> for the others (no "-":
# prune-cache.sh splits keys at "-")
KEY_TARGET=$TARGET
[ "$ARCH" = aarch64 ] || KEY_TARGET=${TARGET}_$ARCH

pmb() {
	pmbootstrap -c "$CFG" -y "$@"
}

# @repo/path -> checkout path; other paths relative to nura-builds
resolve() {
	case $1 in
		@*) r=${1#@}; echo "$NURA_SRC/${r%%/*}${r#"${r%%/*}"}" ;;
		/*) echo "$1" ;;
		*) echo "$here/$1" ;;
	esac
}

# What a stage builds: STAGE_<stage>_<arch> if the target file has it, else STAGE_<stage>
stage_builds() {
	eval "printf '%s\n' \"\${STAGE_$1_$ARCH:-\${STAGE_$1:-}}\""
}

# Hash of a stage's inputs, for the package cache key: what it builds (STAGE_<stage>, so adding a
# package to the list invalidates the cache) and its recipe directories (INPUTS_<stage>)
# The CPU baseline's hash when scripts/abuild-cpu.conf has flags for $ARCH (a "<arch>)" branch),
# nothing otherwise: a change rebuilds only that architecture's packages (plan-packages.py likewise)
cpu_baseline_hash() {
	! grep -q "^[[:space:]]*$ARCH)" "$here/scripts/abuild-cpu.conf" || sha256sum < "$here/scripts/abuild-cpu.conf"
}

stage_hash() {
	builds=$(stage_builds "$1")
	eval "inputs=\${INPUTS_$1:-}"
	# shellcheck disable=SC2154 # set by eval
	{
		echo "$builds"
		# the CPU baseline, for the architectures it has flags for (scripts/abuild-cpu.conf)
		cpu_baseline_hash
		# the service manager the packages are built for, when it isn't systemd
		[ "$SERVICE_MANAGER" = systemd ] || echo "service manager: $SERVICE_MANAGER"
		for p in $inputs; do
			d=$(resolve "$p")
			(cd "$d" && find . -type f ! -path "*/.git/*" | LC_ALL=C sort | xargs sha256sum)
		done
	} | sha256sum | cut -c1-16
}

# The local package repository (built .apk files) as a tarball, and back. The files belong to
# pmbootstrap's build user (uid 12345), so with sudo, keeping the owners.
packages_dir() {
	echo "$NURA_WORK/packages"
}
save_packages() {
	mkdir -p "$NURA_OUT"
	# a stage whose packages are all up to date in the binary repositories builds nothing:
	# pmbootstrap then has made no local repository
	sudo mkdir -p "$NURA_WORK/packages"
	sudo tar -C "$NURA_WORK" -cf "$NURA_OUT/packages.tar" packages
	sudo chown "$(id -u):$(id -g)" "$NURA_OUT/packages.tar"
}
restore_packages() {
	[ -f "$NURA_OUT/packages.tar" ] || return 0
	sudo tar -C "$NURA_WORK" --same-owner -xf "$NURA_OUT/packages.tar"
}
