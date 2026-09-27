#!/usr/bin/env python3
"""
process_geneprop_raw_results.py — Run Genome Properties whole-genome
assignment from a TIGRFAMs domtblout and the EBI genome-properties
flatfiles, producing a normalised per-property TSV.

INPUTS
    --tigrfam-domtbl PATH   HMMER domtblout from the tigrfam stage
                            (e.g. <pipeline_root>/tigrfam/raw/tigrfam_domtbl.out)
    --flatfiles-dir  DIR    EBI genome-properties flatfiles directory
                            (each subdir contains a DESC file:
                             <DIR>/GenProp####/DESC)

OUTPUT (written to --output):
    geneprop_results.tsv    — one row per property, GENEPROP_ prefix

ASSIGNMENT ALGORITHM (per EBI genome-properties spec):
    1.  A step is YES if any of its EV evidence accessions matches a
        TIGRFAMs accession found in the domtblout.
    2.  A property is YES if every required step (RQ=1) is YES.
    3.  Otherwise the property is PARTIAL if the count of YES required
        steps is >= TH (threshold), else NO.
"""

## Module docstring (PEP 257). `from __future__ import annotations`
## (PEP 563) — modern type hints portable across versions.
from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path
from typing import NamedTuple


## ── Structured records (typing.NamedTuple): one for each step and one for
##    each fully-assigned property. Immutable named rows. ──
class genome_property_step_definition(NamedTuple):
    step_number: int
    step_name: str
    step_is_required: bool
    step_evidence_accessions: tuple[str, ...]


class genome_property_definition(NamedTuple):
    property_accession: str
    property_name: str
    property_type: str
    property_threshold: int
    property_steps: tuple[genome_property_step_definition, ...]


class genome_property_assignment_result(NamedTuple):
    property_accession: str
    property_name: str
    property_type: str
    property_threshold: int
    property_steps_total: int
    property_steps_required: int
    property_steps_matched: int
    property_steps_matched_required: int
    property_status: str          ## YES | PARTIAL | NO


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


## ── Step 1: parse a single DESC flatfile into a genome_property_definition ──
##    Format (one record terminated by "//"):
##      AC  GenProp####
##      DE  Description
##      TP  TYPE
##      TH  threshold
##      **
##      SN  1
##      ID  Step name
##      RQ  1
##      EV  ACCESSION; ACCESSION; sufficient;
##      --
##      ...
##      //
def parse_single_desc_flatfile(desc_file_path: Path) -> genome_property_definition | None:
    property_accession_value = ""
    property_name_value = ""
    property_type_value = ""
    property_threshold_value = 0

    accumulated_steps: list[genome_property_step_definition] = []
    current_step_number = 0
    current_step_name = ""
    current_step_is_required = False
    current_step_evidence: list[str] = []
    have_open_step = False

    def flush_current_step() -> None:
        nonlocal have_open_step
        if not have_open_step:
            return
        accumulated_steps.append(genome_property_step_definition(
            step_number              = current_step_number,
            step_name                = current_step_name,
            step_is_required         = current_step_is_required,
            step_evidence_accessions = tuple(current_step_evidence),
        ))
        have_open_step = False

    try:
        input_file_handle = open(desc_file_path)
    except OSError:
        return None

    with input_file_handle:
        for raw_line in input_file_handle:
            stripped_line = raw_line.rstrip("\n")
            if not stripped_line or stripped_line.startswith("#"):
                continue
            if stripped_line.startswith("--") or stripped_line.startswith("**"):
                flush_current_step()
                current_step_number = 0
                current_step_name = ""
                current_step_is_required = False
                current_step_evidence = []
                continue
            if stripped_line.startswith("//"):
                flush_current_step()
                break

            ## Records are 2-character tag + whitespace + value.
            if len(stripped_line) < 4:
                continue
            tag_value = stripped_line[:2]
            payload_value = stripped_line[2:].strip()

            if tag_value == "AC":
                property_accession_value = payload_value
            elif tag_value == "DE":
                property_name_value = payload_value
            elif tag_value == "TP":
                property_type_value = payload_value
            elif tag_value == "TH":
                property_threshold_value = safely_convert_to_integer(payload_value)
            elif tag_value == "SN":
                ## Opening a new step block.
                flush_current_step()
                current_step_number = safely_convert_to_integer(payload_value)
                current_step_name = ""
                current_step_is_required = False
                current_step_evidence = []
                have_open_step = True
            elif tag_value == "ID":
                if have_open_step:
                    current_step_name = payload_value
            elif tag_value == "RQ":
                if have_open_step:
                    current_step_is_required = payload_value.strip() == "1"
            elif tag_value == "EV":
                if have_open_step:
                    ## EV line is semicolon-delimited tokens: at least one
                    ## accession (Pfam/TIGRFAM/InterPro) followed by qualifiers
                    ## like "sufficient". We treat every accession-shaped token
                    ## as evidence.
                    for ev_token in payload_value.split(";"):
                        cleaned_ev_token = ev_token.strip()
                        if not cleaned_ev_token:
                            continue
                        ## Strip trailing version suffix from accessions.
                        if cleaned_ev_token.lower() in ("sufficient", "non-essential"):
                            continue
                        current_step_evidence.append(cleaned_ev_token)
        flush_current_step()

    if not property_accession_value:
        return None

    return genome_property_definition(
        property_accession  = property_accession_value,
        property_name       = property_name_value,
        property_type       = property_type_value,
        property_threshold  = property_threshold_value,
        property_steps      = tuple(accumulated_steps),
    )


## ── Step 2: walk the flatfiles directory and parse every DESC ──
def load_all_genome_property_definitions(flatfiles_root_dir: Path) -> list[genome_property_definition]:
    parsed_properties: list[genome_property_definition] = []
    for property_subdirectory in sorted(flatfiles_root_dir.iterdir()):
        if not property_subdirectory.is_dir():
            continue
        candidate_desc_file = property_subdirectory / "DESC"
        if not candidate_desc_file.is_file():
            continue
        parsed_property = parse_single_desc_flatfile(candidate_desc_file)
        if parsed_property is not None:
            parsed_properties.append(parsed_property)
    return parsed_properties


## ── Step 3: read a HMMER domtblout and return the set of unique target
##    HMM accessions that have at least one hit. ──
##    domtblout columns: target_name, target_acc, tlen, query_name,
##    query_acc, qlen, evalue_full, score_full, bias_full, ...
##    We collect both target_acc and target_name (the latter for HMMs
##    whose acc field is "-").
def collect_matched_hmm_accessions(domtblout_path: Path) -> set[str]:
    matched_accession_set: set[str] = set()
    if not domtblout_path.exists():
        return matched_accession_set
    with open(domtblout_path) as input_file_handle:
        for raw_line in input_file_handle:
            if raw_line.startswith("#") or not raw_line.strip():
                continue
            split_fields = raw_line.split()
            if len(split_fields) < 4:
                continue
            ## In a domtblout the *query* is the HMM. Column layout:
            ##   target_name, target_acc, tlen,
            ##   query_name (=HMM name), query_acc (=HMM acc), qlen, ...
            query_hmm_name = split_fields[3]
            query_hmm_accession = split_fields[4] if len(split_fields) > 4 else "-"
            if query_hmm_name and query_hmm_name != "-":
                matched_accession_set.add(query_hmm_name)
                ## Also store accession trimmed of version suffix:
                matched_accession_set.add(query_hmm_name.split(".")[0])
            if query_hmm_accession and query_hmm_accession != "-":
                matched_accession_set.add(query_hmm_accession)
                matched_accession_set.add(query_hmm_accession.split(".")[0])
    return matched_accession_set


## ── Step 4: assign each property based on the matched accessions ──
def assign_single_property_status(
    property_definition: genome_property_definition,
    matched_accession_set: set[str],
) -> genome_property_assignment_result:
    total_step_count = len(property_definition.property_steps)
    required_step_count = sum(1 for step in property_definition.property_steps if step.step_is_required)

    yes_step_count_total = 0
    yes_step_count_required = 0
    for step_definition in property_definition.property_steps:
        is_yes_step = False
        for evidence_accession in step_definition.step_evidence_accessions:
            stripped_accession = evidence_accession.split(".")[0]
            if (evidence_accession in matched_accession_set
                or stripped_accession in matched_accession_set):
                is_yes_step = True
                break
        if is_yes_step:
            yes_step_count_total += 1
            if step_definition.step_is_required:
                yes_step_count_required += 1

    ## Status decision per EBI spec.
    if required_step_count > 0 and yes_step_count_required == required_step_count:
        property_status_value = "YES"
    elif yes_step_count_required >= property_definition.property_threshold and yes_step_count_required > 0:
        property_status_value = "PARTIAL"
    else:
        property_status_value = "NO"

    return genome_property_assignment_result(
        property_accession              = property_definition.property_accession,
        property_name                   = property_definition.property_name,
        property_type                   = property_definition.property_type,
        property_threshold              = property_definition.property_threshold,
        property_steps_total            = total_step_count,
        property_steps_required         = required_step_count,
        property_steps_matched          = yes_step_count_total,
        property_steps_matched_required = yes_step_count_required,
        property_status                 = property_status_value,
    )


## Canonical column order — defined once, reused for header + writer rows.
COLUMN_HEADER_ROW: list[str] = [
    "organism_name",
    "GENEPROP_property_accession", "GENEPROP_property_name", "GENEPROP_property_type",
    "GENEPROP_property_status", "GENEPROP_property_threshold",
    "GENEPROP_steps_total", "GENEPROP_steps_required",
    "GENEPROP_steps_matched", "GENEPROP_steps_matched_required",
    "GENEPROP_command_used", "GENEPROP_flatfiles_dir_used",
]


## CLI definition (argparse).
def parse_command_line_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tigrfam-domtbl", required=True,
                        help="Path to TIGRFAMs HMMER domtblout file")
    parser.add_argument("--flatfiles-dir", required=True,
                        help="Path to EBI genome-properties flatfiles directory")
    parser.add_argument("--output", required=True,
                        help="Path to write per-property processed TSV (geneprop_results.tsv)")
    parser.add_argument("--output-top1", required=False, default=None,
                        help="Optional path for YES-only TSV (geneprop_top1.tsv)")
    parser.add_argument("--organism-name", required=True,
                        help="Organism name to record on every row")
    parser.add_argument("--command-used", required=False, default="",
                        help="Provenance: command line that produced the raw inputs")
    return parser.parse_args()


## Step 5: write a sorted TSV (csv module for safe quoting).
def write_processed_table(
    results_to_write: list[genome_property_assignment_result],
    output_file_path: Path,
    organism_name_value: str,
    command_used_value: str,
    flatfiles_dir_value: str,
) -> int:
    output_file_path.parent.mkdir(parents=True, exist_ok=True)
    sorted_results = sorted(results_to_write, key=lambda rec: rec.property_accession)
    number_of_rows_written = 0
    with open(output_file_path, "w", newline="") as output_file_handle:
        writer = csv.writer(output_file_handle, delimiter="\t")
        writer.writerow(COLUMN_HEADER_ROW)
        for rec in sorted_results:
            writer.writerow([
                organism_name_value,
                rec.property_accession, rec.property_name, rec.property_type,
                rec.property_status, rec.property_threshold,
                rec.property_steps_total, rec.property_steps_required,
                rec.property_steps_matched, rec.property_steps_matched_required,
                command_used_value, flatfiles_dir_value,
            ])
            number_of_rows_written += 1
    return number_of_rows_written


## Entry point.
def main() -> None:
    command_line_arguments = parse_command_line_arguments()

    domtblout_path = Path(command_line_arguments.tigrfam_domtbl)
    flatfiles_dir_path = Path(command_line_arguments.flatfiles_dir)

    if not domtblout_path.exists():
        print(f"[process_geneprop] ERROR: tigrfam domtblout not found: {domtblout_path}",
              file=sys.stderr)
        raise SystemExit(1)
    if not flatfiles_dir_path.is_dir():
        print(f"[process_geneprop] ERROR: flatfiles dir not found: {flatfiles_dir_path}",
              file=sys.stderr)
        raise SystemExit(1)

    matched_accession_set = collect_matched_hmm_accessions(domtblout_path)
    print(f"[process_geneprop] Matched {len(matched_accession_set)} unique HMM accessions in domtblout")

    all_property_definitions = load_all_genome_property_definitions(flatfiles_dir_path)
    print(f"[process_geneprop] Parsed {len(all_property_definitions)} property definitions from flatfiles")

    all_assignment_results = [
        assign_single_property_status(prop_def, matched_accession_set)
        for prop_def in all_property_definitions
    ]

    main_output_path = Path(command_line_arguments.output)
    number_of_rows_written = write_processed_table(
        all_assignment_results,
        main_output_path,
        command_line_arguments.organism_name,
        command_line_arguments.command_used,
        str(flatfiles_dir_path),
    )
    print(f"[process_geneprop] Wrote {number_of_rows_written} rows → {main_output_path}")

    if command_line_arguments.output_top1:
        top_output_path = Path(command_line_arguments.output_top1)
        yes_only_results = [rec for rec in all_assignment_results if rec.property_status == "YES"]
        number_of_yes_rows = write_processed_table(
            yes_only_results,
            top_output_path,
            command_line_arguments.organism_name,
            command_line_arguments.command_used,
            str(flatfiles_dir_path),
        )
        print(f"[process_geneprop] Wrote {number_of_yes_rows} YES rows → {top_output_path}")


if __name__ == "__main__":
    main()
