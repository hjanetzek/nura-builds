# Device packages of our own (devices/, linked into pmaports' device/testing by setup.sh) and their
# boot loaders (aarch64): the Raspberry Pi 4 with a zynthian kit (docs/zynthian-rpi.md), the plain
# ODROID N2 with its U-Boot (docs/odroid-n2.md). After the kernels: device-odroid-n2's kernel
# choice -kernel-amlogic-rt depends on ours.
# nura-builds-repo (aports/base, all architectures): the package repository as an apk source,
# installed into every image (scripts/image.sh).
ARCHES="aarch64 x86_64 armv7"
PACKAGES="nura-builds-repo device-zynthian-rpi4 u-boot-odroid-n2 device-odroid-n2"
PACKAGES_x86_64="nura-builds-repo"
PACKAGES_armv7="nura-builds-repo"
KEEPGOING=1
