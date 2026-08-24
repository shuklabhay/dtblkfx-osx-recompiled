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
The build script also runs Steinberg's validator against the finished bundle.

The VST3 exposes the original 44 normalized parameters plus the standard VST3
bypass parameter. It uses the host's generic parameter editor. Recreating and
cross-checking the original custom editor is intentionally separate from this
processing port.
