#!/usr/bin/env python3
"""enrich-rast-tsv.py -- enriches rast.tsv files with query-organism SEED variant calls (CLI).

Pass 1 (variant_detector.scan_genome) maps roles to features, pass 2 (call_variants)
calls each subsystem's variant genome-wide, and pass 3 stamps every row with the calls
of its subsystems (row_formatter). SEED data comes from seed_db, role matching from
subsystem_detector.

Usage:
  enrich-rast-tsv.py --db /path/to/db/rasttk --rast-tsv /path/to/rast.tsv
  enrich-rast-tsv.py --db /path/to/db/rasttk --root /path/to/output/rasttk
"""

import argparse
import csv
import shutil
import sys
from pathlib import Path
from typing import Dict

sys.path.insert(0, str(Path(__file__).resolve().parent))
from seed_db import SeedIndex, load_seed_index                         # noqa: E402
from subsystem_detector import (                                        # noqa: E402
    role_token_for_subsystem,
    subsystems_for_row,
    tokenize_description,
)
from variant_detector import SubsystemCall, call_variants, scan_genome  # noqa: E402
import row_formatter as rf                                              # noqa: E402


# ---- Per-row enrichment ----

def _order_subs(subs, calls: Dict[str, SubsystemCall]):
    """Orders subsystems by coverage (descending), then alphabetically."""
    def k(sub: str):
        c = calls.get(sub)
        return (-(c.coverage_fraction if c else 0.0), sub)
    return sorted(subs, key=k)


def enrich_row(row: dict, idx: SeedIndex,
               calls: Dict[str, SubsystemCall]) -> dict:
    """Returns the row with the subsystem, chemistry and reference cells filled in."""
    subs = _order_subs(subsystems_for_row(row, idx), calls)

    seg = {col: [] for col in rf.SUBSYSTEM_COLS}
    ref = {col: [] for col in rf.REFERENCE_COLS}

    for sub in subs:
        call  = calls.get(sub) or SubsystemCall(subsystem=sub)
        smeta = idx.subsystem_meta.get(sub, {})
        role  = role_token_for_subsystem(row, sub, idx)

        seg["subsystem_names"].append(sub)
        seg["subsystem_superclass"].append(
            rf.seg(sub, (row.get("RAST_BVBRC_Superclass") or "").strip()))
        seg["subsystem_class"].append(rf.seg(sub, smeta.get("class", "")))
        seg["subsystem_subclass"].append(rf.seg(sub, smeta.get("subclass", "")))
        seg["subsystem_role_in_subsystem"].append(
            rf.seg(sub, rf.role_in_subsystem_cell(role, sub, idx)))
        seg["subsystem_known_variants"].append(
            rf.seg(sub, rf.INNER_SEP.join(call.known_variants)))
        seg["subsystem_expected_roles"].append(
            rf.seg(sub, rf.format_expected_roles(call)))
        seg["subsystem_roles_detected"].append(
            rf.seg(sub, rf.format_roles_detected(call)))
        seg["subsystem_role_coverage"].append(rf.seg(sub, call.coverage))
        seg["subsystem_role_coverage_fraction"].append(
            rf.seg(sub, f"{call.coverage_fraction:.2f}" if call.coverage_fraction else ""))
        seg["subsystem_called_variants"].append(
            rf.seg(sub, rf.format_called_variants(call)))
        seg["subsystem_variant_call_status"].append(rf.seg(sub, call.status))
        seg["subsystem_curator"].append(rf.seg(sub, smeta.get("curator", "")))
        seg["subsystem_last_modified"].append(rf.seg(sub, smeta.get("last_modified", "")))
        seg["subsystem_description"].append(rf.seg(sub, smeta.get("description", "")))
        seg["subsystem_curator_notes"].append(rf.seg(sub, smeta.get("curator_notes", "")))
        seg["subsystem_legacy_description"].append(
            rf.seg(sub, smeta.get("legacy_description", "")))

        ref["reference_variant_codes"].append(
            rf.seg(sub, rf.INNER_SEP.join(call.known_variants)))
        ref["reference_variant_presence_status"].append(
            rf.seg(sub, rf.format_reference_evidence(idx, sub, "presence_status")))
        ref["reference_variant_genome_count"].append(
            rf.seg(sub, rf.format_reference_evidence(idx, sub, "variant_genome_count")))
        ref["reference_variant_distinct_role_count"].append(
            rf.seg(sub, rf.format_reference_evidence(idx, sub, "variant_distinct_role_count")))

    out = dict(row)
    for col in rf.SUBSYSTEM_COLS:
        out[col] = rf.join_segments(seg[col])
    chem = rf.first_role_chemistry(
        tokenize_description((row.get("RAST_description") or "").strip()),
        idx,
    )
    for col, val in chem.items():
        out[col] = val
    for col in rf.REFERENCE_COLS:
        out[col] = rf.join_segments(ref[col])
    return out


# ---- File-level orchestration ----

def enrich_file(rast_tsv: Path, idx: SeedIndex):
    """Backs up one rast.tsv to .bak, runs the three passes and rewrites it in place."""
    bak = rast_tsv.with_suffix(rast_tsv.suffix + ".bak")
    if not bak.exists():
        shutil.copy2(rast_tsv, bak)

    with bak.open(newline='', encoding='utf-8') as fh:
        reader = csv.DictReader(fh, delimiter='\t')
        rows = list(reader)
        orig_fields = reader.fieldnames or []

    roles_in_genome = scan_genome(rows)                # pass 1
    calls           = call_variants(roles_in_genome, idx)  # pass 2

    out_fields = [c for c in orig_fields if c not in rf.ENRICHED_COLS]
    out_fields.extend(rf.ENRICHED_COLS)

    matched = 0
    enriched_rows = []
    for row in rows:                                   # pass 3
        er = enrich_row(row, idx, calls)
        if er.get("subsystem_names"):
            matched += 1
        enriched_rows.append(er)

    with rast_tsv.open("w", newline='', encoding='utf-8') as fh:
        writer = csv.DictWriter(fh, fieldnames=out_fields, delimiter='\t',
                                lineterminator='\n', extrasaction='ignore')
        writer.writeheader()
        writer.writerows(enriched_rows)
    return len(rows), matched, len(calls)


# ---- CLI ----

def main(argv=None):
    """Enriches one --rast-tsv, or every rast*.tsv under --root."""
    p = argparse.ArgumentParser(
        description="Enrich a rast.tsv (or a tree of them) with SEED variant calls"
    )
    p.add_argument("--db", required=True,
                   help="db/rasttk directory containing subsystem_mapping.tsv and seed_database_long.tsv")
    src = p.add_mutually_exclusive_group(required=True)
    src.add_argument("--rast-tsv", help="single rast.tsv to enrich")
    src.add_argument("--root",     help="directory to recurse; enriches every rast*.tsv found")
    args = p.parse_args(argv)

    db = Path(args.db)
    print(f"[enrich] loading SEED index from {db}", file=sys.stderr)
    idx = load_seed_index(db)
    print(f"[enrich] index: "
          f"{sum(len(v) for v in idx.subsystem_variants.values())} (subsystem,variant) pairs, "
          f"{len(idx.role_to_subsystems)} unique roles, "
          f"{len(idx.subsystem_meta)} subsystems with metadata",
          file=sys.stderr)

    if args.rast_tsv:
        files = [Path(args.rast_tsv)]
    else:
        root = Path(args.root); seen = set(); files = []
        for pat in ("rast.tsv", "rast_*.tsv"):
            for f in root.rglob(pat):
                # Skips backups and archived legacy copies.
                if f.name.endswith(".bak") or ".legacy" in f.name or f in seen:
                    continue
                seen.add(f); files.append(f)
        files.sort()
    if not files:
        print("[enrich] no rast.tsv files found.", file=sys.stderr)
        return 1

    grand_rows = grand_matched = 0
    for f in files:
        n, m, c = enrich_file(f, idx)
        pct = (100.0 * m / n) if n else 0.0
        print(f"  {f}: {m}/{n} rows enriched ({pct:.1f}%); "
              f"{c} subsystems called genome-wide", file=sys.stderr)
        grand_rows += n; grand_matched += m
    print(f"[enrich] done. {len(files)} file(s); "
          f"{grand_matched}/{grand_rows} rows enriched.", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
