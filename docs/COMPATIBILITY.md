# Compatibility audit

This audit asks whether the universal macOS VST3 preserves DtBlkFx 1.1's sound
and behavior. Cross-platform binaries cannot be byte-for-byte identical: VST2
and VST3 have different ABIs, the executables target different CPU instruction
sets, and they use different compiler and FFTW builds. The meaningful target is
the same controls, state, assets, processing topology, and numerically equivalent
audio for identical normalized parameters and input samples.

## Reference artifacts

The Darrell Tam v1.1 archives were downloaded from the original
[Rekkerd DtBlkFx page](https://rekkerd.org/dtblkfx/). The Dozius 2017 x86/x64
builds were downloaded from the current
[Dozius release mirror](https://skullzy.ca/software/DtBlkFx/releases).

Archive SHA-256 digests:

- `dtblkfx1_1_win.zip`: `809ee3fcb38c86ab60a830dba2485f8346aac9025374887f176e67929b2fb50b`
- `dtblkfx1_1_mac.zip`: `2d6a53ae36656d211172daf182c569a2e01dbf2106bbe494afcc714f039c7e2f`
- `DtBlkFx-x86.zip`: `9c5a1384f57e010660225f84977a2f152ea62124e79210b8dc3846778179f33d`
- `DtBlkFx-x64.zip`: `609211d1a1974bc07166312495521b2223f2202d8637666ef04824de0516cdc7`

Stereo plug-in SHA-256 digests:

- Darrell Windows x86 `DtBlkFxS.dll`: `c5de235569bd5dbace91cda39f1b1b2c82159056059cae7034992e40ae3ab8a8`
- Darrell macOS PPC+i386 `DtBlkFxS`: `3c3257eb60f167043c71dc784b7be63b967af6b7d4c1d42fc2ed23e63b87ce2e`
- Dozius Windows x86 `DtBlkFx.dll`: `6ed224e49e1021c841abc930f9f16dcaa1a2f79e17b17dacab7a14fdd9c56951`
- Dozius Windows x64 `DtBlkFx.dll`: `e7a5df7b5984321975a344fd1c58f6cfd0bdf038e9680e66bbd258d9559e976f`

The original archives' 16 PNG and preset resources match the corresponding
repository resources byte-for-byte. The Windows manual matches
`docs/manual.html` apart from whitespace and local image paths. The original
Mac manual is older because that release had no graphical editor and lacked
the later Windows pitch-match addition.

## Static correspondence

Ghidra 10.3.3 was run locally against the Darrell Windows x86 stereo DLL and
the i386 slice of the Darrell Mac stereo VST2. Decompiled output is deliberately
not committed.

The Windows analysis recovered 2,081 functions, including `VSTPluginMain`, the
VST object construction path, FFTW loading, resource loading, and program-bank
loading. The Mac analysis recovered 1,884 functions and its `_VSTPluginMain`.
Both expose the same global control count, eight five-control effect stages,
effect registration order, and effect names found in the preserved source.
Static analysis therefore supports the source provenance and mapping, but is
not treated as audio-equivalence proof.

## Black-box audio comparison

The original and Dozius Windows VST2 binaries were executed under Wine with a
minimal 32/64-bit host. Each reported 44 parameters, 44 VST2 programs (43 named
presets plus `reset current`), two inputs, two outputs, VST 2.4, and zero
reported latency. The old binaries delay audio internally but do not report it
to the host: at 44.1 kHz the first nonzero output was sample 101 with Delay at
zero, 2,205 at 50 ms, and 22,051 at the historical one-beat default.

The same deterministic float32 input and normalized controls were rendered
through every binary and both slices of the VST3. The 60 scenarios cover all 31
effect indices, six eight-effect chains, eight prefixes of the most
phase-sensitive chain, five FFT plans, five overlaps, four delay values, and a
large-FFT/long-delay case.

Against Darrell's 2008 Windows x86 binary:

- VST3 arm64 median signal-to-error ratio: 130.161 dB
- VST3 arm64 worst signal-to-error ratio: 16.734 dB; minimum correlation: 0.989395306
- VST3 x86_64 median signal-to-error ratio: 129.608 dB
- VST3 x86_64 worst signal-to-error ratio: 15.664 dB; minimum correlation: 0.986440474

The worst case begins when the seventh stage adds frequency shifting after six
other spectral operations. Its RMS level differs by approximately 0.001 dB and
its log-magnitude spectrum correlates at approximately 0.996; the lower waveform
score is phase sensitivity rather than a level or spectral-shape mismatch.

The official Dozius Windows x86 and x64 binaries diverge by essentially the
same amount on that exact case: 15.689 dB worst-case signal-to-error ratio and
0.986524256 minimum correlation. Forty of 60 Darrell-x86 versus Dozius-x86
scenarios are byte-identical, with the same phase-sensitive chain as the worst
remaining case. This is strong evidence that the residual difference is the
original algorithm's compiler/architecture sensitivity rather than changed
effect logic.

The port formerly used `-ffast-math` in Release builds. The audit removed it
because floating-point reassociation is inappropriate for a preservation build.
That improved harmonic-effect agreement and makes the compiler preserve normal
IEEE evaluation semantics. The final program-list work did not alter DSP: all
60 arm64 and all 60 x86_64 corpus files remained byte-for-byte identical to the
post-`fast-math` audit build.

## Behavioral scope and intentional differences

The 44 normalized parameter mappings, eight-stage order, 31 effect indices,
factory preset data, legacy chunk state, stereo processing, artwork, and manual
control behavior are preserved. The VST3 adds a standard bypass parameter, a
native AppKit editor with live input/output spectrograms, VST3 factory-program
discovery, an in-editor factory-preset selector, artifact-free bypass state
advancement, deterministic startup parameter ordering, and correct
disable/re-enable lifecycle handling.

A new instance intentionally defaults Delay to zero at the user's request. The
original one-beat value remains selectable and remains in historical presets.
The irreducible FFT block look-ahead is still present and varies with block size
and overlap. The plugin reports zero compensatable latency, matching the
historical VST2 behavior.

The original Mac binary is PPC+i386 VST2 and cannot execute on current macOS,
so it was checked statically and by resource identity rather than dynamically.
The current port is stereo-only, matching `DtBlkFxS`; the historical separate
mono variant has not been ported.

## Release qualification

On macOS 26.4 the universal bundle passes Steinberg validator 3.8.1 with 47
tests passed and zero failed in native arm64 mode. The repository smoke host
passes module loading, all 43 program names and program application, state
round-trip, deterministic audio, live FFT display, bypass lifecycle,
disable/re-enable, and AppKit attachment. The same bundle has loaded and run in
Ableton Live 11.3.43.

This is enough for a source release or clearly labeled beta. A polished binary
release still needs a unique continuation version/maintainer identity, Developer
ID signing, Apple notarization, and clean-machine testing in more than one DAW.
