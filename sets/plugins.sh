# LV2 plugins, Pure Data and its externals, the engines (zynaddsubfx, setBfree, LinuxSampler,
# Aeolus, SooperLooper, ...) and zynthian's jalv. Each recipe is its own package: one failing
# doesn't stop the others.
ARCHES="aarch64 x86_64 armv7"
DIRS="aports/zynthian-jalv aports/engines aports/lv2 aports/pd"
KEEPGOING=1
# armv7 (the Samsung Galaxy S III Neo): zynthian's own engines, and the plugins whose aarch64
# package is smaller than 2 MB (the release "aarch64", 2026-11-13), not the meta packages
# zynthian-lv2-plugins and zynthian-puredata, which depend on all of them. Not chow-kick-lv2:
# xsimd's NEON code doesn't build for 32-bit ARM.
PACKAGES_armv7="zynthian-jalv drivenbymoss aeolus sooperlooper libgig puredata fluid-soundfont linuxsampler setbfree
	abgate-lv2 aether-lv2 aida-x-lv2 ams-lv2 artyfx-lv2 avldrums-lv2 bolliedelay-lv2 chow-centaur-lv2
	dexed-lv2 dpf-plugins-lv2 dragonfly-reverb-lv2 eq10q-lv2 fabla-lv2 foo-yc20-lv2 granulator-lv2
	gula-plugins-lv2 gxplugins-lv2 infamous-lv2 invada-lv2 lv2-examples mimid-lv2 miniopl3-lv2
	mod-arpeggiator-lv2 mod-distortion-lv2 neural-amp-modeler-lv2 padthv1-lv2 punk-console-lv2
	qmidiarp-lv2 ratatouille-lv2 regrader-lv2 samplv1-lv2 shiro-lv2 string-machine-lv2 swh-lv2
	synthv1-lv2 talentedhack-lv2 triceratops-lv2 ykchorus-lv2 zynmi-lv2 pd-abl-link pd-clocker
	pd-freeverb pd-ggee pd-grids pd-hcs pd-iemlib pd-midifile pd-osc pd-plaits pd-tb-peakcomp
	pd-unauthorized"
ADD_ARCH_armv7="aports/lv2/aida-x-lv2 aports/lv2/chow-centaur-lv2 aports/lv2/neural-amp-modeler-lv2 aports/lv2/ratatouille-lv2"
