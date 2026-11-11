#!/bin/sh
# Set up pmbootstrap for a target: check out the source repositories, write the pmbootstrap
# config, initialise the work dir (non-interactively), link the recipe directories into pmaports,
# install the package signing key and restore built packages from $NURA_OUT/packages.tar.
#
# Signing key (required in CI): NURA_ABUILD_KEY (the private key, PEM) and NURA_ABUILD_KEY_NAME (its
# file name, e.g. pmos@local-6ae1d406.rsa). Without them pmbootstrap creates a key per work dir:
# packages from different runs then don't trust each other, and the package cache is useless.
. "$(dirname "$0")/common.sh"

# pmbootstrap (the version the local builds use)
if ! command -v pmbootstrap >/dev/null; then
	pip install --user --break-system-packages "git+https://gitlab.postmarketos.org/postmarketOS/pmbootstrap.git@3.12.1"
	export PATH="$HOME/.local/bin:$PATH"
fi

# Source repositories
mkdir -p "$NURA_SRC"
echo "$REPOS" | while read -r name url branch recipes; do
	[ -n "$name" ] || continue
	var=$(echo "$name" | tr 'a-z-' 'A-Z_')_REF
	eval "ref=\${$var:-$branch}"
	# shellcheck disable=SC2154 # set by eval
	if [ -d "$NURA_SRC/$name/.git" ]; then
		# undo the arch additions of an earlier run (below), or the checkout could refuse
		for p in $ADD_ARCH; do
			case $p in "@$name/"*) git -C "$NURA_SRC/$name" checkout -q -- "${p#"@$name/"}/APKBUILD" 2>/dev/null || true ;; esac
		done
		git -C "$NURA_SRC/$name" fetch -q origin "$ref"
		git -C "$NURA_SRC/$name" checkout -q FETCH_HEAD
	else
		git clone -q --depth 1 --branch "$ref" "$url" "$NURA_SRC/$name"
	fi
	echo "$name: $(git -C "$NURA_SRC/$name" log -1 --format='%h %s')"
done

# Recipes of other repositories that don't list the architecture yet (ADD_ARCH_<arch> in the
# target file): add it to their arch= in the checkout
for p in $ADD_ARCH; do
	f=$(resolve "$p")/APKBUILD
	[ -f "$f" ] || { echo "ADD_ARCH: no $f" >&2; exit 1; }
	if ! grep -Eq "^arch=\"(.* )?($ARCH|all)( .*)?\"" "$f"; then
		sed -i "s/^arch=\"\(.*\)\"/arch=\"\1 $ARCH\"/" "$f"
		echo "$p: $(grep '^arch=' "$f") (added $ARCH)"
	fi
done

# Config: as the local Duet builds (edge, systemd, PipeWire), device and UI of the target
mkdir -p "$(dirname "$CFG")"
cat > "$CFG" <<EOF
[pmbootstrap]
aports = $PMAPORTS
device = $(echo "$DEVICES" | awk '{print $1}')
hostname = nura-$TARGET
is_default_channel = False
locale = C.UTF-8
service_manager = systemd
ssh_keys = False
timezone = Europe/Berlin
ui = $UI
user = user
work = $NURA_WORK
jobs = $(nproc)

[providers]
postmarketos-base-ui-audio-backend = postmarketos-base-ui-audio-backend-pipewire

[mirrors]
EOF

# Signing key, before pmbootstrap init: the build chroots trust the keys in config_abuild. In CI it
# is required: every runner would make its own key, and the next job would not trust the packages.
if [ -n "${GITHUB_ACTIONS:-}" ] && { [ -z "${NURA_ABUILD_KEY:-}" ] || [ -z "${NURA_ABUILD_KEY_NAME:-}" ]; }; then
	echo "::error::NURA_ABUILD_KEY and NURA_ABUILD_KEY_NAME secrets are not set (see README: Secrets)"
	exit 1
fi
if [ -n "${NURA_ABUILD_KEY:-}" ] && [ -n "${NURA_ABUILD_KEY_NAME:-}" ]; then
	keys="$NURA_WORK/config_abuild"
	# The work dir belongs to the user (pmbootstrap writes its log there), config_abuild to
	# pmbootstrap's build user (12345), as pmbootstrap sets them up itself
	mkdir -p "$NURA_WORK"
	sudo mkdir -p "$keys"
	printf '%s\n' "$NURA_ABUILD_KEY" | sudo tee "$keys/$NURA_ABUILD_KEY_NAME" >/dev/null
	sudo openssl rsa -in "$keys/$NURA_ABUILD_KEY_NAME" -pubout -out "$keys/$NURA_ABUILD_KEY_NAME.pub" 2>/dev/null
	echo "PACKAGER_PRIVKEY=\"/home/pmos/.abuild/$NURA_ABUILD_KEY_NAME\"" | sudo tee "$keys/abuild.conf" >/dev/null
	sudo chown -R 12345:12345 "$keys"
	sudo chmod 600 "$keys/$NURA_ABUILD_KEY_NAME"
	# Trusted in the chroots: config_apk_keys is mounted as their /etc/apk/keys. pmbootstrap only
	# copies a key there when it generates one itself (no abuild.conf yet); root-owned like the
	# repository keys it adds
	sudo mkdir -p "$NURA_WORK/config_apk_keys"
	sudo cp "$keys/$NURA_ABUILD_KEY_NAME.pub" "$NURA_WORK/config_apk_keys/"
	sudo chown root:root "$NURA_WORK/config_apk_keys/$NURA_ABUILD_KEY_NAME.pub"
	echo "signing key: $NURA_ABUILD_KEY_NAME"
fi

# CI: pmaports from the Actions cache, brought up to date with origin and without the changes of
# the run that saved it (pinned recipes, overlays, recipe links); pmbootstrap init clones it
# otherwise. Not locally: there it is the user's own checkout.
if [ -n "${GITHUB_ACTIONS:-}" ] && [ -d "$PMAPORTS/.git" ]; then
	git -C "$PMAPORTS" fetch -q origin main
	git -C "$PMAPORTS" checkout -q -B main FETCH_HEAD
	git -C "$PMAPORTS" reset -q --hard
	git -C "$PMAPORTS" clean -qfd
	echo "pmaports: $(git -C "$PMAPORTS" log -1 --format='%h %cs %s')"
fi

# Overlays: the target's recipe directories (with an APKBUILD) copied over the same path in
# pmaports (OVERLAY, or OVERLAY_<arch>, in the target file), other copies of the recipe (e.g. an
# archived one) removed; their list goes to $NURA_WORK/nura-overlays for pin-binary.sh. Before
# pmbootstrap init: it asks about an archived device (no by default) and must see the overlay's.
mkdir -p "$NURA_WORK"
: > "$NURA_WORK/nura-overlays"
if [ -n "${OVERLAY:-}" ]; then
	[ -d "$PMAPORTS/.git" ] || git clone -q https://gitlab.postmarketos.org/postmarketOS/pmaports.git "$PMAPORTS"
	(cd "$here/$OVERLAY" && find . -name APKBUILD | sed 's|^\./||; s|/APKBUILD$||') |
	while read -r dir; do
		(cd "$PMAPORTS" && find . -mindepth 2 -maxdepth 3 -type d -name "$(basename "$dir")" \
			! -path "./.git/*" ! -path "./extra-repos/*") | sed 's|^\./||' |
		while read -r other; do
			[ "$other" = "$dir" ] || { rm -rf "${PMAPORTS:?}/$other"; echo "overlay: removed $other"; }
		done
		rm -rf "${PMAPORTS:?}/$dir"
		mkdir -p "$PMAPORTS/$(dirname "$dir")"
		cp -r "$here/$OVERLAY/$dir" "$PMAPORTS/$dir"
		echo "$dir" >> "$NURA_WORK/nura-overlays"
		echo "overlay: $dir"
	done
fi

# Initialise: every question answered with the default from the config (with a time limit: a
# question whose default isn't accepted would be asked again forever)
if [ ! -f "$NURA_WORK/version" ]; then
	yes "" | timeout 900 pmbootstrap -c "$CFG" init || true
	[ -f "$NURA_WORK/version" ] || { echo "pmbootstrap init failed" >&2; exit 1; }
fi

# Recipe directories into pmaports
aports=$(pmbootstrap -c "$CFG" config aports)
ln -sfn "$here/aports" "$aports/nura-builds"
echo "$REPOS" | while read -r name url branch recipes; do
	[ -n "$name" ] && [ "$recipes" != "-" ] || continue
	ln -sfn "$NURA_SRC/$name/$recipes" "$aports/$name"
done

# Device packages (kernel, ...) at the versions postmarketOS has built, not newer recipes
"$here/scripts/pin-binary.sh"

restore_packages
