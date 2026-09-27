"""subsystem_detector.py -- map RAStTK role descriptions to SEED subsystems.

Two concerns live here:
  (1) Tokenisation -- splitting a RAStTK `RAST_description` into bare role
      tokens (RAStTK joins multi-function annotations with '/', '@', ';',
      and often appends '(EC ...)' qualifiers).
  (2) Subsystem lookup -- given a role token, what SEED subsystems contain
      it? Resolution order:
        a. RAST_BVBRC_Name itself (if RAStTK populated it and the name
           is known to our index)
        b. Strict case-insensitive match against the role column of
           db/rasttk/subsystem_mapping.tsv (via SeedIndex.role_to_subsystems)

This is the ONLY module that decides "which subsystem(s) does this row
contribute to?" — keeping that logic isolated makes it easy to swap in a
fuzzier matcher later if we ever want one.
"""
from __future__ import annotations

import re
from typing import List, Set

from seed_db import SeedIndex


# ---------------------------------------------------------------------------
# Tokenisation
# ---------------------------------------------------------------------------

_SPLIT_RE = re.compile(r'\s*[@/;]\s*')
_EC_RE    = re.compile(r'\s*\(EC\s+[\d\.\-]+\)')


def tokenize_description(desc: str) -> List[str]:
    """Split RAST_description into candidate role-name tokens.

    RAStTK joins multi-function annotations with '/', '@' and ';', and
    qualifies many of them with a trailing '(EC X.X.X.X)'. We strip the
    EC qualifier so the bare role-name can be matched against SEED's role
    column verbatim (case-insensitive).
    """
    if not desc:
        return []
    out: List[str] = []
    for tok in _SPLIT_RE.split(desc):
        tok = _EC_RE.sub('', tok).strip()
        if tok:
            out.append(tok)
    return out


# ---------------------------------------------------------------------------
# Subsystem lookup
# ---------------------------------------------------------------------------

def subsystems_for_row(row: dict, idx: SeedIndex) -> Set[str]:
    """Return the set of subsystems this row contributes to.

    Resolution order:
      1. RAST_BVBRC_Name (if non-empty AND known to our index)
      2. Strict role-name match for every token of RAST_description

    The two paths are mutually exclusive: if RAStTK already supplied a
    subsystem, we trust it and skip the role-only fallback.
    """
    rast_sub = (row.get("RAST_BVBRC_Name") or "").strip()
    if rast_sub and rast_sub in idx.subsystem_variants:
        return {rast_sub}

    found: Set[str] = set()
    desc = (row.get("RAST_description") or "").strip()
    for tok in tokenize_description(desc):
        found.update(idx.role_to_subsystems.get(tok.lower(), ()))
    return found


def role_token_for_subsystem(row: dict, sub: str, idx: SeedIndex) -> str:
    """Return the FIRST role token from this row that belongs to <sub>.

    Used to answer "which of my role tokens is the one tying me to this
    particular subsystem?" so the per-row `subsystem_role_in_subsystem`
    cell can name it explicitly.
    """
    desc = (row.get("RAST_description") or "").strip()
    for tok in tokenize_description(desc):
        if sub in idx.role_to_subsystems.get(tok.lower(), ()):
            return tok
    return ""
