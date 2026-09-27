#!/usr/bin/env python3
"""merge_liftoff.py — Deduplicate and merge per-reference Liftoff GFF3 outputs
into a single non-redundant GFF3 for downstream annotation consolidation.

Strategy:
  For each transferred gene/CDS/RNA feature in any of the per-reference GFF3
  outputs, keep only the instance with the highest coverage score
  (sequence_ID attribute injected by Liftoff).  When coverage scores are equal,
  prefer the reference with the lexicographically smallest name (deterministic).

  The source reference genome is recorded in a new GFF3 attribute:
      transfer_source=<ref_name>

  Features at the same locus (same contig, strand, and overlapping coordinates)
  are considered duplicates — only the best-coverage hit is retained.

Output:
  A GFF3 file containing the merged, deduplicated, sorted annotation.
"""

import argparse
import re
import sys
from pathlib import Path


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Merge per-reference Liftoff GFF3 outputs into one non-redundant GFF3."
    )
    p.add_argument(
        "--synteny-dir",
        required=True,
        help="Top-level synteny output directory (<output>/synteny/).",
    )
    p.add_argument("--output", required=True, help="Destination merged GFF3 path.")
    p.add_argument(
        "--query-name",
        default="query",
        help="Query genome name used in provenance comments [default: query].",
    )
    p.add_argument(
        "--feature-types",
        nargs="+",
        default=["gene", "mRNA", "CDS", "exon", "tRNA", "rRNA", "ncRNA"],
        help="GFF3 feature types to retain [default: gene mRNA CDS exon tRNA rRNA ncRNA].",
    )
    return p.parse_args()


class GFF3Record:
    """Lightweight GFF3 record."""

    __slots__ = ("seqid", "source", "ftype", "start", "end", "score",
                 "strand", "phase", "attrs", "ref_name", "coverage")

    def __init__(self, fields: list[str], ref_name: str) -> None:
        self.seqid  = fields[0]
        self.source = fields[1]
        self.ftype  = fields[2]
        self.start  = int(fields[3])
        self.end    = int(fields[4])
        self.score  = fields[5]
        self.strand = fields[6]
        self.phase  = fields[7]
        self.attrs  = fields[8]
        self.ref_name = ref_name
        self.coverage = _parse_coverage(self.attrs)

    def to_gff3_line(self) -> str:
        attrs = self.attrs.rstrip(";")
        # Append transfer_source attribute
        attrs += f";transfer_source={self.ref_name}"
        return "\t".join([
            self.seqid, self.source, self.ftype,
            str(self.start), str(self.end),
            self.score, self.strand, self.phase, attrs,
        ])


def _parse_coverage(attrs: str) -> float:
    """Extract coverage_score from Liftoff GFF3 attributes."""
    m = re.search(r"coverage_score=([0-9.]+)", attrs)
    if m:
        try:
            return float(m.group(1))
        except ValueError:
            pass
    return 0.0


def _locus_key(rec: GFF3Record) -> tuple:
    """Key for deduplication: same contig, strand, and overlapping locus."""
    return (rec.seqid, rec.strand, rec.ftype, rec.start, rec.end)


def load_gff3(path: Path, ref_name: str, keep_types: set[str]) -> list[GFF3Record]:
    records = []
    with open(path) as fh:
        for line in fh:
            if line.startswith("#") or not line.strip():
                continue
            fields = line.rstrip("\n").split("\t")
            if len(fields) < 9:
                continue
            if fields[2] not in keep_types:
                continue
            records.append(GFF3Record(fields, ref_name))
    return records


def main() -> None:
    args = parse_args()
    synteny_dir = Path(args.synteny_dir)
    keep_types = set(args.feature_types)

    all_records: list[GFF3Record] = []

    # Discover per-reference GFF3 files
    gff3_files = sorted(synteny_dir.rglob("liftoff.gff3"))
    if not gff3_files:
        print(
            f"[merge_liftoff] ERROR: no liftoff.gff3 files found in {synteny_dir}",
            file=sys.stderr,
        )
        sys.exit(1)

    for gff_path in gff3_files:
        ref_name = gff_path.parent.name
        recs = load_gff3(gff_path, ref_name, keep_types)
        all_records.extend(recs)
        print(
            f"[merge_liftoff] {ref_name}: {len(recs)} records loaded",
            file=sys.stderr,
        )

    # Deduplicate: for each locus key, keep the record with the highest coverage;
    # break ties by preferring the lexicographically smallest ref_name.
    best: dict[tuple, GFF3Record] = {}
    for rec in all_records:
        key = _locus_key(rec)
        if key not in best:
            best[key] = rec
        else:
            existing = best[key]
            if rec.coverage > existing.coverage or (
                rec.coverage == existing.coverage
                and rec.ref_name < existing.ref_name
            ):
                best[key] = rec

    merged = sorted(
        best.values(),
        key=lambda r: (r.seqid, r.start, r.end, r.ftype),
    )

    print(
        f"[merge_liftoff] {len(all_records)} total records → "
        f"{len(merged)} after deduplication → {args.output}",
        file=sys.stderr,
    )

    Path(args.output).parent.mkdir(parents=True, exist_ok=True)
    with open(args.output, "w") as fh:
        fh.write("##gff-version 3\n")
        fh.write(f"# merged by merge_liftoff.py; query={args.query_name}\n")
        for rec in merged:
            fh.write(rec.to_gff3_line() + "\n")

    print(f"[merge_liftoff] Done — {args.output}", file=sys.stderr)


if __name__ == "__main__":
    main()
