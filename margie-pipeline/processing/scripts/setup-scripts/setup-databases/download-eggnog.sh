#!/usr/bin/env bash
# download-eggnog.sh — downloads the eggNOG SQLite databases, DIAMOND protein db and Bacteria HMM profiles.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/lib.sh"
tag="download-eggnog"
db_parse_args "$@"

skip eggnog eggnog.db eggnog.taxa.db eggnog_proteins.dmnd \
    && { ok "eggnog: already set up (use --redo to force)"; exit 0; }

d="$(db eggnog)"; run mkdir -p "$d"
base="http://eggnog5.embl.de/download/emapperdb-5.0.2"

# Removes zero-byte stubs so wget -c does a real download.
for stub in eggnog.db.gz eggnog.taxa.tar.gz eggnog_proteins.dmnd.gz; do
    if [[ -f "$d/$stub" && ! -s "$d/$stub" ]]; then
        log "removing empty stub $stub"
        run rm -f "$d/$stub"
    fi
done

if [[ ! -f "$d/eggnog.db" ]] || (( DB_REDO )); then
    log "downloading eggnog.db ($base)..."
    run wget -c --show-progress -P "$d" "$base/eggnog.db.gz"
    run gunzip -f "$d/eggnog.db.gz"
fi

if [[ ! -f "$d/eggnog.taxa.db" ]] || (( DB_REDO )); then
    log "downloading eggnog.taxa.db ($base)..."
    run wget -c --show-progress -P "$d" "$base/eggnog.taxa.tar.gz"
    run tar -xzf "$d/eggnog.taxa.tar.gz" -C "$d"
    run rm -f "$d/eggnog.taxa.tar.gz"
fi

# DIAMOND protein db for the default (fast) emapper mode; ~4.5 GB compressed, ~10 GB extracted.
if [[ ! -f "$d/eggnog_proteins.dmnd" ]] || (( DB_REDO )); then
    log "downloading eggnog_proteins.dmnd ($base)... (~4.5 GB)"
    run wget -c -P "$d" "$base/eggnog_proteins.dmnd.gz"
    run gunzip -f "$d/eggnog_proteins.dmnd.gz"
fi

# Bacteria HMM profiles for the optional higher-sensitivity HMMER mode.
if [[ ! -f "$d/hmmer/Bacteria/Bacteria.hmm.h3f" ]] || (( DB_REDO )); then
    log "downloading Bacteria HMM profiles via container..."
    run_in_container eggnog --entrypoint download_eggnog_data.py --bind "$d:/db" -- \
        --data_dir /db -H -d 2 --dbname Bacteria -y
fi
ok "eggnog ready → $d"
