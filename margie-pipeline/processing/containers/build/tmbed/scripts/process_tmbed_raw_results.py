#!/usr/bin/env python3
"""
process_tmbed_raw_results.py — Post-process TMbed --out-format=1 predictions
into normalised, pipeline-friendly TSVs.

INPUT (written by the run step into <output_dir>/raw/tmbed.pred):
    3-line records per protein:
        >protein_id
        AMINOACID_SEQUENCE...
        LABEL_SEQUENCE...
    where the label character set is:
        B = transmembrane beta strand (out→in)
        b = transmembrane beta strand (in→out)
        H = transmembrane alpha helix (out→in)
        h = transmembrane alpha helix (in→out)
        S = signal peptide
        i = inside (cytoplasmic)
        o = outside (periplasmic/extracellular)

OUTPUT (written under <output_dir>/processed/):
    tmbed_results.tsv  — one row per topology segment  (TMBED_ prefix)
    tmbed_top1.tsv     — one summary row per protein
"""

## Module docstring (PEP 257) up top — describes the script's purpose.
## `from __future__ import annotations` (PEP 563) — modern type hints
## work across Python versions.
from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path
from typing import NamedTuple


## Structured records (typing.NamedTuple): immutable, named, easy to read.
class tmbed_topology_segment(NamedTuple):
    feature_id: str
    tmbed_segment_index: int
    tmbed_segment_count: int
    tmbed_segment_start: int
    tmbed_segment_end: int
    tmbed_segment_length: int
    tmbed_topology: str
    tmbed_raw_label: str
    tmbed_protein_length: int
    tmbed_topology_string: str


class tmbed_protein_summary(NamedTuple):
    feature_id: str
    tmbed_protein_length: int
    tmbed_topology_string: str
    tmbed_number_of_tm_helices: int
    tmbed_number_of_tm_beta_strands: int
    tmbed_has_signal_peptide: bool
    tmbed_number_of_inside_segments: int
    tmbed_number_of_outside_segments: int


## Human-readable mapping for the per-residue label characters emitted by
## TMbed in --out-format=1.
TMBED_LABEL_TO_TOPOLOGY: dict[str, str] = {
    "B": "transmembrane_beta_strand",
    "b": "transmembrane_beta_strand",
    "H": "transmembrane_helix",
    "h": "transmembrane_helix",
    "S": "signal_peptide",
    "i": "inside",
    "o": "outside",
}


## CLI definition (argparse standard library).
def parse_command_line_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True,
                        help="Path to raw TMbed .pred file (tmbed.pred)")
    parser.add_argument("--output", required=True,
                        help="Path to write per-segment processed TSV (tmbed_results.tsv)")
    parser.add_argument("--output-top1", required=False, default=None,
                        help="Optional path for per-protein summary TSV (tmbed_top1.tsv)")
    parser.add_argument("--organism-name", required=True,
                        help="Organism name to record on every row (free text)")
    parser.add_argument("--domain", required=False, default="Unknown",
                        help="Domain label to record on every row (e.g. Archaea/Bacteria)")
    parser.add_argument("--tool-used", required=False, default="",
                        help="Human-readable tool identity/version recorded in output provenance")
    parser.add_argument("--command-used", required=False, default="",
                        help="Exact tmbed command line that produced the raw input")
    parser.add_argument("--database-used", required=False, default="",
                        help="Model/database used (provenance)")
    parser.add_argument("--model-used", required=False, default="ProtT5-XL-U50",
                        help="TMbed encoder model used (default: ProtT5-XL-U50)")
    parser.add_argument("--input-path", required=False, default="",
                        help="Input protein FASTA path recorded for provenance")
    parser.add_argument("--output-path", required=False, default="",
                        help="Output directory path recorded for provenance")
    return parser.parse_args()


## Step 1 — read the 3-line .pred records.
def read_tmbed_predictions(predictions_file_path: Path) -> list[tuple[str, str, str]]:
    parsed_records: list[tuple[str, str, str]] = []
    current_header: str | None = None
    current_sequence: str | None = None
    current_labels: str | None = None

    with open(predictions_file_path) as input_file_handle:
        for raw_line in input_file_handle:
            stripped_line = raw_line.rstrip("\n")
            if not stripped_line:
                continue

            if stripped_line.startswith(">"):
                ## Flush the previous record (if any) before starting a new one.
                if current_header is not None and current_sequence is not None and current_labels is not None:
                    parsed_records.append((current_header, current_sequence, current_labels))
                ## First token after '>' is the protein ID.
                current_header = stripped_line[1:].split(None, 1)[0]
                current_sequence = None
                current_labels = None
            else:
                if current_sequence is None:
                    current_sequence = stripped_line
                elif current_labels is None:
                    current_labels = stripped_line
                else:
                    ## Unexpected extra line — append to labels defensively.
                    current_labels = current_labels + stripped_line

        ## Flush the final record.
        if current_header is not None and current_sequence is not None and current_labels is not None:
            parsed_records.append((current_header, current_sequence, current_labels))

    return parsed_records


## Step 2 — collapse a per-residue label string into contiguous
## (start, end_inclusive, raw_label_char) segments.
def collapse_label_string_into_segments(label_string: str) -> list[tuple[int, int, str]]:
    if not label_string:
        return []
    segments: list[tuple[int, int, str]] = []
    current_start_index = 0
    previous_label = label_string[0]
    for index_in_path, current_label in enumerate(label_string[1:], start=1):
        if current_label != previous_label:
            segments.append((current_start_index, index_in_path - 1, previous_label))
            current_start_index = index_in_path
            previous_label = current_label
    segments.append((current_start_index, len(label_string) - 1, previous_label))
    return segments


## Step 3 — build a compact topology string like "i-H-o-H-i" by reading
## every collapsed segment's topology label (collapsing consecutive labels
## of the same topology so beta/helix direction switches don't multiply).
def build_compact_topology_string(state_segments: list[tuple[int, int, str]]) -> str:
    short_labels: list[str] = []
    previous_short_label = ""
    for _segment_start, _segment_end, raw_label in state_segments:
        topology_label = TMBED_LABEL_TO_TOPOLOGY.get(raw_label, raw_label)
        short_label = {
            "transmembrane_helix": "H",
            "transmembrane_beta_strand": "B",
            "signal_peptide": "S",
            "inside": "i",
            "outside": "o",
        }.get(topology_label, raw_label)
        if short_label != previous_short_label:
            short_labels.append(short_label)
            previous_short_label = short_label
    return "-".join(short_labels)


## Step 4 — turn parsed records into the two processed record lists.
def build_processed_records(
    parsed_records: list[tuple[str, str, str]],
) -> tuple[list[tmbed_topology_segment], list[tmbed_protein_summary]]:

    all_segment_records: list[tmbed_topology_segment] = []
    all_summary_records: list[tmbed_protein_summary] = []

    for protein_id_value, protein_sequence, label_string in parsed_records:
        ## Truncate the label string to the actual sequence length in case
        ## TMbed appended trailing whitespace or padding.
        usable_label_length = min(len(label_string), len(protein_sequence))
        truncated_label_string = label_string[:usable_label_length]

        state_segments = collapse_label_string_into_segments(truncated_label_string)
        topology_string_value = build_compact_topology_string(state_segments)
        total_segment_count = len(state_segments)

        number_of_tm_helices = 0
        number_of_tm_beta_strands = 0
        has_signal_peptide_value = False
        number_of_inside_segments = 0
        number_of_outside_segments = 0

        for segment_position_index, (segment_start, segment_end, raw_label) in enumerate(state_segments, start=1):
            topology_label_value = TMBED_LABEL_TO_TOPOLOGY.get(raw_label, raw_label)
            segment_length_value = segment_end - segment_start + 1

            if topology_label_value == "transmembrane_helix":
                number_of_tm_helices += 1
            elif topology_label_value == "transmembrane_beta_strand":
                number_of_tm_beta_strands += 1
            elif topology_label_value == "signal_peptide":
                has_signal_peptide_value = True
            elif topology_label_value == "inside":
                number_of_inside_segments += 1
            elif topology_label_value == "outside":
                number_of_outside_segments += 1

            all_segment_records.append(tmbed_topology_segment(
                feature_id              = protein_id_value,
                tmbed_segment_index     = segment_position_index,
                tmbed_segment_count     = total_segment_count,
                tmbed_segment_start     = segment_start,
                tmbed_segment_end       = segment_end,
                tmbed_segment_length    = segment_length_value,
                tmbed_topology          = topology_label_value,
                tmbed_raw_label         = raw_label,
                tmbed_protein_length    = len(protein_sequence),
                tmbed_topology_string   = topology_string_value,
            ))

        all_summary_records.append(tmbed_protein_summary(
            feature_id                          = protein_id_value,
            tmbed_protein_length                = len(protein_sequence),
            tmbed_topology_string               = topology_string_value,
            tmbed_number_of_tm_helices          = number_of_tm_helices,
            tmbed_number_of_tm_beta_strands     = number_of_tm_beta_strands,
            tmbed_has_signal_peptide            = has_signal_peptide_value,
            tmbed_number_of_inside_segments     = number_of_inside_segments,
            tmbed_number_of_outside_segments    = number_of_outside_segments,
        ))

    return all_segment_records, all_summary_records


## Canonical column orders — defined once, reused for header + writer rows.
COLUMN_HEADER_FOR_SEGMENTS: list[str] = [
    "organism_name", "domain", "feature_id",
    "TMBED_segment_index", "TMBED_segment_count",
    "TMBED_segment_start", "TMBED_segment_end", "TMBED_segment_length",
    "TMBED_topology", "TMBED_raw_label",
    "TMBED_protein_length", "TMBED_topology_string",
    "TMBED_tool_used", "TMBED_command_used", "TMBED_database_used", "TMBED_model_used",
    "input_path", "output_path",
]

COLUMN_HEADER_FOR_SUMMARY: list[str] = [
    "organism_name", "domain", "feature_id",
    "TMBED_protein_length", "TMBED_topology_string",
    "TMBED_number_of_tm_helices", "TMBED_number_of_tm_beta_strands",
    "TMBED_has_signal_peptide",
    "TMBED_number_of_inside_segments", "TMBED_number_of_outside_segments",
    "TMBED_tool_used", "TMBED_command_used", "TMBED_database_used", "TMBED_model_used",
    "input_path", "output_path",
]


## Step 5a — write the per-segment processed TSV.
def write_segments_table(
    segment_records: list[tmbed_topology_segment],
    output_file_path: Path,
    organism_name_value: str,
    domain_value: str,
    tool_used_value: str,
    command_used_value: str,
    database_used_value: str,
    model_used_value: str,
    input_path_value: str,
    output_path_value: str,
) -> int:
    output_file_path.parent.mkdir(parents=True, exist_ok=True)
    sorted_records = sorted(
        segment_records,
        key=lambda rec: (rec.feature_id, rec.tmbed_segment_index),
    )
    number_of_rows_written = 0
    with open(output_file_path, "w", newline="") as output_file_handle:
        writer = csv.writer(output_file_handle, delimiter="\t")
        writer.writerow(COLUMN_HEADER_FOR_SEGMENTS)
        for rec in sorted_records:
            writer.writerow([
                organism_name_value, domain_value, rec.feature_id,
                rec.tmbed_segment_index, rec.tmbed_segment_count,
                rec.tmbed_segment_start, rec.tmbed_segment_end, rec.tmbed_segment_length,
                rec.tmbed_topology, rec.tmbed_raw_label,
                rec.tmbed_protein_length, rec.tmbed_topology_string,
                tool_used_value, command_used_value, database_used_value, model_used_value,
                input_path_value, output_path_value,
            ])
            number_of_rows_written += 1
    return number_of_rows_written


## Step 5b — write the per-protein summary TSV.
def write_summary_table(
    summary_records: list[tmbed_protein_summary],
    output_file_path: Path,
    organism_name_value: str,
    domain_value: str,
    tool_used_value: str,
    command_used_value: str,
    database_used_value: str,
    model_used_value: str,
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
                rec.tmbed_protein_length, rec.tmbed_topology_string,
                rec.tmbed_number_of_tm_helices, rec.tmbed_number_of_tm_beta_strands,
                "true" if rec.tmbed_has_signal_peptide else "false",
                rec.tmbed_number_of_inside_segments, rec.tmbed_number_of_outside_segments,
                tool_used_value, command_used_value, database_used_value, model_used_value,
                input_path_value, output_path_value,
            ])
            number_of_rows_written += 1
    return number_of_rows_written


## Entry point (standard `if __name__ == "__main__"` idiom).
def main() -> None:
    command_line_arguments = parse_command_line_arguments()

    input_file_path = Path(command_line_arguments.input)
    if not input_file_path.exists():
        print(f"[process_tmbed] ERROR: input not found: {input_file_path}", file=sys.stderr)
        raise SystemExit(1)

    parsed_records = read_tmbed_predictions(input_file_path)
    segment_records, summary_records = build_processed_records(parsed_records)

    main_output_path = Path(command_line_arguments.output)
    number_of_segment_rows = write_segments_table(
        segment_records,
        main_output_path,
        command_line_arguments.organism_name,
        command_line_arguments.domain,
        command_line_arguments.tool_used,
        command_line_arguments.command_used,
        command_line_arguments.database_used,
        command_line_arguments.model_used,
        command_line_arguments.input_path,
        command_line_arguments.output_path,
    )
    print(f"[process_tmbed] Wrote {number_of_segment_rows} segment rows → {main_output_path}")

    if command_line_arguments.output_top1:
        top_output_path = Path(command_line_arguments.output_top1)
        number_of_summary_rows = write_summary_table(
            summary_records,
            top_output_path,
            command_line_arguments.organism_name,
            command_line_arguments.domain,
            command_line_arguments.tool_used,
            command_line_arguments.command_used,
            command_line_arguments.database_used,
            command_line_arguments.model_used,
            command_line_arguments.input_path,
            command_line_arguments.output_path,
        )
        print(f"[process_tmbed] Wrote {number_of_summary_rows} summary rows → {top_output_path}")


if __name__ == "__main__":
    main()
