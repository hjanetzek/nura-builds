# Target: Google Pixel 3 (google-blueline), see docs/google-blueline.md. For now the SDM845 kernel,
# from an overlay of pmaports' recipe (planned: the USB Type-C/VBUS series for USB OTG). Sourced by
# scripts/*.sh; built by .github/workflows/pixel3.yml on pushes to pixel3-* branches.

# No source repositories of our own yet
REPOS=""

# Overlays: recipe directories below overlays/pixel3/, copied over the same path in pmaports
# (scripts/setup.sh); pin-binary.sh leaves them alone
OVERLAY=overlays/pixel3

STAGES="kernel"
STAGE_kernel="linux-postmarketos-qcom-sdm845"
INPUTS_kernel="overlays/pixel3"

# Packages published as their own artifact (the .apk files), per stage
PUBLISH_kernel="linux-postmarketos-qcom-sdm845"

# Images: not yet (zynthian on the Pixel 3 comes later)
UI=none
DEVICES="google-blueline"
