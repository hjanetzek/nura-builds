# Target: Zrythm (the DAW, Qt Quick UI) for Nura, booting into a labwc kiosk session (aarch64,
# x86_64). Sourced by scripts/*.sh. The recipes are Zrythm's own (tools/nura/ on the nura
# branch, see its README and CI.md). Qt 6.12 is Alpine's (aarch64, x86_64); Qt TaskTree and Canvas
# Painter, which Alpine doesn't package, come from nura-builds' package set qt-tools via the package
# repository. The target links Zrythm's recipe directories except its copy of Qt (two recipes of a
# name would clash).

# Source repositories: name, URL, branch (override with ZRYTHM_REF), recipe directories
REPOS="
zrythm https://github.com/hjanetzek/zrythm nura tools/nura/deps,tools/nura/zrythm,tools/nura/postmarketos-ui-zrythm,tools/nura/zrythm-quirks-google-kukui
"

# Zrythm's libraries that aports doesn't package (tools/nura/deps, at the versions in conan.lock):
# pmbootstrap builds only those whose version isn't in the package repository yet (a recipe change
# needs a pkgrel bump). Order (CI.md): debug-assert before type-safe, nlohmann-json before
# nlohmann-json-schema-validator. nlohmann-json (3.12.0_git20250510, the commit Zrythm pins)
# replaces Alpine's 3.12.0 for every package built against the repository (header-only, same ABI
# namespace; zynthian-ui uses its headers). Then Zrythm from the checkout (--src skips $source; seed-distfiles.sh puts
# the sources CPM would fetch into the distfiles cache first), the kiosk UI and the Duet's quirks.
STAGES="deps zrythm"
STAGE_deps="debug-assert; type-safe; nlohmann-json; nlohmann-json-schema-validator; au; gsl-lite; magic-enum; mpmcqueue; scnlib"
STAGE_zrythm="--src=@zrythm zrythm; postmarketos-ui-zrythm; zrythm-quirks-google-kukui"
SEED_zrythm="@zrythm/tools/nura/seed-distfiles.sh"

# Images: pmbootstrap UI (postmarketos-ui-zrythm, which makes its session tinydm's default on
# install: Zrythm images only, never in a zynthian image) and the devices
UI=zrythm
DEVICES="google-kukui"
DEVICES_x86_64="qemu-amd64"
