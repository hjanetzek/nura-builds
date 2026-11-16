# Packages that must no longer come from nura-builds' package repository on an architecture
# (origins: subpackages go with them), because the distribution has them now: fetch-released.sh
# leaves them out of a build's repository, publish.sh removes them from the release's index and
# manifest (and their files) on its next publication. The recipes may stay for other
# architectures (sets/*.sh: ARCHES).
#
# Qt 6.12 and PySide6 6.12 are in Alpine edge for aarch64 and x86_64 since 2026-11 (armv7 still
# has 6.11): ours (same versions, built with other options) would shadow Alpine's or mix with it.
QT_ALPINE="qt6-qtbase qt6-qtshadertools qt6-qtsvg qt6-qtlanguageserver qt6-qtdeclarative qt6-qtwayland qt6-qttools pyside6"
DROPPED_aarch64="$QT_ALPINE"
DROPPED_x86_64="$QT_ALPINE"
DROPPED_armv7=""
