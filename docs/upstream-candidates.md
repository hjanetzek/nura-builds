# Upstream candidates

Fixes in this repository's recipes (patches in `aports/`, or `sed` in a recipe's `prepare()`) that
belong in the upstream projects, and upstream bugs noticed but not fixed here. Changes to zynthian
itself are logged in zynthian-ui's
[docs/upstream-candidates.md](https://github.com/hjanetzek/zynthian-ui/blob/nura/docs/upstream-candidates.md).
Keep it up to date with each fix: add a row when a recipe works around an upstream problem.

Status: **ready** (a patch file, can be sent as is), **sed** (a `sed` in the recipe: needs a proper
patch), **open** (noticed, not fixed), **proposed** (sent upstream, with the link), **merged**.

Patches taken from Debian or Alpine (sooperlooper, eq10q, Qt) are not listed.

## Bugs (on every platform)

| Project | Status | Where | Problem and fix |
|---|---|---|---|
| [LinuxSampler](https://www.linuxsampler.org/) 2.5.0 | ready | `aports/engines/linuxsampler/thread-stop-joined.patch` | **`Thread::StopThread()` detaches a joined thread.** After `pthread_join()` the state is still `PENDING_JOIN` (set by the thread's destructor), so `pthread_detach()` follows on the joined thread: undefined behaviour, glibc returns an error, musl uses freed memory and segfaults. Crashes linuxsampler on every `RESET CHANNEL` of a channel with an SFZ instrument (zynthian removing a chain). Fix: `state = NOT_RUNNING` after the join. |
| [LinuxSampler](https://www.linuxsampler.org/) 2.5.0 | ready | `aports/engines/linuxsampler/thread-sched-self.patch` | **A new thread sets its scheduling through `__thread_id` before it is set.** `SetSchedulingPriority()` runs in the new thread (`pthreadLauncher`) and uses `__thread_id`, which `pthread_create()` may store only after the thread started (musl does): `pthread_setschedparam(0, ...)`, segfault at times at `LOAD ENGINE`. Fix: `pthread_self()`. |
| [MOD Arpeggiator](https://github.com/mod-audio/mod-arpeggiator-lv2) | ready | `aports/lv2/mod-arpeggiator-lv2/midibuffer-by-reference.patch` | **150 KB copied onto the audio thread's stack.** `run()` takes the MIDI buffer by value; with musl's 128 KB default thread stack the host's audio thread overflows (segfault on the first `run()`). Fix: `getMidiBuffer()` returns a const reference. |
| [Monique](https://github.com/surge-synthesizer/monique-monosynth) | ready | `aports/lv2/monique-lv2/headless-no-display.patch` | **Crash without an X display.** The editor code dereferences the host display (`get_host_display()`, null without X); JUCE's LV2 helper creates the editor at build time, so headless builds (CI) die in the plugin's crash handler (SIGKILL). |
| [Vaporizer2](https://github.com/VASTDynamics/Vaporizer2) | sed | `aports/lv2/vaporizer2-lv2/APKBUILD` | **Unchecked `std::optional` dereference.** `processBlock()` does `*getPlayHead()->getPosition()`, empty in hosts that send no time info yet (jalv): abort with `_GLIBCXX_ASSERTIONS`, undefined behaviour without. Fix: keep the `Optional`, its `orFallback()` calls follow. |
| [Regrader](https://github.com/linuxmao-org/regrader-port) | sed | `aports/lv2/regrader-lv2/APKBUILD` | **A macro named `maybe_unused`** (`global.h`) breaks `[[maybe_unused]]` in GCC 15's libstdc++ headers. Fix: rename the macro. |
| [TalentedHack](https://github.com/jeremysalwen/TalentedHack) | sed | `aports/lv2/talentedhack-lv2/APKBUILD` | **C99 `inline` without an external definition** (`midi.c`, `talentedhack.c`, `quantizer.h`): unresolved symbols at `-O0`/`-Os`, multiple definitions with `-fgnu89-inline`. Fix: `static inline`. |

## Portability (musl, current compilers)

| Project | Status | Where | Problem and fix |
|---|---|---|---|
| [LinuxSampler](https://www.linuxsampler.org/) 2.5.0 | sed | `aports/engines/linuxsampler/APKBUILD` | `configure`'s UNIX98 test fails on musl, which has `pthread_mutexattr_settype()` (`HAVE_UNIX98=1` needed); `execinfo.h` included unconditionally (`src/common/global_private.cpp`, backtraces for Mutex debug info only): stub header. |
| [DISTRHO-Ports](https://github.com/DISTRHO/DISTRHO-Ports) (JUCE 5) | sed | `aports/lv2/distrho-ports-lv2/APKBUILD` | `execinfo.h` and `backtrace()` unconditional in JUCE's core (`#if defined (__GLIBC__)` around them); `static_cast<char>(NULL)` in juced's OSC code (`NULL` is `nullptr` on musl). |
| JUCE plugins (CHOW, Surge's Monique, Dusk Audio, KR-106, RipplerX, Helm, Vaporizer2, ...) | sed | their recipes | The same in each bundled JUCE: `execinfo.h`, the glibc locale items `_NL_IDENTIFICATION_*`/`_NL_ADDRESS_*` in `getUserLanguage()`, `stat64` without `_LARGEFILE64_SOURCE`; older JUCE: `<utility>` for `std::exchange`. Upstream JUCE has some of it fixed: a plugin update to a current JUCE removes the need. |
| [Vaporizer2](https://github.com/VASTDynamics/Vaporizer2) | sed | `aports/lv2/vaporizer2-lv2/APKBUILD` | `arc4random()` used unless glibc < 2.36: musl has none (libbsd here). Check for the function, not the glibc version. |
| [Triceratops](https://github.com/thunderox/triceratops) | sed | `aports/lv2/triceratops-lv2/APKBUILD` | `(uint)` cast: `uint` is a glibc typedef. Fix: `unsigned int`. |
| [caps-lv2 (MOD)](https://github.com/moddevices/caps-lv2) | sed | `aports/lv2/mod-caps-lv2/APKBUILD` | glibc's internal `__intN_t` types in `basics.h`. Fix: the standard `<stdint.h>` types. |
| [hcs (Pd)](https://github.com/pd-externals/hcs) | sed | `aports/pd/pd-hcs/APKBUILD` | `stat.c` takes the BSD field names (`st_atimespec`) unless `_POSIX_C_SOURCE` is defined, which glibc defines implicitly and musl doesn't. Fix: the POSIX branch on Linux too. |
| [tap-lv2 (MOD)](https://github.com/moddevices/tap-lv2) | sed | `aports/lv2/mod-tap-lv2/APKBUILD` | `-Werror` in the build flags breaks with newer compilers' warnings. |
| [ChowMultiTool](https://github.com/Chowdhury-DSP/ChowMultiTool) | open | `aports/lv2/chow-multitool-lv2/APKBUILD` | GCC 15's LTO crashes on it (internal compiler error in `write_symbol`): built without JUCE's LTO flags. A GCC bug to report, with a reduced case. |

## Packaging notes for upstream

| Project | Status | Note |
|---|---|---|
| [libgig](https://www.linuxsampler.org/libgig/) | open | The libraries install into `$libdir/libgig` (and LinuxSampler's into `$libdir/linuxsampler`): users depend on libtool `.la` files for the link path and runtime path, which distributions drop. A `-Wl,-rpath` in `gig.pc`, or the standard libdir, would help. |
