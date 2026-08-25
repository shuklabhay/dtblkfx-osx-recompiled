# Source provenance

This repository retains the complete Git history published by Dan Smith at
`https://github.com/dozius/DtBlkFx`. No squashed copy or detached source dump
was used.

The macOS port starts at commit
`77f92cce4a598cf97789ffb6f2ea2f20668e85e9`, the earliest historical commit
that contains the complete DtBlkFx plug-in source. The tag
`upstream-source-complete` names that boundary. The later upstream tip is
retained on tag `upstream-dozius-final` for comparison.

The original DtBlkFx source, resources, VSTGUI, and Windows project material are
grouped under `upstream` without changing their contents. Files under
`src/compat` and `src/vst3` are the new host-compatibility and VST3 boundaries.
Changes inside `upstream/dtblkfx` are limited to platform-width fixes, current
C++ name lookup, macOS synchronization primitives, include filename case,
compile guards that replace
the VST2 host base when building the native VST3, and a headless observation
callback that copies the already-computed pre/post-effect FFT display data. The
effect algorithms, parameter normalization, block processing, preset data, and
effect order are preserved.

One user-facing default intentionally differs: a fresh VST3 instance starts
with the Delay parameter at zero instead of the historical one-beat default.
This does not alter the Delay mapping or processing algorithm, and recalled
legacy state retains its stored value. The VST3 wrapper also adds standard host
bypass and exposes the 43 historical named presets through VST3's program-list
API. The VST2-only `> reset current <` command is not presented as a factory
preset.

The native editor redraws the historical layout from the unmodified upstream
PNG resources and derives its labels, effect menu, encoded controls, frequency
mapping, power scaling, logarithmic spectrum range, and six-stop spectrum
palette from the original GUI and engine sources. The SDK data-exchange helper
keeps allocation and delivery outside the real-time processing path and falls
back to VST3 messages for hosts predating the data-exchange interface.

The VST3 SDK is a submodule pinned to Steinberg tag `v3.8.1_build_84`, commit
`3cdf9ca5d1f5b1b21e0a86832aa4abe55607bd96`. Only its `base`, `cmake`,
`pluginterfaces`, and `public.sdk` submodules are initialized. VSTGUI examples,
tutorials, and documentation are not build dependencies.

FFTW is fetched from the official `fftw-3.3.10.tar.gz` release archive. Its
SHA-256 digest is
`56c932549852cddcfafdab3820b0200c7742675be92179e59e6215b340e26467`.
The generated codelets in the official release archive are required; the FFTW
Git tag alone does not contain them.

DtBlkFx and FFTW are GPL-compatible. The repository remains GPLv3 and preserves
the upstream authorship and notices. The VST3 SDK version used here is MIT
licensed. See `LICENSE`, `NOTICE`, and the dependency license files for terms.

Historical binaries used as independent audit oracles are not committed. Their
download locations, hashes, static-analysis results, and black-box comparison
results are recorded in `docs/COMPATIBILITY.md`.
