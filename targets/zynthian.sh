# Target: zynthian (Qt Quick UI) for Nura on aarch64 devices. Sourced by scripts/*.sh.

# Source repositories: name, URL, branch (override with <NAME>_REF in the environment, e.g.
# ZYNTHIAN_UI_REF=my-branch), recipe directory linked into pmaports ("-": none, sources only)
REPOS="
zynthian-ui https://github.com/hjanetzek/zynthian-ui nura nura
zyncoder    https://github.com/hjanetzek/zyncoder    nura -
drivenbymoss-rust https://github.com/hjanetzek/drivenbymoss-rust main nura
zynthian-packages https://github.com/hjanetzek/zynthian-packages nura nura
zynthian-webconf https://github.com/hjanetzek/zynthian-webconf nura nura
"

# Stages, built in this order; each one a list of pmbootstrap build arguments, separated by ";".
# @<repo> stands for the checkout of a repository (for --src builds). The Qt stages are separate
# because the recipes ask for the other Qt modules without a version: Alpine's Qt 6.11 would
# satisfy that, so the 6.12 packages of a stage must be in the local repository before the next.
STAGES="qt1 qt2 qt3 pyside plugins zynthian"
STAGE_qt1="qt6-qtbase qt6-qtshadertools qt6-qtsvg qt6-qtlanguageserver"
STAGE_qt2="qt6-qtdeclarative"
STAGE_qt3="qt6-qtwayland"
STAGE_pyside="pyside6"
# Engines and plugins the kiosk package depends on, and zynthian's jalv (zynthian-ui depends on it,
# and the --src build of zynthian-ui doesn't build missing dependencies). The meta packages pull in
# the LV2 plugins and Pure Data externals of aports/lv2 and aports/pd; engines (aports/engines) are
# named here, or the always-rebuilt zynthian stage would build them as the kiosk's dependencies.
# The instruments with large data (FluidPlug's SoundFonts, the AVL drumkits: ~450 MB, in -data
# subpackages) aren't in the meta package, to keep images small: built here for the package
# repository, to install by hand.
STAGE_plugins="zynthian-jalv zynthian-lv2-plugins zynthian-puredata zynaddsubfx setbfree sooperlooper fluidplug-lv2 avldrums-lv2"
# zynthian-ui and zyncoder are built from their checkouts (--src skips $source and doesn't build
# missing dependencies, hence the order); seed-distfiles.sh puts the bundled Python packages into
# the distfiles cache first. DrivenByMoss (its zynthian controller drivers, and dbm-nihost for the
# NI Maschine Mk2/JAM) from its checkout too, first (no dependency on the others; the Rust build
# fails early); its recipe fetches the Rust crates itself. The kiosk package depends on both.
STAGE_zynthian="--src=@drivenbymoss-rust drivenbymoss; --src=@drivenbymoss-rust dbm-nihost; --src=@zyncoder zyncoder; zynthian-data; --src=@zynthian-ui zynthian-ui; --src=@zynthian-packages zynthian-packages; --src=@zynthian-webconf zynthian-webconf; postmarketos-ui-zynthian"
SEED_zynthian="@zynthian-ui/nura/seed-distfiles.sh"

# Recipe directories whose contents decide whether a stage's cached packages are still valid
# (paths below the nura-builds checkout, or @<repo>/<path>)
INPUTS_qt1="aports/qt6/qt6-qtbase aports/qt6/qt6-qtshadertools aports/qt6/qt6-qtsvg aports/qt6/qt6-qtlanguageserver"
INPUTS_qt2="aports/qt6/qt6-qtdeclarative"
INPUTS_qt3="aports/qt6/qt6-qtwayland"
INPUTS_pyside="aports/pyside6"
INPUTS_plugins="aports/zynthian-jalv aports/lv2 aports/pd aports/engines"
INPUTS_zynthian=""   # always rebuilt: built from the checkouts

# Stages the weekly run (and the dispatch input "rebuild") builds from scratch: Qt and PySide
# replace Alpine's versions and link against its libraries, so an soname change there breaks them
# without a change to their recipes
REBUILD_STAGES="qt1 qt2 qt3 pyside"

# Images: pmbootstrap UI and the devices (pmaports device names)
UI=zynthian
DEVICES="google-kukui"
# amd64: the QEMU virtual machine (tools/run-qemu.sh), for testing on a desktop
DEVICES_x86_64="qemu-amd64"
# raspberry-pi4 is in pmaports' "downstream" category; add it here once tested
