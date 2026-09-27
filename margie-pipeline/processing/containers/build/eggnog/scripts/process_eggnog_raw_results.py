#!/usr/bin/env python3
"""
process_eggnog_raw_results.py — Post-process eggNOG-mapper annotations TSV
into a normalised, pipeline-friendly per-protein TSV.

INPUT (written by the run step into <output_dir>/raw/eggnog_out.emapper.annotations):
    eggNOG-mapper v2.1+ annotation TSV. Comment lines start with "#" /"##".
    The header line begins with "#query" and looks like:
        #query  seed_ortholog  evalue  score  eggNOG_OGs  max_annot_lvl
        COG_category  Description  Preferred_name  GOs  EC  KEGG_ko
        KEGG_Pathway  KEGG_Module  KEGG_Reaction  KEGG_rclass  BRITE
        KEGG_TC  CAZy  BiGG_Reaction  PFAMs

OUTPUT (written under <output_dir>/processed/):
    eggnog_results.tsv  — one row per annotated protein, EGGNOG_ prefix
    eggnog_top1.tsv     — same content (emapper already outputs one row per protein)
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
class eggnog_mapper_annotation(NamedTuple):
    feature_id: str
    eggnog_seed_ortholog: str
    eggnog_evalue: float
    eggnog_score: float
    eggnog_ogs: str
    eggnog_max_annotation_level: str
    eggnog_cog_category: str
    eggnog_description: str
    eggnog_preferred_name: str
    eggnog_gene_ontology_terms: str
    eggnog_enzyme_commission_numbers: str
    eggnog_kegg_ko: str
    eggnog_kegg_pathway: str
    eggnog_kegg_module: str
    eggnog_kegg_reaction: str
    eggnog_kegg_rclass: str
    eggnog_kegg_brite: str
    eggnog_kegg_tc: str
    eggnog_cazy: str
    eggnog_bigg_reaction: str
    eggnog_pfams: str


## Safe-conversion helper.
def safely_convert_to_float(raw_value: str) -> float:
    if raw_value in ("", ".", "-", None):
        return 0.0
    try:
        return float(raw_value)
    except (TypeError, ValueError):
        return 0.0


## ── Step 1: parse eggNOG-mapper .emapper.annotations TSV ──
##    File contains comment lines beginning with "##". The actual header line
##    starts with "#query" — strip the leading "#" then split on tabs.
##    All trailing rows are data rows; some may have an unannotated marker
##    like "-" in many columns. We keep those values verbatim.
def parse_eggnog_mapper_annotations(annotations_tsv_path: Path) -> list[eggnog_mapper_annotation]:
    parsed_records: list[eggnog_mapper_annotation] = []

    with open(annotations_tsv_path) as input_file_handle:
        header_columns: list[str] | None = None
        for raw_line in input_file_handle:
            stripped_line = raw_line.rstrip("\n")
            if not stripped_line:
                continue
            if stripped_line.startswith("##"):
                continue                                ## emapper meta line
            if stripped_line.startswith("#"):
                ## Header (only one expected). Strip leading "#".
                header_columns = [col.strip().lower()
                                  for col in stripped_line.lstrip("#").split("\t")]
                continue
            if header_columns is None:
                continue   ## data before header — unlikely, but skip

            split_fields = stripped_line.split("\t")
            row_value_map: dict[str, str] = {}
            for column_index, column_name in enumerate(header_columns):
                if column_index < len(split_fields):
                    row_value_map[column_name] = split_fields[column_index].strip()
                else:
                    row_value_map[column_name] = ""

            feature_id_value = row_value_map.get("query", "") or row_value_map.get("#query", "")
            if not feature_id_value:
                continue

            parsed_records.append(eggnog_mapper_annotation(
                feature_id                       = feature_id_value,
                eggnog_seed_ortholog             = row_value_map.get("seed_ortholog", ""),
                eggnog_evalue                    = safely_convert_to_float(row_value_map.get("evalue", "")),
                eggnog_score                     = safely_convert_to_float(row_value_map.get("score", "")),
                eggnog_ogs                       = row_value_map.get("eggnog_ogs", ""),
                eggnog_max_annotation_level      = row_value_map.get("max_annot_lvl", ""),
                eggnog_cog_category              = row_value_map.get("cog_category", ""),
                eggnog_description               = row_value_map.get("description", ""),
                eggnog_preferred_name            = row_value_map.get("preferred_name", ""),
                eggnog_gene_ontology_terms       = row_value_map.get("gos", ""),
                eggnog_enzyme_commission_numbers = row_value_map.get("ec", ""),
                eggnog_kegg_ko                   = row_value_map.get("kegg_ko", ""),
                eggnog_kegg_pathway              = row_value_map.get("kegg_pathway", ""),
                eggnog_kegg_module               = row_value_map.get("kegg_module", ""),
                eggnog_kegg_reaction             = row_value_map.get("kegg_reaction", ""),
                eggnog_kegg_rclass               = row_value_map.get("kegg_rclass", ""),
                eggnog_kegg_brite                = row_value_map.get("brite", ""),
                eggnog_kegg_tc                   = row_value_map.get("kegg_tc", ""),
                eggnog_cazy                      = row_value_map.get("cazy", ""),
                eggnog_bigg_reaction             = row_value_map.get("bigg_reaction", ""),
                eggnog_pfams                     = row_value_map.get("pfams", ""),
            ))

    return parsed_records


## Canonical column order — defined once.
COLUMN_HEADER_ROW: list[str] = [
    "organism_name", "domain", "feature_id",
    "EGGNOG_id", "EGGNOG_evalue", "EGGNOG_score",
    "EGGNOG_OGs", "EGGNOG_max_annotation_level",
    "EGGNOG_COG_category", "EGGNOG_description", "EGGNOG_preferred_name",
    "EGGNOG_GO_terms", "EGGNOG_EC_numbers",
    "EGGNOG_KEGG_ko", "EGGNOG_KEGG_Pathway", "EGGNOG_KEGG_Module",
    "EGGNOG_KEGG_Reaction", "EGGNOG_KEGG_rclass", "EGGNOG_KEGG_BRITE",
    "EGGNOG_KEGG_TC", "EGGNOG_CAZy", "EGGNOG_BiGG_Reaction", "EGGNOG_PFAMs",
    "EGGNOG_tool_used", "EGGNOG_command_used", "EGGNOG_database_used", "EGGNOG_mode_used",
    "input_path", "output_path",
]


## CLI definition (argparse).
def parse_command_line_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True,
                        help="Path to raw eggNOG-mapper annotations file (eggnog_out.emapper.annotations)")
    parser.add_argument("--output", required=True,
                        help="Path to write per-protein processed TSV (eggnog_results.tsv)")
    parser.add_argument("--output-top1", required=False, default=None,
                        help="Optional path for top-1 TSV (eggnog_top1.tsv); emapper already outputs one row per protein")
    parser.add_argument("--organism-name", required=True,
                        help="Organism name to record on every row")
    parser.add_argument("--domain", required=False, default="Unknown",
                        help="Domain label to record on every row (e.g. Archaea/Bacteria)")
    parser.add_argument("--tool-used", required=False, default="",
                        help="Human-readable tool identity/version recorded in output provenance")
    parser.add_argument("--command-used", required=False, default="",
                        help="Exact emapper command line that produced the raw input")
    parser.add_argument("--database-used", required=False, default="",
                        help="eggNOG-mapper data dir used (provenance)")
    parser.add_argument("--mode-used", required=False, default="",
                        help="emapper search mode used (diamond/hmmer)")
    parser.add_argument("--input-path", required=False, default="",
                        help="Input protein FASTA path recorded for provenance")
    parser.add_argument("--output-path", required=False, default="",
                        help="Output directory path recorded for provenance")
    return parser.parse_args()


## Step 2: write a sorted TSV (csv module for safe quoting).
def write_processed_table(
    records_to_write: list[eggnog_mapper_annotation],
    output_file_path: Path,
    organism_name_value: str,
    domain_value: str,
    tool_used_value: str,
    command_used_value: str,
    database_used_value: str,
    mode_used_value: str,
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
                rec.eggnog_seed_ortholog,
                f"{rec.eggnog_evalue:.3e}",
                f"{rec.eggnog_score:.4f}",
                rec.eggnog_ogs, rec.eggnog_max_annotation_level,
                rec.eggnog_cog_category, rec.eggnog_description, rec.eggnog_preferred_name,
                rec.eggnog_gene_ontology_terms, rec.eggnog_enzyme_commission_numbers,
                rec.eggnog_kegg_ko, rec.eggnog_kegg_pathway, rec.eggnog_kegg_module,
                rec.eggnog_kegg_reaction, rec.eggnog_kegg_rclass, rec.eggnog_kegg_brite,
                rec.eggnog_kegg_tc, rec.eggnog_cazy, rec.eggnog_bigg_reaction, rec.eggnog_pfams,
                tool_used_value, command_used_value, database_used_value, mode_used_value,
                input_path_value, output_path_value,
            ])
            number_of_rows_written += 1
    return number_of_rows_written


## Entry point.
def main() -> None:
    command_line_arguments = parse_command_line_arguments()

    input_file_path = Path(command_line_arguments.input)
    if not input_file_path.exists():
        print(f"[process_eggnog] ERROR: input not found: {input_file_path}", file=sys.stderr)
        raise SystemExit(1)

    all_records = parse_eggnog_mapper_annotations(input_file_path)

    main_output_path = Path(command_line_arguments.output)
    number_of_rows_written = write_processed_table(
        all_records,
        main_output_path,
        command_line_arguments.organism_name,
        command_line_arguments.domain,
        command_line_arguments.tool_used,
        command_line_arguments.command_used,
        command_line_arguments.database_used,
        command_line_arguments.mode_used,
        command_line_arguments.input_path,
        command_line_arguments.output_path,
    )
    print(f"[process_eggnog] Wrote {number_of_rows_written} rows → {main_output_path}")

    if command_line_arguments.output_top1:
        ## emapper already outputs at most one annotation per protein; the
        ## top1 file is content-identical to the main file. Kept for layout
        ## consistency across tools.
        top_output_path = Path(command_line_arguments.output_top1)
        number_of_top_rows = write_processed_table(
            all_records,
            top_output_path,
            command_line_arguments.organism_name,
            command_line_arguments.domain,
            command_line_arguments.tool_used,
            command_line_arguments.command_used,
            command_line_arguments.database_used,
            command_line_arguments.mode_used,
            command_line_arguments.input_path,
            command_line_arguments.output_path,
        )
        print(f"[process_eggnog] Wrote {number_of_top_rows} top-1 rows → {top_output_path}")


if __name__ == "__main__":
    main()
