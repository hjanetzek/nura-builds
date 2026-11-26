# Target: zynthian-ui-testing, zynthian's Qt UI from hjanetzek/zynthian-ui's `testing` branch
# (work in progress, force-pushed often), as its own package next to zynthian-ui: the same build
# (zynthian-ui's recipe, generated under another name by scripts/zynthian-ui-testing.sh,
# with the zynlibs and the DrivenByMoss drivers from the branch), the same paths, and
# provides="zynthian-ui=...": a device has either one (zynthian-ui's tools/switch_ui.sh).
# Everything else as the zynthian target (service manager per architecture, the published
# repository as the base); built and published by .github/workflows/zynthian-testing.yml.
# Sourced by scripts/*.sh.
. "$here/targets/zynthian.sh"

# Only zynthian-ui's checkout (override the branch with ZYNTHIAN_UI_REF)
REPOS="
zynthian-ui https://github.com/hjanetzek/zynthian-ui testing -
"

# One stage: --src builds get the version <pkgver base>_p<build time>, so every build is newer
# than the last (an upgrade on the devices) whatever the branch's history does
STAGES="testing"
STAGES_armv7="testing"
STAGE_testing="--src=@zynthian-ui zynthian-ui-testing"
SEED_testing="scripts/zynthian-ui-testing.sh"
