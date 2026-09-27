#!/usr/bin/env python3
"""Remap RASTtk protein FASTA headers from generic protein_N to GFF CDS IDs.

When `rast-export-genome protein_fasta` emits headers like `protein_1`, this
script replaces them with the corresponding `ID=` values from CDS entries in
the GFF3 file, preserving sequence order.
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path


CDS_ID_PATTERN = re.compile(r"(?:^|;)ID=([^;]+)")
GENERIC_HEADER_PATTERN = re.compile(r"^protein_\d+$")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--gff", required=True, help="Path to GFF3 with CDS features")
    parser.add_argument("--faa", required=True, help="Path to protein FASTA to rewrite")
    return parser.parse_args()


def load_cds_ids(gff_path: Path) -> list[str]:
    ids: list[str] = []
    with gff_path.open() as handle:
        for raw in handle:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            fields = line.split("\t")
            if len(fields) < 9 or fields[2] != "CDS":
                continue
            match = CDS_ID_PATTERN.search(fields[8])
            if match:
                ids.append(match.group(1))
    return ids


def collect_headers(faa_path: Path) -> list[str]:
    headers: list[str] = []
    with faa_path.open() as handle:
        for raw in handle:
            if raw.startswith(">"):
                header = raw[1:].strip().split(maxsplit=1)[0]
                headers.append(header)
    return headers


def rewrite_headers(faa_path: Path, replacement_ids: list[str]) -> None:
    output_lines: list[str] = []
    header_index = 0
    with faa_path.open() as handle:
        for raw in handle:
            if raw.startswith(">"):
                stripped = raw[1:].rstrip("\n")
                parts = stripped.split(maxsplit=1)
                suffix = f" {parts[1]}" if len(parts) == 2 else ""
                output_lines.append(f">{replacement_ids[header_index]}{suffix}\n")
                header_index += 1
            else:
                output_lines.append(raw)

    tmp_path = faa_path.with_suffix(faa_path.suffix + ".tmp")
    with tmp_path.open("w") as handle:
        handle.writelines(output_lines)
    tmp_path.replace(faa_path)


def main() -> int:
    args = parse_args()
    gff_path = Path(args.gff)
    faa_path = Path(args.faa)

    if not gff_path.exists() or not faa_path.exists():
        return 1

    cds_ids = load_cds_ids(gff_path)
    faa_headers = collect_headers(faa_path)
    if not faa_headers:
        print("[rasttk-remap] FASTA has no headers; skipping")
        return 0

    if not all(GENERIC_HEADER_PATTERN.match(header) for header in faa_headers):
        print("[rasttk-remap] FASTA already uses non-generic IDs; skipping")
        return 0

    if len(cds_ids) != len(faa_headers):
        print(
            f"[rasttk-remap] CDS/header count mismatch ({len(cds_ids)} vs {len(faa_headers)}); skipping"
        )
        return 0

    rewrite_headers(faa_path, cds_ids)
    print(f"[rasttk-remap] Rewrote {len(faa_headers)} FASTA headers using GFF CDS IDs")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
