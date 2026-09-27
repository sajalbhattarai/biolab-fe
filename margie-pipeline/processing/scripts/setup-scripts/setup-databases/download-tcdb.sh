#!/usr/bin/env bash
# download-tcdb.sh — downloads the TCDB transporter sequences and builds the DIAMOND index (inside the container).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/lib.sh"
tag="download-tcdb"
db_parse_args "$@"

# ---- licence gate ---------------------------------------------------------
# Runs before the skip check so the acceptance record is always written.
licence_gate tcdb TCDB_ACCEPT_LICENCE --accept-tcdb-licence \
    "./setup.sh --databases-only --tool tcdb --accept-tcdb-licence" <<'NOTICE' || exit 0
  ================================================================
  WHY LICENSING MATTERS FOR TCDB
  ================================================================
  The Transporter Classification Database (TCDB) is curated by the
  Saier Lab at UC San Diego and provides a comprehensive classification
  system for membrane transport proteins. It is freely accessible for
  academic and non-profit research, but commercial use requires
  prior written permission. Please read the exact terms below.

  ── DATABASES ────────────────────────────────────────────────────

  ┌─ TCDB 2024 (transporter classification, Saier Lab UCSD) ──── ⚠️
  │ Licence quoted from https://www.tcdb.org/ (acceptable-use policy):
  │
  │   "TCDB is provided free of charge for academic and non-profit
  │    use, subject to proper citation of the database in any
  │    resulting publication. Commercial use of the data requires
  │    prior written permission from the Saier Lab."
  │
  │ * ACADEMIC / non-profit use: FREE. Citation REQUIRED.
  │ * COMMERCIAL use: REQUIRES prior WRITTEN PERMISSION from the
  │                   Saier Lab BEFORE use.
  │   Contact: Milton Saier, msaier@ucsd.edu
  │            UC San Diego, Department of Molecular Biology
  │
  │ The TCDB FASTA is not bundled in this pipeline. Each user
  │ must download it from https://www.tcdb.org/download.php.
  │
  │ Citation: Saier M.H. Jr et al. (2021) Nucleic Acids Research
  │           49(D1):D461-D467. doi:10.1093/nar/gkaa1004
  └────────────────────────────────────────────────────────────────

  ── TOOLS ────────────────────────────────────────────────────────

  ┌─ DIAMOND 2.1.9 (used to build the TCDB search index) ─────────
  │ Licence: GNU General Public License v3.0 or later (GPL-3.0+).
  │ Quoted from the DIAMOND LICENSE:
  │   "This program is free software: you can redistribute it
  │    and/or modify it under the terms of the GNU General Public
  │    License as published by the Free Software Foundation."
  │ Source: https://github.com/bbuchfink/diamond
  └────────────────────────────────────────────────────────────────

  By agreeing below, you declare, on your own responsibility, that:
    (a) Your use is academic / non-profit, OR
    (b) Written permission has already been obtained from the
        Saier Lab (msaier@ucsd.edu).
  Licence compliance is the sole responsibility of the end user.

  All agreements are recorded and logged with the pipeline version
  (git commit hash). A copy of your acceptance record will be
  saved in: logs/licensing/

  ================================================================
NOTICE
skip tcdb tcdb.fasta tcdb.dmnd \
    && { ok "tcdb: already set up (use --redo to force)"; exit 0; }

d="$(db tcdb)"; run mkdir -p "$d"
log "downloading TCDB sequences..."
run wget -c --show-progress -O "$d/tcdb.fasta"   "https://www.tcdb.org/public/tcdb"
run wget -c --show-progress -O "$d/families.tsv" "https://www.tcdb.org/cgi-bin/projectv/public/families.py"
log "building DIAMOND index via container..."
run_in_container tcdb --entrypoint diamond --bind "$d:/db" -- \
    makedb --in /db/tcdb.fasta --db /db/tcdb --threads "$THREADS"
ok "tcdb ready → $d"
