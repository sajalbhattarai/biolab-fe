#!/usr/bin/env python3
"""
process_interpro_raw_results.py — Post-process InterProScan TSV output into
a normalised, pipeline-friendly per-domain TSV plus per-database split TSVs.

INPUT (written by the run step into <output_dir>/raw/interpro.tsv):
    InterProScan TSV (`-f TSV`). One row per domain hit. Columns:
        1  Protein accession           (feature_id)
        2  Sequence MD5 digest
        3  Sequence length
        4  Analysis source             (Pfam, CDD, TIGRFAM, PANTHER, ...)
        5  Signature accession         (e.g. PF00069)
        6  Signature description
        7  Match start
        8  Match end
        9  Score / E-value             (analysis-dependent; "-" for none)
       10  Status                      ("T" if true match)
       11  Date
       12  InterPro accession          (IPRxxxxxx)        — optional, "-"
       13  InterPro description                            — optional, "-"
       14  GO annotations              (when --goterms)    — optional
       15  Pathway annotations         (when --pathways)   — optional

OUTPUT (written under <output_dir>/processed/):
    interpro_results.tsv              — unified: one row per domain hit
    interpro_{db}_results.tsv         — one file per member database, e.g.:
        interpro_pfam_results.tsv
        interpro_tigrfam_results.tsv
        interpro_panther_results.tsv
        interpro_hamap_results.tsv
        interpro_pirsf_results.tsv
        interpro_gene3d_results.tsv
        interpro_cdd_results.tsv
        interpro_coils_results.tsv
        interpro_prints_results.tsv
        interpro_smart_results.tsv
        interpro_sfld_results.tsv
        interpro_superfamily_results.tsv
        interpro_ncbifam_results.tsv
        interpro_mobidb_results.tsv
        interpro_prosite_patterns_results.tsv
        interpro_prosite_profiles_results.tsv
        interpro_funfam_results.tsv

    Column layout for each per-database TSV:
        feature_id, organism_name
        INTERPRO_{DB}_id, INTERPRO_{DB}_description   — signature-level
        INTERPRO_id, INTERPRO_description              — shared InterPro entry
        INTERPRO_go_terms, INTERPRO_pathways           — from InterPro entry
        input_path, output_path                        — provenance paths
        INTERPRO_{DB}_command_used, _database_used, _analyses_used
        INTERPRO_{DB}_evalue, _match_start, _match_end — stats at end
"""
from __future__ import annotations

import argparse
import csv
import sys
from collections import defaultdict
from pathlib import Path
from typing import NamedTuple


class interproscan_domain_hit(NamedTuple):
    feature_id: str
    interpro_sequence_md5: str
    interpro_sequence_length: int
    interpro_analysis: str
    interpro_signature_accession: str
    interpro_signature_description: str
    interpro_match_start: int
    interpro_match_end: int
    interpro_score_or_evalue: str
    interpro_status: str
    interpro_date: str
    interpro_accession: str
    interpro_description: str
    interpro_go_terms: str
    interpro_pathways: str


INTERPRO_EMPTY_TOKENS = {"-", "", "N/A", "None"}


def normalise_optional_field(raw_value: str) -> str:
    if raw_value is None:
        return ""
    stripped_value = raw_value.strip()
    if stripped_value in INTERPRO_EMPTY_TOKENS:
        return ""
    return stripped_value


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


def parse_interproscan_tsv(interproscan_tsv_path: Path) -> list[interproscan_domain_hit]:
    parsed_records: list[interproscan_domain_hit] = []

    with open(interproscan_tsv_path) as input_file_handle:
        for raw_line in input_file_handle:
            stripped_line = raw_line.rstrip("\n")
            if not stripped_line:
                continue
            if stripped_line.lstrip().startswith("#"):
                continue

            split_fields = stripped_line.split("\t")
            if len(split_fields) < 11:
                continue

            def safe_field(column_index: int) -> str:
                if column_index < len(split_fields):
                    return split_fields[column_index]
                return ""

            parsed_records.append(interproscan_domain_hit(
                feature_id                     = safe_field(0).strip(),
                interpro_sequence_md5          = safe_field(1).strip(),
                interpro_sequence_length       = safely_convert_to_integer(safe_field(2)),
                interpro_analysis              = safe_field(3).strip(),
                interpro_signature_accession   = safe_field(4).strip(),
                interpro_signature_description = normalise_optional_field(safe_field(5)),
                interpro_match_start           = safely_convert_to_integer(safe_field(6)),
                interpro_match_end             = safely_convert_to_integer(safe_field(7)),
                interpro_score_or_evalue       = normalise_optional_field(safe_field(8)),
                interpro_status                = safe_field(9).strip(),
                interpro_date                  = safe_field(10).strip(),
                interpro_accession             = normalise_optional_field(safe_field(11)),
                interpro_description           = normalise_optional_field(safe_field(12)),
                interpro_go_terms              = normalise_optional_field(safe_field(13)),
                interpro_pathways              = normalise_optional_field(safe_field(14)),
            ))

    return parsed_records


# ── Unified output ─────────────────────────────────────────────────────────────

COLUMN_HEADER_ROW: list[str] = [
    "feature_id", "organism_name",
    "INTERPRO_analysis", "INTERPRO_signature_accession", "INTERPRO_signature_description",
    "INTERPRO_sequence_md5", "INTERPRO_sequence_length",
    "INTERPRO_match_start", "INTERPRO_match_end",
    "INTERPRO_score_or_evalue", "INTERPRO_status", "INTERPRO_date",
    "INTERPRO_accession", "INTERPRO_description",
    "INTERPRO_go_terms", "INTERPRO_pathways",
    "INTERPRO_command_used", "INTERPRO_database_used", "INTERPRO_analyses_used",
]


def write_unified_table(
    records: list[interproscan_domain_hit],
    output_path: Path,
    organism_name: str,
    command_used: str,
    database_used: str,
    analyses_used: str,
) -> int:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    sorted_records = sorted(
        records,
        key=lambda r: (r.feature_id, r.interpro_match_start, r.interpro_signature_accession),
    )
    n = 0
    with open(output_path, "w", newline="") as fh:
        writer = csv.writer(fh, delimiter="\t")
        writer.writerow(COLUMN_HEADER_ROW)
        for rec in sorted_records:
            writer.writerow([
                rec.feature_id, organism_name,
                rec.interpro_analysis,
                rec.interpro_signature_accession, rec.interpro_signature_description,
                rec.interpro_sequence_md5, rec.interpro_sequence_length,
                rec.interpro_match_start, rec.interpro_match_end,
                rec.interpro_score_or_evalue, rec.interpro_status, rec.interpro_date,
                rec.interpro_accession, rec.interpro_description,
                rec.interpro_go_terms, rec.interpro_pathways,
                command_used, database_used, analyses_used,
            ])
            n += 1
    return n


# ── Per-database split output ──────────────────────────────────────────────────
#
# Maps InterProScan analysis name → (output file basename, column prefix).
# All member databases use the INTERPRO_{DB} prefix for their signature columns
# so they are clearly distinct from standalone tools (e.g. standalone Pfam uses
# PFAM_*, while InterPro-via-Pfam uses INTERPRO_PFAM_*).

ANALYSIS_DB_MAP: dict[str, tuple[str, str]] = {
    "Hamap":             ("interpro_hamap",            "INTERPRO_HAMAP"),
    "TIGRFAM":           ("interpro_tigrfam",          "INTERPRO_TIGRFAM"),
    "NCBIfam":           ("interpro_ncbifam",          "INTERPRO_NCBIFAM"),
    "Pfam":              ("interpro_pfam",             "INTERPRO_PFAM"),
    "PANTHER":           ("interpro_panther",          "INTERPRO_PANTHER"),
    "PIRSF":             ("interpro_pirsf",            "INTERPRO_PIRSF"),
    "Gene3D":            ("interpro_gene3d",           "INTERPRO_GENE3D"),
    "CDD":               ("interpro_cdd",              "INTERPRO_CDD"),
    "Coils":             ("interpro_coils",            "INTERPRO_COILS"),
    "PRINTS":            ("interpro_prints",           "INTERPRO_PRINTS"),
    "SMART":             ("interpro_smart",            "INTERPRO_SMART"),
    "SFLD":              ("interpro_sfld",             "INTERPRO_SFLD"),
    "SUPERFAMILY":       ("interpro_superfamily",      "INTERPRO_SUPERFAMILY"),
    "MobiDBLite":        ("interpro_mobidb",           "INTERPRO_MOBIDB"),
    "ProSitePatterns":   ("interpro_prosite_patterns", "INTERPRO_PROSITE_PATTERNS"),
    "ProSiteProfiles":   ("interpro_prosite_profiles", "INTERPRO_PROSITE_PROFILES"),
    "FunFam":            ("interpro_funfam",           "INTERPRO_FUNFAM"),
}


def _db_columns(prefix: str, has_evalue: bool = True) -> list[str]:
    """Column header for a per-database split TSV.

    Layout:
        feature_id, organism_name
        {PREFIX}_id, {PREFIX}_description   — signature-level annotation
        INTERPRO_id, INTERPRO_description   — shared InterPro entry
        INTERPRO_go_terms, INTERPRO_pathways
        input_path, output_path             — provenance paths
        {PREFIX}_command_used, _database_used, _analyses_used
        {PREFIX}_evalue (if applicable), _match_start, _match_end   — stats at end
    """
    cols = [
        "feature_id", "organism_name",
        f"{prefix}_id",
        f"{prefix}_description",
        "INTERPRO_id",
        "INTERPRO_description",
        "INTERPRO_go_terms",
        "INTERPRO_pathways",
        "input_path",
        "output_path",
        f"{prefix}_command_used",
        f"{prefix}_database_used",
        f"{prefix}_analyses_used",
    ]
    if has_evalue:
        cols.append(f"{prefix}_evalue")
    cols += [f"{prefix}_match_start", f"{prefix}_match_end"]
    return cols


# Databases that do not produce an evalue / score in InterProScan output.
_NO_EVALUE = {"INTERPRO_COILS", "INTERPRO_MOBIDB"}


def write_per_database_tables(
    records: list[interproscan_domain_hit],
    output_dir: Path,
    organism_name: str,
    command_used: str,
    database_used: str,
    analyses_used: str,
    input_path: str,
    output_path: str,
) -> dict[str, int]:
    """Split unified records by analysis and write one TSV per database."""
    by_analysis: dict[str, list[interproscan_domain_hit]] = defaultdict(list)
    for rec in records:
        by_analysis[rec.interpro_analysis].append(rec)

    counts: dict[str, int] = {}
    for analysis, hits in sorted(by_analysis.items()):
        if analysis not in ANALYSIS_DB_MAP:
            continue
        basename, prefix = ANALYSIS_DB_MAP[analysis]
        has_evalue = prefix not in _NO_EVALUE
        out_path = output_dir / f"{basename}_results.tsv"
        cols = _db_columns(prefix, has_evalue=has_evalue)

        sorted_hits = sorted(
            hits,
            key=lambda r: (r.feature_id, r.interpro_match_start, r.interpro_signature_accession),
        )
        n = 0
        with open(out_path, "w", newline="") as fh:
            writer = csv.DictWriter(fh, fieldnames=cols, delimiter="\t",
                                    extrasaction="ignore", lineterminator="\n")
            writer.writeheader()
            for rec in sorted_hits:
                row: dict[str, str | int] = {
                    "feature_id":              rec.feature_id,
                    "organism_name":           organism_name,
                    f"{prefix}_id":            rec.interpro_signature_accession,
                    f"{prefix}_description":   rec.interpro_signature_description,
                    "INTERPRO_id":             rec.interpro_accession,
                    "INTERPRO_description":    rec.interpro_description,
                    "INTERPRO_go_terms":       rec.interpro_go_terms,
                    "INTERPRO_pathways":       rec.interpro_pathways,
                    "input_path":              input_path,
                    "output_path":             output_path,
                    f"{prefix}_command_used":  command_used,
                    f"{prefix}_database_used": database_used,
                    f"{prefix}_analyses_used": analyses_used,
                    f"{prefix}_match_start":   rec.interpro_match_start,
                    f"{prefix}_match_end":     rec.interpro_match_end,
                }
                if has_evalue:
                    row[f"{prefix}_evalue"] = rec.interpro_score_or_evalue
                writer.writerow(row)
                n += 1
        counts[basename] = n
    return counts


# ── CLI ────────────────────────────────────────────────────────────────────────

def parse_command_line_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True,
                        help="Path to raw InterProScan TSV output (interpro.tsv)")
    parser.add_argument("--output", required=True,
                        help="Path to write unified processed TSV (interpro_results.tsv)")
    parser.add_argument("--output-dir", required=False, default=None,
                        help="Directory for per-database split TSVs (defaults to --output parent)")
    parser.add_argument("--output-top1", required=False, default=None,
                        help="Deprecated — ignored")
    parser.add_argument("--organism-name", required=True,
                        help="Organism name to record on every row")
    parser.add_argument("--command-used", required=False, default="",
                        help="Exact interproscan.sh command line (provenance)")
    parser.add_argument("--database-used", required=False, default="",
                        help="InterProScan installation directory (provenance)")
    parser.add_argument("--analyses-used", required=False, default="",
                        help="--applications value passed to InterProScan (provenance)")
    parser.add_argument("--input-path", required=False, default="",
                        help="Input FASTA path (provenance; recorded in per-db TSVs)")
    parser.add_argument("--output-path", required=False, default="",
                        help="Output directory path (provenance; recorded in per-db TSVs)")
    return parser.parse_args()


def main() -> None:
    args = parse_command_line_arguments()

    input_path = Path(args.input)
    if not input_path.exists():
        print(f"[process_interpro] ERROR: input not found: {input_path}", file=sys.stderr)
        raise SystemExit(1)

    all_records = parse_interproscan_tsv(input_path)

    # Write unified table
    main_output_path = Path(args.output)
    n_unified = write_unified_table(
        all_records, main_output_path,
        args.organism_name, args.command_used, args.database_used, args.analyses_used,
    )
    print(f"[process_interpro] Wrote {n_unified} rows → {main_output_path}")

    # Write per-database split tables
    out_dir = Path(args.output_dir) if args.output_dir else main_output_path.parent
    out_dir.mkdir(parents=True, exist_ok=True)
    db_counts = write_per_database_tables(
        all_records, out_dir,
        args.organism_name, args.command_used, args.database_used, args.analyses_used,
        args.input_path, args.output_path,
    )
    for basename, count in sorted(db_counts.items()):
        print(f"[process_interpro] Wrote {count} rows → {out_dir}/{basename}_results.tsv")


if __name__ == "__main__":
    main()
