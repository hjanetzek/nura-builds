# Target: zynthian (Qt Quick UI) for Nura (aarch64, x86_64, armv7). Sourced by scripts/*.sh.

# Source repositories: name, URL, branch (override with <NAME>_REF in the environment, e.g.
# ZYNTHIAN_UI_REF=my-branch), recipe directory linked into pmaports ("-": none, sources only)
REPOS="
zynthian-ui https://github.com/hjanetzek/zynthian-ui main nura
zyncoder    https://github.com/hjanetzek/zyncoder    nura -
zynthian-packages https://github.com/hjanetzek/zynthian-packages nura nura
zynthian-webconf https://github.com/hjanetzek/zynthian-webconf nura nura
"

# Stages, built in this order; each one a list of pmbootstrap build arguments, separated by ";".
# @<repo> stands for the checkout of a repository (for --src builds). Only the target's own
# packages: Qt, PySide, the plugins and engines, zynthian-jalv, drivenbymoss and Mesa are package sets (sets/,
# workflow sets.yml), published to the package repository, which every target build starts from
# (scripts/fetch-released.sh, docs/ci-plan.md). The kiosk package depends on the plugin meta
# packages (zynthian-lv2-plugins, zynthian-puredata) from there. The instruments with large data
# (FluidPlug's SoundFonts, the AVL drumkits, the FluidR3 SoundFonts), gearmulator and plugdata are
# in the repository but not in the meta packages; zynthian-factory-content (zynthian-packages)
# installs what ZynthianOS' image has of them.
STAGES="zynthian upstream"
# zynthian-ui and zyncoder are built from their checkouts (--src skips $source and doesn't build
# missing dependencies, hence the order); seed-distfiles.sh puts the bundled Python packages into
# the distfiles cache first. DrivenByMoss (its zynthian controller drivers, the NI Maschine Mk2/JAM
# support in zynthian's process included) from its checkout too, first (no dependency on the others;
# the Rust build fails early); its recipe fetches the Rust crates itself. The kiosk package depends on it.
STAGE_zynthian="--src=@zyncoder zyncoder; zynthian-data; --src=@zynthian-ui zynthian-ui; --src=@zynthian-packages zynthian-packages; --src=@zynthian-webconf zynthian-webconf; postmarketos-ui-zynthian"
SEED_zynthian="@zynthian-ui/nura/seed-distfiles.sh"
# aarch64: also the zynthian kits' hardware (Raspberry Pi 4, docs/zynthian-rpi.md): zyncoder-hw (the
# kits' builds of zyncore, from the zyncoder checkout) and zynthian-hw (zynthian-kit, the kit setup)
STAGE_zynthian_aarch64="$STAGE_zynthian; --src=@zyncoder zyncoder-hw; zynthian-hw"
# zynthian-ui from upstream's branches (vangelis, tomita) with the port patches, the Tk UI, for
# those who want zynthian as upstream ships it (aports/zynthian-upstream, docs/zynthian-upstream.md).
# After the zynthian stage: they need zyncoder, which is only built from its checkout there.
# Not in images; they provide zynthian-ui, so the kiosk package works with either.
STAGE_upstream="zynthian-ui-vangelis zynthian-ui-tomita"

# Images: pmbootstrap UI and the devices (pmaports device names)
UI=zynthian
DEVICES="google-kukui zynthian-rpi4"
# zynthian-rpi4: a Raspberry Pi 4 with a zynthian kit (devices/device-zynthian-rpi4,
# docs/zynthian-rpi.md, docs/rpi-plan.md). Extra packages of a device's image:
# EXTRA_PACKAGES_<device, "-" as "_">
EXTRA_PACKAGES_zynthian_rpi4="zynthian-hw"
# Images the workflow builds (IMAGE_DEVICES_<arch>; default DEVICES): aarch64 for now only the Pi, one image per
# kit with the kit preset (IMAGE_KITS_<device>, scripts/image.sh): written to an SD card and booted,
# nothing to configure. The Duet's image by hand (zynthian.yml, input devices).
IMAGE_DEVICES_aarch64="zynthian-rpi4"
IMAGE_KITS_zynthian_rpi4="V4 V5"
# The Pi's kernel (device-zynthian-rpi4-kernel-*): Alpine's linux-rpi for now; rpi-rt is ours with
# PREEMPT_RT (aports/kernel/linux-rpi-rt), not the default until tested on the kits
IMAGE_KERNEL_zynthian_rpi4="rpi"
# The user's password in the images: ZynthianOS' ("raspberry"), so zynthian owners can log in as they
# are used to (the secret NURA_IMAGE_PASSWORD overrides it)
IMAGE_PASSWORD="raspberry"
# amd64: the QEMU virtual machine (zynthian-ui's nura/tools/run_qemu.sh), for testing on a desktop
DEVICES_x86_64="qemu-amd64"
# raspberry-pi4 is in pmaports' "downstream" category; add it here once tested

# armv7: the Samsung Galaxy S III Neo (samsung-s3ve3g, MSM8226) and other MSM8226 phones. Only
# part of the plugins are built for armv7 (sets/plugins.sh), not the meta packages, so the kiosk
# package (postmarketos-ui-zynthian) isn't built: the image is a plain one (UI "none") with
# zynthian-ui installed, for bringing up the device.
# Overrides: <VAR>_<arch> (common.sh: STAGES, UI, IMAGE_PACKAGES; STAGE_<stage>_<arch>).
STAGES_armv7="zynthian"
STAGE_zynthian_armv7="--src=@zyncoder zyncoder; zynthian-data; --src=@zynthian-ui zynthian-ui; --src=@zynthian-packages zynthian-packages; --src=@zynthian-webconf zynthian-webconf"
UI_armv7=none
IMAGE_PACKAGES_armv7="zynthian-ui"
# Device: the generic mainline MSM8226 port (pmaports device/testing, linux-postmarketos-qcom-msm8226
# with the s3ve3g's device tree; booted by lk2nd, flashed once with heimdall). The S III Neo's own
# device package (samsung-s3ve3g) is archived, with the downstream 3.4 kernel: too old for systemd.
DEVICES_armv7="qcom-msm8226"
# Recipes of the other repositories whose arch= lacks armv7 (aarch64 x86_64): setup.sh adds it in
# the checkouts until the recipes list armv7 themselves
ADD_ARCH_armv7="@zynthian-ui/nura/zynthian-ui @zynthian-ui/nura/zyncoder"
