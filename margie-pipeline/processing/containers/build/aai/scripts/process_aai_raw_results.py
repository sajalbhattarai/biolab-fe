#!/usr/bin/env python3
"""process_aai_raw_results.py — normalise EzAAI pairwise output to a symmetric
N×N matrix TSV for downstream use by the 'closest' container.

EzAAI 'calculate' outputs tab-separated rows:
    genome_A  genome_B  AAI_score  bidirectional_hits  ...

This script pivots those rows into a full N×N symmetric matrix:
    ""         genome_A  genome_B  genome_C
    genome_A   100.0     88.3      72.1
    genome_B   88.3      100.0     69.8
    genome_C   72.1      69.8      100.0

Self-comparisons are set to 100.0.  Pairs not reported by EzAAI are filled
with "NA".  The output is tab-separated with a header row.
"""

import argparse
import csv
import sys


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Normalise EzAAI pairwise output to a symmetric N×N matrix TSV."
    )
    p.add_argument("--input", required=True, help="EzAAI pairwise output TSV")
    p.add_argument("--output", required=True, help="Destination matrix TSV path")
    p.add_argument(
        "--collection-name",
        default="collection",
        help="Label for provenance messages [default: collection]",
    )
    return p.parse_args()


def main() -> None:
    args = parse_args()

    scores: dict[tuple[str, str], float] = {}
    genomes: set[str] = set()

    with open(args.input, newline="") as fh:
        for lineno, line in enumerate(fh, start=1):
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) < 3:
                print(
                    f"[process_aai] WARNING: line {lineno} has <3 fields, skipping: {line!r}",
                    file=sys.stderr,
                )
                continue
            g1, g2, score_str = parts[0], parts[1], parts[2]
            try:
                score = float(score_str)
            except ValueError:
                print(
                    f"[process_aai] WARNING: non-numeric score on line {lineno}: {score_str!r}",
                    file=sys.stderr,
                )
                continue
            genomes.update([g1, g2])
            # Symmetrise: EzAAI may or may not report both directions; take the
            # average when both directions are present.
            key_ab = (g1, g2)
            key_ba = (g2, g1)
            if key_ab in scores:
                scores[key_ab] = (scores[key_ab] + score) / 2.0
            else:
                scores[key_ab] = score
            if key_ba not in scores:
                scores[key_ba] = score

    if not genomes:
        print("[process_aai] ERROR: no valid rows parsed from input", file=sys.stderr)
        sys.exit(1)

    genome_list = sorted(genomes)
    print(
        f"[process_aai] {len(genome_list)} genomes; writing {len(genome_list)}×{len(genome_list)} matrix → {args.output}",
        file=sys.stderr,
    )

    with open(args.output, "w", newline="") as fh:
        w = csv.writer(fh, delimiter="\t")
        # Header row: blank corner + genome names
        w.writerow([""] + genome_list)
        for g1 in genome_list:
            row = [g1]
            for g2 in genome_list:
                if g1 == g2:
                    row.append("100.0")
                else:
                    v = scores.get((g1, g2), None)
                    row.append(f"{v:.4f}" if v is not None else "NA")
            w.writerow(row)

    print(f"[process_aai] Done — {args.output}", file=sys.stderr)


if __name__ == "__main__":
    main()
