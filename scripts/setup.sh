#!/bin/sh
# Set up pmbootstrap for a target: check out the source repositories, write the pmbootstrap
# config, initialise the work dir (non-interactively), link the recipe directories into pmaports,
# install the package signing key and restore built packages from $NURA_OUT/packages.tar.
#
# Signing key (optional): NURA_ABUILD_KEY (the private key, PEM) and NURA_ABUILD_KEY_NAME (its
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
		git -C "$NURA_SRC/$name" fetch -q origin "$ref"
		git -C "$NURA_SRC/$name" checkout -q FETCH_HEAD
	else
		git clone -q --depth 1 --branch "$ref" "$url" "$NURA_SRC/$name"
	fi
	echo "$name: $(git -C "$NURA_SRC/$name" log -1 --format='%h %s')"
done

# Config: as the local Duet builds (edge, systemd, PipeWire), device and UI of the target
mkdir -p "$(dirname "$CFG")"
cat > "$CFG" <<EOF
[pmbootstrap]
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

# Initialise: every question answered with the default from the config
if [ ! -f "$NURA_WORK/version" ]; then
	yes "" | pmbootstrap -c "$CFG" init || true
	[ -f "$NURA_WORK/version" ] || { echo "pmbootstrap init failed" >&2; exit 1; }
fi

# Recipe directories into pmaports
aports=$(pmbootstrap -c "$CFG" config aports)
ln -sfn "$here/aports" "$aports/nura-builds"
echo "$REPOS" | while read -r name url branch recipes; do
	[ -n "$name" ] && [ "$recipes" != "-" ] || continue
	ln -sfn "$NURA_SRC/$name/$recipes" "$aports/$name"
done

# Signing key
if [ -n "${NURA_ABUILD_KEY:-}" ] && [ -n "${NURA_ABUILD_KEY_NAME:-}" ]; then
	keys="$NURA_WORK/config_abuild"
	sudo mkdir -p "$keys"
	printf '%s\n' "$NURA_ABUILD_KEY" | sudo tee "$keys/$NURA_ABUILD_KEY_NAME" >/dev/null
	sudo openssl rsa -in "$keys/$NURA_ABUILD_KEY_NAME" -pubout -out "$keys/$NURA_ABUILD_KEY_NAME.pub" 2>/dev/null
	echo "PACKAGER_PRIVKEY=\"/home/pmos/.abuild/$NURA_ABUILD_KEY_NAME\"" | sudo tee "$keys/abuild.conf" >/dev/null
	sudo chown -R 12345:12345 "$keys"
	sudo chmod 600 "$keys/$NURA_ABUILD_KEY_NAME"
	echo "signing key: $NURA_ABUILD_KEY_NAME"
fi

restore_packages
