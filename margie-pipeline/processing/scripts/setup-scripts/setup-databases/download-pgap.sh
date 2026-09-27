#!/usr/bin/env bash
# download-pgap.sh — downloads the NCBI PGAP HMM library and builds the hmmpress index (inside the container).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/lib.sh"
tag="download-pgap"
db_parse_args "$@"

skip pgap hmm_PGAP.LIB hmm_PGAP.LIB.h3i hmm_PGAP.tsv \
    && { ok "pgap: already set up (use --redo to force)"; exit 0; }

d="$(db pgap)"; run mkdir -p "$d"
log "downloading NCBI PGAP HMM library..."
run wget -c --show-progress -P "$d" \
    "https://ftp.ncbi.nlm.nih.gov/hmm/current/hmm_PGAP.LIB" \
    "https://ftp.ncbi.nlm.nih.gov/hmm/current/hmm_PGAP.tsv"
log "running hmmpress via container (may take minutes)..."
run_in_container pgap --entrypoint bash --bind "$d:/db" -- -c 'hmmpress -f /db/hmm_PGAP.LIB'
ok "pgap ready → $d"
