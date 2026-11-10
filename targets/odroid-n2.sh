# Target: Hardkernel ODROID N2 / N2+ (Amlogic S922X): the PREEMPT_RT kernel
# (aports/kernel/linux-postmarketos-amlogic-rt: pmaports' linux-postmarketos-amlogic with
# PREEMPT_RT and 1000 Hz) and the plain N2's device packages, as .apk artifacts
# (apks-odroid-n2-kernel, apks-odroid-n2-device). Sourced by scripts/*.sh;
# built by .github/workflows/odroid-n2.yml on pushes to odroid-* branches (and by hand).
# Devices: the N2+ is pmaports' device-odroid-n2plus; the plain N2 is devices/device-odroid-n2 (with
# devices/u-boot-odroid-n2), built in the device stage.

# No source repositories of our own: the recipe is in aports/
REPOS=""

STAGES="kernel device"
STAGE_kernel="linux-postmarketos-amlogic-rt"
INPUTS_kernel="aports/kernel/linux-postmarketos-amlogic-rt"
# The plain N2 (devices/): U-Boot with the N2's boot firmware, the device package with the kernel
# choice (linux-postmarketos-amlogic from postmarketOS' repository, or the RT build above)
STAGE_device="u-boot-odroid-n2 device-odroid-n2"
INPUTS_device="devices/u-boot-odroid-n2 devices/device-odroid-n2"

# Packages published as their own artifact (the .apk files), per stage
PUBLISH_kernel="linux-postmarketos-amlogic-rt"
PUBLISH_device="u-boot-odroid-n2 device-odroid-n2 device-odroid-n2-kernel-amlogic device-odroid-n2-kernel-amlogic-rt"

# Images: none yet. The device only sets up pmbootstrap (aarch64), as in targets/rpi4.sh: no
# prompt that setup.sh's default answers would refuse
UI=none
DEVICES="qemu-aarch64"
