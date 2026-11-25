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
# 2026-11-18: also the plugins under 10 MB (aarch64) whose recipes allow armv7 and that aren't JUCE
# builds (JUCE ones take long on armv7 and are too heavy for the S III): mod-mda, geonkick,
# mod-utilities, guitarix, pd-cyclone, mod-pitchshifter, and zynaddsubfx (one of zynthian's own
# engines). Also Helm and DISTRHO's ports (OB-Xd, TAL, ...), JUCE builds but used by many factory
# snapshots (a try: heavy on the S III's CPU).
# 2026-11-23: eDrumSynth (MicroDexed-touch's drum engine; 12 % of the S III's CPU, idle or playing),
# mTrio and mAnalog (mdt-va-lv2: MicroDexed-touch's Trio and Analog; about 0.2 % with 8 voices).
# rt-tests (cyclictest, ...: latency measurements, also of the S III's audio setup).
PACKAGES_armv7="zynthian-jalv drivenbymoss zynaddsubfx aeolus sooperlooper libgig puredata fluid-soundfont linuxsampler setbfree
	abgate-lv2 aether-lv2 aida-x-lv2 ams-lv2 artyfx-lv2 avldrums-lv2 bolliedelay-lv2 chow-centaur-lv2
	dexed-lv2 dpf-plugins-lv2 dragonfly-reverb-lv2 eq10q-lv2 fabla-lv2 foo-yc20-lv2 granulator-lv2
	gula-plugins-lv2 gxplugins-lv2 infamous-lv2 invada-lv2 lv2-examples mimid-lv2 miniopl3-lv2
	mod-arpeggiator-lv2 mod-distortion-lv2 neural-amp-modeler-lv2 padthv1-lv2 punk-console-lv2
	qmidiarp-lv2 ratatouille-lv2 regrader-lv2 samplv1-lv2 shiro-lv2 string-machine-lv2 swh-lv2
	synthv1-lv2 talentedhack-lv2 triceratops-lv2 ykchorus-lv2 zynmi-lv2 pd-abl-link pd-clocker
	pd-freeverb pd-ggee pd-grids pd-hcs pd-iemlib pd-midifile pd-osc pd-plaits pd-tb-peakcomp
	pd-unauthorized pd-cyclone mod-mda-lv2 geonkick-lv2 mod-utilities-lv2 guitarix-lv2
	mod-pitchshifter-lv2 helm-lv2 distrho-ports-lv2
	edrumsynth-lv2 mdt-va-lv2 rt-tests"
# armv7 is a playground (what the old phone can do): -funsafe-math-optimizations lets GCC vectorise
# float code with armv7 NEON (NEON flushes denormals); -O3 because many plugin builds end up with
# abuild's -Os (DPF with NOOPT=true, meson's plain build type, Makefiles that append $(CFLAGS) after
# their own -O3). Measured on the S III Neo (lv2bench): artyfx 1.22x (up to 3.1x), String Machine's
# chorus 1.5x, Helm 1.3x, OB-Xd 1.35x
CFLAGS_armv7="-funsafe-math-optimizations -O3"
ADD_ARCH_armv7="aports/lv2/helm-lv2 aports/lv2/aida-x-lv2 aports/lv2/chow-centaur-lv2 aports/lv2/neural-amp-modeler-lv2 aports/lv2/ratatouille-lv2"
