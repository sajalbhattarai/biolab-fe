#!/usr/bin/env python3
"""rank_closest.py — Rank top-N closest organisms per genome from all-vs-all
AAI and/or ANI symmetric matrices produced by the 'aai' and 'ani' containers.

No external database is required; all scoring is within the user's own
annotated collection.

Composite score formula:
    composite = w_aai * (aai / 100) + w_ani * (ani / 100)
    where w_aai and w_ani are renormalised to sum to 1.0.

    When only one matrix is provided, that signal alone is used (w = 1.0).

Output columns:
    query_genome, rank, reference_genome, aai, ani, composite_score
"""

import argparse
import csv
import sys
from pathlib import Path


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Rank top-N closest organisms per genome from AAI + ANI matrices."
    )
    p.add_argument("--aai",
                   help="Symmetric AAI matrix TSV from the 'aai' container (optional)")
    p.add_argument("--ani",
                   help="Symmetric ANI matrix TSV from the 'ani' container (optional)")
    p.add_argument("--output", required=True,
                   help="Destination TSV path for closest_organisms.tsv")
    p.add_argument("--top-n", type=int, default=5,
                   help="Number of closest organisms to report per genome [default: 5]")
    p.add_argument("--weight-aai", type=float, default=0.5,
                   help="Weight for AAI signal in composite score [default: 0.5]")
    p.add_argument("--weight-ani", type=float, default=0.5,
                   help="Weight for ANI signal in composite score [default: 0.5]")
    p.add_argument("--collection-name", default="collection")
    return p.parse_args()


def _read_matrix(path: str) -> dict[str, dict[str, float | None]]:
    """Read a symmetric N×N matrix TSV with a blank-corner header row.

    First column = row labels; first row = column labels (after blank corner).
    Returns: {row_genome: {col_genome: score_or_None}}
    """
    result: dict[str, dict[str, float | None]] = {}
    with open(path, newline="") as fh:
        reader = csv.reader(fh, delimiter="\t")
        header = next(reader)
        # Strip possible blank leading cell
        if header and header[0] == "":
            col_labels = header[1:]
        else:
            col_labels = header[1:]  # same either way — first col is row label
        for row in reader:
            if not row:
                continue
            g1 = row[0]
            result[g1] = {}
            for g2, val in zip(col_labels, row[1:]):
                try:
                    result[g1][g2] = float(val)
                except (ValueError, TypeError):
                    result[g1][g2] = None
    return result


def _to_float(s: str) -> float | None:
    try:
        return float(s)
    except (ValueError, TypeError):
        return None


def _composite(
    aai: float | None,
    ani: float | None,
    w_aai: float,
    w_ani: float,
    has_aai: bool,
    has_ani: bool,
) -> float:
    """Compute renormalised weighted composite score in [0, 1]."""
    parts: list[tuple[float, float]] = []
    if has_aai and aai is not None:
        parts.append((w_aai, aai / 100.0))
    if has_ani and ani is not None:
        parts.append((w_ani, ani / 100.0))
    if not parts:
        return 0.0
    total_weight = sum(w for w, _ in parts)
    return round(sum(w * v for w, v in parts) / total_weight, 6)


def main() -> None:
    args = parse_args()

    if not args.aai and not args.ani:
        print("[rank_closest] ERROR: at least one of --aai or --ani must be provided",
              file=sys.stderr)
        sys.exit(1)

    aai_matrix = _read_matrix(args.aai) if args.aai else {}
    ani_matrix = _read_matrix(args.ani) if args.ani else {}

    has_aai = bool(aai_matrix)
    has_ani = bool(ani_matrix)

    # Union of all genome names
    all_genomes: set[str] = set()
    if has_aai:
        all_genomes.update(aai_matrix.keys())
    if has_ani:
        all_genomes.update(ani_matrix.keys())

    if not all_genomes:
        print("[rank_closest] ERROR: no genomes found in input matrices", file=sys.stderr)
        sys.exit(1)

    # All possible reference genomes (union of matrix columns, minus self)
    all_refs: set[str] = set()
    if has_aai:
        for row_d in aai_matrix.values():
            all_refs.update(row_d.keys())
    if has_ani:
        for row_d in ani_matrix.values():
            all_refs.update(row_d.keys())

    output_rows: list[dict] = []

    for query in sorted(all_genomes):
        refs = sorted(all_refs - {query})
        if not refs:
            print(f"[rank_closest] WARNING: no candidates for {query}; skipping.",
                  file=sys.stderr)
            continue

        ranked: list[dict] = []
        for ref in refs:
            aai_v = aai_matrix.get(query, {}).get(ref) if has_aai else None
            ani_v = ani_matrix.get(query, {}).get(ref) if has_ani else None
            comp = _composite(aai_v, ani_v, args.weight_aai, args.weight_ani,
                              has_aai, has_ani)
            ranked.append({
                "query_genome":     query,
                "reference_genome": ref,
                "aai":              f"{aai_v:.4f}" if aai_v is not None else "NA",
                "ani":              f"{ani_v:.4f}" if ani_v is not None else "NA",
                "composite_score":  comp,
            })

        ranked.sort(key=lambda r: r["composite_score"], reverse=True)
        for rank_i, entry in enumerate(ranked[: args.top_n], start=1):
            entry["rank"] = rank_i
            output_rows.append(entry)

    print(
        f"[rank_closest] {len(all_genomes)} genomes, "
        f"{len(output_rows)} ranking rows → {args.output}",
        file=sys.stderr,
    )

    Path(args.output).parent.mkdir(parents=True, exist_ok=True)
    fieldnames = [
        "query_genome", "rank", "reference_genome", "aai", "ani", "composite_score",
    ]
    with open(args.output, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=fieldnames, delimiter="\t",
                           extrasaction="ignore")
        w.writeheader()
        w.writerows(output_rows)

    print(f"[rank_closest] Done — {args.output}", file=sys.stderr)


if __name__ == "__main__":
    main()
