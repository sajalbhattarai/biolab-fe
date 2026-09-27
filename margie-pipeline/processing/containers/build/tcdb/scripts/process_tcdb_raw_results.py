#!/usr/bin/env python3
"""
process_tcdb_raw_results.py — Post-process TCDB DIAMOND blastp output into
a normalised, pipeline-friendly per-protein TSV.

INPUT (written by the run step into <output_dir>/raw/tcdb.tsv):
    DIAMOND blastp `-f 6` 7-column tabular output:
        qseqid sseqid pident length evalue bitscore stitle

    DIAMOND was invoked with `-k 1 --id 30 -e 1e-5` so each query has at
    most one hit row (best-hit).

    TCDB sseqid format looks like: `gnl|TC-DB|<uniprot_id>|<tc_id>`
    where <tc_id> is the canonical TC classification, e.g. `1.A.1.1.1`.

OPTIONAL: <output_dir>/raw/families.tsv (copied from the DB directory) —
    two-column TSV mapping TC family prefix → family description. If
    present, the processor enriches each row with TCDB_family_description.

OUTPUT (written under <output_dir>/processed/):
    tcdb_results.tsv  — one row per blast hit, TCDB_ prefix
    tcdb_top1.tsv     — same content (DIAMOND -k 1 already best-hit)
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
class tcdb_diamond_hit(NamedTuple):
    feature_id: str
    tcdb_subject_id: str
    tcdb_tc_id: str
    tcdb_tc_family_prefix: str
    tcdb_subject_title: str
    tcdb_percent_identity: float
    tcdb_alignment_length: int
    tcdb_evalue: float
    tcdb_bitscore: float


## Safe-conversion helpers.
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


## ── TC identifier extraction ──
##    Canonical TC numbers look like 1.A.1.1.1 (digit, letter, digit, digit,
##    digit). We accept any 5-token dotted form starting with digit.letter.
##    The "family prefix" is the first three tokens (e.g. 1.A.1) used for
##    optional families.tsv lookup.
TC_IDENTIFIER_PATTERN = re.compile(r"\b(\d+\.[A-Z]\.\d+(?:\.\d+){0,3})\b")

def extract_tc_identifier_from_subject_id(subject_id_value: str, subject_title_value: str) -> str:
    ## Try the sseqid first (most reliable: ends with TC id after final `|`).
    for source_string in (subject_id_value, subject_title_value):
        match = TC_IDENTIFIER_PATTERN.search(source_string)
        if match is not None:
            return match.group(1)
    return ""


def derive_family_prefix_from_tc_identifier(tc_identifier: str) -> str:
    if not tc_identifier:
        return ""
    tokens = tc_identifier.split(".")
    if len(tokens) >= 3:
        return ".".join(tokens[:3])
    return tc_identifier


## Optional families.tsv: TC_prefix<TAB>description.
def load_optional_family_description_map(families_tsv_path: Path) -> dict[str, str]:
    if not families_tsv_path.exists():
        return {}
    family_description_map: dict[str, str] = {}
    with open(families_tsv_path) as families_file_handle:
        for raw_line in families_file_handle:
            stripped_line = raw_line.rstrip("\n")
            if not stripped_line or stripped_line.startswith("#"):
                continue
            split_fields = stripped_line.split("\t")
            if len(split_fields) < 2:
                continue
            family_description_map[split_fields[0].strip()] = split_fields[1].strip()
    return family_description_map


## ── Step 1: parse DIAMOND `-f 6` 7-column TSV ──
def parse_diamond_tcdb_tsv(diamond_tsv_path: Path) -> list[tcdb_diamond_hit]:
    parsed_records: list[tcdb_diamond_hit] = []

    with open(diamond_tsv_path) as input_file_handle:
        for raw_line in input_file_handle:
            stripped_line = raw_line.rstrip("\n")
            if not stripped_line:
                continue
            if stripped_line.lstrip().startswith("#"):
                continue

            ## stitle (col 6) may legitimately contain tabs — preserve verbatim.
            split_fields = stripped_line.split("\t", 6)
            if len(split_fields) < 6:
                continue   ## malformed; skip

            subject_id_value    = split_fields[1]
            subject_title_value = split_fields[6] if len(split_fields) > 6 else ""

            tc_identifier_value   = extract_tc_identifier_from_subject_id(
                subject_id_value, subject_title_value)
            tc_family_prefix_value = derive_family_prefix_from_tc_identifier(
                tc_identifier_value)

            parsed_records.append(tcdb_diamond_hit(
                feature_id            = split_fields[0],
                tcdb_subject_id       = subject_id_value,
                tcdb_tc_id            = tc_identifier_value,
                tcdb_tc_family_prefix = tc_family_prefix_value,
                tcdb_subject_title    = subject_title_value,
                tcdb_percent_identity = safely_convert_to_float(split_fields[2]),
                tcdb_alignment_length = safely_convert_to_integer(split_fields[3]),
                tcdb_evalue           = safely_convert_to_float(split_fields[4]),
                tcdb_bitscore         = safely_convert_to_float(split_fields[5]),
            ))

    return parsed_records


## Canonical column order — defined once.
COLUMN_HEADER_ROW: list[str] = [
    "organism_name", "domain", "feature_id",
    "TCDB_subject_id", "TCDB_id", "TCDB_tc_family_prefix", "TCDB_family_description",
    "TCDB_description",
    "TCDB_percent_identity", "TCDB_alignment_length",
    "TCDB_evalue", "TCDB_bitscore",
    "TCDB_tool_used", "TCDB_command_used", "TCDB_database_used",
    "TCDB_evalue_threshold_used", "TCDB_percent_identity_threshold_used",
    "input_path", "output_path",
]


## CLI definition (argparse).
def parse_command_line_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True,
                        help="Path to raw DIAMOND tabular output (tcdb.tsv)")
    parser.add_argument("--output", required=True,
                        help="Path to write per-protein processed TSV (tcdb_results.tsv)")
    parser.add_argument("--output-top1", required=False, default=None,
                        help="Optional path for top-1 TSV (tcdb_top1.tsv); same content for DIAMOND -k 1")
    parser.add_argument("--families-tsv", required=False, default=None,
                        help="Optional TCDB families.tsv (TC_prefix<TAB>description) for description enrichment")
    parser.add_argument("--organism-name", required=True,
                        help="Organism name to record on every row")
    parser.add_argument("--domain", required=False, default="Unknown",
                        help="Domain label to record on every row (e.g. Archaea/Bacteria)")
    parser.add_argument("--tool-used", required=False, default="",
                        help="Human-readable tool identity/version recorded in output provenance")
    parser.add_argument("--command-used", required=False, default="",
                        help="Exact DIAMOND command line that produced the raw input")
    parser.add_argument("--database-used", required=False, default="",
                        help="TCDB database (.dmnd) used (provenance)")
    parser.add_argument("--evalue-threshold-used", required=False, default="",
                        help="DIAMOND e-value cutoff used (provenance)")
    parser.add_argument("--percent-identity-threshold-used", required=False, default="",
                        help="DIAMOND percent-identity cutoff used (provenance)")
    parser.add_argument("--input-path", required=False, default="",
                        help="Input protein FASTA path recorded for provenance")
    parser.add_argument("--output-path", required=False, default="",
                        help="Output directory path recorded for provenance")
    return parser.parse_args()


## Step 2: write a sorted TSV (csv module for safe quoting).
def write_processed_table(
    records_to_write: list[tcdb_diamond_hit],
    output_file_path: Path,
    organism_name_value: str,
    domain_value: str,
    family_description_map: dict[str, str],
    tool_used_value: str,
    command_used_value: str,
    database_used_value: str,
    evalue_threshold_value: str,
    percent_identity_threshold_value: str,
    input_path_value: str,
    output_path_value: str,
) -> int:
    output_file_path.parent.mkdir(parents=True, exist_ok=True)
    sorted_records = sorted(records_to_write,
                            key=lambda rec: (rec.feature_id, -rec.tcdb_bitscore))
    number_of_rows_written = 0
    with open(output_file_path, "w", newline="") as output_file_handle:
        writer = csv.writer(output_file_handle, delimiter="\t")
        writer.writerow(COLUMN_HEADER_ROW)
        for rec in sorted_records:
            family_description_value = family_description_map.get(rec.tcdb_tc_family_prefix, "")
            writer.writerow([
                organism_name_value, domain_value, rec.feature_id,
                rec.tcdb_subject_id, rec.tcdb_tc_id, rec.tcdb_tc_family_prefix, family_description_value,
                rec.tcdb_subject_title,
                f"{rec.tcdb_percent_identity:.4f}", rec.tcdb_alignment_length,
                f"{rec.tcdb_evalue:.3e}", f"{rec.tcdb_bitscore:.4f}",
                tool_used_value, command_used_value, database_used_value,
                evalue_threshold_value, percent_identity_threshold_value,
                input_path_value, output_path_value,
            ])
            number_of_rows_written += 1
    return number_of_rows_written


## Entry point.
def main() -> None:
    command_line_arguments = parse_command_line_arguments()

    input_file_path = Path(command_line_arguments.input)
    if not input_file_path.exists():
        print(f"[process_tcdb] ERROR: input not found: {input_file_path}", file=sys.stderr)
        raise SystemExit(1)

    family_description_map: dict[str, str] = {}
    if command_line_arguments.families_tsv:
        family_description_map = load_optional_family_description_map(
            Path(command_line_arguments.families_tsv))

    all_records = parse_diamond_tcdb_tsv(input_file_path)

    main_output_path = Path(command_line_arguments.output)
    number_of_rows_written = write_processed_table(
        all_records,
        main_output_path,
        command_line_arguments.organism_name,
        command_line_arguments.domain,
        family_description_map,
        command_line_arguments.tool_used,
        command_line_arguments.command_used,
        command_line_arguments.database_used,
        command_line_arguments.evalue_threshold_used,
        command_line_arguments.percent_identity_threshold_used,
        command_line_arguments.input_path,
        command_line_arguments.output_path,
    )
    print(f"[process_tcdb] Wrote {number_of_rows_written} rows → {main_output_path}")

    if command_line_arguments.output_top1:
        ## DIAMOND `-k 1` already emits at most one row per query — the top1
        ## file is content-identical. Kept for layout consistency.
        top_output_path = Path(command_line_arguments.output_top1)
        number_of_top_rows = write_processed_table(
            all_records,
            top_output_path,
            command_line_arguments.organism_name,
            command_line_arguments.domain,
            family_description_map,
            command_line_arguments.tool_used,
            command_line_arguments.command_used,
            command_line_arguments.database_used,
            command_line_arguments.evalue_threshold_used,
            command_line_arguments.percent_identity_threshold_used,
            command_line_arguments.input_path,
            command_line_arguments.output_path,
        )
        print(f"[process_tcdb] Wrote {number_of_top_rows} top-1 rows → {top_output_path}")


if __name__ == "__main__":
    main()
