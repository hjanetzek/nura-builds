# Qt Quick (qt6-qtdeclarative), after the base modules it links against.
# Only armv7: Alpine edge has Qt 6.12 for aarch64 and x86_64 since 2026-11 (sets/dropped.sh), armv7 still 6.11
ARCHES="armv7"
PACKAGES="qt6-qtdeclarative"
FORCE_AFTER="qt-base"
