#!/bin/sh
# A setting of the target for the architecture (after common.sh's <VAR>_<arch> overrides), for
# workflows: STAGES, DEVICES, UI, ...
#
# Usage: target-var.sh NAME      (TARGET, NURA_ARCH from the environment)
. "$(dirname "$0")/common.sh"
eval "printf '%s\n' \"\${$1:-}\""
