"""row_formatter.py -- per-row cell formatting for the enriched rast.tsv.

All display-convention rules live here so the row-emitter in
`enrich-rast-tsv.py` stays declarative.

Conventions (locked with the user):
  - ' | ' between subsystems within a single cell
  - '; ' between inner items inside a per-subsystem segment
  - ',' is NEVER used inside a value (it would collide with CSV-ish parsing
    downstream); when we list feature IDs we use commas internally, but
    they're wrapped in parentheses so the outer parser never sees a bare
    comma.
  - Every per-subsystem segment is prefixed with '<subsystem>: '
  - Empty segments are dropped (we never emit 'subsystem: ' with nothing
    after the colon)

Output columns (in order):
  §1 already in the input tsv (organism, domain, feature_id,
     RAST_*, ...)
  §2 SUBSYSTEM_COLS         -- subsystem identity + variant call
  §3 CHEMISTRY_COLS         -- EC / ModelSEED / KEGG reaction & compound
  §4 REFERENCE_COLS         -- reference-organism variant evidence

This module exports the column-name lists too so the writer can stitch
the final header in the correct order.
"""
from __future__ import annotations

from typing import Dict, List

from seed_db import SeedIndex, canonical_role
from variant_detector import SubsystemCall


SEG_SEP   = " | "
INNER_SEP = "; "


# ---------------------------------------------------------------------------
# Column layout
# ---------------------------------------------------------------------------

# Logical order within the subsystem block: identity -> hierarchy ->
# role context -> role-coverage evidence -> variant inventory ->
# variant call -> catalog / curation provenance.
SUBSYSTEM_COLS = [
    # identity
    "subsystem_names",
    # local SEED hierarchy (parallel to RAST_BVBRC_*)
    "subsystem_superclass",
    "subsystem_class",
    "subsystem_subclass",
    # this role's place inside each subsystem
    "subsystem_role_in_subsystem",
    # role inventory + presence evidence
    "subsystem_expected_roles",
    "subsystem_roles_detected",
    "subsystem_role_coverage",
    "subsystem_role_coverage_fraction",
    # variant inventory -> variant call
    "subsystem_known_variants",
    "subsystem_called_variants",
    "subsystem_variant_call_status",
    # catalog / curation provenance
    "subsystem_curator",
    "subsystem_last_modified",
    "subsystem_description",
    "subsystem_curator_notes",
    "subsystem_legacy_description",
]
CHEMISTRY_COLS = [
    "ec_numbers",
    "modelseed_reaction_ids",
    "modelseed_reaction_equations",
    "modelseed_compound_ids",
    "modelseed_compound_names",
    "modelseed_compound_formulas",
    "kegg_reaction_ids",
    "kegg_reaction_names",
    "kegg_reaction_definitions",
    "kegg_reaction_equations",
    "kegg_compound_ids",
    "kegg_compound_names",
]
REFERENCE_COLS = [
    "reference_variant_codes",
    "reference_variant_presence_status",
    "reference_variant_genome_count",
    "reference_variant_distinct_role_count",
]
ENRICHED_COLS = SUBSYSTEM_COLS + CHEMISTRY_COLS + REFERENCE_COLS


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def seg(subsystem: str, value: str) -> str:
    """Format one '<subsystem>: <value>' segment; empty value -> empty segment."""
    if value is None or value == "":
        return ""
    return f"{subsystem}: {value}"


def join_segments(segments: List[str]) -> str:
    return SEG_SEP.join(s for s in segments if s)


def variant_sort_key(v: str):
    """Sort variants numerically when possible: 0, 1, 1.1, 2, ..., then '-1', '*1'."""
    try:
        return (0, float(v))
    except (TypeError, ValueError):
        return (1, v)


# ---------------------------------------------------------------------------
# Per-subsystem inner-cell formatters
# ---------------------------------------------------------------------------

def format_called_variants(call: SubsystemCall) -> str:
    """e.g. '1 (FolA; FolB; FolK), 2 (FolA; FolB)'."""
    if not call.called_variants:
        return ""
    pieces: List[str] = []
    for vt in call.called_variants:
        if vt.detected_roles:
            pieces.append(f"{vt.variant_code} ({INNER_SEP.join(vt.detected_roles)})")
        else:
            pieces.append(vt.variant_code)
    return ", ".join(pieces)


def format_expected_roles(call: SubsystemCall) -> str:
    """Roles required by the called (or, if no call, the largest known) variant."""
    if call.called_variants:
        roles = call.called_variants[0].expected_roles
    elif call.variant_tally:
        roles = max(call.variant_tally, key=lambda v: len(v.expected_roles)).expected_roles
    else:
        return ""
    if not roles:
        return ""
    return f"{INNER_SEP.join(roles)} (total: {len(roles)})"


def format_roles_detected(call: SubsystemCall) -> str:
    """e.g. 'FolA (fig|...peg.7); FolB (fig|...peg.12) (2/4)'."""
    if not call.detected_roles:
        return ""
    items: List[str] = []
    for role in call.detected_roles:
        rl = role.lower()
        features = call.detected_features.get(rl, [])
        if features:
            seen = set(); ordered = []
            for f in features:
                if f not in seen:
                    seen.add(f); ordered.append(f)
            items.append(f"{role} ({','.join(ordered)})")
        else:
            items.append(role)
    return f"{INNER_SEP.join(items)} ({call.coverage})"


def format_reference_evidence(idx: SeedIndex, sub: str, key: str) -> str:
    """e.g. '1: present; -1: absent' (variant_code -> field value)."""
    variants = sorted(idx.subsystem_known_variants.get(sub, ()),
                      key=lambda v: (variant_sort_key(v), v))
    parts: List[str] = []
    for v in variants:
        ref = idx.subsystem_variant_ref.get((sub, v), {})
        val = (ref.get(key, "") or "").strip()
        parts.append(f"{v}: {val}" if val else f"{v}:")
    return INNER_SEP.join(parts)


def role_in_subsystem_cell(role_token: str, sub: str, idx: SeedIndex) -> str:
    """'<canonical role name> [abbr: <SEED abbreviation>]' when known."""
    if not role_token:
        return ""
    rl = role_token.lower()
    canon = canonical_role(idx, rl)
    meta = idx.role_meta.get((sub, rl), {})
    abbr = (meta.get("role_abbreviation") or "").strip()
    return f"{canon} [abbr: {abbr}]" if abbr else canon


def first_role_chemistry(role_tokens: List[str], idx: SeedIndex) -> Dict[str, str]:
    """Take the first role token whose chemistry is populated; emit those cells.

    Chemistry (ModelSEED + KEGG + EC) is a per-role property, not a
    per-subsystem one, so we only fill it once per row.
    """
    for tok in role_tokens:
        rl = tok.lower()
        for sub in sorted(idx.role_to_subsystems.get(rl, ())):
            meta = idx.role_meta.get((sub, rl))
            if meta and any(meta.get(k) for k in CHEMISTRY_COLS):
                return {k: meta.get(k, "") for k in CHEMISTRY_COLS}
    return {k: "" for k in CHEMISTRY_COLS}
