#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

git -C "$repo_dir" submodule update --init third_party/vst3sdk
git -C "$repo_dir/third_party/vst3sdk" submodule update --init base cmake pluginterfaces public.sdk

cmake -S "$repo_dir" -B "$repo_dir/build" -DCMAKE_BUILD_TYPE=Release -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
cmake --build "$repo_dir/build" --target DtBlkFx validator --parallel
"$repo_dir/build/bin/Release/validator" "$repo_dir/build/VST3/Release/DtBlkFx.vst3"
