#!/usr/bin/env python3
"""
process_pfam_raw_results.py — Post-process HMMER `hmmscan --domtblout`
output produced by the pfam container into a normalised, pipeline-friendly TSV.

INPUT  (HMMER domain-table format, written to <output_dir>/raw/pfam_domtbl.out):
    A whitespace-separated table where each row is one domain hit. Lines
    starting with '#' are comments and are skipped. 22 fixed columns then a
    free-text description.

OUTPUT (written to <output_dir>/processed/pfam_results.tsv):
    Tab-separated table, one row per significant domain hit, with universal
    columns first (feature_id, organism_name, gram_stain) and then all PFAM
    fields prefixed with `PFAM_`. A companion `pfam_top1.tsv` is also
    written that, for trusted-cutoff (--cut_ga) HMMER output, simply
    preserves every hit — no overlap collapsing. Multi-domain proteins
    therefore produce multiple rows; consolidation ';'-joins them.
"""

## Module docstring above (PEP 257): describes the script's purpose so other
## team members can read it at a glance.
## `from __future__ import annotations` (PEP 563) lets us use modern type
## hints like `list[str]` on any Python version we ship.
from __future__ import annotations

import argparse
import csv
import sys
from collections import defaultdict
from pathlib import Path
from typing import NamedTuple


## Structured record (typing.NamedTuple): one immutable, named row capturing
## every field we want to write to the processed TSV. Using names instead of
## positional tuples makes the writer code below much easier to read.
class pfam_domain_hit(NamedTuple):
    feature_id: str
    pfam_name: str
    pfam_id: str
    pfam_target_length: int
    pfam_query_length: int
    pfam_full_seq_evalue: float
    pfam_full_seq_score: float
    pfam_full_seq_bias: float
    pfam_domain_number: int
    pfam_domain_total: int
    pfam_domain_c_evalue: float
    pfam_domain_i_evalue: float
    pfam_domain_score: float
    pfam_domain_bias: float
    pfam_hmm_from: int
    pfam_hmm_to: int
    pfam_alignment_from: int
    pfam_alignment_to: int
    pfam_envelope_from: int
    pfam_envelope_to: int
    pfam_accuracy: float
    pfam_description: str


## Safe-conversion helpers (defensive programming): HMMER sometimes writes
## "-" or other non-numeric placeholders. Wrapping float()/int() lets us
## fall back to 0 instead of crashing the whole run.
def safely_convert_to_float(raw_value: str) -> float:
    try:
        return float(raw_value)
    except (TypeError, ValueError):
        return 0.0


def safely_convert_to_integer(raw_value: str) -> int:
    try:
        return int(raw_value)
    except (TypeError, ValueError):
        return 0


## CLI definition (argparse standard library): every flag is declared in one
## place with help text. argparse generates --help for us.
def parse_command_line_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True,
                        help="Path to raw hmmscan --domtblout file (pfam_domtbl.out)")
    parser.add_argument("--output", required=True,
                        help="Path to write the main processed TSV (pfam_results.tsv)")
    parser.add_argument("--output-top1", required=False, default=None,
                        help="Optional path for the all-trusted-hits companion TSV (pfam_top1.tsv)")
    parser.add_argument("--organism-name", required=True,
                        help="Organism name to record on every row (free text)")
    parser.add_argument("--domain", required=False, default="Unknown",
                        help="Domain label to record on every row (e.g. Archaea/Bacteria)")
    parser.add_argument("--tool-used", required=False, default="",
                        help="Human-readable tool identity/version recorded in output provenance")
    parser.add_argument("--command-used", required=False, default="",
                        help="Exact hmmscan command line that produced the raw input")
    parser.add_argument("--database-used", required=False, default="",
                        help="Database identity/version/source recorded in output provenance")
    parser.add_argument("--threshold-considered", required=False, default="--cut_ga",
                        help="HMMER significance threshold flag used (default: --cut_ga)")
    parser.add_argument("--input-path", required=False, default="",
                        help="Input protein FASTA path recorded for provenance")
    parser.add_argument("--output-path", required=False, default="",
                        help="Output directory path recorded for provenance")
    return parser.parse_args()


## Step 1 — read the domain table.
## HMMER's --domtblout is whitespace-separated, NOT a clean TSV: the final
## "description of target" column can itself contain spaces. So we split into
## at most 23 fields with str.split(maxsplit=22) and treat the remainder as
## the description. Lines starting with '#' are header/comment lines.
def read_hmmscan_domain_table(domain_table_path: Path) -> list[pfam_domain_hit]:
    parsed_hits: list[pfam_domain_hit] = []

    with open(domain_table_path) as input_file_handle:
        for raw_line in input_file_handle:
            stripped_line = raw_line.rstrip("\n")
            if not stripped_line or stripped_line.startswith("#"):
                continue

            ## Split into the 22 fixed fields plus a free-text description
            ## tail. maxsplit=22 means "split at most 22 times" → 23 pieces.
            split_fields = stripped_line.split(maxsplit=22)
            if len(split_fields) < 22:
                continue   ## malformed row, skip

            description_text = split_fields[22] if len(split_fields) == 23 else ""

            parsed_hits.append(pfam_domain_hit(
                ## column 4 (query name) = the protein ID from the input FASTA
                feature_id              = split_fields[3],
                ## column 1 = Pfam family name (e.g. ABC_tran)
                pfam_name               = split_fields[0],
                ## column 2 = Pfam accession / stable ID (e.g. PF00005.30)
                pfam_id                 = split_fields[1],
                pfam_target_length      = safely_convert_to_integer(split_fields[2]),
                pfam_query_length       = safely_convert_to_integer(split_fields[5]),
                pfam_full_seq_evalue    = safely_convert_to_float(split_fields[6]),
                pfam_full_seq_score     = safely_convert_to_float(split_fields[7]),
                pfam_full_seq_bias      = safely_convert_to_float(split_fields[8]),
                pfam_domain_number      = safely_convert_to_integer(split_fields[9]),
                pfam_domain_total       = safely_convert_to_integer(split_fields[10]),
                pfam_domain_c_evalue    = safely_convert_to_float(split_fields[11]),
                pfam_domain_i_evalue    = safely_convert_to_float(split_fields[12]),
                pfam_domain_score       = safely_convert_to_float(split_fields[13]),
                pfam_domain_bias        = safely_convert_to_float(split_fields[14]),
                pfam_hmm_from           = safely_convert_to_integer(split_fields[15]),
                pfam_hmm_to             = safely_convert_to_integer(split_fields[16]),
                pfam_alignment_from     = safely_convert_to_integer(split_fields[17]),
                pfam_alignment_to       = safely_convert_to_integer(split_fields[18]),
                pfam_envelope_from      = safely_convert_to_integer(split_fields[19]),
                pfam_envelope_to        = safely_convert_to_integer(split_fields[20]),
                pfam_accuracy           = safely_convert_to_float(split_fields[21]),
                pfam_description        = description_text,
            ))

    return parsed_hits


## Step 2 — keep ALL trusted-cutoff domain hits per protein.
## Every row in the upstream domtblout already passed --cut_ga (or the
## equivalent trusted threshold), so every hit is valid evidence — we do
## not collapse overlapping or non-overlapping hits. Consolidation later
## ';'-joins per-column values across all of a protein's rows.
def select_all_trusted_domain_hits(
    all_domain_hits: list[pfam_domain_hit],
) -> list[pfam_domain_hit]:
    return list(all_domain_hits)


## The canonical column order. We define it once and reuse it for the header
## row and for write_processed_table below. Universal columns first, then
## every PFAM-specific column prefixed with `PFAM_`, then provenance.
COLUMN_HEADER_ROW: list[str] = [
    "organism_name", "domain", "feature_id",
    "PFAM_id", "PFAM_name", "PFAM_description",
    "PFAM_target_length", "PFAM_query_length",
    "PFAM_full_seq_evalue", "PFAM_full_seq_score", "PFAM_full_seq_bias",
    "PFAM_domain_number", "PFAM_domain_total",
    "PFAM_domain_c_evalue", "PFAM_domain_i_evalue",
    "PFAM_domain_score", "PFAM_domain_bias",
    "PFAM_hmm_from", "PFAM_hmm_to",
    "PFAM_alignment_from", "PFAM_alignment_to",
    "PFAM_envelope_from", "PFAM_envelope_to",
    "PFAM_accuracy",
    "PFAM_tool_used", "PFAM_command_used", "PFAM_database_used", "PFAM_threshold_considered",
    "input_path", "output_path",
]


## Step 3 — write a sorted, fully-populated TSV (uses read_hmmscan_domain_table
## results and the csv module for safe quoting/escaping). Rows are sorted by
## feature_id then envelope_from so the same protein's domains appear in
## N→C order. mkdir(parents=True, exist_ok=True) makes the call idempotent.
def write_processed_table(
    hits_to_write: list[pfam_domain_hit],
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

    sorted_hits = sorted(
        hits_to_write,
        key=lambda hit: (hit.feature_id, hit.pfam_envelope_from),
    )

    number_of_rows_written = 0
    with open(output_file_path, "w", newline="") as output_file_handle:
        writer = csv.writer(output_file_handle, delimiter="\t")
        writer.writerow(COLUMN_HEADER_ROW)
        for hit in sorted_hits:
            writer.writerow([
                organism_name_value, domain_value, hit.feature_id,
                hit.pfam_id, hit.pfam_name, hit.pfam_description,
                hit.pfam_target_length, hit.pfam_query_length,
                hit.pfam_full_seq_evalue, hit.pfam_full_seq_score, hit.pfam_full_seq_bias,
                hit.pfam_domain_number, hit.pfam_domain_total,
                hit.pfam_domain_c_evalue, hit.pfam_domain_i_evalue,
                hit.pfam_domain_score, hit.pfam_domain_bias,
                hit.pfam_hmm_from, hit.pfam_hmm_to,
                hit.pfam_alignment_from, hit.pfam_alignment_to,
                hit.pfam_envelope_from, hit.pfam_envelope_to,
                hit.pfam_accuracy,
                tool_used_value, command_used_value, database_used_value, threshold_considered_value,
                input_path_value, output_path_value,
            ])
            number_of_rows_written += 1

    return number_of_rows_written


## Entry point (standard `if __name__ == "__main__"` idiom): wires the three
## steps together — read → (optionally pick best-per-gene) → write.
def main() -> None:
    command_line_arguments = parse_command_line_arguments()

    input_file_path = Path(command_line_arguments.input)
    if not input_file_path.exists():
        print(f"[process_pfam] ERROR: input not found: {input_file_path}", file=sys.stderr)
        raise SystemExit(1)

    all_parsed_hits = read_hmmscan_domain_table(input_file_path)

    main_output_path = Path(command_line_arguments.output)
    number_of_rows_written = write_processed_table(
        all_parsed_hits,
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
    print(f"[process_pfam] Wrote {number_of_rows_written} rows → {main_output_path}")

    if command_line_arguments.output_top1:
        top_one_output_path = Path(command_line_arguments.output_top1)
        best_per_feature = select_all_trusted_domain_hits(all_parsed_hits)
        number_of_top_rows_written = write_processed_table(
            best_per_feature,
            top_one_output_path,
            command_line_arguments.organism_name,
            command_line_arguments.domain,
            command_line_arguments.tool_used,
            command_line_arguments.command_used,
            command_line_arguments.database_used,
            command_line_arguments.threshold_considered,
            command_line_arguments.input_path,
            command_line_arguments.output_path,
        )
        print(f"[process_pfam] Wrote {number_of_top_rows_written} rows → {top_one_output_path}")


if __name__ == "__main__":
    main()
