#!/usr/bin/env bash
# download-merops.sh — downloads the MEROPS peptidase library and builds its DIAMOND index (inside the container).
# MEROPS is academic-only; the download needs licence acceptance through licence-gate.sh
# (--accept-merops-licence, MEROPS_ACCEPT_LICENCE=1, or the typed statement at a terminal).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/lib.sh"
tag="download-merops"
db_parse_args "$@"

# ---- licence gate ---------------------------------------------------------
# Runs before the skip check so the acceptance record is always written.
licence_gate merops MEROPS_ACCEPT_LICENCE --accept-merops-licence \
    "./setup.sh --databases-only --tool merops --accept-merops-licence" <<'NOTICE' || exit 0
  ================================================================
  WHY LICENSING MATTERS FOR MEROPS
  ================================================================
  MEROPS was developed at EMBL-EBI and represents years of expert
  manual curation of peptidase sequences, families and inhibitors.
  It is freely accessible for academic use, but commercial use
  requires a paid licence. Using it without the appropriate licence
  is a legal violation. Please read the terms below carefully.

  ── DATABASES ────────────────────────────────────────────────────

  ┌─ MEROPS 12.5 (peptidase database, EMBL-EBI) ─────────────── ⚠️
  │ Licence quoted from https://www.ebi.ac.uk/merops/about/license.shtml:
  │
  │   "The MEROPS database is freely accessible for academic use.
  │    Commercial organisations should contact the MEROPS team to
  │    obtain a licence before downloading or using the data."
  │
  │ * ACADEMIC / non-commercial use: FREE. Citation REQUIRED.
  │ * COMMERCIAL use: REQUIRES a paid licence from EMBL-EBI
  │                   BEFORE download or use.
  │   Contact: merops-helpdesk@ebi.ac.uk
  │
  │ Re-distribution of the MEROPS database is NOT permitted under
  │ either licence. Each end user must download it themselves.
  │
  │ Citation: Rawlings N.D. et al. (2018) Nucleic Acids Research
  │           46(D1):D624-D632. doi:10.1093/nar/gkx1134
  └────────────────────────────────────────────────────────────────

  ── TOOLS ────────────────────────────────────────────────────────

  ┌─ DIAMOND 2.1.9 (used to build the MEROPS search index) ───────
  │ Licence: GNU General Public License v3.0 or later (GPL-3.0+).
  │ Quoted from the DIAMOND LICENSE:
  │   "This program is free software: you can redistribute it
  │    and/or modify it under the terms of the GNU General Public
  │    License as published by the Free Software Foundation."
  │ Source: https://github.com/bbuchfink/diamond
  └────────────────────────────────────────────────────────────────

  By agreeing below, you declare, on your own responsibility, that:
    (a) Your use is academic / non-commercial, OR
    (b) A commercial MEROPS licence has already been obtained
        from EMBL-EBI.
  Licence compliance is the sole responsibility of the end user.
  Users uncertain of their status should answer "no" and consult
  their institution's licensing office.

  All agreements are recorded and logged with the pipeline version
  (git commit hash). A copy of your acceptance record will be
  saved in: logs/licensing/

  ================================================================
NOTICE
skip merops pepunit.lib merops_scan.lib merops.dmnd \
    && { ok "merops: already set up (use --redo to force)"; exit 0; }

d="$(db merops)"; run mkdir -p "$d"
base="https://ftp.ebi.ac.uk/pub/databases/merops/current_release"
log "downloading MEROPS sequences..."
run wget -c --show-progress -P "$d" "$base/pepunit.lib" "$base/merops_scan.lib"
log "building DIAMOND index via container..."
run_in_container merops --entrypoint diamond --bind "$d:/db" -- \
    makedb --in /db/merops_scan.lib --db /db/merops --threads "$THREADS"
ok "merops ready → $d"
