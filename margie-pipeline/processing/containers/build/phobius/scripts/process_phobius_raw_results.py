#!/usr/bin/env python3
"""
process_phobius_raw_results.py — Post-process Phobius -long output into
normalised, pipeline-friendly TSVs.

INPUT (Phobius -long format):
    ID   <protein_id>
    FT   SIGNAL        1     22
    FT   REGION        1      4       N-REGION.
    FT   REGION        5     17       H-REGION.
    FT   REGION       18     22       C-REGION.
    FT   DOMAIN       23     34       NON CYTOPLASMIC.
    FT   TRANSMEM     35     56
    FT   DOMAIN       57     78       CYTOPLASMIC.
    //

INPUT (Phobius -short format):
    SEQENCE ID                     TM SP PREDICTION
    sp|...|name                     4  Y n8-17c22/23o35-56i...

OUTPUTS:
    phobius_results.tsv  — one row per topology segment
    phobius_top1.tsv     — one row per protein (summary statistics)
"""
from __future__ import annotations

import argparse
import csv
import re
import sys
from pathlib import Path

PER_SEGMENT_COLUMNS = [
    "organism_name",
    "domain",
    "feature_id",
    "phobius_segment_index",
    "phobius_segment_count",
    "phobius_segment_start",
    "phobius_segment_end",
    "phobius_segment_length",
    "phobius_segment_type",        # SIGNAL | TRANSMEM | DOMAIN
    "phobius_segment_label",       # raw 3rd field (e.g. CYTOPLASMIC, NON CYTOPLASMIC, "")
    "phobius_has_signal_peptide",  # Y | N
    "phobius_signal_cleavage_pos", # int or ""
    "phobius_n_transmembrane",
    "phobius_topology_short",      # short-format prediction string
    "phobius_protein_length",
    "PHOBIUS_tool_used",
    "phobius_command_used",
    "PHOBIUS_database_used",
    "phobius_model_used",
    "input_path",
    "output_path",
]

TOP1_COLUMNS = [
    "organism_name",
    "domain",
    "feature_id",
    "phobius_has_signal_peptide",
    "phobius_signal_cleavage_pos",
    "phobius_n_transmembrane",
    "phobius_n_segments",
    "phobius_topology_short",
    "phobius_protein_length",
    "phobius_first_tm_start",
    "phobius_first_tm_end",
    "PHOBIUS_tool_used",
    "phobius_command_used",
    "PHOBIUS_database_used",
    "phobius_model_used",
    "input_path",
    "output_path",
]


def parse_command_line_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-long",  required=True, help="phobius -long output")
    parser.add_argument("--input-short", required=True, help="phobius -short output")
    parser.add_argument("--output",      required=True, help="Per-segment TSV")
    parser.add_argument("--output-top1", required=True, help="Per-protein summary TSV")
    parser.add_argument("--organism-name", required=True)
    parser.add_argument("--domain", default="Unknown")
    parser.add_argument("--tool-used",   default="")
    parser.add_argument("--command-used", default="")
    parser.add_argument("--database-used", default="")
    parser.add_argument("--model-used",   default="phobius.model")
    parser.add_argument("--input-path", default="")
    parser.add_argument("--output-path", default="")
    return parser.parse_args()


def parse_long_format(long_file_path: Path) -> dict[str, dict]:
    """Returns dict keyed by protein_id → {segments: [...], signal_cleavage: int|None}."""
    per_protein: dict[str, dict] = {}
    current_id: str | None = None
    current_segments: list[dict] = []
    current_cleavage: int | None = None

    def _flush() -> None:
        if current_id is not None:
            per_protein[current_id] = {
                "segments": list(current_segments),
                "signal_cleavage": current_cleavage,
            }

    with open(long_file_path, "r", encoding="utf-8", errors="replace") as fh:
        for raw_line in fh:
            line = raw_line.rstrip("\n")
            if not line:
                continue
            if line.startswith("ID"):
                _flush()
                # ID   <protein_id>
                parts = line.split(None, 1)
                current_id = parts[1].strip() if len(parts) > 1 else ""
                current_segments = []
                current_cleavage = None
            elif line.startswith("FT"):
                # FT   <TYPE>   <start>   <end>   [optional label, trailing '.']
                fields = line.split(None, 4)
                if len(fields) < 4:
                    continue
                seg_type = fields[1]
                try:
                    seg_start = int(fields[2])
                    seg_end   = int(fields[3])
                except ValueError:
                    continue
                seg_label = fields[4].rstrip(".").strip() if len(fields) > 4 else ""
                # SIGNAL line: end pos is the cleavage site
                if seg_type == "SIGNAL":
                    current_cleavage = seg_end
                current_segments.append({
                    "type": seg_type,
                    "start": seg_start,
                    "end":   seg_end,
                    "label": seg_label,
                })
            elif line.startswith("//"):
                _flush()
                current_id = None
                current_segments = []
                current_cleavage = None
        _flush()

    return per_protein


def parse_short_format(short_file_path: Path) -> dict[str, dict]:
    """Returns dict keyed by protein_id → {tm: int, sp: 'Y'|'N', prediction: str}.

    Phobius -short header line:  'SEQENCE ID                     TM SP PREDICTION'
    Data rows are whitespace-separated; protein_id may contain spaces only if
    quoted (Phobius doesn't quote — it splits on first whitespace), so we use
    the last three fields as TM/SP/PREDICTION.
    """
    out: dict[str, dict] = {}
    with open(short_file_path, "r", encoding="utf-8", errors="replace") as fh:
        for raw_line in fh:
            line = raw_line.rstrip("\n")
            if not line or line.startswith("SEQENCE"):
                continue
            tokens = line.split()
            if len(tokens) < 4:
                continue
            prediction = tokens[-1]
            sp_flag    = tokens[-2]
            try:
                tm_count = int(tokens[-3])
            except ValueError:
                continue
            protein_id = " ".join(tokens[:-3])
            # short format truncates IDs to first whitespace; use first token only
            protein_id_first = protein_id.split()[0] if protein_id else ""
            out[protein_id_first] = {
                "tm":         tm_count,
                "sp":         sp_flag,
                "prediction": prediction,
            }
    return out


def main() -> int:
    args = parse_command_line_arguments()

    long_data  = parse_long_format(Path(args.input_long))
    short_data = parse_short_format(Path(args.input_short))

    out_path  = Path(args.output)
    top1_path = Path(args.output_top1)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    top1_path.parent.mkdir(parents=True, exist_ok=True)

    written_segments = 0
    written_top1 = 0

    with open(out_path, "w", encoding="utf-8", newline="") as seg_fh, \
         open(top1_path, "w", encoding="utf-8", newline="") as top1_fh:
        seg_writer  = csv.DictWriter(seg_fh,  fieldnames=PER_SEGMENT_COLUMNS, delimiter="\t")
        top1_writer = csv.DictWriter(top1_fh, fieldnames=TOP1_COLUMNS,        delimiter="\t")
        seg_writer.writeheader()
        top1_writer.writeheader()

        # Iterate in the order they appeared in the long file.
        for protein_id, payload in long_data.items():
            protein_id_first = protein_id.split()[0] if protein_id else ""
            short = short_data.get(protein_id_first, {})
            tm_count   = short.get("tm", "")
            sp_flag    = short.get("sp", "N")
            prediction = short.get("prediction", "")

            segments_only_topology = [
                s for s in payload["segments"]
                if s["type"] in {"SIGNAL", "TRANSMEM", "DOMAIN"}
            ]
            protein_length = max(
                (s["end"] for s in payload["segments"]),
                default=0,
            )
            n_segments = len(segments_only_topology)

            first_tm_start = ""
            first_tm_end   = ""
            for s in segments_only_topology:
                if s["type"] == "TRANSMEM":
                    first_tm_start = s["start"]
                    first_tm_end   = s["end"]
                    break

            cleavage = payload["signal_cleavage"]
            cleavage_str = "" if cleavage is None else str(cleavage)

            for idx, s in enumerate(segments_only_topology, start=1):
                seg_writer.writerow({
                    "organism_name":               args.organism_name,
                    "domain":                      args.domain,
                    "feature_id":                  protein_id_first,
                    "phobius_segment_index":       idx,
                    "phobius_segment_count":       n_segments,
                    "phobius_segment_start":       s["start"],
                    "phobius_segment_end":         s["end"],
                    "phobius_segment_length":      s["end"] - s["start"] + 1,
                    "phobius_segment_type":        s["type"],
                    "phobius_segment_label":       s["label"],
                    "phobius_has_signal_peptide":  sp_flag,
                    "phobius_signal_cleavage_pos": cleavage_str,
                    "phobius_n_transmembrane":     tm_count,
                    "phobius_topology_short":      prediction,
                    "phobius_protein_length":      protein_length,
                    "PHOBIUS_tool_used":           args.tool_used,
                    "phobius_command_used":        args.command_used,
                    "PHOBIUS_database_used":       args.database_used,
                    "phobius_model_used":          args.model_used,
                    "input_path":                  args.input_path,
                    "output_path":                 args.output_path,
                })
                written_segments += 1

            top1_writer.writerow({
                "organism_name":               args.organism_name,
                "domain":                      args.domain,
                "feature_id":                  protein_id_first,
                "phobius_has_signal_peptide":  sp_flag,
                "phobius_signal_cleavage_pos": cleavage_str,
                "phobius_n_transmembrane":     tm_count,
                "phobius_n_segments":          n_segments,
                "phobius_topology_short":      prediction,
                "phobius_protein_length":      protein_length,
                "phobius_first_tm_start":      first_tm_start,
                "phobius_first_tm_end":        first_tm_end,
                "PHOBIUS_tool_used":           args.tool_used,
                "phobius_command_used":        args.command_used,
                "PHOBIUS_database_used":       args.database_used,
                "phobius_model_used":          args.model_used,
                "input_path":                  args.input_path,
                "output_path":                 args.output_path,
            })
            written_top1 += 1

    print(f"[process_phobius] Wrote {written_segments} segment rows -> {out_path}", file=sys.stderr)
    print(f"[process_phobius] Wrote {written_top1} protein rows    -> {top1_path}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
