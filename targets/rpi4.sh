# Target: Raspberry Pi 4 (zynthian kits, docs/zynthian-rpi.md). For now the PREEMPT_RT kernel
# (aports/kernel/linux-rpi-rt: Alpine's linux-rpi with PREEMPT_RT and 1000 Hz), as the .apk
# artifact apks-rpi4-kernel. Sourced by scripts/*.sh; built by .github/workflows/rpi4.yml on
# pushes to rpi4-* branches (and by hand). The device package and the zynthian packages for the
# Pi come from the zynthian target.

# No source repositories of our own: the recipe is in aports/
REPOS=""

STAGES="kernel"
STAGE_kernel="linux-rpi-rt"
INPUTS_kernel="aports/kernel/linux-rpi-rt"

# Packages published as their own artifact (the .apk files), per stage
PUBLISH_kernel="linux-rpi-rt linux-rpi-rt-dev"

# Images: none (the Pi image is built locally, docs/zynthian-rpi.md)
UI=none
DEVICES="raspberry-pi4"
