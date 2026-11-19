# Qt modules Zrythm needs that Alpine doesn't package (new in 6.12): Qt TaskTree and Qt Canvas
# Painter, built against Alpine's Qt 6.12 (they use its private API: rebuilt when Alpine's Qt
# changes, check-abi.py notices a soname change, a pkgrel bump forces it otherwise). Qt Tools comes
# from Alpine.
ARCHES="aarch64 x86_64"
PACKAGES="qt6-qttasktree qt6-qtcanvaspainter"
