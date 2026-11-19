# device-zynthian-rpi4 (sourced by tinydm for Wayland sessions): with the V4 kit's SPI panel
# (zynscreen-drm overlay, /dev/dri/zynscreen from 90-zynthian-hw.rules) the kiosk's compositor
# uses only the panel, not vc4's HDMI outputs. The panel has no GPU: wlroots renders on it in
# software (pixman), or set WLR_DRM_DEVICES in /etc/default/zynthian to try others.
if [ -e /dev/dri/zynscreen ] && [ -z "${WLR_DRM_DEVICES:-}" ]; then
	export WLR_DRM_DEVICES=/dev/dri/zynscreen
fi
