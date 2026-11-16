# Package sets

Packages built from nura-builds' own recipes and published to the package repository (the
releases `<arch>`), independently of the targets (docs/ci-plan.md). One file per set, sourced by
scripts/set-packages.sh and scripts/plan-packages.py; `order` lists the sets in build order (a set
may depend on the sets before it).

Variables of a set file:
- `ARCHES`: architectures to build for
- `PACKAGES`: the packages (recipe directory names, as pmbootstrap builds them), in build
  order; `;` separates groups whose later ones need the earlier ones in the repository first
  (Qt: the recipes ask for the other Qt modules without a version, Alpine's would do)
- `DIRS`: instead of (or besides) `PACKAGES`: every recipe directory below these directories
- `PACKAGES_<arch>`, `EXCLUDE_<arch>`: another list for an architecture, or packages left out
  there. A recipe whose arch= excludes the architecture is skipped anyway.
- `FORCE_AFTER`: sets whose rebuild forces this set's rebuild (packages linked against them,
  e.g. qt-declarative after qt-base)
- `KEEPGOING`: a package that fails doesn't stop the others (reported in the run's summary)
- `ADD_ARCH_<arch>`: recipe directories whose arch= lacks the architecture yet: added for the build
