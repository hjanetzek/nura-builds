# Qt 6.12 for Nura

Recipes for the Qt 6.12 modules zynthian's Qt Quick UI needs (qtbase, qtshadertools, qtsvg,
qtlanguageserver, qtdeclarative, qtwayland) and those Zrythm needs besides (qttools without qdoc and
clang's lupdate, qtcanvaspainter and qttasktree, new in 6.12). Alpine edge ships Qt 6.11; these are
the recipes of aports MR !107047, copied from Zrythm's Nura port (`tools/nura/qt6` on its
`nura-duet` branch; the target zrythm doesn't link that directory: two recipes of a name would
clash). Built as the package sets qt-base, qt-declarative, qt-wayland and qt-tools (sets/). The changes from the MR are marked
`# zrythm:` in each APKBUILD: Release builds without LTO and without debug info (the builds run
under qemu on x86_64 hosts, and debug info takes several GB), and qtwayland without its own
-private-dev in makedepends.

Once Alpine has Qt 6.12, drop these and build PySide6 against Alpine's Qt.
