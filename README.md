# DtBlkFx for modern macOS — 64-bit VST3 & AUv2

**A working Apple Silicon and Intel Mac port of Darrell Tam's DtBlkFx spectral effects plug-in.** The original FFT processing, interface, 44 controls, 43 factory presets, artwork, and state format are preserved in native 64-bit VST3 and AUv2 builds.

**[Download DtBlkFx v1.0 for macOS](https://github.com/shuklabhay/dtblkfx-osx-recompiled/releases/tag/v1.0)** · [Compatibility and audio comparison](docs/COMPATIBILITY.md) · [Build from source](docs/BUILDING.md)

![DtBlkFx 64-bit VST3 running on modern macOS with live before-and-after spectrograms for drums, guitar, voice, and piano](https://raw.githubusercontent.com/shuklabhay/dtblkfx-osx-recompiled/main/docs/images/dtblkfx-macos-vst3-real-audio-before-after.png)

DtBlkFx is a free, open-source FFT-based audio effect created by Darrell Tam. The original Mac release was a 32-bit VST2 for PowerPC and Intel and no longer runs in current DAWs. This continuation makes DtBlkFx usable on modern macOS without replacing its DSP or rebuilding its interface in another framework.

## Download and install

The [latest release](https://github.com/shuklabhay/dtblkfx-osx-recompiled/releases/latest) includes:

- **VST3:** Apple Silicon and Intel, for hosts such as Ableton Live
- **AUv2:** Apple Silicon and Intel, for Audio Unit hosts
- **Factory preset pack:** standard VST3 preset files

Download the format you need, unzip it, and copy it to the matching folder:

- `DtBlkFx.vst3` → `~/Library/Audio/Plug-Ins/VST3/`
- `DtBlkFx.component` → `~/Library/Audio/Plug-Ins/Components/`

Then restart or rescan plug-ins in your DAW. The v1.0 binaries are ad-hoc signed but not Apple-notarized, so macOS may require manual approval. This is an unofficial preservation release; see [current compatibility and release limitations](docs/COMPATIBILITY.md#release-qualification).

## What is preserved

- Original stereo FFT effect engine and all 31 spectral operations
- All 44 normalized parameters and eight ordered effect stages
- All 43 named factory presets and legacy chunk state
- Original artwork and control behavior
- Live input and processed-output spectrograms
- Native universal binaries for Apple Silicon (`arm64`) and Intel (`x86_64`)
- VST3 host bypass, state recall, factory-program discovery, and AUv2 wrapping

The port uses a small native VST3/AppKit boundary and does not use JUCE. New instances intentionally start with zero user delay; the FFT engine retains the algorithmic look-ahead inherent to block processing.

## How close does it sound to the original?

The restored plug-in was compared against Darrell Tam's Windows x86 binary across 60 deterministic audio scenarios covering all 31 effects, multi-effect chains, FFT plans, overlap settings, and delay values.

- Apple Silicon median signal-to-error ratio: **130.161 dB**
- Intel Mac median signal-to-error ratio: **129.608 dB**
- All original images and preset resources match the archived releases byte-for-byte
- The residual worst-case difference matches the architecture sensitivity already present between the historical Windows x86 and x64 builds

See the [full compatibility audit](docs/COMPATIBILITY.md) for methodology, hashes, measurements, and known limitations.

## Build and verify

Requirements are macOS 11 or newer, Xcode Command Line Tools, Git, and CMake 3.25 or newer.

```sh
./tools/build.sh
```

This produces `build/VST3/Release/DtBlkFx.vst3` and runs the validator and smoke-test loop in both arm64 and x86_64 modes when Rosetta is available.

Build the universal AUv2 wrapper separately:

```sh
./tools/build_auv2.sh
```

This produces `build-au/AU/Release/DtBlkFx.component`. See [the build guide](docs/BUILDING.md) for details.

## Provenance and licensing

The repository retains the complete upstream Git history. The port begins at the earliest commit containing the complete plug-in source, tagged `upstream-source-complete`; the later Dozius source tip is tagged `upstream-dozius-final`. See [source provenance](docs/PROVENANCE.md).

DtBlkFx and this continuation are distributed under GNU GPL version 3. The preserved DtBlkFx files permit GPL version 2 or any later version. FFTW is GPLv2-or-later, and the pinned VST3 SDK is MIT licensed. See `LICENSE`, `NOTICE`, and the dependency notices. DtBlkFx was created by Darrell Tam; this port is not an official release from or endorsement by Darrell Tam.
