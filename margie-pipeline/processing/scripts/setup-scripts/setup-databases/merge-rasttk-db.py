#!/usr/bin/env python3
"""merge-rasttk-db.py — merges the db/rasttk source files into two canonical outputs.

Adds SEED_superclass and SEED_subsystem_id (from subsystem_mapping_wide.tsv) and
SEED_reaction_stoichiometry (from seed_database.json) to seed_database_long.tsv,
adds the first two to seed_database.json (both rewritten via .tmp + rename), and
deletes subsystem_mapping.tsv and seed_database_wide.tsv, which the outputs absorb.

Usage: python3 merge-rasttk-db.py [db/rasttk/]   (default: db/rasttk/ under the project root)
"""
from __future__ import annotations

import csv
import json
import os
import re
import sys
from pathlib import Path


# ---- Helpers ----

def _norm(s: str) -> str:
    """Lowercases and collapses whitespace for fuzzy subsystem-name matching."""
    return re.sub(r"\s+", " ", s.strip().lower())


def _build_stoich_cell(reactions: list) -> str:
    """Encodes a JSON role's SEED_reactions as compact JSON ('' when empty).

    Keeps only what the flat TSV lacks: ModelSEED reaction_side + stoich_coeff and KEGG formulas.
    """
    if not reactions:
        return ""
    out = []
    for rxn in reactions:
        if not isinstance(rxn, dict):
            continue
        entry: dict = {"rxn": rxn.get("SEED_reaction_id", "")}

        mseed = rxn.get("SEED_modelseed_compounds") or []
        if mseed:
            entry["mseed_cpds"] = [
                {
                    "id":     c.get("SEED_compound_id", ""),
                    "side":   c.get("SEED_reaction_side", ""),
                    "stoich": c.get("SEED_stoich_coeff", ""),
                }
                for c in mseed if isinstance(c, dict)
            ]

        kegg_rxns = rxn.get("SEED_kegg_reactions") or []
        kegg_formulas: dict[str, dict] = {}
        for kr in kegg_rxns:
            if not isinstance(kr, dict):
                continue
            for kc in kr.get("SEED_kegg_compounds") or []:
                if not isinstance(kc, dict):
                    continue
                kid = kc.get("SEED_kegg_compound_id", "")
                if kid:
                    kegg_formulas[kid] = {
                        "name":    kc.get("SEED_kegg_compound_name", ""),
                        "formula": kc.get("SEED_kegg_compound_formula", ""),
                    }
        if kegg_formulas:
            entry["kegg_cpds"] = kegg_formulas

        out.append(entry)

    return json.dumps(out, separators=(",", ":"), ensure_ascii=False) if out else ""


# ---- Step 1 — build superclass/subsystem_id lookup from subsystem_mapping_wide ----

def load_wide_lookup(wide_path: Path) -> dict[str, dict]:
    """Maps normalised subsystem name -> {superclass, subsystem_id}."""
    lookup: dict[str, dict] = {}
    if not wide_path.exists():
        print(f"  [warn] {wide_path.name} not found — SEED_superclass and "
              "SEED_subsystem_id will be empty", file=sys.stderr)
        return lookup
    with wide_path.open(encoding="utf-8") as fh:
        for row in csv.DictReader(fh, delimiter="\t"):
            name = row.get("subsystem_name", "").strip()
            if not name:
                continue
            lookup[_norm(name)] = {
                "superclass":   row.get("superclass", "").strip(),
                "subsystem_id": row.get("subsystem_id", "").strip(),
            }
    print(f"  loaded {len(lookup):,} subsystem entries from {wide_path.name}")
    return lookup


# ---- Step 2 — build (sub, role_lower) -> stoich cell from seed_database.json ----

def load_stoich_lookup(json_path: Path) -> dict[tuple, str]:
    """Maps (subsystem, lowercased role) -> compact JSON stoichiometry string."""
    print(f"  loading {json_path.name} …", end=" ", flush=True)
    with json_path.open(encoding="utf-8") as fh:
        data = json.load(fh)
    print(f"{len(data):,} subsystems")

    lookup: dict[tuple, str] = {}
    for item in data:
        sub = (item.get("SEED_subsystem") or "").strip()
        for variant in item.get("SEED_variants") or []:
            for role in variant.get("SEED_roles") or []:
                rname = (role.get("SEED_role") or "").strip()
                if not rname:
                    continue
                key = (sub, rname.lower())
                if key not in lookup:
                    cell = _build_stoich_cell(role.get("SEED_reactions") or [])
                    lookup[key] = cell
    print(f"  built stoich lookup for {len(lookup):,} (subsystem, role) pairs")
    return lookup


# ---- Step 3 — write enhanced seed_database_long.tsv ----

NEW_LONG_COLS = ["SEED_superclass", "SEED_subsystem_id", "SEED_reaction_stoichiometry"]


def write_long(long_path: Path, wide_lookup: dict, stoich_lookup: dict) -> None:
    """Rewrites seed_database_long.tsv with the three NEW_LONG_COLS appended."""
    tmp = long_path.with_suffix(".tsv.tmp")
    rows_written = supclass_hits = stoich_hits = 0

    with long_path.open(encoding="utf-8") as src, \
         tmp.open("w", encoding="utf-8", newline="") as dst:

        reader = csv.DictReader(src, delimiter="\t")
        original_cols = reader.fieldnames or []
        new_cols = [c for c in NEW_LONG_COLS if c not in original_cols]
        writer = csv.DictWriter(
            dst, fieldnames=original_cols + new_cols,
            delimiter="\t", extrasaction="ignore", lineterminator="\n",
        )
        writer.writeheader()

        for row in reader:
            sub  = (row.get("SEED_subsystem") or "").strip()
            role = (row.get("SEED_role")      or "").strip()

            wide = wide_lookup.get(_norm(sub), {})
            row["SEED_superclass"]   = wide.get("superclass", "")
            row["SEED_subsystem_id"] = wide.get("subsystem_id", "")
            if wide.get("superclass"):
                supclass_hits += 1

            stoich = stoich_lookup.get((sub, role.lower()), "")
            row["SEED_reaction_stoichiometry"] = stoich
            if stoich:
                stoich_hits += 1

            writer.writerow(row)
            rows_written += 1

    tmp.replace(long_path)
    print(f"  wrote {rows_written:,} rows to {long_path.name}")
    print(f"    SEED_superclass populated:          {supclass_hits:,} / {rows_written:,} rows")
    print(f"    SEED_reaction_stoichiometry filled: {stoich_hits:,} / {rows_written:,} rows")


# ---- Step 4 — write enhanced seed_database.json ----

def write_json(json_path: Path, wide_lookup: dict) -> None:
    """Rewrites seed_database.json with SEED_superclass and SEED_subsystem_id per subsystem."""
    print(f"  loading {json_path.name} for rewrite …", end=" ", flush=True)
    with json_path.open(encoding="utf-8") as fh:
        data = json.load(fh)
    print(f"{len(data):,} subsystems")

    hits = 0
    for item in data:
        sub  = (item.get("SEED_subsystem") or "").strip()
        wide = wide_lookup.get(_norm(sub), {})
        item["SEED_superclass"]   = wide.get("superclass", "")
        item["SEED_subsystem_id"] = wide.get("subsystem_id", "")
        if wide.get("superclass"):
            hits += 1

    # Keeps the original formatting (indent=2).
    tmp = json_path.with_suffix(".json.tmp")
    with tmp.open("w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2, ensure_ascii=False)
        fh.write("\n")
    tmp.replace(json_path)
    print(f"  wrote {len(data):,} subsystems to {json_path.name}")
    print(f"    SEED_superclass populated: {hits:,} / {len(data):,} subsystems")


# ---- Step 5 — delete now-redundant files ----

REDUNDANT = ["subsystem_mapping.tsv", "seed_database_wide.tsv"]


def delete_redundant(db: Path) -> None:
    """Deletes the files absorbed into the two outputs."""
    for name in REDUNDANT:
        p = db / name
        if p.exists():
            p.unlink()
            print(f"  deleted {name}")
        else:
            print(f"  (already gone) {name}")


# ---- Main ----

def main() -> None:
    """Runs the lookups, both rewrites and the cleanup for the given db/rasttk directory."""
    if len(sys.argv) > 1:
        db = Path(sys.argv[1]).resolve()
    else:
        # Defaults to db/rasttk/ under the project root.
        here = Path(__file__).resolve().parent
        db = here.parent.parent.parent.parent / "db" / "rasttk"

    if not db.is_dir():
        print(f"error: db directory not found: {db}", file=sys.stderr)
        sys.exit(1)

    print(f"\n=== merge-rasttk-db  db={db} ===\n")

    wide_path  = db / "subsystem_mapping_wide.tsv"
    json_path  = db / "seed_database.json"
    long_path  = db / "seed_database_long.tsv"

    for p in [json_path, long_path]:
        if not p.exists():
            print(f"error: required input missing: {p}", file=sys.stderr)
            sys.exit(1)

    print("[1/4] loading subsystem_mapping_wide …")
    wide_lookup = load_wide_lookup(wide_path)

    print("\n[2/4] building stoichiometry lookup from seed_database.json …")
    stoich_lookup = load_stoich_lookup(json_path)

    print("\n[3/4] writing enhanced seed_database_long.tsv …")
    write_long(long_path, wide_lookup, stoich_lookup)

    print("\n[4/4] writing enhanced seed_database.json …")
    write_json(json_path, wide_lookup)

    print("\n[5/5] deleting redundant files …")
    delete_redundant(db)

    print("\n=== done ===")
    print(f"  seed_database_long.tsv  — 30 cols (+SEED_superclass, +SEED_subsystem_id, +SEED_reaction_stoichiometry)")
    print(f"  seed_database.json      — +SEED_superclass, +SEED_subsystem_id per subsystem")
    print(f"  subsystem_mapping.tsv   — deleted (data in seed_database_long)")
    print(f"  seed_database_wide.tsv  — deleted (pivotable from seed_database_long)")


if __name__ == "__main__":
    main()
