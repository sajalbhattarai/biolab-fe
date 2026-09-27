#!/usr/bin/env bash
# download-kegg.sh — downloads the KOfam HMM profiles and ko_list (the free portion of KEGG).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/lib.sh"
tag="download-kegg"
db_parse_args "$@"

skip kegg ko_list profiles \
    && { ok "kegg: already set up (use --redo to force)"; exit 0; }

d="$(db kegg)"; run mkdir -p "$d"
warn "KEGG: KOfam download is large; if you already have profiles/ + ko_list, copy them to $d"
log "downloading KOfam profiles + ko_list..."
run wget -c --show-progress -P "$d" \
    "https://www.genome.jp/ftp/db/kofam/profiles.tar.gz" \
    "https://www.genome.jp/ftp/db/kofam/ko_list.gz"
run tar -xzf "$d/profiles.tar.gz" -C "$d"
run gunzip -kf "$d/ko_list.gz"
ok "kegg ready → $d"
