#!/usr/bin/env bash
# download-interpro.sh — downloads InterProScan 5.77-108.0 (~40 GB extracted).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/lib.sh"
tag="download-interpro"
db_parse_args "$@"

# ---- licence gate ---------------------------------------------------------
# Runs before the skip check so the acceptance record is always written.
# The whole download is gated because member databases ProSite and SMART are academic-only.
licence_gate interpro INTERPRO_ACCEPT_LICENCE --accept-interpro-licence \
    "./setup.sh --databases-only --tool interpro --accept-interpro-licence" <<'NOTICE' || exit 0
  ================================================================
  WHY LICENSING MATTERS FOR InterProScan
  ================================================================
  InterProScan integrates many independently-developed member
  databases, each with its own licence. While the InterProScan
  engine itself is Apache-2.0 (commercial-friendly), two of its
  bundled member databases — ProSite and SMART — are free for
  academic use only and require a separate commercial licence.
  You cannot opt out of individual member databases at install
  time. Please read the exact terms below carefully.

  ── TOOLS ────────────────────────────────────────────────────────

  ┌─ InterProScan 5.x core engine (EMBL-EBI) ─────────────────────
  │ Licence: Apache License 2.0 (commercial OK for the engine).
  │ Quoted from https://github.com/ebi-pf-team/interproscan/LICENSE:
  │
  │   "Licensed under the Apache License, Version 2.0 (the
  │    'License'); you may not use this file except in compliance
  │    with the License. You may obtain a copy of the License at
  │    http://www.apache.org/licenses/LICENSE-2.0
  │    Unless required by applicable law or agreed to in writing,
  │    software distributed under the License is distributed on an
  │    'AS IS' BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
  │    either express or implied."
  │
  │ Citations:
  │   Jones P. et al. (2014) Bioinformatics 30(9):1236-1240
  │   Paysan-Lafosse T. et al. (2023) NAR 51(D1):D418-D427
  └────────────────────────────────────────────────────────────────

  ── DATABASES (bundled member databases) ─────────────────────────

  ┌─ Pfam, TIGRFAMs, HAMAP, PIRSF, Gene3D, SUPERFAMILY ──────────
  │ Licence: various open licences (CC-BY, CC-BY-SA, free for any
  │ use). No restrictions for academic or commercial use.
  └────────────────────────────────────────────────────────────────

  ┌─ ProSite (Swiss Institute of Bioinformatics, bundled) ──── ⚠️
  │ Licence quoted from https://prosite.expasy.org/prosite_license.html:
  │
  │   "The use of the PROSITE database is free of charge for
  │    academic and non-commercial use. Commercial users must
  │    obtain a licence from the SIB."
  │
  │ * ACADEMIC / non-commercial use: FREE.
  │ * COMMERCIAL use: REQUIRES a licence from SIB.
  │   Contact: licensing@sib.swiss
  └────────────────────────────────────────────────────────────────

  ┌─ SMART (EMBL, bundled) ────────────────────────────────── ⚠️
  │ Licence quoted from http://smart.embl.de/:
  │
  │   "SMART is freely accessible to academic users; commercial
  │    users require a separate licence from EMBL."
  │
  │ * ACADEMIC use: FREE.
  │ * COMMERCIAL use: REQUIRES a licence from EMBL.
  │   Contact: smart@embl.de
  └────────────────────────────────────────────────────────────────

  By agreeing below, you declare, on your own responsibility, that:
    (a) Your use is academic / non-commercial, OR
    (b) The necessary commercial licences for ProSite (SIB) and/or
        SMART (EMBL) have already been obtained, OR
    (c) Those member analyses will be disabled at run-time.
  Licence compliance is the sole responsibility of the end user.

  All agreements are recorded and logged with the pipeline version
  (git commit hash). A copy of your acceptance record will be
  saved in: logs/licensing/

  ================================================================
NOTICE
skip interpro interproscan.sh \
    && { ok "interpro: already set up (use --redo to force)"; exit 0; }

d="$(db interpro)"; run mkdir -p "$d"
ver="5.77-108.0"
tar="interproscan-${ver}-64-bit.tar.gz"
log "downloading InterProScan ${ver} (this is large)..."
run wget -c --show-progress -P "$d" "https://ftp.ebi.ac.uk/pub/software/unix/iprscan/5/${ver}/${tar}"
run tar -xzf "$d/$tar" -C "$d" --strip-components=1
ok "interpro ready → $d"
