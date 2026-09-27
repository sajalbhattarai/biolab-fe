#!/usr/bin/env python3
"""
process_cog_raw_results.py — Post-process COGclassifier v2 output into a
normalised, pipeline-friendly per-protein TSV.

INPUT (written by the run step into <output_dir>/raw/cog_classify.tsv):
    COGclassifier TSV. Header row + one row per classified protein.
    Typical columns include:
        QUERY_ID, COG_ID, CDD_ID, EVALUE, IDENTITY, GENE_NAME,
        COG_NAME, COG_FUNC_LETTER, COG_FUNC_DESC, ...

OUTPUT (written under <output_dir>/processed/):
    cog_results.tsv  — one row per classified protein, COG_ prefix
    cog_top1.tsv     — same (COGclassifier already gives one row per protein)
"""

## Module docstring (PEP 257). `from __future__ import annotations`
## (PEP 563) — modern type hints portable across versions.
from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path
from typing import NamedTuple


## Structured per-protein record (typing.NamedTuple).
class cog_classification_record(NamedTuple):
    feature_id: str
    cog_id: str
    cdd_id: str
    cog_evalue: float
    cog_identity: float
    cog_gene_name: str
    cog_name: str
    cog_func_letter: str
    cog_func_description: str


## Safe-conversion helpers.
def safely_convert_to_float(raw_value: str) -> float:
    if raw_value in ("", ".", "-", None):
        return 0.0
    try:
        return float(raw_value)
    except (TypeError, ValueError):
        return 0.0


## ── Step 1: parse cog_classify.tsv (header-aware to be robust to schema drift) ──
def parse_cog_classify_tsv(classify_tsv_path: Path) -> list[cog_classification_record]:
    parsed_records: list[cog_classification_record] = []

    with open(classify_tsv_path) as input_file_handle:
        header_line = input_file_handle.readline().rstrip("\n")
        if not header_line:
            return parsed_records

        header_columns = [col.strip().upper() for col in header_line.split("\t")]

        def find_column_index(*candidate_names: str) -> int:
            for candidate_name in candidate_names:
                for column_index, column_name in enumerate(header_columns):
                    if column_name == candidate_name.upper():
                        return column_index
            return -1

        query_idx       = find_column_index("QUERY_ID", "QUERY")
        cog_id_idx      = find_column_index("COG_ID")
        cdd_id_idx      = find_column_index("CDD_ID")
        evalue_idx      = find_column_index("EVALUE", "E_VALUE", "E-VALUE")
        identity_idx    = find_column_index("IDENTITY", "%IDENTITY", "PIDENT")
        gene_name_idx   = find_column_index("GENE_NAME", "GENE")
        cog_name_idx    = find_column_index("COG_NAME")
        func_letter_idx = find_column_index("COG_FUNC_LETTER", "FUNC_LETTER", "COG_LETTER", "LETTER")
        func_desc_idx   = find_column_index("COG_FUNC_DESC", "FUNC_DESC", "COG_DESCRIPTION", "DESCRIPTION")

        if query_idx < 0:
            print("[process_cog] WARNING: could not find QUERY_ID column in cog_classify.tsv",
                  file=sys.stderr)
            return parsed_records

        for raw_line in input_file_handle:
            stripped_line = raw_line.rstrip("\n")
            if not stripped_line:
                continue
            split_fields = stripped_line.split("\t")

            def safe_lookup(column_index: int) -> str:
                if column_index < 0 or column_index >= len(split_fields):
                    return ""
                return split_fields[column_index].strip()

            feature_id_value = safe_lookup(query_idx)
            if not feature_id_value:
                continue

            parsed_records.append(cog_classification_record(
                feature_id           = feature_id_value,
                cog_id               = safe_lookup(cog_id_idx),
                cdd_id               = safe_lookup(cdd_id_idx),
                cog_evalue           = safely_convert_to_float(safe_lookup(evalue_idx)),
                cog_identity         = safely_convert_to_float(safe_lookup(identity_idx)),
                cog_gene_name        = safe_lookup(gene_name_idx),
                cog_name             = safe_lookup(cog_name_idx),
                cog_func_letter      = safe_lookup(func_letter_idx),
                cog_func_description = safe_lookup(func_desc_idx),
            ))

    return parsed_records


## Canonical column order — defined once.
COLUMN_HEADER_ROW: list[str] = [
    "organism_name", "domain", "gram_stain", "feature_id",
    "COG_id", "COG_cdd_id",
    "COG_description", "COG_function_description",
    "COG_gene_name", "COG_evalue", "COG_identity",
    "COG_func_letter",
    "COG_tool_used",
    "COG_command_used", "COG_database_used", "COG_evalue_threshold_used",
    "input_path", "output_path",
]


## CLI definition (argparse).
def parse_command_line_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True,
                        help="Path to raw COGclassifier output (cog_classify.tsv)")
    parser.add_argument("--output", required=True,
                        help="Path to write per-protein processed TSV (cog_results.tsv)")
    parser.add_argument("--output-top1", required=False, default=None,
                        help="Optional path for top-1 TSV (cog_top1.tsv); same content as --output for COG")
    parser.add_argument("--organism-name", required=True,
                        help="Organism name to record on every row")
    parser.add_argument("--domain", required=False, default="Unknown",
                        choices=["Archaea", "Bacteria", "Eukaryota", "Unknown"],
                        help="Domain label to record on every row (default: Unknown)")
    parser.add_argument("--gram-stain", required=False, default="",
                        choices=["", "positive", "negative", "unknown"],
                        help="Gram stain label to record on every row (default: unknown)")
    parser.add_argument("--command-used", required=False, default="",
                        help="Exact COGclassifier command line that produced the raw input")
    parser.add_argument("--database-used", required=False, default="",
                        help="COG database directory used (provenance)")
    parser.add_argument("--evalue-threshold-used", required=False, default="",
                        help="RPS-BLAST e-value cutoff used (provenance)")
    parser.add_argument("--tool-used", required=False, default="",
                        help="Tool name and version string with source URL (provenance)")
    parser.add_argument("--input-path", required=False, default="",
                        help="Actual input .faa file path used during this run (provenance)")
    parser.add_argument("--output-path", required=False, default="",
                        help="Actual output directory path used during this run (provenance)")
    return parser.parse_args()


## Step 2: write a sorted TSV (csv module for safe quoting).
def write_processed_table(
    records_to_write: list[cog_classification_record],
    output_file_path: Path,
    organism_name_value: str,
    domain_value: str,
    gram_stain_value: str,
    command_used_value: str,
    database_used_value: str,
    evalue_threshold_value: str,
    tool_used_value: str = "",
    input_path_value: str = "",
    output_path_value: str = "",
) -> int:
    output_file_path.parent.mkdir(parents=True, exist_ok=True)
    sorted_records = sorted(records_to_write, key=lambda rec: rec.feature_id)
    number_of_rows_written = 0
    with open(output_file_path, "w", newline="") as output_file_handle:
        writer = csv.writer(output_file_handle, delimiter="\t")
        writer.writerow(COLUMN_HEADER_ROW)
        for rec in sorted_records:
            writer.writerow([
                organism_name_value, domain_value, gram_stain_value, rec.feature_id,
                rec.cog_id, rec.cdd_id,
                rec.cog_name, rec.cog_func_description,
                rec.cog_gene_name, f"{rec.cog_evalue:.3e}", f"{rec.cog_identity:.4f}",
                rec.cog_func_letter,
                tool_used_value,
                command_used_value, database_used_value, evalue_threshold_value,
                input_path_value, output_path_value,
            ])
            number_of_rows_written += 1
    return number_of_rows_written


## Entry point.
def main() -> None:
    command_line_arguments = parse_command_line_arguments()

    input_file_path = Path(command_line_arguments.input)
    if not input_file_path.exists():
        print(f"[process_cog] ERROR: input not found: {input_file_path}", file=sys.stderr)
        raise SystemExit(1)

    all_records = parse_cog_classify_tsv(input_file_path)

    main_output_path = Path(command_line_arguments.output)
    number_of_rows_written = write_processed_table(
        all_records,
        main_output_path,
        command_line_arguments.organism_name,
        command_line_arguments.domain,
        command_line_arguments.gram_stain,
        command_line_arguments.command_used,
        command_line_arguments.database_used,
        command_line_arguments.evalue_threshold_used,
        tool_used_value=command_line_arguments.tool_used,
        input_path_value=command_line_arguments.input_path,
        output_path_value=command_line_arguments.output_path,
    )
    print(f"[process_cog] Wrote {number_of_rows_written} rows → {main_output_path}")

    if command_line_arguments.output_top1:
        ## COGclassifier already emits one row per protein (best hit), so the
        ## top1 file is content-identical to the main file. We still write it
        ## to keep the file-layout consistent across tools.
        top_output_path = Path(command_line_arguments.output_top1)
        number_of_top_rows = write_processed_table(
            all_records,
            top_output_path,
            command_line_arguments.organism_name,
            command_line_arguments.domain,
            command_line_arguments.gram_stain,
            command_line_arguments.command_used,
            command_line_arguments.database_used,
            command_line_arguments.evalue_threshold_used,
            tool_used_value=command_line_arguments.tool_used,
            input_path_value=command_line_arguments.input_path,
            output_path_value=command_line_arguments.output_path,
        )
        print(f"[process_cog] Wrote {number_of_top_rows} top-1 rows → {top_output_path}")


if __name__ == "__main__":
    main()
