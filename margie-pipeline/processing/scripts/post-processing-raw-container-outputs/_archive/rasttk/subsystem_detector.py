"""subsystem_detector.py -- maps RAStTK role descriptions to SEED subsystems.

Tokenises RAST_description into bare role names and resolves each row's subsystems,
from RAST_BVBRC_Name when known, else by strict case-insensitive role match
(SeedIndex.role_to_subsystems). The only module that decides a row's subsystems.
"""

import re
from typing import List, Set

from seed_db import SeedIndex


# ---- Tokenisation ----

_SPLIT_RE = re.compile(r'\s*[@/;]\s*')
_EC_RE    = re.compile(r'\s*\(EC\s+[\d\.\-]+\)')


def tokenize_description(desc: str) -> List[str]:
    """Splits RAST_description on '/', '@' and ';' into role tokens, dropping '(EC ...)' qualifiers."""
    if not desc:
        return []
    out: List[str] = []
    for tok in _SPLIT_RE.split(desc):
        tok = _EC_RE.sub('', tok).strip()
        if tok:
            out.append(tok)
    return out


# ---- Subsystem lookup ----

def subsystems_for_row(row: dict, idx: SeedIndex) -> Set[str]:
    """Returns the subsystems this row contributes to.

    Uses RAST_BVBRC_Name when it is a known subsystem; otherwise matches every
    RAST_description token against the SEED role index (case-insensitive).
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
    """Returns the first role token of the row that belongs to <sub> (for the role-in-subsystem cell)."""
    desc = (row.get("RAST_description") or "").strip()
    for tok in tokenize_description(desc):
        if sub in idx.role_to_subsystems.get(tok.lower(), ()):
            return tok
    return ""
