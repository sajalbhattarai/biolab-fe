#!/usr/bin/env python3
"""Infer envelope type from upstream annotation descriptor text.

Implements explicit diderm/monoderm marker sets with a minimal
high-confidence subset, using weighted evidence from processed outputs of:
  - tigrfam
  - pgap
  - pfam
  - uniprot
"""

from __future__ import annotations

import argparse
import csv
import json
import re
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path

TOOLS = ("tigrfam", "pgap", "pfam", "uniprot")


@dataclass(frozen=True)
class Marker:
    marker_id: str
    classes: str
    category: str
    patterns: tuple[str, ...]
    high_confidence: bool = False


# Marker catalog specified by user.
MARKERS: tuple[Marker, ...] = (
    # Diderm: outer membrane biogenesis
    Marker("bamA", "diderm", "outer_membrane_biogenesis", (r"\bbamA\b",), True),
    Marker("bamB", "diderm", "outer_membrane_biogenesis", (r"\bbamB\b",)),
    Marker("bamC", "diderm", "outer_membrane_biogenesis", (r"\bbamC\b",)),
    Marker("bamD", "diderm", "outer_membrane_biogenesis", (r"\bbamD\b",)),
    Marker("bamE", "diderm", "outer_membrane_biogenesis", (r"\bbamE\b",)),
    Marker("omp85", "diderm", "outer_membrane_biogenesis", (r"\bomp85\b",), True),

    # Diderm: lipid A and LPS biosynthesis
    Marker("lpxA", "diderm", "lipidA_lps_biosynthesis", (r"\blpxA\b",)),
    Marker("lpxB", "diderm", "lipidA_lps_biosynthesis", (r"\blpxB\b",)),
    Marker("lpxC", "diderm", "lipidA_lps_biosynthesis", (r"\blpxC\b",), True),
    Marker("lpxD", "diderm", "lipidA_lps_biosynthesis", (r"\blpxD\b",)),
    Marker("lpxH", "diderm", "lipidA_lps_biosynthesis", (r"\blpxH\b",)),
    Marker("lpxK", "diderm", "lipidA_lps_biosynthesis", (r"\blpxK\b",)),
    Marker("kdtA_waaA", "diderm", "lipidA_lps_biosynthesis", (r"\bkdtA\b", r"\bwaaA\b"), True),

    # Diderm: LPS transport
    Marker("lptA", "diderm", "lps_transport", (r"\blptA\b",)),
    Marker("lptB", "diderm", "lps_transport", (r"\blptB\b",)),
    Marker("lptC", "diderm", "lps_transport", (r"\blptC\b",)),
    Marker("lptD", "diderm", "lps_transport", (r"\blptD\b",), True),
    Marker("lptE", "diderm", "lps_transport", (r"\blptE\b",)),
    Marker("lptF", "diderm", "lps_transport", (r"\blptF\b",)),
    Marker("lptG", "diderm", "lps_transport", (r"\blptG\b",)),

    # Diderm: outer membrane lipoprotein trafficking
    Marker("lolA", "diderm", "lipoprotein_trafficking", (r"\blolA\b",)),
    Marker("lolB", "diderm", "lipoprotein_trafficking", (r"\blolB\b",)),
    Marker("lolC", "diderm", "lipoprotein_trafficking", (r"\blolC\b",)),
    Marker("lolD", "diderm", "lipoprotein_trafficking", (r"\blolD\b",)),
    Marker("lolE", "diderm", "lipoprotein_trafficking", (r"\blolE\b",)),

    # Diderm: outer membrane proteins and porins
    Marker("ompA", "diderm", "outer_membrane_proteins", (r"\bompA\b",)),
    Marker("ompC", "diderm", "outer_membrane_proteins", (r"\bompC\b",)),
    Marker("ompF", "diderm", "outer_membrane_proteins", (r"\bompF\b",)),
    Marker("ompW", "diderm", "outer_membrane_proteins", (r"\bompW\b",)),
    Marker("ompX", "diderm", "outer_membrane_proteins", (r"\bompX\b",)),

    # Monoderm: wall teichoic acid biosynthesis
    Marker("tagA", "monoderm", "wall_teichoic_acid", (r"\btagA\b",), True),
    Marker("tagB", "monoderm", "wall_teichoic_acid", (r"\btagB\b",)),
    Marker("tagD", "monoderm", "wall_teichoic_acid", (r"\btagD\b",)),
    Marker("tagF", "monoderm", "wall_teichoic_acid", (r"\btagF\b",)),
    Marker("tagO", "monoderm", "wall_teichoic_acid", (r"\btagO\b",), True),

    # Monoderm: lipoteichoic acid biosynthesis
    Marker("ltaS", "monoderm", "lipoteichoic_acid", (r"\bltaS\b",), True),
    Marker("ltaA", "monoderm", "lipoteichoic_acid", (r"\bltaA\b",)),
    Marker("yfnI", "monoderm", "lipoteichoic_acid", (r"\byfnI\b",)),

    # Monoderm: D-alanylation
    Marker("dltA", "monoderm", "d_alanylation", (r"\bdltA\b",)),
    Marker("dltB", "monoderm", "d_alanylation", (r"\bdltB\b",), True),
    Marker("dltC", "monoderm", "d_alanylation", (r"\bdltC\b",)),
    Marker("dltD", "monoderm", "d_alanylation", (r"\bdltD\b",)),

    # Monoderm: sortase anchoring
    Marker("srtA", "monoderm", "sortase_anchoring", (r"\bsrtA\b",), True),
    Marker("srtB", "monoderm", "sortase_anchoring", (r"\bsrtB\b",)),
    Marker("srtC", "monoderm", "sortase_anchoring", (r"\bsrtC\b",)),
    Marker("srtD", "monoderm", "sortase_anchoring", (r"\bsrtD\b",)),

    # Monoderm: pilus-associated proteins
    Marker("spaA", "monoderm", "pilus_associated", (r"\bspaA\b",)),
    Marker("spaB", "monoderm", "pilus_associated", (r"\bspaB\b",)),
    Marker("spaC", "monoderm", "pilus_associated", (r"\bspaC\b",)),
    Marker("spaD", "monoderm", "pilus_associated", (r"\bspaD\b",)),
    Marker("spaE", "monoderm", "pilus_associated", (r"\bspaE\b",)),
    Marker("spaF", "monoderm", "pilus_associated", (r"\bspaF\b",)),

    # Monoderm: actinobacterial markers
    Marker("pks13", "monoderm", "actinobacterial_monoderm", (r"\bpks13\b",)),
    Marker("fadD32", "monoderm", "actinobacterial_monoderm", (r"\bfadD32\b",)),
    Marker("accD4", "monoderm", "actinobacterial_monoderm", (r"\baccD4\b",)),
    Marker("kasA", "monoderm", "actinobacterial_monoderm", (r"\bkasA\b",)),
    Marker("kasB", "monoderm", "actinobacterial_monoderm", (r"\bkasB\b",)),
    Marker("mmaA1", "monoderm", "actinobacterial_monoderm", (r"\bmmaA1\b",)),
    Marker("mmaA2", "monoderm", "actinobacterial_monoderm", (r"\bmmaA2\b",)),
    Marker("mmaA3", "monoderm", "actinobacterial_monoderm", (r"\bmmaA3\b",)),
    Marker("mmaA4", "monoderm", "actinobacterial_monoderm", (r"\bmmaA4\b",)),

    # Additional motifs/domains
    Marker("LPXTG", "monoderm", "motif_or_domain", (r"lpxtg",), True),
    Marker("SLH_domain", "monoderm", "motif_or_domain", (r"\bslh\b", r"s-layer homology")),
    Marker("CWB2_domain", "monoderm", "motif_or_domain", (r"\bcwb2\b",)),
)

MARKER_REGEX: dict[str, tuple[re.Pattern[str], ...]] = {
    m.marker_id: tuple(re.compile(p, flags=re.IGNORECASE) for p in m.patterns)
    for m in MARKERS
}
MARKER_BY_ID = {m.marker_id: m for m in MARKERS}


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser()
    p.add_argument("--input-dir", required=True)
    p.add_argument("--raw-output", required=True)
    p.add_argument("--summary-output", required=True)
    p.add_argument("--organism-name", required=True)
    p.add_argument("--domain", required=True)
    return p.parse_args()


def descriptor_columns(fieldnames: list[str]) -> list[str]:
    keys = []
    for f in fieldnames:
        lf = f.lower()
        if any(token in lf for token in ("desc", "description", "function", "product", "annotation", "name", "title", "gene", "symbol", "locus")):
            keys.append(f)
    return keys


def _normalized(s: str) -> str:
    return (s or "").strip().lower()


def _path_matches_organism(proc_dir: Path, organism_name: str) -> bool:
    name = _normalized(organism_name)
    if not name or name in {"unknown", "na", "n/a"}:
        return True

    parent = _normalized(proc_dir.parent.name)
    if name == parent or name in parent:
        return True

    return name in _normalized(str(proc_dir))


def iter_tool_processed_dirs(input_dir: Path, tool: str, organism_name: str) -> list[Path]:
    """Find processed directories for a tool across flat and nested layouts.

    Supported layouts include:
      1) <input>/<tool>/processed
      2) <input>/<tool>/<domain>/<organism>/processed
      3) Any deeper nested variant under <input>/<tool>
      4) <input>/<tool>/<tool>_results.tsv directly, with no processed/
         nesting at all -- the flat layout margie_sb's own clean per-genome
         output tree actually uses (see _shared.py's discover_tool_tables()
         in workflow_tools/consolidation/ for the same convention), which is
         what this script is really invoked against via run_envelope's -i.
    """
    seen: set[Path] = set()
    candidates: list[Path] = []

    # Preferred fast-path: expected layout under <input>/<tool>/...
    tool_root = input_dir / tool
    if tool_root.exists():
        direct = tool_root / "processed"
        if direct.is_dir() and direct not in seen:
            candidates.append(direct)
            seen.add(direct)

        for p in sorted(tool_root.rglob("processed")):
            if not p.is_dir() or p in seen:
                continue
            candidates.append(p)
            seen.add(p)

    # Universal fallback: discover any processed dir whose ancestry contains
    # the required tool folder name anywhere under the configured input root.
    if not candidates:
        for p in sorted(input_dir.rglob("processed")):
            if not p.is_dir() or p in seen:
                continue
            parent_names = {part.lower() for part in p.parts}
            if tool.lower() not in parent_names:
                continue
            candidates.append(p)
            seen.add(p)

    # Flat-tree fallback: no processed/ subdirectory exists anywhere under
    # margie_sb's clean output tree, so the tool's own root folder IS the
    # right place to look -- only reached when neither layout above found
    # anything, so this can never double-count against a real processed/ dir.
    if not candidates and tool_root.exists() and any(tool_root.glob("*.tsv")):
        candidates.append(tool_root)
        seen.add(tool_root)

    if not candidates:
        return []

    matched = [p for p in candidates if _path_matches_organism(p, organism_name)]
    # If strict organism filtering removes everything, fall back to all tool dirs.
    return matched if matched else candidates


def marker_hits(text: str) -> list[Marker]:
    hits = []
    for marker in MARKERS:
        for rgx in MARKER_REGEX[marker.marker_id]:
            if rgx.search(text):
                hits.append(marker)
                break
    return hits


def score_marker(marker: Marker) -> int:
    if marker.high_confidence:
        return 5
    if marker.category == "motif_or_domain":
        return 2
    return 3


def _first_nonempty(rec: dict[str, str], keys: tuple[str, ...]) -> str:
    for k in keys:
        v = rec.get(k, "")
        if v not in (None, ""):
            return str(v)
    return ""


def _tool_feature_id(rec: dict[str, str]) -> str:
    return _first_nonempty(
        rec,
        (
            "feature_id",
            "Feature_ID",
            "ID",
            "qseqid",
        ),
    )


def _tool_start_end_strand(tool: str, rec: dict[str, str]) -> tuple[str, str, str]:
    tool_u = tool.upper()
    start = _first_nonempty(
        rec,
        (
            f"{tool_u}_alignment_from",
            f"{tool_u}_envelope_from",
            f"{tool_u}_hmm_from",
            "start",
            "Start",
        ),
    )
    end = _first_nonempty(
        rec,
        (
            f"{tool_u}_alignment_to",
            f"{tool_u}_envelope_to",
            f"{tool_u}_hmm_to",
            "end",
            "End",
        ),
    )
    strand = _first_nonempty(rec, ("strand", "Strand", "STRAND"))
    return start, end, strand


def _tool_id_desc(tool: str, rec: dict[str, str]) -> tuple[str, str]:
    if tool == "tigrfam":
        return rec.get("TIGRFAM_id", ""), _first_nonempty(rec, ("TIGRFAM_description", "TIGRFAM_name"))
    if tool == "pfam":
        return rec.get("PFAM_id", ""), _first_nonempty(rec, ("PFAM_description", "PFAM_name"))
    if tool == "pgap":
        return rec.get("PGAP_id", ""), _first_nonempty(rec, ("PGAP_description", "PGAP_name"))
    if tool == "uniprot":
        return _first_nonempty(rec, ("UNIPROT_accession", "UNIPROT_subject_id")), _first_nonempty(
            rec,
            ("UNIPROT_protein_name", "UNIPROT_subject_title", "UNIPROT_entry_name"),
        )
    return "", ""


def infer_type(
    diderm_score: int,
    monoderm_score: int,
    diderm_hc: int,
    monoderm_hc: int,
    domain: str,
) -> tuple[str, str]:
    """Returns (envelope_type, inference_basis). inference_basis records
    *how* the call was made, since envelope_type alone can't distinguish
    a real evidence-based call from the conservative default -- e.g.
    Mycoplasma genitalium (wall-less: zero marker hits on both sides)
    gets the same "diderm-gram-negative-like" envelope_type as a genuine
    Gram-negative organism, but basis=default_no_evidence instead of
    score_majority/high_confidence_markers."""
    d = (domain or "").strip().lower()
    if d == "archaea":
        return "archaea", "archaea_domain"

    # High-confidence precedence when one side is clearly dominant.
    if diderm_hc >= 2 and monoderm_hc == 0:
        return "diderm-gram-negative-like", "high_confidence_markers"
    if monoderm_hc >= 2 and diderm_hc == 0:
        return "monoderm-gram-positive-like", "high_confidence_markers"

    if diderm_score > monoderm_score:
        return "diderm-gram-negative-like", "score_majority"
    if monoderm_score > diderm_score:
        return "monoderm-gram-positive-like", "score_majority"

    # Conservative tie-breaker -- no clear winner, including the literal
    # zero-evidence case (wall-less organisms, or genuinely no hits at all).
    return "diderm-gram-negative-like", "default_no_evidence"


def main() -> int:
    args = parse_args()
    input_dir = Path(args.input_dir)
    raw_output = Path(args.raw_output)
    summary_output = Path(args.summary_output)
    raw_output.parent.mkdir(parents=True, exist_ok=True)
    summary_output.parent.mkdir(parents=True, exist_ok=True)

    raw_rows: list[dict[str, str]] = []
    filtered_rows_by_tool: dict[str, list[dict[str, str]]] = defaultdict(list)
    filtered_headers_by_tool: dict[str, list[str]] = {}
    processed_rows: list[dict[str, str]] = []
    diderm_total = 0
    monoderm_total = 0
    diderm_hc_total = 0
    monoderm_hc_total = 0
    unique_diderm: set[str] = set()
    unique_monoderm: set[str] = set()

    for tool in TOOLS:
        proc_dirs = iter_tool_processed_dirs(input_dir, tool, args.organism_name)
        if not proc_dirs:
            continue

        for proc_dir in proc_dirs:
            for tsv in sorted(proc_dir.rglob("*.tsv")):
                with tsv.open("r", encoding="utf-8", newline="") as handle:
                    reader = csv.DictReader(handle, delimiter="\t")
                    if not reader.fieldnames:
                        continue
                    if tool not in filtered_headers_by_tool:
                        filtered_headers_by_tool[tool] = list(reader.fieldnames)
                    dcols = descriptor_columns(reader.fieldnames)
                    for idx, rec in enumerate(reader, start=1):
                        parts = [rec.get(c, "") for c in dcols] if dcols else ["\t".join(rec.values())]
                        text = " | ".join([p for p in parts if p])
                        if not text:
                            continue

                        hits = marker_hits(text)
                        if not hits:
                            continue

                        for marker in hits:
                            weight = score_marker(marker)
                            if marker.classes == "diderm":
                                diderm_total += weight
                                unique_diderm.add(marker.marker_id)
                                if marker.high_confidence:
                                    diderm_hc_total += 1
                            else:
                                monoderm_total += weight
                                unique_monoderm.add(marker.marker_id)
                                if marker.high_confidence:
                                    monoderm_hc_total += 1

                            raw_rows.append(
                                {
                                    "tool": tool,
                                    "file": str(tsv),
                                    "row": str(idx),
                                    "marker_id": marker.marker_id,
                                    "marker_class": marker.classes,
                                    "category": marker.category,
                                    "high_confidence": str(marker.high_confidence).lower(),
                                    "weight": str(weight),
                                    "snippet": text[:300],
                                }
                            )

                            filtered_row = dict(rec)
                            filtered_row["ENVELOPE_marker_id"] = marker.marker_id
                            filtered_row["ENVELOPE_marker_class"] = marker.classes
                            filtered_row["ENVELOPE_marker_category"] = marker.category
                            filtered_row["ENVELOPE_marker_weight"] = str(weight)
                            filtered_rows_by_tool[tool].append(filtered_row)

                            start, end, strand = _tool_start_end_strand(tool, rec)
                            tigrfam_id, tigrfam_desc = ("", "")
                            pfam_id, pfam_desc = ("", "")
                            pgap_id, pgap_desc = ("", "")
                            uniprot_id, uniprot_desc = ("", "")
                            tool_id, tool_desc = _tool_id_desc(tool, rec)
                            if tool == "tigrfam":
                                tigrfam_id, tigrfam_desc = tool_id, tool_desc
                            elif tool == "pfam":
                                pfam_id, pfam_desc = tool_id, tool_desc
                            elif tool == "pgap":
                                pgap_id, pgap_desc = tool_id, tool_desc
                            elif tool == "uniprot":
                                uniprot_id, uniprot_desc = tool_id, tool_desc

                            processed_rows.append(
                                {
                                    "organism": args.organism_name,
                                    "domain": args.domain,
                                    "envelope": marker.classes,
                                    "feature_id": _tool_feature_id(rec),
                                    "strand": strand,
                                    "start": start,
                                    "end": end,
                                    "TIGRFAM_id": tigrfam_id,
                                    "TIGRFAM_description": tigrfam_desc,
                                    "PFAM_id": pfam_id,
                                    "PFAM_description": pfam_desc,
                                    "PGAP_id": pgap_id,
                                    "PGAP_description": pgap_desc,
                                    "UNIPROT_id": uniprot_id,
                                    "UNIPROT_description": uniprot_desc,
                                    "what_genes": marker.marker_id,
                                }
                            )

    envelope_type, inference_basis = infer_type(
        diderm_total,
        monoderm_total,
        diderm_hc_total,
        monoderm_hc_total,
        args.domain,
    )

    with raw_output.open("w", encoding="utf-8", newline="") as out:
        w = csv.DictWriter(
            out,
            fieldnames=[
                "tool",
                "file",
                "row",
                "marker_id",
                "marker_class",
                "category",
                "high_confidence",
                "weight",
                "snippet",
            ],
            delimiter="\t",
        )
        w.writeheader()
        for r in raw_rows:
            w.writerow(r)

    evidence = {
        "unique_diderm_markers": sorted(unique_diderm),
        "unique_monoderm_markers": sorted(unique_monoderm),
        "diderm_high_confidence_hits": diderm_hc_total,
        "monoderm_high_confidence_hits": monoderm_hc_total,
    }

    diderm_requirements = sorted(m.marker_id for m in MARKERS if m.classes == "diderm")
    monoderm_requirements = sorted(m.marker_id for m in MARKERS if m.classes == "monoderm")

    processed_output = summary_output.parent / "envelope_results.tsv"
    with processed_output.open("w", encoding="utf-8", newline="") as out:
        fieldnames = [
            "organism",
            "domain",
            "envelope",
            "feature_id",
            "strand",
            "start",
            "end",
            "TIGRFAM_id",
            "TIGRFAM_description",
            "PFAM_id",
            "PFAM_description",
            "PGAP_id",
            "PGAP_description",
            "UNIPROT_id",
            "UNIPROT_description",
            "what_genes",
            "DIDERM_gene_requirements",
            "MONDERM_gene_requirements",
            "DIDERM_gene_hits",
            "MONODERM_gene_hits",
            "DIDERM_genescore",
            "MONODERM_gene_score",
            "Decision",
            "inference_basis",
        ]
        w = csv.DictWriter(out, fieldnames=fieldnames, delimiter="\t")
        w.writeheader()
        for rec in processed_rows:
            row = dict(rec)
            row["DIDERM_gene_requirements"] = ",".join(diderm_requirements)
            row["MONDERM_gene_requirements"] = ",".join(monoderm_requirements)
            row["DIDERM_gene_hits"] = ",".join(sorted(unique_diderm))
            row["MONODERM_gene_hits"] = ",".join(sorted(unique_monoderm))
            row["DIDERM_genescore"] = str(diderm_total)
            row["MONODERM_gene_score"] = str(monoderm_total)
            row["Decision"] = envelope_type
            row["inference_basis"] = inference_basis
            w.writerow(row)

    for tool, rows in filtered_rows_by_tool.items():
        if not rows:
            continue
        out_tsv = raw_output.parent / f"{tool}_marker_hits.tsv"
        headers = list(filtered_headers_by_tool.get(tool, []))
        for extra in ("ENVELOPE_marker_id", "ENVELOPE_marker_class", "ENVELOPE_marker_category", "ENVELOPE_marker_weight"):
            if extra not in headers:
                headers.append(extra)
        with out_tsv.open("w", encoding="utf-8", newline="") as out:
            w = csv.DictWriter(out, fieldnames=headers, delimiter="\t")
            w.writeheader()
            for row in rows:
                w.writerow(row)

    with summary_output.open("w", encoding="utf-8", newline="") as out:
        fieldnames = [
            "organism",
            "domain",
            "envelope_type",
            "diderm_score",
            "monoderm_score",
            "diderm_high_conf_hits",
            "monoderm_high_conf_hits",
            "signals_count",
            "inference_basis",
            "evidence_json",
        ]
        w = csv.DictWriter(out, fieldnames=fieldnames, delimiter="\t")
        w.writeheader()
        w.writerow(
            {
                "organism": args.organism_name,
                "domain": args.domain,
                "envelope_type": envelope_type,
                "diderm_score": diderm_total,
                "monoderm_score": monoderm_total,
                "diderm_high_conf_hits": diderm_hc_total,
                "monoderm_high_conf_hits": monoderm_hc_total,
                "signals_count": len(raw_rows),
                "inference_basis": inference_basis,
                "evidence_json": json.dumps(evidence, sort_keys=True),
            }
        )

    print(f"diderm_score={diderm_total}")
    print(f"monoderm_score={monoderm_total}")
    print(f"diderm_high_conf_hits={diderm_hc_total}")
    print(f"monoderm_high_conf_hits={monoderm_hc_total}")
    print(f"signals={len(raw_rows)}")
    print(f"envelope_type={envelope_type}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
