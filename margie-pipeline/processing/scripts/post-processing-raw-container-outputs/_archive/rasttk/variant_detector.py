"""variant_detector.py -- query-organism SEED variant calling in two passes.

scan_genome() maps every role found in RAST_description to its features; call_variants()
scores each touched subsystem's variants by coverage (|detected| / |expected roles|)
and keeps every variant tied for the best score.
"""

from collections import defaultdict
from dataclasses import dataclass, field
from typing import Dict, List, Set, Tuple

from seed_db import SeedIndex, canonical_role
from subsystem_detector import tokenize_description  # Re-exported for callers.


# ---- Per-subsystem call record ----

@dataclass
class SubsystemCall:
    """Query-organism variant call for one subsystem.

    Role lists hold SEED original-case names; detected_features maps
    role_lower -> feature_ids carrying that role (paralogues included).
    """
    subsystem: str
    known_variants: List[str] = field(default_factory=list)
    # Union of roles detected across all variants.
    detected_roles: List[str] = field(default_factory=list)
    detected_features: Dict[str, List[str]] = field(default_factory=dict)
    # Per-variant tallies, by coverage descending.
    variant_tally: List["VariantTally"] = field(default_factory=list)
    # Variants tied for the best coverage.
    called_variants: List["VariantTally"] = field(default_factory=list)
    coverage: str = ""             # e.g. "3/4" of the best variant's expected roles
    coverage_fraction: float = 0.0
    status: str = ""                # complete | partial | no-match


@dataclass
class VariantTally:
    """Expected and detected roles, and coverage, for one variant."""
    variant_code: str
    expected_roles: List[str] = field(default_factory=list)
    detected_roles: List[str] = field(default_factory=list)
    coverage: str = ""
    coverage_fraction: float = 0.0


# ---- Pass 1 ----

def scan_genome(rast_rows) -> Dict[str, List[Tuple[str, str]]]:
    """Builds role_lower -> [(feature_id, original role token)] from every row (pass 1)."""
    roles: Dict[str, List[Tuple[str, str]]] = defaultdict(list)
    for row in rast_rows:
        fid  = (row.get("feature_id")  or "").strip()
        desc = (row.get("RAST_description") or "").strip()
        if not fid or not desc:
            continue
        for tok in tokenize_description(desc):
            roles[tok.lower()].append((fid, tok))
    return roles


# ---- Pass 2 ----

def call_variants(roles_in_genome: Dict[str, List[Tuple[str, str]]],
                  idx: SeedIndex) -> Dict[str, SubsystemCall]:
    """Computes the variant call of every subsystem touched by a detected role (pass 2)."""
    # Subsystems touched by at least one detected role.
    touched: Set[str] = set()
    for role_lower in roles_in_genome:
        touched.update(idx.role_to_subsystems.get(role_lower, ()))

    calls: Dict[str, SubsystemCall] = {}
    for sub in sorted(touched):
        call = SubsystemCall(subsystem=sub)
        variants = idx.subsystem_variants.get(sub, {})
        call.known_variants = sorted(variants.keys(),
                                     key=lambda v: (_variant_sort_key(v), v))

        # Roles detected in this subsystem (union across variants).
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

        # Ranks variants by coverage_fraction descending, then variant_code.
        call.variant_tally.sort(
            key=lambda vt: (-vt.coverage_fraction, _variant_sort_key(vt.variant_code), vt.variant_code)
        )

        if call.variant_tally:
            best = call.variant_tally[0]
            call.called_variants = [vt for vt in call.variant_tally
                                    if vt.coverage_fraction == best.coverage_fraction
                                    and vt.coverage_fraction > 0]
            # Subsystem coverage is reported against the best variant.
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
    """Sorts variants numerically where possible: 1, 1.1, 1.2, 2, ..., then -1, *1."""
    try:
        # Negative variants (e.g. -1) sort last among numeric ones.
        f = float(v)
        return (0, f)
    except (TypeError, ValueError):
        return (1, v)
