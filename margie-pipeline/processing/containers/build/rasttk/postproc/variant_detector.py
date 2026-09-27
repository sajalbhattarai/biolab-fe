"""variant_caller.py -- query-organism-centric SEED variant calling.

Two-pass design (the caller invokes both):

  Pass 1: scan_genome(rast_rows)
        Walks every row of the rast TSV once and builds:
            roles_in_genome : role_lower -> list of (feature_id, RAST_description)
        Roles are extracted from RAST_description by splitting on the
        multi-function separators '/', '@', ';' and stripping trailing
        '(EC ...)' annotations. Strict case-insensitive match against
        SeedIndex.role_to_subsystems is used downstream.

  Pass 2: call_variants(roles_in_genome, seed_index)
        For every subsystem touched by at least one detected role:
          - enumerate every known variant of that subsystem
          - compute detected_roles = expected_roles(variant) ∩ roles_in_genome
          - rank variants by coverage = |detected| / |expected|, descending
          - emit a SubsystemCall capturing all variants tied for the best
            coverage (variants sharing the top score; not just "ambiguous"
            -- per user direction, we list every plausible variant)
"""
from __future__ import annotations

from collections import defaultdict
from dataclasses import dataclass, field
from typing import Dict, List, Set, Tuple

from seed_db import SeedIndex, canonical_role
from subsystem_detector import tokenize_description  # re-export for callers


# ---------------------------------------------------------------------------
# Per-subsystem call record
# ---------------------------------------------------------------------------

@dataclass
class SubsystemCall:
    """Query-organism variant call for one subsystem.

    All role lists hold ORIGINAL-CASE role names (from SEED, not RAStTK),
    so downstream cells render consistently regardless of how RAStTK spelt
    the role.

    detected_features maps role_lower -> list of feature_ids in the query
    genome that carry that role (one role may map to multiple paralogues).
    """
    subsystem: str
    known_variants: List[str] = field(default_factory=list)
    # the union of roles detected across ALL variants of this subsystem
    detected_roles: List[str] = field(default_factory=list)
    detected_features: Dict[str, List[str]] = field(default_factory=dict)
    # per-variant tallies (sorted descending by coverage)
    variant_tally: List["VariantTally"] = field(default_factory=list)
    # the variant(s) tied for best coverage (== variant_tally[0].coverage)
    called_variants: List["VariantTally"] = field(default_factory=list)
    coverage: str = ""             # "3/4" wrt the best variant's expected set
    coverage_fraction: float = 0.0  # numeric form
    status: str = ""                # complete | partial | no-match


@dataclass
class VariantTally:
    variant_code: str
    expected_roles: List[str] = field(default_factory=list)
    detected_roles: List[str] = field(default_factory=list)
    coverage: str = ""
    coverage_fraction: float = 0.0


# ---------------------------------------------------------------------------
# Pass 1
# ---------------------------------------------------------------------------

def scan_genome(rast_rows) -> Dict[str, List[Tuple[str, str]]]:
    """Build role_lower -> [(feature_id, original_role_token)] from every row."""
    roles: Dict[str, List[Tuple[str, str]]] = defaultdict(list)
    for row in rast_rows:
        fid  = (row.get("feature_id")  or "").strip()
        desc = (row.get("RAST_description") or "").strip()
        if not fid or not desc:
            continue
        for tok in tokenize_description(desc):
            roles[tok.lower()].append((fid, tok))
    return roles


# ---------------------------------------------------------------------------
# Pass 2
# ---------------------------------------------------------------------------

def call_variants(roles_in_genome: Dict[str, List[Tuple[str, str]]],
                  idx: SeedIndex) -> Dict[str, SubsystemCall]:
    """Compute per-subsystem variant calls for every subsystem touched."""
    # Which subsystems are touched by at least one detected role?
    touched: Set[str] = set()
    for role_lower in roles_in_genome:
        touched.update(idx.role_to_subsystems.get(role_lower, ()))

    calls: Dict[str, SubsystemCall] = {}
    for sub in sorted(touched):
        call = SubsystemCall(subsystem=sub)
        variants = idx.subsystem_variants.get(sub, {})
        call.known_variants = sorted(variants.keys(),
                                     key=lambda v: (_variant_sort_key(v), v))

        # roles detected in this subsystem (union across variants)
        detected_lower: Set[str] = set()
        for variant_code, expected_roles in variants.items():
            expected_lower = {r.lower() for r in expected_roles}
            inter = expected_lower & roles_in_genome.keys()
            detected_lower.update(inter)

            vt = VariantTally(
                variant_code=variant_code,
                expected_roles=sorted(expected_roles, key=str.lower),
                detected_roles=sorted(
                    (canonical_role(idx, rl) for rl in inter),
                    key=str.lower,
                ),
            )
            n_exp = len(expected_roles)
            n_det = len(inter)
            vt.coverage = f"{n_det}/{n_exp}"
            vt.coverage_fraction = (n_det / n_exp) if n_exp else 0.0
            call.variant_tally.append(vt)

        call.detected_roles = sorted(
            (canonical_role(idx, rl) for rl in detected_lower),
            key=str.lower,
        )
        call.detected_features = {
            rl: [fid for fid, _ in roles_in_genome.get(rl, [])]
            for rl in detected_lower
        }

        # rank variants: coverage_fraction desc, then variant_code asc
        call.variant_tally.sort(
            key=lambda vt: (-vt.coverage_fraction, _variant_sort_key(vt.variant_code), vt.variant_code)
        )

        if call.variant_tally:
            best = call.variant_tally[0]
            call.called_variants = [vt for vt in call.variant_tally
                                    if vt.coverage_fraction == best.coverage_fraction
                                    and vt.coverage_fraction > 0]
            # Coverage of THIS subsystem is reported wrt the best variant.
            call.coverage          = best.coverage
            call.coverage_fraction = best.coverage_fraction
            if best.coverage_fraction >= 1.0:
                call.status = "complete"
            elif best.coverage_fraction > 0:
                call.status = "partial"
            else:
                call.status = "no-match"
        else:
            call.status = "no-match"

        calls[sub] = call
    return calls


def _variant_sort_key(v: str):
    """Sort variants numerically when possible: 1, 1.1, 1.2, 2, ..., then -1, *1 etc."""
    try:
        # negative variants (e.g. -1) sort last among numeric
        f = float(v)
        return (0, f)
    except (TypeError, ValueError):
        return (1, v)
