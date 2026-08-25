#!/usr/bin/env python3
"""Compare directories of interleaved float32 oracle renders."""

from __future__ import annotations

import argparse
import array
import math
import statistics
import sys
from pathlib import Path


def read_floats(path: Path) -> array.array[float]:
    """Read native float32 samples and normalize endianness."""
    samples = array.array("f")
    with path.open("rb") as stream:
        samples.fromfile(stream, path.stat().st_size // samples.itemsize)
    if sys.byteorder != "little":
        samples.byteswap()
    return samples


def metrics(left: array.array[float], right: array.array[float]) -> tuple[float, float]:
    """Return signal-to-error ratio and Pearson correlation."""
    if len(left) != len(right) or not left:
        raise ValueError("renders must contain the same nonzero sample count")

    signal = 0.0
    error = 0.0
    left_sum = 0.0
    right_sum = 0.0
    left_square_sum = 0.0
    right_square_sum = 0.0
    cross_sum = 0.0
    for left_sample, right_sample in zip(left, right, strict=True):
        difference = left_sample - right_sample
        signal += right_sample * right_sample
        error += difference * difference
        left_sum += left_sample
        right_sum += right_sample
        left_square_sum += left_sample * left_sample
        right_square_sum += right_sample * right_sample
        cross_sum += left_sample * right_sample

    snr = math.inf if error == 0.0 else 10.0 * math.log10(signal / error)
    count = len(left)
    covariance = cross_sum - left_sum * right_sum / count
    left_variance = left_square_sum - left_sum * left_sum / count
    right_variance = right_square_sum - right_sum * right_sum / count
    denominator = math.sqrt(max(0.0, left_variance * right_variance))
    correlation = 1.0 if denominator == 0.0 and error == 0.0 else covariance / denominator
    return snr, correlation


def compare(left_directory: Path, right_directory: Path) -> int:
    """Compare matching renders and print per-scenario and summary metrics."""
    left_paths = sorted(left_directory.glob("*.f32"))
    if not left_paths:
        raise ValueError(f"no .f32 renders found in {left_directory}")

    rows: list[tuple[str, float, float]] = []
    print("scenario,snr_db,correlation")
    for left_path in left_paths:
        right_path = right_directory / left_path.name
        if not right_path.is_file():
            raise ValueError(f"missing matching render: {right_path}")
        snr, correlation = metrics(read_floats(left_path), read_floats(right_path))
        rows.append((left_path.stem, snr, correlation))
        print(f"{left_path.stem},{snr:.9f},{correlation:.12f}")

    worst = min(rows, key=lambda row: row[1])
    print(
        f"summary,count={len(rows)},median_snr_db={statistics.median(row[1] for row in rows):.9f},"
        f"minimum_snr_db={worst[1]:.9f},minimum_snr_scenario={worst[0]},"
        f"minimum_correlation={min(row[2] for row in rows):.12f}"
    )
    return 0


def main() -> int:
    """Parse directories and run the oracle comparison."""
    parser = argparse.ArgumentParser()
    parser.add_argument("left", type=Path)
    parser.add_argument("right", type=Path)
    arguments = parser.parse_args()
    return compare(arguments.left, arguments.right)


if __name__ == "__main__":
    raise SystemExit(main())
