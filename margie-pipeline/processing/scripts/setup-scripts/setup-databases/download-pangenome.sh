#!/usr/bin/env bash
# download-pangenome.sh — creates the $DB_ROOT/pangenome/fingerprint/ scratch directory.
# Nothing is downloaded; the fingerprint stage fills it as organisms run.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/lib.sh"
tag="download-pangenome"
db_parse_args "$@"

d="$(db pangenome)/fingerprint"
log "pangenome has no static download — the fingerprint stage fills it as organisms run"
run mkdir -p "$d"
ok "pangenome workspace ready (empty) → $d"
