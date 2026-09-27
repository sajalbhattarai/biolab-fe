#!/usr/bin/env bash
# download-tigrfam.sh — downloads the TIGRFAMs 15.0 HMM library and builds the hmmpress index (inside the container).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/lib.sh"
tag="download-tigrfam"
db_parse_args "$@"

skip tigrfam TIGRFAMs_15.0_HMM.LIB TIGRFAMs_15.0_HMM.LIB.h3i TIGR_ROLE_NAMES \
    && { ok "tigrfam: already set up (use --redo to force)"; exit 0; }

d="$(db tigrfam)"; run mkdir -p "$d"
base="https://ftp.ncbi.nlm.nih.gov/hmm/TIGRFAMs/release_15.0"
log "downloading TIGRFAMs HMM library + role files..."
run wget -c --show-progress -P "$d" \
    "$base/TIGRFAMs_15.0_HMM.LIB.gz" \
    "$base/TIGRFAMS_ROLE_LINK" \
    "$base/TIGRFAMS_GO_LINK" \
    "$base/TIGR_ROLE_NAMES"
run gunzip -kf "$d/TIGRFAMs_15.0_HMM.LIB.gz"
log "running hmmpress via container..."
run_in_container tigrfam --entrypoint hmmpress --bind "$d:/db" -- /db/TIGRFAMs_15.0_HMM.LIB
ok "tigrfam ready → $d"
