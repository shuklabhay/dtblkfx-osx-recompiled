#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

git -C "$repo_dir" submodule update --init third_party/vst3sdk
git -C "$repo_dir/third_party/vst3sdk" submodule update --init base cmake pluginterfaces public.sdk

cmake -S "$repo_dir" -B "$repo_dir/build-au" \
  -DCMAKE_BUILD_TYPE=Release \
  -DDTBLKFX_BUILD_AUV2=ON \
  -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64"
cmake --build "$repo_dir/build-au" --target DtBlkFxAU dtblkfx_au_presets --parallel

echo "$repo_dir/build-au/AU/Release/DtBlkFx.component"
