#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
current_bundle="$repo_dir/build/VST3/Release/DtBlkFx.vst3"
output_dir="$repo_dir/tmp_dtblk-osx-recompiled/benchmark"
reference_bundle="${1:-}"

mkdir -p "$output_dir"
cmake --build "$repo_dir/build" --target DtBlkFx dtblkfx_perf --parallel

for architecture in arm64 x86_64; do
    if [ "$architecture" = x86_64 ] && ! arch -x86_64 /usr/bin/true 2>/dev/null; then
        continue
    fi
    arch -"$architecture" "$repo_dir/build/bin/Release/dtblkfx_perf" "$current_bundle" \
        > "$output_dir/current-$architecture.csv"
    if [ -n "$reference_bundle" ]; then
        arch -"$architecture" "$repo_dir/build/bin/Release/dtblkfx_perf" "$reference_bundle" \
            > "$output_dir/reference-$architecture.csv"
        diff -u \
            <(cut -d, -f1-4 "$output_dir/reference-$architecture.csv") \
            <(cut -d, -f1-4 "$output_dir/current-$architecture.csv")
    fi
done

echo "Benchmark reports: $output_dir"
