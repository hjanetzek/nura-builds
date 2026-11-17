# Device packages of our own (devices/, linked into pmaports' device/testing by setup.sh) and their
# boot loaders (aarch64): the Raspberry Pi 4 with a zynthian kit (docs/zynthian-rpi.md), the plain
# ODROID N2 with its U-Boot (docs/odroid-n2.md). After the kernels: device-odroid-n2's kernel
# choice -kernel-amlogic-rt depends on ours.
# nura-builds-repo (aports/base, all architectures): the package repository as an apk source,
# installed into every image (scripts/image.sh). nura-powerkey (aports/base): the power key
# switches the screen on phones and tablets (Duet, Pixel 3).
ARCHES="aarch64 x86_64 armv7"
PACKAGES="nura-builds-repo nura-powerkey device-zynthian-rpi4 u-boot-odroid-n2 device-odroid-n2"
PACKAGES_x86_64="nura-builds-repo nura-powerkey"
PACKAGES_armv7="nura-builds-repo nura-powerkey"
KEEPGOING=1
