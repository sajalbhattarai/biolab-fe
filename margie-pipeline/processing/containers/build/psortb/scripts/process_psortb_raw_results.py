#!/usr/bin/env python3
"""
process_psortb_raw_results.py — Post-process PSORTb v3 terse output into
normalised, pipeline-friendly TSVs.

INPUT (written by the run step into <output_dir>/raw/psortb.txt):
    Tab-separated, header row followed by one row per protein:
        SeqID<TAB>Localization<TAB>Score
    PSORTb writes "Unknown" with a low score when no confident prediction
    is reached.

OUTPUT (written under <output_dir>/processed/):
    psortb_results.tsv  — one row per protein  (PSORTB_ prefix)
    psortb_top1.tsv     — only proteins with a confident (non-Unknown) localization
"""

## Module docstring (PEP 257) up top — clear summary of inputs/outputs.
## `from __future__ import annotations` (PEP 563) — modern type hints
## portable across Python versions.
from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path
from typing import NamedTuple


## Structured record (typing.NamedTuple): immutable, named row per protein.
class psortb_protein_localization(NamedTuple):
    feature_id: str
    psortb_localization: str
    psortb_score: float
    psortb_is_confident: bool


## Safe-conversion helper (defensive programming): PSORTb writes a float
## but occasional non-numeric placeholders shouldn't crash the run.
def safely_convert_to_float(raw_value: str) -> float:
    if raw_value in ("", ".", "-", None):
        return 0.0
    try:
        return float(raw_value)
    except (TypeError, ValueError):
        return 0.0


## Localization strings PSORTb treats as a confident, informative prediction.
## "Unknown" is dropped to the top1 ("confident-only") output.
PSORTB_UNCONFIDENT_LOCALIZATIONS: set[str] = {"Unknown", "unknown", ""}


## CLI definition (argparse standard library).
def parse_command_line_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True,
                        help="Path to raw PSORTb terse TSV (psortb.txt)")
    parser.add_argument("--output", required=True,
                        help="Path to write per-protein processed TSV (psortb_results.tsv)")
    parser.add_argument("--output-top1", required=False, default=None,
                        help="Optional path for confident-only TSV (psortb_top1.tsv)")
    parser.add_argument("--organism-name", required=True,
                        help="Organism name to record on every row (free text)")
    parser.add_argument("--domain", required=False, default="Unknown",
                        help="Domain label to record on every row (e.g. Archaea/Bacteria)")
    parser.add_argument("--tool-used", required=False, default="",
                        help="Human-readable tool identity/version recorded in output provenance")
    parser.add_argument("--command-used", required=False, default="",
                        help="Exact PSORTb command line that produced the raw input")
    parser.add_argument("--database-used", required=False, default="",
                        help="Model/database used (provenance)")
    parser.add_argument("--gram-class", required=False, default="",
                        help="PSORTb -k value (n|p|a) recorded as provenance")
    parser.add_argument("--input-path", required=False, default="",
                        help="Input protein FASTA path recorded for provenance")
    parser.add_argument("--output-path", required=False, default="",
                        help="Output directory path recorded for provenance")
    return parser.parse_args()


## Step 1 — read the PSORTb terse output. The first non-blank line is a
## header ("SeqID\tLocalization\tScore") and is skipped.
def read_psortb_terse_tsv(raw_tsv_file_path: Path) -> list[psortb_protein_localization]:
    parsed_records: list[psortb_protein_localization] = []

    with open(raw_tsv_file_path) as input_file_handle:
        header_seen = False
        for raw_line in input_file_handle:
            stripped_line = raw_line.rstrip("\n")
            if not stripped_line or stripped_line.startswith("#"):
                continue
            if not header_seen and stripped_line.lower().startswith("seqid"):
                header_seen = True
                continue

            split_fields = stripped_line.split("\t")
            if len(split_fields) < 3:
                continue   ## malformed line, skip

            protein_id_value = split_fields[0].strip()
            localization_value = split_fields[1].strip()
            score_value = safely_convert_to_float(split_fields[2].strip())

            is_confident_value = localization_value not in PSORTB_UNCONFIDENT_LOCALIZATIONS

            parsed_records.append(psortb_protein_localization(
                feature_id           = protein_id_value,
                psortb_localization  = localization_value,
                psortb_score         = score_value,
                psortb_is_confident  = is_confident_value,
            ))

    return parsed_records


## Canonical column order — defined once, reused for header + writer rows.
COLUMN_HEADER_ROW: list[str] = [
    "organism_name", "domain", "feature_id",
    "PSORTB_localization", "PSORTB_score", "PSORTB_is_confident",
    "PSORTB_tool_used", "PSORTB_command_used", "PSORTB_database_used", "PSORTB_gram_class",
    "input_path", "output_path",
]


## Step 2 — write a sorted TSV (uses csv module for safe quoting).
def write_processed_table(
    records_to_write: list[psortb_protein_localization],
    output_file_path: Path,
    organism_name_value: str,
    domain_value: str,
    tool_used_value: str,
    command_used_value: str,
    database_used_value: str,
    gram_class_value: str,
    input_path_value: str,
    output_path_value: str,
) -> int:
    output_file_path.parent.mkdir(parents=True, exist_ok=True)
    sorted_records = sorted(records_to_write, key=lambda rec: rec.feature_id)
    number_of_rows_written = 0
    with open(output_file_path, "w", newline="") as output_file_handle:
        writer = csv.writer(output_file_handle, delimiter="\t")
        writer.writerow(COLUMN_HEADER_ROW)
        for rec in sorted_records:
            writer.writerow([
                organism_name_value, domain_value, rec.feature_id,
                rec.psortb_localization, rec.psortb_score,
                "true" if rec.psortb_is_confident else "false",
                tool_used_value, command_used_value, database_used_value, gram_class_value,
                input_path_value, output_path_value,
            ])
            number_of_rows_written += 1
    return number_of_rows_written


## Entry point (standard `if __name__ == "__main__"` idiom).
def main() -> None:
    command_line_arguments = parse_command_line_arguments()

    input_file_path = Path(command_line_arguments.input)
    if not input_file_path.exists():
        print(f"[process_psortb] ERROR: input not found: {input_file_path}", file=sys.stderr)
        raise SystemExit(1)

    all_records = read_psortb_terse_tsv(input_file_path)

    main_output_path = Path(command_line_arguments.output)
    number_of_rows_written = write_processed_table(
        all_records,
        main_output_path,
        command_line_arguments.organism_name,
        command_line_arguments.domain,
        command_line_arguments.tool_used,
        command_line_arguments.command_used,
        command_line_arguments.database_used,
        command_line_arguments.gram_class,
        command_line_arguments.input_path,
        command_line_arguments.output_path,
    )
    print(f"[process_psortb] Wrote {number_of_rows_written} rows → {main_output_path}")

    if command_line_arguments.output_top1:
        top_output_path = Path(command_line_arguments.output_top1)
        confident_records = [rec for rec in all_records if rec.psortb_is_confident]
        number_of_confident_rows = write_processed_table(
            confident_records,
            top_output_path,
            command_line_arguments.organism_name,
            command_line_arguments.domain,
            command_line_arguments.tool_used,
            command_line_arguments.command_used,
            command_line_arguments.database_used,
            command_line_arguments.gram_class,
            command_line_arguments.input_path,
            command_line_arguments.output_path,
        )
        print(f"[process_psortb] Wrote {number_of_confident_rows} confident rows → {top_output_path}")


if __name__ == "__main__":
    main()
