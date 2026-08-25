#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
plugin="$repo_dir/build/VST3/Release/DtBlkFx.vst3"
validator="$repo_dir/build/bin/Release/validator"
smoke="$repo_dir/build/bin/Release/dtblkfx_smoke"

codesign --verify --deep --strict "$plugin"
arch -arm64 "$validator" -e -q "$plugin"
arch -arm64 "$smoke" "$plugin"

if arch -x86_64 /usr/bin/true 2>/dev/null; then
    arch -x86_64 "$validator" -e -q "$plugin"
    arch -x86_64 "$smoke" "$plugin"
fi
