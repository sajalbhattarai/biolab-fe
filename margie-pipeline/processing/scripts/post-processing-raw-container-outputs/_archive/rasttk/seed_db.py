"""seed_db.py -- loads db/rasttk/seed_database_long.tsv into in-memory SEED indexes.

The table has one row per (subsystem, role, variant) with 30 SEED_* columns: role /
variant membership, per-role chemistry (EC, ModelSEED, KEGG, stoichiometry),
per-subsystem curator metadata and per-variant reference-organism evidence.
"""

import csv
from collections import defaultdict
from pathlib import Path
from typing import Dict, List, Set, Tuple


# ---- Index container (plain dicts, JSON-friendly) ----

class SeedIndex:
    """All in-memory lookups built from seed_database_long.tsv."""

    def __init__(self) -> None:
        # role_lower -> subsystems that contain it
        self.role_to_subsystems: Dict[str, Set[str]] = defaultdict(set)

        # subsystem -> {variant_code -> expected role names (original case)}
        self.subsystem_variants: Dict[str, Dict[str, Set[str]]] = defaultdict(lambda: defaultdict(set))

        # subsystem -> known variant codes
        self.subsystem_known_variants: Dict[str, Set[str]] = defaultdict(set)

        # (subsystem, role_lower) -> per-role metadata dict
        #   role_abbreviation, ec_numbers, modelseed_*, kegg_*, reaction_stoichiometry
        self.role_meta: Dict[Tuple[str, str], Dict[str, str]] = {}

        # subsystem -> per-subsystem metadata dict
        #   superclass, class, subclass, curator, last_modified,
        #   description, legacy_description, curator_notes
        self.subsystem_meta: Dict[str, Dict[str, str]] = {}

        # (subsystem, variant_code) -> reference-organism evidence dict
        #   presence_status, variant_genome_count, variant_distinct_role_count
        self.subsystem_variant_ref: Dict[Tuple[str, str], Dict[str, str]] = {}

        # role_lower -> original-case spellings
        self.role_canonical: Dict[str, Set[str]] = defaultdict(set)


# ---- Loader ----

def load_seed_index(db_dir: Path) -> SeedIndex:
    """Loads seed_database_long.tsv from db_dir and builds all indexes."""
    db = Path(db_dir)
    long_file = db / "seed_database_long.tsv"

    if not long_file.exists():
        raise FileNotFoundError(f"missing: {long_file}")

    idx = SeedIndex()
    _load_long(long_file, idx)
    return idx


def _first_nonempty(existing: str, new: str) -> str:
    """Returns the existing value when non-empty, else the new one (both stripped)."""
    e = (existing or "").strip()
    if e:
        return e
    return (new or "").strip()


def _load_long(path: Path, idx: SeedIndex) -> None:
    """Builds all indexes from the merged 30-column seed_database_long.tsv."""
    with path.open(newline="", encoding="utf-8") as fh:
        r = csv.DictReader(fh, delimiter="\t")
        for row in r:
            sub     = (row.get("SEED_subsystem") or "").strip()
            role    = (row.get("SEED_role")      or "").strip()
            variant = (row.get("SEED_variant_code") or "").strip()
            if not sub or not role:
                continue
            rlow = role.lower()

            # --- role/variant membership indexes ---
            idx.role_to_subsystems[rlow].add(sub)
            idx.role_canonical[rlow].add(role)
            if variant:
                idx.subsystem_variants[sub][variant].add(role)
                idx.subsystem_known_variants[sub].add(variant)

            # --- per-(subsystem,role) chemistry + abbreviation ---
            # Keeps the first populated record; a role repeats across variants with the same chemistry.
            key = (sub, rlow)
            existing = idx.role_meta.get(key, {})
            chem_keys = [
                ("role_abbreviation",            "SEED_role_abbreviation"),
                ("ec_numbers",                   "SEED_ec_numbers"),
                ("modelseed_reaction_ids",       "SEED_reaction_ids"),
                ("modelseed_reaction_equations", "SEED_reaction_equations"),
                ("modelseed_compound_ids",       "SEED_modelseed_compound_ids"),
                ("modelseed_compound_names",     "SEED_modelseed_compound_names"),
                ("modelseed_compound_formulas",  "SEED_modelseed_compound_formulas"),
                ("kegg_reaction_ids",            "SEED_kegg_reaction_ids"),
                ("kegg_reaction_names",          "SEED_kegg_reaction_names"),
                ("kegg_reaction_definitions",    "SEED_kegg_reaction_definitions"),
                ("kegg_reaction_equations",      "SEED_kegg_reaction_equations"),
                ("kegg_compound_ids",            "SEED_kegg_compound_ids"),
                ("kegg_compound_names",          "SEED_kegg_compound_names"),
                ("reaction_stoichiometry",       "SEED_reaction_stoichiometry"),
            ]
            updated = dict(existing)
            for out_key, src_key in chem_keys:
                updated[out_key] = _first_nonempty(
                    existing.get(out_key, ""), row.get(src_key, ""))
            idx.role_meta[key] = updated

            # --- per-subsystem metadata ---
            smeta = idx.subsystem_meta.setdefault(sub, {})
            sm_keys = [
                ("superclass",         "SEED_superclass"),
                ("class",              "SEED_class"),
                ("subclass",           "SEED_subclass"),
                ("curator",            "SEED_author"),
                ("last_modified",      "SEED_last_modified"),
                ("description",        "SEED_web_description"),
                ("legacy_description", "SEED_sapling_description"),
            ]
            for out_key, src_key in sm_keys:
                smeta[out_key] = _first_nonempty(
                    smeta.get(out_key, ""), row.get(src_key, ""))
            existing_notes = smeta.get("curator_notes", "")
            extra_notes = " ".join(s for s in (
                (row.get("SEED_notes") or "").strip(),
                (row.get("SEED_hope_curation_notes") or "").strip(),
            ) if s)
            smeta["curator_notes"] = _first_nonempty(existing_notes, extra_notes)

            # --- per-(subsystem,variant) reference-organism evidence ---
            if variant:
                rk = (sub, variant)
                ref = idx.subsystem_variant_ref.setdefault(rk, {})
                for out_key, src_key in [
                    ("presence_status",             "SEED_presence_status"),
                    ("variant_genome_count",        "SEED_variant_genome_count"),
                    ("variant_distinct_role_count", "SEED_variant_distinct_role_count"),
                ]:
                    ref[out_key] = _first_nonempty(
                        ref.get(out_key, ""), row.get(src_key, ""))


# ---- Accessors (used by variant_detector and row_formatter) ----

def canonical_role(idx: SeedIndex, role_lower: str) -> str:
    """Returns one canonical original-case spelling for a role (first alphabetically)."""
    s = idx.role_canonical.get(role_lower)
    if not s:
        return role_lower
    return sorted(s)[0]
