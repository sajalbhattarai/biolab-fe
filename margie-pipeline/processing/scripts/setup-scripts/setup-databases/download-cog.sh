#!/usr/bin/env bash
# download-cog.sh — downloads the NCBI CDD profiles and COG2024 annotation tables.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/lib.sh"
tag="download-cog"
db_parse_args "$@"

skip cog cddid.tbl cdd.info Cog_LE/NCBI/data/Cog cog-24.def.tab cog-24.fun.tab cog-24.pathways.tab \
    && { ok "cog: already set up (use --redo to force)"; exit 0; }

d="$(db cog)"; run mkdir -p "$d"
log "downloading CDD profiles + COG2024 tables → $d"
run wget -c --show-progress -P "$d" \
    "https://ftp.ncbi.nlm.nih.gov/pub/mmdb/cdd/cddid.tbl.gz" \
    "https://ftp.ncbi.nlm.nih.gov/pub/mmdb/cdd/cdd.info" \
    "https://ftp.ncbi.nlm.nih.gov/pub/mmdb/cdd/little_endian/Cog_LE.tar.gz" \
    "https://ftp.ncbi.nlm.nih.gov/pub/COG/COG2024/data/cog-24.def.tab" \
    "https://ftp.ncbi.nlm.nih.gov/pub/COG/COG2024/data/cog-24.fun.tab" \
    "https://ftp.ncbi.nlm.nih.gov/pub/COG/COG2024/data/cog-24.pathways.tab"
run gunzip -kf "$d/cddid.tbl.gz"
run mkdir -p "$d/Cog_LE"
run tar -xzf "$d/Cog_LE.tar.gz" -C "$d/Cog_LE"
ok "cog ready → $d"
