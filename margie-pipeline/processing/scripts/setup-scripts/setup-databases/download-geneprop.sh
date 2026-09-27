#!/usr/bin/env bash
# download-geneprop.sh — downloads the Genome Properties flatfiles (ebi-pf-team/genome-properties).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/lib.sh"
tag="download-geneprop"
db_parse_args "$@"

skip geneprop flatfiles \
    && { ok "geneprop: already set up (use --redo to force)"; exit 0; }

d="$(db geneprop)"; run mkdir -p "$d"
if [[ -d "$d/.git" ]]; then
    log "updating existing geneprop clone..."
    run git -C "$d" pull --ff-only
else
    log "cloning ebi-pf-team/genome-properties → $d"
    run git clone --depth 1 "https://github.com/ebi-pf-team/genome-properties.git" "$d"
fi
ok "geneprop ready → $d/flatfiles/"
