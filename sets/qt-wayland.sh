# Qt's Wayland platform plugin.
# Not built anymore: Alpine edge has Qt 6.12 (and PySide6 6.12) on aarch64, x86_64 and armv7
# (sets/dropped.sh). The recipes stay for when Alpine lags behind again.
ARCHES=""
PACKAGES="qt6-qtwayland"
FORCE_AFTER="qt-base qt-declarative"
