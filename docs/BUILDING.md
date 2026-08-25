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

The VST3 exposes the original 44 normalized parameters plus the standard VST3
bypass parameter. Its native AppKit editor uses the original 410 by 409 pixel
artwork and layout, supports parameter editing and effect menus, and renders
the preserved engine's live input and output FFT data through VST3's real-time
data exchange API. No JUCE or VSTGUI binary dependency is used.

Run the complete verification loop independently with:

```sh
./scripts/test.sh
```

The smoke host loads the module, round-trips controller state, attaches and
renders the NSView editor, edits a parameter, processes deterministic stereo
audio, verifies that live FFT data changes the editor before and after a
disable/re-enable cycle, and detaches the view. Set `DTBLKFX_SMOKE_PNG` to an
output path when running `dtblkfx_smoke` directly to save its final live editor
render as a PNG.
