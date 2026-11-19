# Plugin GUIs on Nura: plan

Status: 2026-11-07. Goal: zynthian opens an LV2 plugin's own GUI on demand (device menu >
Plugin GUI), shown by niri on a workspace of its own, next to zynthian's Qt UI.

## How it works

| Part | Where | What |
|---|---|---|
| niri session | `aports/zynthian/postmarketos-ui-zynthian` (subpackage `postmarketos-ui-zynthian-niri`, `kiosk-session zynthian-niri`) | zynthian on its workspace, every other window floating on a workspace of its own (`zynthian-niri-workspaces`), the overview to switch (Ctrl+Alt+O), a scrolling layout (Ctrl+Alt+S). X11 through xwayland-satellite, OpenGL on the GPU (glamor on). Sets `ZYNTHIAN_NATIVE_GUI=1` and `ZYNTHIAN_NATIVE_GUI_SCALE` (output scale). |
| jalv GTK frontend | nura-builds `aports/zynthian-jalv` (subpackage `zynthian-jalv-gtk`), `gtk-hide-ui.patch` | `jalv.gtk3 -H` starts with the window hidden; `ui show` / `ui hide` / `ui toggle` on stdin; closing the window only hides it; changes reported as `#GUI> shown` / `#GUI> hidden`. suil hosts X11 UIs (x11-in-gtk3) and GTK3 UIs; GTK2 and Qt5 UIs can't be hosted (Alpine's suil has no wrappers for them). |
| zynthian engine | zynthian-ui `zyngine/zynthian_engine_jalv.py` | With `ZYNTHIAN_NATIVE_GUI` and `DISPLAY`, plugins with an installed X11 UI run as `jalv.gtk3 -H -m` (GDK on X11, `DPF_SCALE_FACTOR` from the session); `show_native_gui()`, state from the `#GUI>` lines. |
| UI detection | zynthian-ui `zyngine/zynthian_lv2.py` `get_plugin_ui()` | From lilv: the preferred UI class (Qt5UI, Qt4UI, GtkUI, X11UI) among the UIs whose **binary is installed**; before, a substring search of the TTL counted UIs that weren't built. |
| Device menu | zynthian-ui `zynqt/screens/processor_options.py` | "☐ Plugin GUI" for processors whose engine can show one. |

The UI type is stored in zynthian's engine config at the plugin rescan
(`zynthian_lv2.py engines`): rescan after installing plugins with GUIs (`tools/device-update.sh -r`
does).

## Done

- jalv fork change (local branch `nura-ui-toggle` of zynthian/jalv, commit `c3c13b5`); recipe with
  the patch and `zynthian-jalv-gtk` (nura-builds branch `jalv-gtk`, built by CI with
  `packages.yml`, installed on the Duet).
- zynthian-ui (branch `nura-niri`): niri session, UI detection, engine, device menu.
- Tested on the Duet by script: ZamComp's GUI started hidden, shown (own workspace, focused) and
  hidden again (back to zynthian); detection: 53 enabled engines with an installed X11 UI (93
  before), abGate no longer Qt5UI.

## Next

1. **Test from zynthian's device menu** on the Duet (niri session): add a plugin with a GUI to a
   chain (ZamComp, x42-dpl, Surge XT, Odin2), device menu > Plugin GUI, back with the overview.
2. **Test the GUIs that are already shipped** in `jalv.gtk3` (no build work): Surge XT, Odin2,
   Vaporizer2, Helm, Monique, KR-106, ChowTapeModel, DuskVerb, 4K EQ 2 (Dusk DAF), a Zam plugin,
   x42-dpl, synthv1 (Qt6 inside GTK through the X11UI wrapper: needs xcb). Check: renders (GLX),
   size (scaling), input by touch, CPU while shown.
3. **Merge**: zynthian-ui `nura-niri` into `nura`, nura-builds `jalv-gtk` into `main`, push when
   no CI run is active; offer the jalv patch to zynthian/jalv and the UI detection to zynthian-ui
   (both in `docs/upstream-candidates.md` of zynthian-ui).
4. **Recipes with GUIs** (the packaging agent; list below).
5. **Touch gesture** to toggle between the overview and full screen (a swipe from a screen edge):
   to be designed (niri has no touchscreen gesture for the overview; a layer-shell strip at the
   edge is one option).

## Recipes: GUIs to enable (for the packaging agent)

"E" = plugins enabled in zynthian's default config. Hostable: X11UI or GTK3 UI. After building:
the UI binary must be installed (the detection only counts installed UIs), the TTL must declare it.

### Already shipped (no recipe change; to test, step 2)

JUCE recipes build the GUI into the plugin `.so` (manifest: `a ui:X11UI ; lv2:binary <libX.so>`):
byod, chow-centaur, chow-kick, chow-matrix, chow-multitool, chow-phaser, chow-tape-model, jc303,
kr106, monique, ripplerx, roboverb, surge-xt, odin2 (juce_opengl), vaporizer2 (juce_opengl),
dusk-audio-juce (12 bundles), helm (old JUCE, GL). Monolithic DPF+OpenGL: dusk-audio (DAF, 9
bundles). Qt6 UI with an X11UI wrapper: synthv1, samplv1, padthv1. Alpine: x42-plugins (robtk GL),
zam-plugins (DPF GL).

### First batch

| Recipe | E | Disabled by | Change |
|---|---|---|---|
| dragonfly-reverb-lv2 | 4 | `HAVE_OPENGL=false lv2_dsp` (APKBUILD:21) | `make -C "$p" NOOPT=true lv2_sep`; makedepends `+libx11-dev libxext-dev libxrandr-dev libxcursor-dev mesa-dev`; `package()` also copies `*_ui.so`. The release tarball has DPF's pugl-upstream. The simplest test of a GUI we build. |
| guitarix-lv2 | 33 | `--no-lv2-gui` (APKBUILD:33) | drop the flag; `+cairo-dev libx11-dev` (libxputty, its own X11/cairo toolkit); check that `waf configure` doesn't ask for gtkmm with `--no-standalone`. |
| gxplugins-lv2 | 25 | `make SSE_CFLAGS= mod` (APKBUILD:35, comment :7) | `make SSE_CFLAGS=`, adapt the install to the GUI target; `+cairo-dev libx11-dev`. The non-MOD TTLs differ: diff URIs, ports and presets against the MOD ones (saved snapshots). |
| distrho-ports-lv2 | 15 | `-Dlinux-headless=true` (APKBUILD:46) | `false`; `+freetype-dev libx11-dev libxext-dev libxcursor-dev libxinerama-dev libxrandr-dev`; JUCE 5, a much longer build. OB-Xd, TAL NoiseMaker, Vex, ... |

### Then

| Recipe | E | Change |
|---|---|---|
| mimid-lv2 | 1 | DPF Cairo: `lv2_sep` with cairo (APKBUILD:33), pugl-upstream as an extra source, `+cairo-dev libx11-dev`. Its TTL already names the missing `MiMi-d_ui.so`. |
| triceratops-lv2 | 1 | revert the `HAS_UI 0` sed (:27) and `HAVE_DGL/OPENGL/CAIRO=false lv2_dsp` (:33); pugl source; `+cairo-dev libx11-dev`. |
| string-machine-lv2 | 3 | revert the `HAS_UI 0` sed (:29) and `HAVE_CAIRO=false` (:35); as triceratops (the two chorus plugins probably have no UI). |
| regrader-lv2 | 1 | revert the `HAS_UI 0` sed (:26), `lv2_dsp` (:34); pugl source; `+libx11-dev mesa-dev`. |
| ykchorus-lv2 | 1 | DPF with `HAS_UI 1`: drop `HAVE_OPENGL=false lv2_dsp` (:29); pugl source (comment :27); `+libx11-dev mesa-dev`. |
| dpf-plugins-lv2 | 7 | as dragonfly (APKBUILD:25) plus pugl-upstream as an extra source (a submodule in the v1.7 archive). Nekobi, MVerb, 3BandEQ (in `broken_ui` as False), PingPongPan; Kars has no UI. |
| aida-x-lv2 | 1 | `--target AIDA-X-lv2 AIDA-X-lv2-ui` (:22), copy `AIDA-X_ui.so` (makedepends already have X11 and GL). Low priority: zynthian has its own widget. |
| aether-lv2 | 1 | revert the sed removing `aether_ui` (:21-23) and `--target aether_dsp` (:29); glad/pugl/nanovg submodules as sources; `+libx11-dev mesa-dev`. |
| artyfx-lv2 | 2 | `-DBUILD_GUI=ON` (:23); `+cairo-dev libx11-dev mesa-dev` (AVTK: pugl and cairo, to check). |
| avldrums-lv2 | 5 | robtk OpenGL: drop `BUILDOPENGL=no` (:23); robtk submodule as a source; `+mesa-dev glu-dev cairo-dev pango-dev libx11-dev`. |
| setbfree (engines) | 2 | robtk OpenGL UIs (b_synth, whirl): `+mesa-dev glu-dev ftgl-dev libx11-dev` (to check). |
| qmidiarp-lv2 | 2 | only the robtk UIs: drop `--disable-lv2rtkpluginuis` (:24), keep the Qt5 ones off; `+mesa-dev glu-dev cairo-dev pango-dev`. |
| infamous-lv2, fabla-lv2 | 3, 1 | NTK GUIs: NTK would have to be packaged first. |

### Not hostable (leave as they are)

calf (GTK2; 26 enabled), invada, eq10q, ams, foo-yc20, amsynth (GTK2 / gtkmm2), abgate (GTK2 and
Qt5), granulator (faust Qt). Their UIs aren't installed, so zynthian shows none.

### Notes for building

- OpenGL GUIs (DPF GL, robtk, JUCE with juce_opengl) need GLX: on the GPU in the niri session; in
  the cage session XWayland runs without glamor (llvmpipe, CPU next to the DSP). Cairo toolkits
  (libxputty, DPF Cairo) are lighter.
- JUCE GUIs already compile with the musl workarounds; their runtime is untested (libX11 loaded
  when the editor opens, fonts through fontconfig, the editor on the UI thread: mind musl's 128 KB
  thread stacks).
- Size: JUCE in every bundle (dusk-audio-juce is 99 MB).
- Scaling: DPF honours `ui:scaleFactor` / `DPF_SCALE_FACTOR` (newer DPF; the zam-plugins' doesn't),
  JUCE uses Xft.dpi, robtk is mostly fixed size, Qt6 needs `QT_QPA_PLATFORM=xcb` and
  `QT_SCALE_FACTOR`.
- Build in the clean CI environment (`packages.yml --ref <branch>`); the Duet hides missing
  makedepends.

## Known issues

- **Monique: the SETUP and INFO panels (and the keyboard) are cut off.** They extend the GUI at
  the bottom: the editor grows in height. Monique's GUI is resizable with a fixed aspect ratio,
  and in the full-screen plugin window JUCE fits it to the width: with a panel open the window
  gets taller than the screen (seen: 1174x970 logical on the Duet's 1280x800) and the bottom part
  is cut off. Without the panels it fits (1280x800). Possible fixes: a per-plugin scale factor
  (`jalv.gtk3 -S`, from the GUI's height with the panels open) instead of full-screen, a floating
  window niri can move, or fitting to the height in JUCE's LV2 wrapper.

## Open questions

- Do JUCE GUIs (Surge XT, Odin2) run in jalv.gtk3 on musl and Panfrost?
- Qt6 GUIs (rncbc) inside a GTK process through the X11UI wrapper.
- Plugin dialogs (file choosers) currently get a workspace of their own.
- Memory per shown GUI on the 4 GB Duet; CPU of GL GUIs while shown.
- The niri session's touch gesture for the overview.
