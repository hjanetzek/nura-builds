# Target: Samsung Galaxy S III Neo (samsung-s3ve3g, MSM8226, armv7), see docs/samsung-s3ve3g.md.
# The mainline kernel with a full device tree for the phone and the device package on it, from
# overlays of pmaports' recipes (pmaports' device package is archived: the downstream kernel 3.4).
# Sourced by scripts/*.sh with NURA_ARCH=armv7; built by .github/workflows/galaxy-s3-neo.yml on
# pushes to galaxy-s3-neo* branches. Images are built locally (docs/samsung-s3ve3g.md).

# No source repositories of our own
REPOS=""

# Overlays: recipe directories below overlays/s3ve3g/, copied over the same path in pmaports
# (scripts/setup.sh, before pmbootstrap init; other copies of a recipe, such as pmaports' archived
# device package, removed); pin-binary.sh leaves them alone
OVERLAY=overlays/s3ve3g

STAGES="kernel"
STAGE_kernel="linux-postmarketos-qcom-msm8226 device-samsung-s3ve3g"
INPUTS_kernel="overlays/s3ve3g"

# Packages published as their own artifact (the .apk files), per stage
PUBLISH_kernel="linux-postmarketos-qcom-msm8226 device-samsung-s3ve3g"

# Images (locally): a minimal one, no UI
UI=none
DEVICES="samsung-s3ve3g"
