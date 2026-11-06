#!/bin/sh
# Add a stage's cached packages to the local repository, which holds the previous stage's packages
# (scripts/setup.sh restored them): files the repository already has are kept, so packages the
# previous stage rebuilt (the weekly rebuild of Qt) replace the older copies in this stage's cache,
# which holds the earlier stages' packages too. Then re-index (and sign) the repository.
#
# Usage: merge-cached.sh PACKAGES_TAR [--save]   (--save: write $NURA_OUT/packages.tar again)
. "$(dirname "$0")/common.sh"

sudo tar -C "$NURA_WORK" --same-owner --skip-old-files -xf "$1"
pmb index
[ "${2:-}" != "--save" ] || save_packages
