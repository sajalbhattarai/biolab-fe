#!/usr/bin/env bash
# download-uniprot.sh — downloads the UniProt Swiss-Prot FASTA and builds the DIAMOND index (inside the container).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/lib.sh"
tag="download-uniprot"
db_parse_args "$@"

skip uniprot uniprot_sprot.fasta uniprot_sprot.dmnd \
    && { ok "uniprot: already set up (use --redo to force)"; exit 0; }

d="$(db uniprot)"; run mkdir -p "$d"
base="https://ftp.uniprot.org/pub/databases/uniprot/current_release/knowledgebase/complete"
log "downloading Swiss-Prot..."
run wget -c --show-progress -P "$d" "$base/uniprot_sprot.fasta.gz" "$base/uniprot_sprot.dat.gz"
run gunzip -kf "$d/uniprot_sprot.fasta.gz"
log "building DIAMOND index via container..."
run_in_container uniprot --entrypoint diamond --bind "$d:/db" -- \
    makedb --in /db/uniprot_sprot.fasta --db /db/uniprot_sprot --threads "$THREADS"
ok "uniprot ready → $d"
