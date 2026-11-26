# PySide6 (Qt for Python) for zynthian's Qt UI, against our Qt 6.12 (it uses Qt's private API,
# tied to the Qt build). Not built anymore: Alpine edge has PySide6 6.12 (all modules; ours is a
# subset) with its Qt 6.12 on aarch64, x86_64 and armv7 (sets/dropped.sh); the recipe stays.
ARCHES=""
PACKAGES="pyside6"
FORCE_AFTER="qt-base qt-declarative qt-wayland"
