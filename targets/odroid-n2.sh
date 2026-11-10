# Target: Hardkernel ODROID N2 / N2+ (Amlogic S922X). For now the PREEMPT_RT kernel
# (aports/kernel/linux-postmarketos-amlogic-rt: pmaports' linux-postmarketos-amlogic with
# PREEMPT_RT and 1000 Hz), as the .apk artifact apks-odroid-n2-kernel. Sourced by scripts/*.sh;
# built by .github/workflows/odroid-n2.yml on pushes to odroid-* branches (and by hand).
# Devices: pmaports' device-odroid-n2plus (mainline U-Boot's odroid-n2 build, extlinux); a plain
# N2 is the same with deviceinfo_dtb="amlogic/meson-g12b-odroid-n2" (the kernel ships both dtbs).

# No source repositories of our own: the recipe is in aports/
REPOS=""

STAGES="kernel"
STAGE_kernel="linux-postmarketos-amlogic-rt"
INPUTS_kernel="aports/kernel/linux-postmarketos-amlogic-rt"

# Packages published as their own artifact (the .apk files), per stage
PUBLISH_kernel="linux-postmarketos-amlogic-rt"

# Images: none yet. The device only sets up pmbootstrap (aarch64), as in targets/rpi4.sh: no
# prompt that setup.sh's default answers would refuse
UI=none
DEVICES="qemu-aarch64"
