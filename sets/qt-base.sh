# Qt 6.12's base modules (replacing Alpine's 6.11; the zynthian Qt UI needs 6.12).
# Not built anymore: Alpine edge has Qt 6.12 (and PySide6 6.12) on aarch64, x86_64 and armv7
# (sets/dropped.sh). The recipes stay for when Alpine lags behind again.
ARCHES=""
PACKAGES="qt6-qtbase qt6-qtshadertools qt6-qtsvg qt6-qtlanguageserver"
