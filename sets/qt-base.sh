# Qt 6.12's base modules (replacing Alpine's 6.11; the zynthian Qt UI needs 6.12).
# Only armv7: Alpine edge has Qt 6.12 for aarch64 and x86_64 since 2026-11 (sets/dropped.sh), armv7 still 6.11
ARCHES="armv7"
PACKAGES="qt6-qtbase qt6-qtshadertools qt6-qtsvg qt6-qtlanguageserver"
