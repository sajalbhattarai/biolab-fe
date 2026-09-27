#!/usr/bin/env python3
"""process_ani_raw_results.py — normalise FastANI pairwise output to a symmetric
N×N matrix TSV for downstream use by the 'closest' container.

FastANI outputs tab-separated rows when run with query list vs. reference list:
    /path/to/query.fna  /path/to/ref.fna  ANI_score  mapped_frags  total_frags

This script:
  1. Extracts the genome base name (without directory and .fna extension).
  2. Symmetrises the scores (FastANI is directional; we average both directions).
  3. Writes a full N×N matrix with genome names as row and column headers.

Pairs that were not reported by FastANI (below --minFraction threshold) are
filled with "NA" in the output matrix.
"""

import argparse
import csv
import sys
from pathlib import Path


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Normalise FastANI pairwise output to a symmetric N×N matrix TSV."
    )
    p.add_argument("--input", required=True, help="FastANI pairwise output TSV")
    p.add_argument("--output", required=True, help="Destination matrix TSV path")
    p.add_argument(
        "--collection-name",
        default="collection",
        help="Label for provenance messages [default: collection]",
    )
    return p.parse_args()


def _genome_label(path_str: str) -> str:
    """Strip directory prefix and .fna extension to get a clean genome label."""
    return Path(path_str).stem


def main() -> None:
    args = parse_args()

    scores: dict[tuple[str, str], list[float]] = {}
    genomes: set[str] = set()

    with open(args.input, newline="") as fh:
        for lineno, line in enumerate(fh, start=1):
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) < 3:
                print(
                    f"[process_ani] WARNING: line {lineno} has <3 fields, skipping: {line!r}",
                    file=sys.stderr,
                )
                continue
            g1 = _genome_label(parts[0])
            g2 = _genome_label(parts[1])
            try:
                score = float(parts[2])
            except ValueError:
                print(
                    f"[process_ani] WARNING: non-numeric ANI on line {lineno}: {parts[2]!r}",
                    file=sys.stderr,
                )
                continue
            genomes.update([g1, g2])
            scores.setdefault((g1, g2), []).append(score)
            scores.setdefault((g2, g1), []).append(score)

    if not genomes:
        print("[process_ani] ERROR: no valid rows parsed from input", file=sys.stderr)
        sys.exit(1)

    genome_list = sorted(genomes)
    print(
        f"[process_ani] {len(genome_list)} genomes; writing {len(genome_list)}×{len(genome_list)} matrix → {args.output}",
        file=sys.stderr,
    )

    with open(args.output, "w", newline="") as fh:
        w = csv.writer(fh, delimiter="\t")
        w.writerow([""] + genome_list)
        for g1 in genome_list:
            row = [g1]
            for g2 in genome_list:
                if g1 == g2:
                    row.append("100.0")
                else:
                    vals = scores.get((g1, g2))
                    if vals:
                        row.append(f"{sum(vals) / len(vals):.4f}")
                    else:
                        row.append("NA")
            w.writerow(row)

    print(f"[process_ani] Done — {args.output}", file=sys.stderr)


if __name__ == "__main__":
    main()
