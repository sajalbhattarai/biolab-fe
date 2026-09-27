#!/usr/bin/env bash
# download-dbcan.sh — downloads the dbCAN reference database (inside the container).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/lib.sh"
tag="download-dbcan"
db_parse_args "$@"

skip dbcan CAZy.dmnd dbCAN.hmm \
    && { ok "dbcan: already set up (use --redo to force)"; exit 0; }

d="$(db dbcan)"; run mkdir -p "$d"
log "downloading dbCAN database via container → $d"
run_in_container dbcan --entrypoint run_dbcan --bind "$d:/db" -- database --db_dir /db --aws_s3
ok "dbcan ready → $d"
