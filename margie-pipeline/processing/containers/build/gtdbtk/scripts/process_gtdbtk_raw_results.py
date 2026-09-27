#!/usr/bin/env python3
# process_gtdbtk_raw_results.py — normalise GTDB-Tk summary TSVs into one table
from __future__ import annotations

import argparse
import csv
from pathlib import Path

# =============================================================================
# Argument parsing
# =============================================================================

def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser()
    p.add_argument("--bac-summary",     required=True)
    p.add_argument("--arc-summary",     required=True)
    p.add_argument("--output",          required=True)
    p.add_argument("--collection-name", required=True)
    p.add_argument("--tool-used",       default="")
    p.add_argument("--database-used",   default="")
    p.add_argument("--input-path",      default="")
    p.add_argument("--output-path",     default="")
    return p.parse_args()

# =============================================================================
# Summary reading
# =============================================================================

def read_summary(path: Path, domain_label: str) -> list[dict[str, str]]:
    if not path.exists() or path.stat().st_size == 0:
        return []
    rows: list[dict[str, str]] = []
    with path.open("r", newline="") as fh:
        for rec in csv.DictReader(fh, delimiter="\t"):
            genome = rec.get("user_genome", "")
            if not genome:
                continue
            # GTDB-Tk v2.x retains fastani_* column names even though skani
            # replaced FastANI as the ANI tool in v2.4 — read as-is, rename on output
            rows.append({
                "genome":                       genome,
                "GTDBTK_domain":                domain_label,
                "GTDBTK_classification":        rec.get("classification", ""),
                "GTDBTK_classification_method": rec.get("classification_method", ""),
                "GTDBTK_ani_reference":         rec.get("fastani_reference", ""),
                "GTDBTK_ani_value":             rec.get("fastani_ani", ""),
                "GTDBTK_ani_af":                rec.get("fastani_af", ""),
                "GTDBTK_red_value":             rec.get("red_value", ""),
                "GTDBTK_warnings":              rec.get("warnings", ""),
            })
    return rows

# =============================================================================
# Main
# =============================================================================

def main() -> None:
    args = parse_args()

    all_rows = sorted(
        read_summary(Path(args.bac_summary), "Bacteria") +
        read_summary(Path(args.arc_summary),  "Archaea"),
        key=lambda r: r["genome"],
    )

    out_path = Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    headers = [
        "collection_name", "genome",
        "GTDBTK_domain", "GTDBTK_classification", "GTDBTK_classification_method",
        "GTDBTK_ani_reference", "GTDBTK_ani_value", "GTDBTK_ani_af",
        "GTDBTK_red_value", "GTDBTK_warnings",
        "GTDBTK_tool_used", "GTDBTK_database_used",
        "input_path", "output_path",
    ]

    with out_path.open("w", newline="") as fh:
        w = csv.writer(fh, delimiter="\t")
        w.writerow(headers)
        for r in all_rows:
            w.writerow([
                args.collection_name,          r["genome"],
                r["GTDBTK_domain"],            r["GTDBTK_classification"],
                r["GTDBTK_classification_method"],
                r["GTDBTK_ani_reference"],     r["GTDBTK_ani_value"],
                r["GTDBTK_ani_af"],            r["GTDBTK_red_value"],
                r["GTDBTK_warnings"],
                args.tool_used,                args.database_used,
                args.input_path,               args.output_path,
            ])

    print(f"[process_gtdbtk] Wrote {len(all_rows)} rows -> {out_path}")


if __name__ == "__main__":
    main()
