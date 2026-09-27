#!/usr/bin/env python3
"""
process_dbcan_raw_results.py — Post-process dbCAN (run_dbcan v5) raw output
into a normalised per-protein TSV.

INPUT (written by the run step into <output_dir>/raw/):
    overview.tsv   — dbCAN consensus per-gene table
                      columns (v5):  Gene ID  EC#  dbCAN_hmm  dbCAN_sub  DIAMOND  #ofTools

    (Other raw files such as diamond.out, hmmer.out, dbCAN-sub.out are kept
     under raw/ for downstream debugging but not consumed by this processor.)

OUTPUT (written under <output_dir>/processed/):
    dbcan_results.tsv  — one row per protein, DBCAN_ prefix
    dbcan_top1.tsv     — only proteins with at least one CAZyme call (any of
                         hmm / sub / diamond has a non-"-" value)
"""

## Module docstring (PEP 257). `from __future__ import annotations`
## (PEP 563) — modern type hints portable across versions.
from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path
from typing import NamedTuple


## Structured per-protein record (typing.NamedTuple): immutable named row.
class dbcan_protein_cazyme_call(NamedTuple):
    feature_id: str
    dbcan_ec_numbers: str
    dbcan_hmm_hit: str
    dbcan_sub_hit: str
    dbcan_diamond_hit: str
    dbcan_tool_count: int
    dbcan_number_of_tools_hit: int
    dbcan_consensus_family: str
    dbcan_threshold_met: bool   # True when >= 2 tools agree on consensus family
    dbcan_has_call: bool        # True when >= 1 tool returned any hit


## Safe-conversion helper (defensive programming).
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


## Tokens dbCAN uses to mean "no call from this method".
DBCAN_EMPTY_TOKENS: set[str] = {"-", "", "N", "NA", "None"}


def count_method_hits(hmm_call_value: str, sub_call_value: str, diamond_call_value: str) -> int:
    number_of_tools_hit = 0
    if hmm_call_value not in DBCAN_EMPTY_TOKENS:
        number_of_tools_hit += 1
    if sub_call_value not in DBCAN_EMPTY_TOKENS:
        number_of_tools_hit += 1
    if diamond_call_value not in DBCAN_EMPTY_TOKENS:
        number_of_tools_hit += 1
    return number_of_tools_hit


## ── Helper: pick a single consensus CAZy family from the three method calls.
##    Strips the trailing "(start-end)" coordinate annotations and chooses
##    the most common non-empty family among the methods.
def derive_consensus_family_from_method_calls(
    hmm_call_value: str,
    sub_call_value: str,
    diamond_call_value: str,
) -> str:
    def strip_coordinate_suffix(raw_call: str) -> str:
        if "(" in raw_call:
            return raw_call.split("(", 1)[0]
        return raw_call

    candidate_families: list[str] = []
    for raw_call_value in (hmm_call_value, sub_call_value, diamond_call_value):
        if raw_call_value in DBCAN_EMPTY_TOKENS:
            continue
        ## dbCAN may pipe-separate multiple families in one method's call;
        ## take the first (highest-scoring) one.
        primary_family = raw_call_value.split("|")[0]
        primary_family = primary_family.split("+")[0]
        primary_family = strip_coordinate_suffix(primary_family).strip()
        if primary_family:
            candidate_families.append(primary_family)

    if not candidate_families:
        return ""

    ## Consensus call: require >= 2 methods to agree on the same family.
    ## Single-tool hits are NOT promoted — they remain visible via the
    ## individual hmm_hit / sub_hit / diamond_hit columns only.
    family_to_count: dict[str, int] = {}
    for family_name in candidate_families:
        family_to_count[family_name] = family_to_count.get(family_name, 0) + 1
    best_family_name, best_count_value = max(family_to_count.items(),
                                             key=lambda kv: kv[1])
    if best_count_value >= 2:
        return best_family_name
    return ""


## ── Step 1: parse the dbCAN overview.tsv file ──
##    Robust to both v4 and v5 column orderings by looking at the header row.
def parse_dbcan_overview_tsv(overview_tsv_path: Path) -> list[dbcan_protein_cazyme_call]:
    parsed_records: list[dbcan_protein_cazyme_call] = []

    with open(overview_tsv_path) as input_file_handle:
        header_line = input_file_handle.readline().rstrip("\n")
        if not header_line:
            return parsed_records

        header_columns = [column_name.strip().lower() for column_name in header_line.split("\t")]

        def find_column_index(*candidate_names: str) -> int:
            for candidate_name in candidate_names:
                for column_index, column_name in enumerate(header_columns):
                    if column_name == candidate_name.lower():
                        return column_index
            return -1

        gene_id_column_index    = find_column_index("gene id", "gene_id", "gene")
        ec_column_index         = find_column_index("ec#", "ec", "ec_number", "ec#:no")
        hmm_column_index        = find_column_index("dbcan_hmm", "hmmer", "dbcan_hmmer", "hmm")
        sub_column_index        = find_column_index("dbcan_sub", "dbcan-sub", "dbcansub")
        diamond_column_index    = find_column_index("diamond", "dbcan_diamond")
        toolcount_column_index  = find_column_index("#oftools", "#ofTools", "tool_count")

        if gene_id_column_index < 0:
            print("[process_dbcan] WARNING: could not find Gene ID column in overview.tsv header",
                  file=sys.stderr)
            return parsed_records

        for raw_line in input_file_handle:
            stripped_line = raw_line.rstrip("\n")
            if not stripped_line:
                continue
            split_fields = stripped_line.split("\t")

            def safe_lookup(column_index: int) -> str:
                if column_index < 0 or column_index >= len(split_fields):
                    return "-"
                value_token = split_fields[column_index].strip()
                return value_token if value_token else "-"

            feature_id_value     = safe_lookup(gene_id_column_index)
            if feature_id_value in DBCAN_EMPTY_TOKENS:
                continue

            ec_numbers_value     = safe_lookup(ec_column_index)
            hmm_call_value       = safe_lookup(hmm_column_index)
            sub_call_value       = safe_lookup(sub_column_index)
            diamond_call_value   = safe_lookup(diamond_column_index)
            tool_count_value     = safely_convert_to_integer(safe_lookup(toolcount_column_index))
            number_of_tools_hit_value = count_method_hits(
                hmm_call_value,
                sub_call_value,
                diamond_call_value,
            )

            has_any_call_flag = not (
                hmm_call_value     in DBCAN_EMPTY_TOKENS
                and sub_call_value in DBCAN_EMPTY_TOKENS
                and diamond_call_value in DBCAN_EMPTY_TOKENS
            )

            consensus_family_value = derive_consensus_family_from_method_calls(
                hmm_call_value, sub_call_value, diamond_call_value,
            )

            parsed_records.append(dbcan_protein_cazyme_call(
                feature_id              = feature_id_value,
                dbcan_ec_numbers        = ec_numbers_value,
                dbcan_hmm_hit           = hmm_call_value,
                dbcan_sub_hit           = sub_call_value,
                dbcan_diamond_hit       = diamond_call_value,
                dbcan_tool_count        = tool_count_value,
                dbcan_number_of_tools_hit = number_of_tools_hit_value,
                dbcan_consensus_family  = consensus_family_value,
                dbcan_threshold_met     = bool(consensus_family_value),
                dbcan_has_call          = has_any_call_flag,
            ))

    return parsed_records


## Canonical column order — defined once.
## threshold_met = True when >= 2 tools agree (official call); has_call = any tool hit.
COLUMN_HEADER_ROW: list[str] = [
    "organism_name", "domain", "feature_id",
    "DBCAN_id", "DBCAN_description", "DBCAN_ec_numbers",
    "DBCAN_hmm_hit", "DBCAN_sub_hit", "DBCAN_diamond_hit",
    "DBCAN_threshold_met", "DBCAN_has_call",
    "DBCAN_tool_used", "DBCAN_command_used", "DBCAN_database_used", "DBCAN_methods_used",
    "input_path", "output_path",
    "DBCAN_tool_count", "DBCAN_number_of_tools_hit",
]


## CLI definition (argparse).
def parse_command_line_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True,
                        help="Path to raw dbCAN overview.tsv")
    parser.add_argument("--output", required=True,
                        help="Path to write per-protein processed TSV (dbcan_results.tsv)")
    parser.add_argument("--output-top1", required=False, default=None,
                        help="Optional path for calls-only TSV (dbcan_top1.tsv)")
    parser.add_argument("--organism-name", required=True,
                        help="Organism name to record on every row")
    parser.add_argument("--domain", required=False, default="Unknown",
                        help="Domain label to record on every row (e.g. Archaea/Bacteria)")
    parser.add_argument("--tool-used", required=False, default="",
                        help="Human-readable tool identity/version recorded in output provenance")
    parser.add_argument("--command-used", required=False, default="",
                        help="Exact run_dbcan command line that produced the raw input")
    parser.add_argument("--database-used", required=False, default="",
                        help="Database identity/version/source recorded in output provenance")
    parser.add_argument("--methods-used", required=False, default="",
                        help="run_dbcan --methods string (provenance)")
    parser.add_argument("--input-path", required=False, default="",
                        help="Input protein FASTA path recorded for provenance")
    parser.add_argument("--output-path", required=False, default="",
                        help="Output directory path recorded for provenance")
    return parser.parse_args()


## Step 2: write a sorted TSV (csv module for safe quoting).
def write_processed_table(
    records_to_write: list[dbcan_protein_cazyme_call],
    output_file_path: Path,
    organism_name_value: str,
    domain_value: str,
    tool_used_value: str,
    command_used_value: str,
    database_used_value: str,
    methods_used_value: str,
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
                rec.dbcan_consensus_family, "", rec.dbcan_ec_numbers,
                rec.dbcan_hmm_hit, rec.dbcan_sub_hit, rec.dbcan_diamond_hit,
                "true" if rec.dbcan_threshold_met else "false",
                "true" if rec.dbcan_has_call else "false",
                tool_used_value, command_used_value, database_used_value, methods_used_value,
                input_path_value, output_path_value,
                rec.dbcan_tool_count, rec.dbcan_number_of_tools_hit,
            ])
            number_of_rows_written += 1
    return number_of_rows_written


## Entry point.
def main() -> None:
    command_line_arguments = parse_command_line_arguments()

    input_file_path = Path(command_line_arguments.input)
    if not input_file_path.exists():
        print(f"[process_dbcan] ERROR: input not found: {input_file_path}", file=sys.stderr)
        raise SystemExit(1)

    all_records = parse_dbcan_overview_tsv(input_file_path)

    main_output_path = Path(command_line_arguments.output)
    number_of_rows_written = write_processed_table(
        all_records,
        main_output_path,
        command_line_arguments.organism_name,
        command_line_arguments.domain,
        command_line_arguments.tool_used,
        command_line_arguments.command_used,
        command_line_arguments.database_used,
        command_line_arguments.methods_used,
        command_line_arguments.input_path,
        command_line_arguments.output_path,
    )
    print(f"[process_dbcan] Wrote {number_of_rows_written} rows → {main_output_path}")

    if command_line_arguments.output_top1:
        top_output_path = Path(command_line_arguments.output_top1)
        called_records_only = [rec for rec in all_records if rec.dbcan_has_call]
        number_of_called_rows = write_processed_table(
            called_records_only,
            top_output_path,
            command_line_arguments.organism_name,
            command_line_arguments.domain,
            command_line_arguments.tool_used,
            command_line_arguments.command_used,
            command_line_arguments.database_used,
            command_line_arguments.methods_used,
            command_line_arguments.input_path,
            command_line_arguments.output_path,
        )
        print(f"[process_dbcan] Wrote {number_of_called_rows} called rows → {top_output_path}")


if __name__ == "__main__":
    main()
