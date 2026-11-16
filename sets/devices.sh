# Device packages of our own (devices/, linked into pmaports' device/testing by setup.sh) and their
# boot loaders (aarch64): the Raspberry Pi 4 with a zynthian kit (docs/zynthian-rpi.md), the plain
# ODROID N2 with its U-Boot (docs/odroid-n2.md). After the kernels: device-odroid-n2's kernel
# choice -kernel-amlogic-rt depends on ours.
ARCHES="aarch64"
PACKAGES="device-zynthian-rpi4 u-boot-odroid-n2 device-odroid-n2"
KEEPGOING=1
