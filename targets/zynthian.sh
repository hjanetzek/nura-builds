# Target: zynthian (Qt Quick UI) for Nura on aarch64 devices. Sourced by scripts/*.sh.

# Source repositories: name, URL, branch (override with <NAME>_REF in the environment, e.g.
# ZYNTHIAN_UI_REF=my-branch), recipe directory linked into pmaports ("-": none, sources only)
REPOS="
zynthian-ui https://github.com/hjanetzek/zynthian-ui main nura
zyncoder    https://github.com/hjanetzek/zyncoder    nura -
drivenbymoss-rust https://github.com/hjanetzek/drivenbymoss-rust main nura
zynthian-packages https://github.com/hjanetzek/zynthian-packages nura nura
zynthian-webconf https://github.com/hjanetzek/zynthian-webconf nura nura
"

# Stages, built in this order; each one a list of pmbootstrap build arguments, separated by ";".
# @<repo> stands for the checkout of a repository (for --src builds). The Qt stages are separate
# because the recipes ask for the other Qt modules without a version: Alpine's Qt 6.11 would
# satisfy that, so the 6.12 packages of a stage must be in the local repository before the next.
STAGES="qt1 qt2 qt3 pyside plugins zynthian upstream"
STAGE_qt1="qt6-qtbase qt6-qtshadertools qt6-qtsvg qt6-qtlanguageserver"
STAGE_qt2="qt6-qtdeclarative"
STAGE_qt3="qt6-qtwayland"
STAGE_pyside="pyside6"
# Engines and plugins the kiosk package depends on, and zynthian's jalv (zynthian-ui depends on it,
# and the --src build of zynthian-ui doesn't build missing dependencies). The meta packages pull in
# the LV2 plugins and Pure Data externals of aports/lv2 and aports/pd; engines (aports/engines) are
# named here, or the always-rebuilt zynthian stage would build them as the kiosk's dependencies.
# The instruments with large data (FluidPlug's SoundFonts, the AVL drumkits: ~450 MB, in -data
# subpackages; the FluidR3 SoundFonts, 150 MB) aren't in the meta package, to keep images small:
# built here for the package repository; zynthian-factory-content (zynthian-packages) installs what
# ZynthianOS' image has of them. gearmulator (Osirus, OsTIrus) needs the user's ROMs: repository only too.
# plugdata (Pure Data with a JUCE GUI, standalone and LV2): repository only for now, meant as a GUI for
# Pd patches later.
STAGE_plugins="zynthian-jalv zynthian-lv2-plugins zynthian-puredata zynaddsubfx setbfree sooperlooper aeolus libgig linuxsampler fluidplug-lv2 avldrums-lv2 fluid-soundfont gearmulator-lv2 plugdata"
# zynthian-ui and zyncoder are built from their checkouts (--src skips $source and doesn't build
# missing dependencies, hence the order); seed-distfiles.sh puts the bundled Python packages into
# the distfiles cache first. DrivenByMoss (its zynthian controller drivers, the NI Maschine Mk2/JAM
# support in zynthian's process included) from its checkout too, first (no dependency on the others;
# the Rust build fails early); its recipe fetches the Rust crates itself. The kiosk package depends on it.
STAGE_zynthian="--src=@drivenbymoss-rust drivenbymoss; --src=@zyncoder zyncoder; zynthian-data; --src=@zynthian-ui zynthian-ui; --src=@zynthian-packages zynthian-packages; --src=@zynthian-webconf zynthian-webconf; postmarketos-ui-zynthian"
SEED_zynthian="@zynthian-ui/nura/seed-distfiles.sh"
# zynthian-ui from upstream's branches (vangelis, tomita) with the port patches, the Tk UI, for
# those who want zynthian as upstream ships it (aports/zynthian-upstream, docs/zynthian-upstream.md).
# After the zynthian stage: they need zyncoder, which is only built from its checkout there.
# Not in images; they provide zynthian-ui, so the kiosk package works with either.
STAGE_upstream="zynthian-ui-vangelis zynthian-ui-tomita"

# Recipe directories whose contents decide whether a stage's cached packages are still valid
# (paths below the nura-builds checkout, or @<repo>/<path>)
INPUTS_qt1="aports/qt6/qt6-qtbase aports/qt6/qt6-qtshadertools aports/qt6/qt6-qtsvg aports/qt6/qt6-qtlanguageserver"
INPUTS_qt2="aports/qt6/qt6-qtdeclarative"
INPUTS_qt3="aports/qt6/qt6-qtwayland"
INPUTS_pyside="aports/pyside6"
INPUTS_plugins="aports/zynthian-jalv aports/lv2 aports/pd aports/engines"
INPUTS_zynthian=""   # always rebuilt: built from the checkouts
INPUTS_upstream="aports/zynthian-upstream"

# Stages the weekly run (and the dispatch input "rebuild") builds from scratch: Qt and PySide
# replace Alpine's versions and link against its libraries, so an soname change there breaks them
# without a change to their recipes
REBUILD_STAGES="qt1 qt2 qt3 pyside"

# Images: pmbootstrap UI and the devices (pmaports device names)
UI=zynthian
DEVICES="google-kukui"
# amd64: the QEMU virtual machine (zynthian-ui's nura/tools/run_qemu.sh), for testing on a desktop
DEVICES_x86_64="qemu-amd64"
# raspberry-pi4 is in pmaports' "downstream" category; add it here once tested

# armv7 (branch zynthian-arm7, workflow zynthian-armv7.yml): the Samsung Galaxy S III Neo
# (samsung-s3ve3g, MSM8226) and other MSM8226 phones. Without the plugins stage (the LV2 plugins,
# Pure Data, the large engines): an "engines" stage builds only what zynthian-ui itself depends
# on. The kiosk package (postmarketos-ui-zynthian) depends on the plugins, so it isn't built: the
# image is a plain one (UI "none") with zynthian-ui installed, for bringing up the device.
# Overrides: <VAR>_<arch> (common.sh: STAGES, UI, IMAGE_PACKAGES; STAGE_<stage>_<arch>).
STAGES_armv7="qt1 qt2 qt3 pyside engines zynthian mesa"
STAGE_engines="zynthian-jalv aeolus sooperlooper"
# Last, so that a failure there doesn't hold up zynthian: Mesa with the freedreno a3xx fix for Qt
# Quick's flicker on the S III Neo (aports/mesa)
STAGE_mesa="mesa"
INPUTS_mesa="aports/mesa"
INPUTS_engines="aports/zynthian-jalv aports/engines/aeolus aports/engines/sooperlooper"
STAGE_zynthian_armv7="--src=@drivenbymoss-rust drivenbymoss; --src=@zyncoder zyncoder; zynthian-data; --src=@zynthian-ui zynthian-ui; --src=@zynthian-packages zynthian-packages; --src=@zynthian-webconf zynthian-webconf"
UI_armv7=none
IMAGE_PACKAGES_armv7="zynthian-ui"
# Device: the generic mainline MSM8226 port (pmaports device/testing, linux-postmarketos-qcom-msm8226
# with the s3ve3g's device tree; booted by lk2nd, flashed once with heimdall). The S III Neo's own
# device package (samsung-s3ve3g) is archived, with the downstream 3.4 kernel: too old for systemd.
DEVICES_armv7="qcom-msm8226"
# Recipes of the other repositories whose arch= lacks armv7 (aarch64 x86_64): setup.sh adds it in
# the checkouts until the recipes list armv7 themselves
ADD_ARCH_armv7="@zynthian-ui/nura/zynthian-ui @zynthian-ui/nura/zyncoder @drivenbymoss-rust/nura/drivenbymoss"
