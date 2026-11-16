# Qt modules Zrythm needs besides zynthian's: Qt Tools (Linguist; without qdoc and clang's lupdate),
# Qt Canvas Painter and Qt TaskTree (new in 6.12, not in aports)
ARCHES="aarch64 x86_64"
PACKAGES="qt6-qttasktree qt6-qttools qt6-qtcanvaspainter"
FORCE_AFTER="qt-base qt-declarative"
