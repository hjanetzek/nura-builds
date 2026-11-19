#!/bin/sh
# The origins sets/dropped.sh lists for the architecture (NURA_ARCH), space-separated
. "$(dirname "$0")/../sets/dropped.sh"
eval "printf '%s\n' \"\${DROPPED_${NURA_ARCH:-aarch64}:-}\""
