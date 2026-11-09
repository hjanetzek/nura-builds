# Pianoteq on Nura: plan

Status: plan, 2026-11-09. Not implemented. Shared snapshots use Pianoteq in 21 chains (engine PT)
and 5 more as LV2 (see "Wanted by shared snapshots" in lv2-plugins.md).

Pianoteq is proprietary (Modartt), licensed per user, and shipped only as prebuilt glibc binaries.
So it can't be a package of this repository. It works like the content packs instead
(factory-content.md): a helper downloads or takes the user's file and installs it in the user's
directories, and nothing is hosted or redistributed here.

## How ZynthianOS does it

- `zynthian-sys/scripts/recipes/install_pianoteq_demo.sh`: downloads the trial
  (`http://download.zynthian.org/pianoteq_trial_v921.tar.xz`, 39 MB, Pianoteq 9) and runs:
- `install_pianoteq_binary.sh <file.7z|file.tar.xz>`: unpacks only `*/arm-64bit` (or `arm-32bit`),
  the documentation and the licence into `$ZYNTHIAN_SW_DIR/pianoteq`, and links the binary as
  `$ZYNTHIAN_SW_DIR/pianoteq/pianoteq`. It links the LV2 bundle into `$ZYNTHIAN_PLUGINS_DIR/lv2`
  and exports the LV2 presets (`pianoteq --export-lv2-presets`, version > 7.2).
- webconf's Pianoteq page (`lib/pianoteq_handler.py`) runs the same script for an uploaded
  licensed `.7z`/`.tar.xz`, moves `.ptq` instruments to `~/.local/share/Modartt/Pianoteq/Addons`,
  activates the licence (`pianoteq --prefs ... --activate <serial>`) and sets the voice limit and
  rate options.
- zynthian's PT engine (`zyngine/zynthian_engine_pianoteq.py`) runs `$ZYNTHIAN_SW_DIR/pianoteq/pianoteq`
  headless. On Nura that is `~/.local/share/zynthian/sw/pianoteq` (`ZYNTHIAN_SW_DIR`), and
  `ZYNTHIAN_PLUGINS_DIR` is `~/.local/share/zynthian/plugins`, both already in the user's home.

## The open question: glibc

What the trial's aarch64 binaries need (`readelf -d`): `ld-linux-aarch64.so.1`, `libc.so.6`,
`libdl.so.2`, `libpthread.so.0`, `libm.so.6`, `libgcc_s.so.1`, `libasound.so.2`, `libGL.so.1`,
`libfreetype.so.6`, `libfontconfig.so.1`, and for the LV2 `.so` also `libstdc++.so.6`. That's a
short list, all available on Alpine except glibc itself.

1. **gcompat** (Alpine, `gcompat`): a glibc compatibility layer on musl that provides
   `ld-linux-aarch64.so.1` and `libc.so.6`. Try this first: it's the only way the **LV2** version
   can work, because it loads into jalv (a musl process). Risks: symbols gcompat lacks
   (versioned glibc symbols), and glibc behaviour Pianoteq relies on.
2. **A private glibc runtime** for the standalone engine only, if gcompat fails: glibc's
   libraries in their own directory (e.g. `/usr/lib/glibc-runtime`), the binary started through
   that loader (`ld-linux-aarch64.so.1 --library-path ... pianoteq`, or `patchelf` on install).
   The LV2 version can't work this way (no glibc library in a musl process).

Step 1 of the plan answers this: run the trial binary (`--version`, then headless with sound)
and the LV2 bundle in jalv on the Duet with gcompat.

## Plan

1. **Feasibility** on the Duet: gcompat, then the trial: `--version`, the engine command line
   zynthian uses, sound via the Midi Through test, CPU load (the Duet's 4 big cores), and the LV2
   bundle in jalv. If only the standalone works, the LV2 part is dropped (snapshots with the LV2
   version then need the engine).
2. **`zynthian-pianoteq`**, a script in zynthian-packages' nura directory next to
   `zynthian-factory-content` (same package, same conventions: run as the device user, sudo only
   for apk):
   - `zynthian-pianoteq trial`: downloads the trial from download.zynthian.org, as ZynthianOS does.
   - `zynthian-pianoteq install <file>`: the user's licensed `.7z`/`.tar.xz` (binary) or `.ptq`
     (instrument), as webconf's page.
   - `zynthian-pianoteq activate <serial>`, `-l` (what is installed), `remove`.
   - Unpacks `arm-64bit` (or `x86-64bit` on x86-64) into `$ZYNTHIAN_SW_DIR/pianoteq`, links the
     binary and the LV2 bundle (`$ZYNTHIAN_PLUGINS_DIR/lv2`), exports the LV2 presets, and then
     rescans LV2.
   - Installs `gcompat` (and `7zip` for `.7z`) with apk if missing; or zynthian-packages gets
     `depends` on them (both small).
3. **webconf** (Nura fork): its Pianoteq page calls `zynthian-pianoteq install` instead of
   zynthian-sys' recipe, so uploading from a browser works as on ZynthianOS.
4. **factory-content.md / zynthian-factory-content**: mention the trial; don't install it by
   default (ZynthianOS' image has it, but it's a trial and needs network).
5. Later, with the admin-menu entry for optional data (lv2-plugins.md, "Optional data"): install
   the trial and activate a licence from zynthian's UI.

Never: putting Pianoteq's files in a package, an image, or a CI artifact.
