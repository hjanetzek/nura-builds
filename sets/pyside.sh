# PySide6 (Qt for Python) for zynthian's Qt UI, against our Qt 6.12 (it uses Qt's private API,
# tied to the Qt build). Only armv7: Alpine edge has PySide6 6.12 for aarch64 and x86_64 (with all
# modules; ours is a subset), sets/dropped.sh
ARCHES="armv7"
PACKAGES="pyside6"
FORCE_AFTER="qt-base qt-declarative qt-wayland"
