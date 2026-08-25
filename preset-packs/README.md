# DtBlkFx preset packs

`DtBlkFx-VST3-Presets.zip` contains all 43 factory programs as standard
`.vstpreset` files. Extract its `VST3 Presets` folder into
`~/Library/Audio/Presets/` or import individual files in a compatible VST3
host.

`DtBlkFx-Ableton-Live-Presets.zip` contains the same 43 states as Ableton Live
11 `.adv` device presets. Extract its `DtBlkFx` folder into the Ableton User
Library. The pack is separate because Live does not populate its device preset
field from the VST3 program-list API.

The repository's preset generator asks the built plug-in to select each factory
program, saves it through Steinberg's canonical preset API, reloads every file
through the plug-in, and compares the restored state with all 44 normalized
DtBlkFx parameters. Each Ableton device preset embeds that already validated
component state in a device template captured from Ableton Live 11.

The archives are release artifacts in the repository. Building or packaging
them does not install either pack.
