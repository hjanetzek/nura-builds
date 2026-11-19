# Kernels: PREEMPT_RT variants for zynthian hardware (aarch64). Each is its own build; one failing
# doesn't stop the other. Long builds, but only when their recipe changes.
# - linux-rpi-rt: Alpine's linux-rpi with PREEMPT_RT and 1000 Hz (Raspberry Pi 4 kits)
# - linux-postmarketos-amlogic-rt: pmaports' linux-postmarketos-amlogic with PREEMPT_RT and 1000 Hz
#   (ODROID N2/N2+, docs/odroid-n2.md)
ARCHES="aarch64"
PACKAGES="linux-rpi-rt linux-postmarketos-amlogic-rt"
KEEPGOING=1
