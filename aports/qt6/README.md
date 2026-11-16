# Qt 6.12 for Nura

Alpine edge has Qt 6.12 (and PySide6 6.12) for aarch64 and x86_64 since November 2026, but still
6.11 for armv7. So:

- **armv7** (the Samsung Galaxy S III Neo): these recipes, for the modules zynthian's Qt Quick UI
  needs (qtbase, qtshadertools, qtsvg, qtlanguageserver, qtdeclarative, qtwayland), and PySide6
  against them (`aports/pyside6`); package sets qt-base, qt-declarative, qt-wayland, pyside
  (`sets/`, ARCHES armv7).
- **aarch64, x86_64**: Alpine's Qt and PySide6. Ours are left out of builds and removed from the
  package repository (`sets/dropped.sh`): with the same versions they would shadow Alpine's or mix
  with it (Qt's private API ties the modules to one build).
- **qtcanvaspainter, qttasktree** (new in 6.12, Zrythm needs them, Alpine doesn't package them):
  built against Alpine's Qt for aarch64 and x86_64 (package set qt-tools). Qt Tools comes from
  Alpine (the recipe here is gone).

The recipes are those of aports MR !107047, copied from Zrythm's Nura port (`tools/nura/qt6` on its
`nura` branch; the target zrythm doesn't link that directory: two recipes of a name would clash).
The changes from the MR are marked `# zrythm:` in each APKBUILD: Release builds without LTO and
without debug info, and qtwayland without its own -private-dev in makedepends.

Once Alpine has Qt 6.12 for armv7 too: drop the six module recipes and `aports/pyside6`, remove
the sets qt-base, qt-declarative, qt-wayland and pyside, and add the modules to `DROPPED_armv7`.
