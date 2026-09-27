#!/usr/bin/env python3
"""
process_merops_raw_results.py — Post-process MEROPS DIAMOND blastp output
into a normalised, pipeline-friendly per-protein TSV.

INPUT (written by the run step into <output_dir>/raw/merops.tsv):
    DIAMOND blastp `-f 6` 13-column tabular output:
        qseqid sseqid pident length mismatch gapopen
        qstart qend sstart send evalue bitscore stitle

    DIAMOND was invoked with `-k 1` so each query already has at most
    one hit row (best-hit). The stitle column for MEROPS pepunit looks
    like e.g. "MER0000001 - cysteine peptidase ... family C01".

OUTPUT (written under <output_dir>/processed/):
    merops_results.tsv  — one row per blast hit, MEROPS_ prefix
    merops_top1.tsv     — same content (DIAMOND -k 1 already best-hit)
"""

## Module docstring (PEP 257). `from __future__ import annotations`
## (PEP 563) — modern type hints portable across versions.
from __future__ import annotations

import argparse
import csv
import re
import sys
from pathlib import Path
from typing import NamedTuple


## Structured per-hit record (typing.NamedTuple).
class merops_diamond_hit(NamedTuple):
    feature_id: str
    merops_subject_id: str
    merops_family: str
    merops_subject_title: str
    merops_percent_identity: float
    merops_alignment_length: int
    merops_mismatches: int
    merops_gap_openings: int
    merops_query_start: int
    merops_query_end: int
    merops_subject_start: int
    merops_subject_end: int
    merops_evalue: float
    merops_bitscore: float


## Safe-conversion helpers (defensive programming).
def safely_convert_to_float(raw_value: str) -> float:
    if raw_value in ("", ".", "-", None):
        return 0.0
    try:
        return float(raw_value)
    except (TypeError, ValueError):
        return 0.0


def safely_convert_to_integer(raw_value: str) -> int:
    if raw_value in ("", ".", "-", None):
        return 0
    try:
        return int(raw_value)
    except (TypeError, ValueError):
        try:
            return int(float(raw_value))
        except (TypeError, ValueError):
            return 0


## ── Step 1: parse a DIAMOND `-f 6` 13-column TSV ──
##    Columns:
##        0  qseqid        feature id (query)
##        1  sseqid        MEROPS identifier (e.g. MER0000001)
##        2  pident        % identity
##        3  length        alignment length
##        4  mismatch
##        5  gapopen
##        6  qstart
##        7  qend
##        8  sstart
##        9  send
##       10  evalue
##       11  bitscore
##       12  stitle        full subject title (free text, may contain tabs)
##
##    The stitle commonly contains a peptidase-family tag such as "family C01"
##    or "C01" — we extract it best-effort but never fail.
MEROPS_FAMILY_PATTERN = re.compile(r"\b([A-Z]\d{2,3}[A-Za-z]?)\b")

def extract_merops_family_from_subject_title(subject_title: str) -> str:
    match = MEROPS_FAMILY_PATTERN.search(subject_title)
    if match is None:
        return ""
    return match.group(1)


def parse_diamond_merops_tsv(diamond_tsv_path: Path) -> list[merops_diamond_hit]:
    parsed_records: list[merops_diamond_hit] = []

    with open(diamond_tsv_path) as input_file_handle:
        for raw_line in input_file_handle:
            stripped_line = raw_line.rstrip("\n")
            if not stripped_line:
                continue
            if stripped_line.lstrip().startswith("#"):
                continue

            ## stitle (col 12) may legitimately contain tabs. Split with maxsplit=12
            ## so the title is preserved verbatim.
            split_fields = stripped_line.split("\t", 12)
            if len(split_fields) < 12:
                continue   ## malformed; skip

            subject_title_value = split_fields[12] if len(split_fields) > 12 else ""

            parsed_records.append(merops_diamond_hit(
                feature_id              = split_fields[0],
                merops_subject_id       = split_fields[1],
                merops_family           = extract_merops_family_from_subject_title(subject_title_value),
                merops_subject_title    = subject_title_value,
                merops_percent_identity = safely_convert_to_float(split_fields[2]),
                merops_alignment_length = safely_convert_to_integer(split_fields[3]),
                merops_mismatches       = safely_convert_to_integer(split_fields[4]),
                merops_gap_openings     = safely_convert_to_integer(split_fields[5]),
                merops_query_start      = safely_convert_to_integer(split_fields[6]),
                merops_query_end        = safely_convert_to_integer(split_fields[7]),
                merops_subject_start    = safely_convert_to_integer(split_fields[8]),
                merops_subject_end      = safely_convert_to_integer(split_fields[9]),
                merops_evalue           = safely_convert_to_float(split_fields[10]),
                merops_bitscore         = safely_convert_to_float(split_fields[11]),
            ))

    return parsed_records


## Canonical column order — defined once.
COLUMN_HEADER_ROW: list[str] = [
    "organism_name", "domain", "feature_id",
    "MEROPS_id", "MEROPS_family",
    "MEROPS_description",
    "MEROPS_percent_identity", "MEROPS_alignment_length",
    "MEROPS_mismatches", "MEROPS_gap_openings",
    "MEROPS_query_start", "MEROPS_query_end",
    "MEROPS_subject_start", "MEROPS_subject_end",
    "MEROPS_evalue", "MEROPS_bitscore",
    "MEROPS_tool_used", "MEROPS_command_used", "MEROPS_database_used", "MEROPS_evalue_threshold_used",
    "input_path", "output_path",
]


## CLI definition (argparse).
def parse_command_line_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True,
                        help="Path to raw DIAMOND tabular output (merops.tsv)")
    parser.add_argument("--output", required=True,
                        help="Path to write per-protein processed TSV (merops_results.tsv)")
    parser.add_argument("--output-top1", required=False, default=None,
                        help="Optional path for top-1 TSV (merops_top1.tsv); same content for DIAMOND -k 1")
    parser.add_argument("--organism-name", required=True,
                        help="Organism name to record on every row")
    parser.add_argument("--domain", required=False, default="Unknown",
                        help="Domain label to record on every row (e.g. Archaea/Bacteria)")
    parser.add_argument("--tool-used", required=False, default="",
                        help="Human-readable tool identity/version recorded in output provenance")
    parser.add_argument("--command-used", required=False, default="",
                        help="Exact DIAMOND command line that produced the raw input")
    parser.add_argument("--database-used", required=False, default="",
                        help="MEROPS database (.dmnd) used (provenance)")
    parser.add_argument("--evalue-threshold-used", required=False, default="",
                        help="DIAMOND e-value cutoff used (provenance)")
    parser.add_argument("--input-path", required=False, default="",
                        help="Input protein FASTA path recorded for provenance")
    parser.add_argument("--output-path", required=False, default="",
                        help="Output directory path recorded for provenance")
    return parser.parse_args()


## Step 2: write a sorted TSV (csv module for safe quoting).
def write_processed_table(
    records_to_write: list[merops_diamond_hit],
    output_file_path: Path,
    organism_name_value: str,
    domain_value: str,
    tool_used_value: str,
    command_used_value: str,
    database_used_value: str,
    evalue_threshold_value: str,
    input_path_value: str,
    output_path_value: str,
) -> int:
    output_file_path.parent.mkdir(parents=True, exist_ok=True)
    sorted_records = sorted(records_to_write,
                            key=lambda rec: (rec.feature_id, -rec.merops_bitscore))
    number_of_rows_written = 0
    with open(output_file_path, "w", newline="") as output_file_handle:
        writer = csv.writer(output_file_handle, delimiter="\t")
        writer.writerow(COLUMN_HEADER_ROW)
        for rec in sorted_records:
            writer.writerow([
                organism_name_value, domain_value, rec.feature_id,
                rec.merops_subject_id, rec.merops_family,
                rec.merops_subject_title,
                f"{rec.merops_percent_identity:.4f}", rec.merops_alignment_length,
                rec.merops_mismatches, rec.merops_gap_openings,
                rec.merops_query_start, rec.merops_query_end,
                rec.merops_subject_start, rec.merops_subject_end,
                f"{rec.merops_evalue:.3e}", f"{rec.merops_bitscore:.4f}",
                tool_used_value, command_used_value, database_used_value, evalue_threshold_value,
                input_path_value, output_path_value,
            ])
            number_of_rows_written += 1
    return number_of_rows_written


## Entry point.
def main() -> None:
    command_line_arguments = parse_command_line_arguments()

    input_file_path = Path(command_line_arguments.input)
    if not input_file_path.exists():
        print(f"[process_merops] ERROR: input not found: {input_file_path}", file=sys.stderr)
        raise SystemExit(1)

    all_records = parse_diamond_merops_tsv(input_file_path)

    main_output_path = Path(command_line_arguments.output)
    number_of_rows_written = write_processed_table(
        all_records,
        main_output_path,
        command_line_arguments.organism_name,
        command_line_arguments.domain,
        command_line_arguments.tool_used,
        command_line_arguments.command_used,
        command_line_arguments.database_used,
        command_line_arguments.evalue_threshold_used,
        command_line_arguments.input_path,
        command_line_arguments.output_path,
    )
    print(f"[process_merops] Wrote {number_of_rows_written} rows → {main_output_path}")

    if command_line_arguments.output_top1:
        ## DIAMOND `-k 1` already emits at most one row per query — the top1
        ## file is content-identical. Kept for layout consistency.
        top_output_path = Path(command_line_arguments.output_top1)
        number_of_top_rows = write_processed_table(
            all_records,
            top_output_path,
            command_line_arguments.organism_name,
            command_line_arguments.domain,
            command_line_arguments.tool_used,
            command_line_arguments.command_used,
            command_line_arguments.database_used,
            command_line_arguments.evalue_threshold_used,
            command_line_arguments.input_path,
            command_line_arguments.output_path,
        )
        print(f"[process_merops] Wrote {number_of_top_rows} top-1 rows → {top_output_path}")


if __name__ == "__main__":
    main()
