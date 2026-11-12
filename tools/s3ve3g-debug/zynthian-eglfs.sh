#!/bin/sh
# zynthian's Qt UI full-screen on the Samsung Galaxy S III Neo without a compositor (Qt's eglfs on
# KMS), as the logged-in user (groups video, input, audio). Copy to the phone and run there.
#
# - ZYNTHIAN_UI=qt: the Qt UI (without it zynthian_desktop.sh starts the Tk UI through XWayland)
# - eglfs_kms on the GPU's DRM device (/tmp/kms.json: { "device": "/dev/dri/card1" })
# - landscape by ZYNTHIAN_UI_ROTATION=90 (zynthian-ui 780cf605: the UI rotated in QML; eglfs doesn't
#   rotate Qt Quick, the MDP planes can't rotate by 90); scale 1.5: 853x480 logical pixels
# - touch through Qt's evdevtouch (QT_QPA_EGLFS_NO_LIBINPUT=1): raw panel coordinates, which the QML
#   rotation maps; libinput would apply the udev calibration matrix meant for cage
# - FD_MESA_DEBUG=inorder: works around the freedreno a3xx flicker until Mesa 26.2.6-r1 (nura-builds
#   armv7 repository) is installed
# - JACK with the dummy backend (no audio codec driver yet)
# Logs: /tmp/zyn-eglfs.log, /tmp/jackd.log. zynthian_desktop.sh restarts zynthian when it exits:
# stop that script first when restarting by hand, or two instances fight over DRM master.
[ -f /tmp/kms.json ] || echo '{ "device": "/dev/dri/card1" }' > /tmp/kms.json
pgrep -x jackd >/dev/null || { jackd -R -d dummy -r 48000 -p 256 > /tmp/jackd.log 2>&1 & sleep 2; }
export ZYNTHIAN_UI=qt ZYNTHIAN_FULLSCREEN=1 ZYNTHIAN_UI_SCALE=auto ZYNTHIAN_UI_ROTATION=${ZYNTHIAN_UI_ROTATION:-90}
export QT_QPA_PLATFORM=eglfs QT_QPA_EGLFS_INTEGRATION=eglfs_kms QT_QPA_EGLFS_KMS_CONFIG=/tmp/kms.json
export QT_QPA_EGLFS_NO_LIBINPUT=1 QT_SCALE_FACTOR=${QT_SCALE_FACTOR:-1.5} QT_QPA_EGLFS_HIDECURSOR=1
export FD_MESA_DEBUG=${FD_MESA_DEBUG-inorder}
exec zynthian > /tmp/zyn-eglfs.log 2>&1
