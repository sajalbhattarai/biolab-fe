#!/usr/bin/env python3
"""
process_kegg_raw_results.py — Post-process KofamScan "detail" output into
a normalised, pipeline-friendly per-hit TSV.

INPUT (written by the run step into <output_dir>/raw/kegg.txt):
    KofamScan detail-format output. Each non-header line is one HMM hit.
    Significant hits (score above the per-KO threshold) are flagged with
    a "*" in column 0.

    Example:
        #  gene name      KO       thrshld   score    E-value   KO definition
        #--------------- -------- --------- -------- --------- ----------------
        *  gene1         K00001   50.0      125.5    1.2e-30   alcohol dehydrogenase
           gene1         K00002   100.0     60.1     2.1e-10   sub-threshold hit

OUTPUT (written under <output_dir>/processed/):
    kegg_results.tsv  — one row per HMM hit, KEGG_ prefix
    kegg_top1.tsv     — best above-threshold hit per protein (by score)
"""

## Module docstring (PEP 257). `from __future__ import annotations`
## (PEP 563) — modern type hints portable across versions.
from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path
from typing import NamedTuple


## Structured per-hit record (typing.NamedTuple).
class kegg_kofamscan_hit(NamedTuple):
    feature_id: str
    kegg_ko: str
    kegg_threshold: float
    kegg_score: float
    kegg_evalue: float
    kegg_ko_definition: str
    kegg_is_above_threshold: bool


## Safe-conversion helpers (defensive programming).
def safely_convert_to_float(raw_value: str) -> float:
    if raw_value in ("", ".", "-", None):
        return 0.0
    try:
        return float(raw_value)
    except (TypeError, ValueError):
        return 0.0


## ── Step 1: parse a KofamScan detail-format text file ──
##    The file has comment-style header lines starting with "#". Every other
##    non-blank line is one hit:
##        col0:  "*" or " " (above-threshold marker)
##        col1:  gene name
##        col2:  KO id
##        col3:  threshold
##        col4:  score
##        col5:  E-value
##        col6+: KO definition (free text, may contain whitespace)
def parse_kofamscan_detail_output(detail_file_path: Path) -> list[kegg_kofamscan_hit]:
    parsed_records: list[kegg_kofamscan_hit] = []

    with open(detail_file_path) as input_file_handle:
        for raw_line in input_file_handle:
            stripped_line = raw_line.rstrip("\n")
            if not stripped_line:
                continue
            if stripped_line.lstrip().startswith("#"):
                continue
            ## Lines of dashes are dividers, skip.
            if set(stripped_line.strip().replace(" ", "")) <= {"-"}:
                continue

            ## The first column is a 1-char marker ("*" or " ") which may be
            ## absent on lines that came from old kofamscan versions.
            ## Detect by checking whether the first non-space token is "*".
            is_above_threshold_flag = stripped_line.startswith("*")
            payload_line = stripped_line[1:] if (stripped_line[:1] in ("*", " ")) else stripped_line

            split_fields = payload_line.split()
            if len(split_fields) < 6:
                continue   ## malformed; skip

            feature_id_value      = split_fields[0]
            ko_value              = split_fields[1]
            threshold_value       = safely_convert_to_float(split_fields[2])
            score_value           = safely_convert_to_float(split_fields[3])
            evalue_value          = safely_convert_to_float(split_fields[4])
            ko_definition_value   = " ".join(split_fields[5:])

            parsed_records.append(kegg_kofamscan_hit(
                feature_id              = feature_id_value,
                kegg_ko                 = ko_value,
                kegg_threshold          = threshold_value,
                kegg_score              = score_value,
                kegg_evalue             = evalue_value,
                kegg_ko_definition      = ko_definition_value,
                kegg_is_above_threshold = is_above_threshold_flag,
            ))

    return parsed_records


## ── Step 2: select the single best above-threshold hit per protein ──
##    Ranking: above-threshold wins; tiebreak by highest score; then lowest
##    E-value; then KO id lexicographic.
def select_best_above_threshold_hit_per_protein(
    all_hits: list[kegg_kofamscan_hit],
) -> list[kegg_kofamscan_hit]:
    best_hit_by_feature_id: dict[str, kegg_kofamscan_hit] = {}
    for hit_record in all_hits:
        if not hit_record.kegg_is_above_threshold:
            continue
        existing_hit = best_hit_by_feature_id.get(hit_record.feature_id)
        if existing_hit is None:
            best_hit_by_feature_id[hit_record.feature_id] = hit_record
            continue
        ## Tie-break: higher score wins, then lower E-value, then KO id asc.
        if (hit_record.kegg_score > existing_hit.kegg_score
            or (hit_record.kegg_score == existing_hit.kegg_score
                and hit_record.kegg_evalue < existing_hit.kegg_evalue)
            or (hit_record.kegg_score == existing_hit.kegg_score
                and hit_record.kegg_evalue == existing_hit.kegg_evalue
                and hit_record.kegg_ko < existing_hit.kegg_ko)):
            best_hit_by_feature_id[hit_record.feature_id] = hit_record
    return list(best_hit_by_feature_id.values())


## Canonical column order — defined once.
COLUMN_HEADER_ROW: list[str] = [
    "organism_name", "domain", "feature_id",
    "KEGG_id", "KEGG_description",
    "KEGG_threshold", "KEGG_score", "KEGG_evalue", "KEGG_is_above_threshold",
    "KEGG_tool_used", "KEGG_command_used", "KEGG_database_used", "KEGG_threshold_considered",
    "input_path", "output_path",
]


## CLI definition (argparse).
def parse_command_line_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True,
                        help="Path to raw KofamScan detail-format output (kegg.txt)")
    parser.add_argument("--output", required=True,
                        help="Path to write per-hit processed TSV (kegg_results.tsv)")
    parser.add_argument("--output-top1", required=False, default=None,
                        help="Optional path for best-above-threshold-per-protein TSV (kegg_top1.tsv)")
    parser.add_argument("--organism-name", required=True,
                        help="Organism name to record on every row")
    parser.add_argument("--domain", required=False, default="Unknown",
                        help="Domain label to record on every row (e.g. Archaea/Bacteria)")
    parser.add_argument("--tool-used", required=False, default="",
                        help="Human-readable tool identity/version recorded in output provenance")
    parser.add_argument("--command-used", required=False, default="",
                        help="Exact KofamScan command line that produced the raw input")
    parser.add_argument("--database-used", required=False, default="",
                        help="KEGG database directory used (provenance)")
    parser.add_argument("--threshold-considered", required=False, default="adaptive threshold from ko_list",
                        help="Significance thresholding method used")
    parser.add_argument("--input-path", required=False, default="",
                        help="Input protein FASTA path recorded for provenance")
    parser.add_argument("--output-path", required=False, default="",
                        help="Output directory path recorded for provenance")
    return parser.parse_args()


## Step 3: write a sorted TSV (csv module for safe quoting).
def write_processed_table(
    records_to_write: list[kegg_kofamscan_hit],
    output_file_path: Path,
    organism_name_value: str,
    domain_value: str,
    tool_used_value: str,
    command_used_value: str,
    database_used_value: str,
    threshold_considered_value: str,
    input_path_value: str,
    output_path_value: str,
) -> int:
    output_file_path.parent.mkdir(parents=True, exist_ok=True)
    sorted_records = sorted(records_to_write,
                            key=lambda rec: (rec.feature_id, -rec.kegg_score, rec.kegg_ko))
    number_of_rows_written = 0
    with open(output_file_path, "w", newline="") as output_file_handle:
        writer = csv.writer(output_file_handle, delimiter="\t")
        writer.writerow(COLUMN_HEADER_ROW)
        for rec in sorted_records:
            writer.writerow([
                organism_name_value, domain_value, rec.feature_id,
                rec.kegg_ko, rec.kegg_ko_definition,
                f"{rec.kegg_threshold:.4f}", f"{rec.kegg_score:.4f}",
                f"{rec.kegg_evalue:.3e}",
                "true" if rec.kegg_is_above_threshold else "false",
                tool_used_value,
                command_used_value,
                database_used_value,
                threshold_considered_value,
                input_path_value,
                output_path_value,
            ])
            number_of_rows_written += 1
    return number_of_rows_written


## Entry point.
def main() -> None:
    command_line_arguments = parse_command_line_arguments()

    input_file_path = Path(command_line_arguments.input)
    if not input_file_path.exists():
        print(f"[process_kegg] ERROR: input not found: {input_file_path}", file=sys.stderr)
        raise SystemExit(1)

    all_records = parse_kofamscan_detail_output(input_file_path)

    main_output_path = Path(command_line_arguments.output)
    number_of_rows_written = write_processed_table(
        all_records,
        main_output_path,
        command_line_arguments.organism_name,
        command_line_arguments.domain,
        command_line_arguments.tool_used,
        command_line_arguments.command_used,
        command_line_arguments.database_used,
        command_line_arguments.threshold_considered,
        command_line_arguments.input_path,
        command_line_arguments.output_path,
    )
    print(f"[process_kegg] Wrote {number_of_rows_written} rows → {main_output_path}")

    if command_line_arguments.output_top1:
        top_output_path = Path(command_line_arguments.output_top1)
        best_hits_only = select_best_above_threshold_hit_per_protein(all_records)
        number_of_top_rows = write_processed_table(
            best_hits_only,
            top_output_path,
            command_line_arguments.organism_name,
            command_line_arguments.domain,
            command_line_arguments.tool_used,
            command_line_arguments.command_used,
            command_line_arguments.database_used,
            command_line_arguments.threshold_considered,
            command_line_arguments.input_path,
            command_line_arguments.output_path,
        )
        print(f"[process_kegg] Wrote {number_of_top_rows} top-1 rows → {top_output_path}")


if __name__ == "__main__":
    main()
