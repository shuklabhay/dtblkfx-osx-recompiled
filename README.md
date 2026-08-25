# dtblkfx-osx-recompiled

An unofficial universal macOS VST3 continuation of Darrell Tam's DtBlkFx 1.1.
It preserves the original FFT effect engine, parameters, factory presets, art,
and state format behind a small native VST3/AppKit boundary. It does not use
JUCE.

The current VST3 and AUv2 bundles run natively on Apple Silicon and Intel Macs,
expose the original 44 controls and 43 factory presets, display live
input/output spectrograms, support artifact-free host bypass and state recall,
and default new instances to zero user delay. The FFT still has the algorithmic
look-ahead inherent to block processing.

## Status

The source and DSP are suitable for public review and beta use. The locally
produced binary is not yet a polished public download: it is ad-hoc signed, not
Developer ID signed or notarized, and has only been exercised in Steinberg's
validator, the repository smoke/performance hosts, and Ableton Live 11 on one
Mac. See [the compatibility audit](docs/COMPATIBILITY.md) for numerical results
and remaining limitations.

## Build and verify

Requirements are macOS 11 or newer, Xcode Command Line Tools, Git, and CMake
3.25 or newer.

```sh
./tools/build.sh
```

This produces `build/VST3/Release/DtBlkFx.vst3` and runs the complete validator
and smoke loop in both arm64 and x86_64 modes when Rosetta is available. Build
dependencies stay under the ignored `build` directory. See
[the build guide](docs/BUILDING.md) for details.

Build the universal AUv2 wrapper separately with:

```sh
./tools/build_auv2.sh
```

This produces `build-au/AU/Release/DtBlkFx.component`. It uses Steinberg's
official AUv2 wrapper and Apple's AudioUnitSDK around the same VST3 module; it
does not duplicate or rewrite the DSP.

For local installation:

```sh
mkdir -p "$HOME/Library/Audio/Plug-Ins/VST3"
cp -R build/VST3/Release/DtBlkFx.vst3 "$HOME/Library/Audio/Plug-Ins/VST3/"
```

Then rescan VST3 plug-ins in the host. A public binary should instead be signed
with a Developer ID certificate and notarized.

## Provenance and licensing

The repository retains the complete upstream Git history. The port begins at
the earliest commit containing the complete plug-in source, tagged
`upstream-source-complete`; the later Dozius source tip is tagged
`upstream-dozius-final`. See [source provenance](docs/PROVENANCE.md).

DtBlkFx and this continuation are distributed under GNU GPL version 3. The
preserved DtBlkFx files permit GPL version 2 or any later version. FFTW is
GPLv2-or-later, and the pinned VST3 SDK is MIT licensed. See `LICENSE`, `NOTICE`,
and the dependency notices. DtBlkFx was created by Darrell Tam; this port is not
an official release from or endorsement by Darrell Tam.
