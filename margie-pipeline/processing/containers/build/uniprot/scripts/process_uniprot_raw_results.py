#!/usr/bin/env python3
"""
process_uniprot_raw_results.py — Post-process UniProt/Swiss-Prot DIAMOND
blastp output into a normalised, pipeline-friendly per-protein TSV.

INPUT (written by the run step into <output_dir>/raw/uniprot.tsv):
    DIAMOND blastp `-f 6` 7-column tabular output:
        qseqid sseqid pident length evalue bitscore stitle

    DIAMOND was invoked with `-k 1 --id 30 -e 1e-5` so each query has at
    most one hit row (best-hit).

    Swiss-Prot sseqid format: `sp|<accession>|<entry_name>`
    Swiss-Prot stitle format: `sp|<accession>|<entry_name> <description> OS=<organism> OX=<taxid> GN=<gene> PE=<evidence> SV=<version>`

OUTPUT (written under <output_dir>/processed/):
    uniprot_results.tsv  — one row per blast hit, UNIPROT_ prefix
    uniprot_top1.tsv     — same content (DIAMOND -k 1 already best-hit)
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
class uniprot_diamond_hit(NamedTuple):
    feature_id: str
    uniprot_subject_id: str
    uniprot_accession: str
    uniprot_entry_name: str
    uniprot_protein_name: str
    uniprot_gene_name: str
    uniprot_organism: str
    uniprot_taxonomy_id: str
    uniprot_subject_title: str
    uniprot_percent_identity: float
    uniprot_alignment_length: int
    uniprot_evalue: float
    uniprot_bitscore: float


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


## ── Swiss-Prot sseqid + stitle parsing ──
##    sseqid: `sp|<accession>|<entry_name>`  or  `tr|<accession>|<entry_name>`
##    stitle: `<sseqid> <protein description> OS=<organism> OX=<taxid> GN=<gene> PE=<evidence> SV=<version>`
SWISSPROT_SUBJECT_ID_PATTERN = re.compile(r"^(?:sp|tr)\|([^|]+)\|(\S+)")
STITLE_FIELD_TAG_PATTERN = re.compile(
    r"\s(OS|OX|GN|PE|SV)=", flags=re.IGNORECASE)


def parse_swissprot_subject_id(subject_id_value: str) -> tuple[str, str]:
    match = SWISSPROT_SUBJECT_ID_PATTERN.search(subject_id_value)
    if match is None:
        return ("", "")
    return (match.group(1), match.group(2))


def parse_swissprot_stitle(
    subject_title_value: str,
    subject_id_value: str,
) -> tuple[str, str, str, str]:
    """Return (protein_name, organism, taxonomy_id, gene_name) — best-effort."""
    if not subject_title_value:
        return ("", "", "", "")

    ## Strip the leading sseqid (if present) — protein name starts after it.
    remainder_text = subject_title_value
    if subject_id_value and remainder_text.startswith(subject_id_value):
        remainder_text = remainder_text[len(subject_id_value):].lstrip()

    ## Locate the first tag (OS=, OX=, GN=, PE=, SV=). Everything before it
    ## is the protein description.
    tag_match = STITLE_FIELD_TAG_PATTERN.search(remainder_text)
    if tag_match is None:
        return (remainder_text.strip(), "", "", "")

    protein_name_value = remainder_text[:tag_match.start()].strip()
    tagged_remainder   = remainder_text[tag_match.start():]

    ## Split the tagged remainder into a {tag_name: value} dict.
    ## re.split keeps the captured tag-name groups in the result list, so
    ## the output alternates: [leading_text, TAG_1, VALUE_1, TAG_2, VALUE_2, ...].
    tag_value_map: dict[str, str] = {}
    parts = re.split(r"\s(OS|OX|GN|PE|SV)=", tagged_remainder, flags=re.IGNORECASE)
    for index in range(1, len(parts) - 1, 2):
        tag_name  = parts[index].upper()
        tag_value = parts[index + 1].strip()
        tag_value_map[tag_name] = tag_value

    return (
        protein_name_value,
        tag_value_map.get("OS", ""),
        tag_value_map.get("OX", ""),
        tag_value_map.get("GN", ""),
    )


## ── Step 1: parse DIAMOND `-f 6` 7-column TSV ──
def parse_diamond_uniprot_tsv(diamond_tsv_path: Path) -> list[uniprot_diamond_hit]:
    parsed_records: list[uniprot_diamond_hit] = []

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

            accession_value, entry_name_value = parse_swissprot_subject_id(subject_id_value)
            (
                protein_name_value,
                organism_value,
                taxonomy_id_value,
                gene_name_value,
            ) = parse_swissprot_stitle(subject_title_value, subject_id_value)

            parsed_records.append(uniprot_diamond_hit(
                feature_id               = split_fields[0],
                uniprot_subject_id       = subject_id_value,
                uniprot_accession        = accession_value,
                uniprot_entry_name       = entry_name_value,
                uniprot_protein_name     = protein_name_value,
                uniprot_gene_name        = gene_name_value,
                uniprot_organism         = organism_value,
                uniprot_taxonomy_id      = taxonomy_id_value,
                uniprot_subject_title    = subject_title_value,
                uniprot_percent_identity = safely_convert_to_float(split_fields[2]),
                uniprot_alignment_length = safely_convert_to_integer(split_fields[3]),
                uniprot_evalue           = safely_convert_to_float(split_fields[4]),
                uniprot_bitscore         = safely_convert_to_float(split_fields[5]),
            ))

    return parsed_records


## Canonical column order — defined once.
COLUMN_HEADER_ROW: list[str] = [
    "organism_name", "domain", "feature_id",
    "UNIPROT_id", "UNIPROT_subject_id", "UNIPROT_entry_name",
    "UNIPROT_description", "UNIPROT_gene_name",
    "UNIPROT_source_organism", "UNIPROT_source_taxonomy_id",
    "UNIPROT_percent_identity", "UNIPROT_alignment_length",
    "UNIPROT_evalue", "UNIPROT_bitscore",
    "UNIPROT_subject_title",
    "UNIPROT_tool_used", "UNIPROT_command_used", "UNIPROT_database_used",
    "UNIPROT_evalue_threshold_used", "UNIPROT_percent_identity_threshold_used",
    "input_path", "output_path",
]


## CLI definition (argparse).
def parse_command_line_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True,
                        help="Path to raw DIAMOND tabular output (uniprot.tsv)")
    parser.add_argument("--output", required=True,
                        help="Path to write per-protein processed TSV (uniprot_results.tsv)")
    parser.add_argument("--output-top1", required=False, default=None,
                        help="Optional path for top-1 TSV (uniprot_top1.tsv); same content for DIAMOND -k 1")
    parser.add_argument("--organism-name", required=True,
                        help="Organism name to record on every row")
    parser.add_argument("--domain", required=False, default="Unknown",
                        help="Domain label to record on every row (e.g. Archaea/Bacteria)")
    parser.add_argument("--tool-used", required=False, default="",
                        help="Human-readable tool identity/version recorded in output provenance")
    parser.add_argument("--command-used", required=False, default="",
                        help="Exact DIAMOND command line that produced the raw input")
    parser.add_argument("--database-used", required=False, default="",
                        help="UniProt database (.dmnd) used (provenance)")
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
    records_to_write: list[uniprot_diamond_hit],
    output_file_path: Path,
    organism_name_value: str,
    domain_value: str,
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
                            key=lambda rec: (rec.feature_id, -rec.uniprot_bitscore))
    number_of_rows_written = 0
    with open(output_file_path, "w", newline="") as output_file_handle:
        writer = csv.writer(output_file_handle, delimiter="\t")
        writer.writerow(COLUMN_HEADER_ROW)
        for rec in sorted_records:
            writer.writerow([
                organism_name_value, domain_value, rec.feature_id,
                rec.uniprot_accession, rec.uniprot_subject_id, rec.uniprot_entry_name,
                rec.uniprot_protein_name, rec.uniprot_gene_name,
                rec.uniprot_organism, rec.uniprot_taxonomy_id,
                f"{rec.uniprot_percent_identity:.4f}", rec.uniprot_alignment_length,
                f"{rec.uniprot_evalue:.3e}", f"{rec.uniprot_bitscore:.4f}",
                rec.uniprot_subject_title,
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
        print(f"[process_uniprot] ERROR: input not found: {input_file_path}", file=sys.stderr)
        raise SystemExit(1)

    all_records = parse_diamond_uniprot_tsv(input_file_path)

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
        command_line_arguments.percent_identity_threshold_used,
        command_line_arguments.input_path,
        command_line_arguments.output_path,
    )
    print(f"[process_uniprot] Wrote {number_of_rows_written} rows → {main_output_path}")

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
            command_line_arguments.percent_identity_threshold_used,
            command_line_arguments.input_path,
            command_line_arguments.output_path,
        )
        print(f"[process_uniprot] Wrote {number_of_top_rows} top-1 rows → {top_output_path}")


if __name__ == "__main__":
    main()
