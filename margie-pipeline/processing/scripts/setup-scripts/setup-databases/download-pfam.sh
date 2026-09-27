#!/usr/bin/env bash
# download-pfam.sh — downloads the Pfam-A HMM library and builds the hmmpress index (inside the container).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/lib.sh"
tag="download-pfam"
db_parse_args "$@"

skip pfam Pfam-A.hmm Pfam-A.hmm.h3i Pfam-A.hmm.dat \
    && { ok "pfam: already set up (use --redo to force)"; exit 0; }

d="$(db pfam)"; run mkdir -p "$d"
log "downloading Pfam-A HMM library..."
run wget -c --show-progress -P "$d" \
    "https://ftp.ebi.ac.uk/pub/databases/Pfam/current_release/Pfam-A.hmm.gz" \
    "https://ftp.ebi.ac.uk/pub/databases/Pfam/current_release/Pfam-A.hmm.dat.gz" \
    "https://ftp.ebi.ac.uk/pub/databases/Pfam/current_release/Pfam-C.gz"
run gunzip -kf "$d/Pfam-A.hmm.gz" "$d/Pfam-A.hmm.dat.gz" "$d/Pfam-C.gz"
log "running hmmpress via container..."
run_in_container pfam --entrypoint hmmpress --bind "$d:/db" -- /db/Pfam-A.hmm
ok "pfam ready → $d"
