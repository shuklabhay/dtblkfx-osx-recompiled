#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
generated_dir="$repo_dir/tmp_dtblk-osx-recompiled/vst3-presets"

cmake --build "$repo_dir/build" --target DtBlkFx dtblkfx_presets --parallel
rm -rf "$generated_dir"
"$repo_dir/build/bin/Release/dtblkfx_presets" \
  "$repo_dir/build/VST3/Release/DtBlkFx.vst3" \
  "$generated_dir"
python3 "$repo_dir/scripts/package_presets.py" package \
  "$generated_dir" \
  "$repo_dir/preset-packs/source/DtBlkFx-Live11.template.adv" \
  "$repo_dir/preset-packs"
