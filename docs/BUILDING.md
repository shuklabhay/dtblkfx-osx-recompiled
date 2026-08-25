# Building DtBlkFx VST3 on macOS

The build requires Git, CMake 3.25 or newer, Apple Clang, and the macOS Command
Line Tools. It does not require JUCE, Homebrew, a system FFTW installation, or
the original VST2 SDK.

Run:

```sh
./scripts/build.sh
```

The script initializes only the VST3 SDK submodules used by this plug-in. CMake
downloads the official FFTW 3.3.10 source archive into `build/_deps` and checks
its SHA-256 digest before building it statically. All generated files and
downloaded build dependencies remain under the ignored `build` directory.

The resulting universal macOS bundle is:

```text
build/VST3/Release/DtBlkFx.vst3
```

The default build targets macOS 11 or newer on both Apple Silicon and Intel.
The build script also runs Steinberg's validator and the local host smoke test
against the finished bundle in native Apple Silicon mode and, when Rosetta is
available, Intel mode.

The VST3 exposes the original 44 normalized parameters, all 43 named factory
presets through the VST3 program-list API, and the standard VST3 bypass
parameter. Its native AppKit editor preserves the original 410 by 409 pixel
artwork and control layout, adds a 30-pixel factory-preset selector, supports
parameter editing and effect menus, and renders the preserved engine's live
input and output FFT data through VST3's real-time data exchange API. No JUCE or
VSTGUI binary dependency is used.

Run the complete verification loop independently with:

```sh
./scripts/test.sh
```

The smoke host loads the module, verifies and selects the historical program
bank and visible selector, verifies host-independent startup ordering,
round-trips controller and component state, attaches and renders the NSView
editor, edits a parameter, processes deterministic stereo audio, proves that a
long-delay impulse cannot leak out after bypass, verifies that live FFT data
changes the editor before and after a disable/re-enable cycle, and detaches the
view. Set `DTBLKFX_SMOKE_PNG` to an output path when running `dtblkfx_smoke`
directly to save its final live editor render as a PNG.

The performance host renders a deterministic 60-scenario corpus covering every
effect type, multi-effect chains, every stage of a phase-sensitive chain, five
FFT sizes, five overlaps, four delays, and a large-FFT/long-delay case. Set
`DTBLKFX_PERF_OUTPUT_DIR` to write interleaved stereo float32 output for sample
comparison. Generated reports and audio stay under the ignored
`tmp_dtblk-osx-recompiled` directory.

## Historical binary oracle

The optional `tests/legacy_vst2_host.cpp` is a self-contained Windows VST2 host
for the same 60 scenarios. It needs no VST2 SDK. Build the 32-bit host with a
MinGW cross-compiler, create an ignored output directory, and run it with Wine
against an independently downloaded historical DLL:

```sh
i686-w64-mingw32-g++ -std=c++17 -O2 -static \
  -static-libgcc -static-libstdc++ tests/legacy_vst2_host.cpp \
  -o tmp_dtblk-osx-recompiled/legacy_vst2_host-x86.exe
```

Wine paths and setup vary, so pass the DLL and output directory in Windows path
form. The original DLL must remain beside its `dtblkfx` resource directory.
Do not commit downloaded binaries or rendered audio.

Compare two completed render directories without third-party Python packages:

```sh
./scripts/compare_oracles.py path/to/current-renders path/to/reference-renders
```

The known reference artifact hashes and audited results are in
`docs/COMPATIBILITY.md`.
