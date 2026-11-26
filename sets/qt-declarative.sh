# Qt Quick (qt6-qtdeclarative), after the base modules it links against.
# Not built anymore: Alpine edge has Qt 6.12 (and PySide6 6.12) on aarch64, x86_64 and armv7
# (sets/dropped.sh). The recipes stay for when Alpine lags behind again.
ARCHES=""
PACKAGES="qt6-qtdeclarative"
FORCE_AFTER="qt-base"
