#!/usr/bin/env python3
"""
process_deepsig_raw_results.py — Post-process DeepSig GFF3 output into
normalised, pipeline-friendly TSVs.

INPUT (written by the run step into <output_dir>/raw/deepsig.gff3):
    Standard GFF3, 9 tab-separated columns:
      seqid  source  type  start  end  score  strand  phase  attributes
    where:
      seqid      = protein ID
      type       = feature class (e.g. "Signal peptide", "Lipoprotein signal peptide",
                   "Transmembrane", "Other")
      start/end  = 1-based, inclusive coordinates
      score      = prediction probability (0-1)
      attributes = key=value;key=value (DeepSig writes evidence=DeepSig and may add more)

OUTPUT (written under <output_dir>/processed/):
    deepsig_results.tsv  — one row per GFF3 feature line  (DEEPSIG_ prefix)
    deepsig_top1.tsv     — one summary row per protein
"""

## Module docstring (PEP 257) up top — describes the script's purpose so
## anyone reading it understands input/output without scanning code.
## `from __future__ import annotations` (PEP 563) keeps modern type hints
## like `list[str]` and `dict[str, str]` portable across Python versions.
from __future__ import annotations

import argparse
import csv
import sys
from collections import defaultdict
from pathlib import Path
from typing import NamedTuple


## Structured records (typing.NamedTuple): immutable, named rows — much
## easier to read than positional tuples, no field-order bugs.
class deepsig_feature_record(NamedTuple):
    feature_id: str
    deepsig_feature_type: str
    deepsig_start: int
    deepsig_end: int
    deepsig_length: int
    deepsig_score: float
    deepsig_evidence: str
    deepsig_attributes: str


class deepsig_protein_summary(NamedTuple):
    feature_id: str
    deepsig_has_signal_peptide: bool
    deepsig_best_feature_type: str
    deepsig_best_start: int
    deepsig_best_end: int
    deepsig_best_length: int
    deepsig_best_score: float
    deepsig_total_features: int


## Safe-conversion helpers (defensive programming): GFF3 score is "." when
## not available; start/end should always be integers but we don't want
## a single weird line to crash the run.
def safely_convert_to_float(raw_value: str) -> float:
    if raw_value in ("", ".", None):
        return 0.0
    try:
        return float(raw_value)
    except (TypeError, ValueError):
        return 0.0


def safely_convert_to_integer(raw_value: str) -> int:
    try:
        return int(raw_value)
    except (TypeError, ValueError):
        return 0


## Feature-type labels we treat as "signal peptide present". DeepSig writes
## these strings in the GFF3 `type` column for prokaryotic predictions.
DEEPSIG_SIGNAL_PEPTIDE_FEATURE_TYPES: set[str] = {
    "Signal peptide",
    "Lipoprotein signal peptide",
    "TAT signal peptide",
    "Pilin signal peptide",
}


## CLI definition (argparse standard library): every flag declared in one
## place. argparse auto-generates --help.
def parse_command_line_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True,
                        help="Path to raw DeepSig GFF3 file (deepsig.gff3)")
    parser.add_argument("--output", required=True,
                        help="Path to write per-feature processed TSV (deepsig_results.tsv)")
    parser.add_argument("--output-top1", required=False, default=None,
                        help="Optional path for per-protein summary TSV (deepsig_top1.tsv)")
    parser.add_argument("--organism-name", required=True,
                        help="Organism name to record on every row (free text)")
    parser.add_argument("--domain", required=False, default="Unknown",
                        help="Domain label to record on every row (e.g. Archaea/Bacteria)")
    parser.add_argument("--tool-used", required=False, default="",
                        help="Human-readable tool identity/version recorded in output provenance")
    parser.add_argument("--command-used", required=False, default="",
                        help="Exact deepsig command line that produced the raw input")
    parser.add_argument("--database-used", required=False, default="",
                        help="Model/database used (provenance)")
    parser.add_argument("--organism-class", required=False, default="",
                        help="DeepSig -k value (gramn|gramp|euk) recorded as provenance")
    parser.add_argument("--input-path", required=False, default="",
                        help="Input protein FASTA path recorded for provenance")
    parser.add_argument("--output-path", required=False, default="",
                        help="Output directory path recorded for provenance")
    return parser.parse_args()


## Step 1 — parse the GFF3 attributes field (key=value;key=value) into a
## plain dict. Used to surface DeepSig's `evidence=` field separately.
def parse_gff3_attributes_field(attributes_field_value: str) -> dict[str, str]:
    parsed_attribute_pairs: dict[str, str] = {}
    if not attributes_field_value or attributes_field_value == ".":
        return parsed_attribute_pairs
    for raw_key_value_pair in attributes_field_value.split(";"):
        stripped_pair = raw_key_value_pair.strip()
        if not stripped_pair or "=" not in stripped_pair:
            continue
        key_part, _, value_part = stripped_pair.partition("=")
        parsed_attribute_pairs[key_part.strip()] = value_part.strip()
    return parsed_attribute_pairs


## Step 2 — read the GFF3 file (lines beginning with '#' are comments).
def read_deepsig_gff3_file(gff3_file_path: Path) -> list[deepsig_feature_record]:
    parsed_records: list[deepsig_feature_record] = []
    with open(gff3_file_path) as input_file_handle:
        for raw_line in input_file_handle:
            stripped_line = raw_line.rstrip("\n")
            if not stripped_line or stripped_line.startswith("#"):
                continue
            split_fields = stripped_line.split("\t")
            if len(split_fields) < 9:
                continue   ## malformed line, skip

            attributes_dict = parse_gff3_attributes_field(split_fields[8])
            evidence_value = attributes_dict.get("evidence", "")

            start_position = safely_convert_to_integer(split_fields[3])
            end_position = safely_convert_to_integer(split_fields[4])
            feature_length = max(0, end_position - start_position + 1)

            parsed_records.append(deepsig_feature_record(
                feature_id              = split_fields[0],
                deepsig_feature_type    = split_fields[2],
                deepsig_start           = start_position,
                deepsig_end             = end_position,
                deepsig_length          = feature_length,
                deepsig_score           = safely_convert_to_float(split_fields[5]),
                deepsig_evidence        = evidence_value,
                deepsig_attributes      = split_fields[8],
            ))
    return parsed_records


## Step 3 — for each protein, pick the single most informative feature.
## Priority: signal-peptide feature types beat everything else; within the
## same priority class, higher score wins.
def select_best_feature_per_protein(
    all_feature_records: list[deepsig_feature_record],
) -> list[deepsig_protein_summary]:

    records_grouped_by_protein: dict[str, list[deepsig_feature_record]] = defaultdict(list)
    for record in all_feature_records:
        records_grouped_by_protein[record.feature_id].append(record)

    def ranking_key(record: deepsig_feature_record) -> tuple[int, float]:
        ## Lower tuple sorts first. We want signal-peptide hits first,
        ## then highest score. Negate score so sorted ascending gives best first.
        is_signal_peptide = record.deepsig_feature_type in DEEPSIG_SIGNAL_PEPTIDE_FEATURE_TYPES
        priority_value = 0 if is_signal_peptide else 1
        return (priority_value, -record.deepsig_score)

    summary_records: list[deepsig_protein_summary] = []
    for protein_id_value in sorted(records_grouped_by_protein):
        candidate_records = records_grouped_by_protein[protein_id_value]
        ranked_records = sorted(candidate_records, key=ranking_key)
        best_record = ranked_records[0]
        has_signal_peptide_value = best_record.deepsig_feature_type in DEEPSIG_SIGNAL_PEPTIDE_FEATURE_TYPES
        summary_records.append(deepsig_protein_summary(
            feature_id                      = protein_id_value,
            deepsig_has_signal_peptide      = has_signal_peptide_value,
            deepsig_best_feature_type       = best_record.deepsig_feature_type,
            deepsig_best_start              = best_record.deepsig_start,
            deepsig_best_end                = best_record.deepsig_end,
            deepsig_best_length             = best_record.deepsig_length,
            deepsig_best_score              = best_record.deepsig_score,
            deepsig_total_features          = len(candidate_records),
        ))
    return summary_records


## Canonical column orders — defined once, reused for header + writer rows.
COLUMN_HEADER_FOR_FEATURES: list[str] = [
    "organism_name", "domain", "feature_id",
    "DEEPSIG_feature_type",
    "DEEPSIG_start", "DEEPSIG_end", "DEEPSIG_length",
    "DEEPSIG_score", "DEEPSIG_evidence", "DEEPSIG_attributes",
    "DEEPSIG_tool_used", "DEEPSIG_command_used", "DEEPSIG_database_used", "DEEPSIG_organism_class",
    "input_path", "output_path",
]

COLUMN_HEADER_FOR_SUMMARY: list[str] = [
    "organism_name", "domain", "feature_id",
    "DEEPSIG_has_signal_peptide",
    "DEEPSIG_best_feature_type",
    "DEEPSIG_best_start", "DEEPSIG_best_end", "DEEPSIG_best_length",
    "DEEPSIG_best_score", "DEEPSIG_total_features",
    "DEEPSIG_tool_used", "DEEPSIG_command_used", "DEEPSIG_database_used", "DEEPSIG_organism_class",
    "input_path", "output_path",
]


## Step 4a — write the per-feature processed TSV (uses csv module for safe
## quoting; mkdir(parents=True, exist_ok=True) keeps the call idempotent).
def write_features_table(
    feature_records: list[deepsig_feature_record],
    output_file_path: Path,
    organism_name_value: str,
    domain_value: str,
    tool_used_value: str,
    command_used_value: str,
    database_used_value: str,
    organism_class_value: str,
    input_path_value: str,
    output_path_value: str,
) -> int:
    output_file_path.parent.mkdir(parents=True, exist_ok=True)
    sorted_records = sorted(
        feature_records,
        key=lambda rec: (rec.feature_id, rec.deepsig_start),
    )
    number_of_rows_written = 0
    with open(output_file_path, "w", newline="") as output_file_handle:
        writer = csv.writer(output_file_handle, delimiter="\t")
        writer.writerow(COLUMN_HEADER_FOR_FEATURES)
        for rec in sorted_records:
            writer.writerow([
                organism_name_value, domain_value, rec.feature_id,
                rec.deepsig_feature_type,
                rec.deepsig_start, rec.deepsig_end, rec.deepsig_length,
                rec.deepsig_score, rec.deepsig_evidence, rec.deepsig_attributes,
                tool_used_value, command_used_value, database_used_value, organism_class_value,
                input_path_value, output_path_value,
            ])
            number_of_rows_written += 1
    return number_of_rows_written


## Step 4b — write the per-protein summary TSV.
def write_summary_table(
    summary_records: list[deepsig_protein_summary],
    output_file_path: Path,
    organism_name_value: str,
    domain_value: str,
    tool_used_value: str,
    command_used_value: str,
    database_used_value: str,
    organism_class_value: str,
    input_path_value: str,
    output_path_value: str,
) -> int:
    output_file_path.parent.mkdir(parents=True, exist_ok=True)
    sorted_records = sorted(summary_records, key=lambda rec: rec.feature_id)
    number_of_rows_written = 0
    with open(output_file_path, "w", newline="") as output_file_handle:
        writer = csv.writer(output_file_handle, delimiter="\t")
        writer.writerow(COLUMN_HEADER_FOR_SUMMARY)
        for rec in sorted_records:
            writer.writerow([
                organism_name_value, domain_value, rec.feature_id,
                "true" if rec.deepsig_has_signal_peptide else "false",
                rec.deepsig_best_feature_type,
                rec.deepsig_best_start, rec.deepsig_best_end, rec.deepsig_best_length,
                rec.deepsig_best_score, rec.deepsig_total_features,
                tool_used_value, command_used_value, database_used_value, organism_class_value,
                input_path_value, output_path_value,
            ])
            number_of_rows_written += 1
    return number_of_rows_written


## Entry point (standard `if __name__ == "__main__"` idiom): wires the
## steps together — read → (optionally summarise) → write.
def main() -> None:
    command_line_arguments = parse_command_line_arguments()

    input_file_path = Path(command_line_arguments.input)
    if not input_file_path.exists():
        print(f"[process_deepsig] ERROR: input not found: {input_file_path}", file=sys.stderr)
        raise SystemExit(1)

    all_feature_records = read_deepsig_gff3_file(input_file_path)

    main_output_path = Path(command_line_arguments.output)
    number_of_feature_rows = write_features_table(
        all_feature_records,
        main_output_path,
        command_line_arguments.organism_name,
        command_line_arguments.domain,
        command_line_arguments.tool_used,
        command_line_arguments.command_used,
        command_line_arguments.database_used,
        command_line_arguments.organism_class,
        command_line_arguments.input_path,
        command_line_arguments.output_path,
    )
    print(f"[process_deepsig] Wrote {number_of_feature_rows} feature rows → {main_output_path}")

    if command_line_arguments.output_top1:
        top_output_path = Path(command_line_arguments.output_top1)
        summary_records = select_best_feature_per_protein(all_feature_records)
        number_of_summary_rows = write_summary_table(
            summary_records,
            top_output_path,
            command_line_arguments.organism_name,
            command_line_arguments.domain,
            command_line_arguments.tool_used,
            command_line_arguments.command_used,
            command_line_arguments.database_used,
            command_line_arguments.organism_class,
            command_line_arguments.input_path,
            command_line_arguments.output_path,
        )
        print(f"[process_deepsig] Wrote {number_of_summary_rows} summary rows → {top_output_path}")


if __name__ == "__main__":
    main()
