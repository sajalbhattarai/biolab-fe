#!/usr/bin/env bash
# download-gtdbtk.sh — downloads and unpacks the GTDB-Tk reference data tarball into $DB_ROOT/gtdbtk.
# The source URL can be overridden with GTDBTK_DATA_URL. Usage: ./download-gtdbtk.sh [--redo]

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/lib.sh"
tag="download-gtdbtk"
db_parse_args "$@"

d="$(db gtdbtk)"
GTDBTK_DATA_URL="${GTDBTK_DATA_URL:-https://data.ace.uq.edu.au/public/gtdb/data/releases/latest/auxillary_files/gtdbtk_package/full_package/gtdbtk_data.tar.gz}"
TARBALL="$d/gtdbtk_data.tar.gz"

# Sentinel used by GTDB-Tk data packages.
if skip gtdbtk taxonomy/gtdb_taxonomy.tsv .gtdbtk_data_root; then
    ok "gtdbtk: database already present (use --redo to force)"
    exit 0
fi

run mkdir -p "$d"

log "downloading GTDB-Tk reference data into $d"
log "this may take a while depending on network and storage throughput"
log "source: $GTDBTK_DATA_URL"

run wget -q --show-progress -O "$TARBALL" "$GTDBTK_DATA_URL"
run tar -xvzf "$TARBALL" -C "$d"

if (( DB_DRYRUN )); then
    ok "gtdbtk dry-run plan complete"
    exit 0
fi

data_root=""
if [[ -s "$d/taxonomy/gtdb_taxonomy.tsv" ]]; then
    data_root="$d"
else
    tax_file="$(find "$d" -maxdepth 4 -type f -path '*/taxonomy/gtdb_taxonomy.tsv' -print -quit 2>/dev/null || true)"
    if [[ -n "$tax_file" ]]; then
        data_root="$(dirname "$(dirname "$tax_file")")"
    fi
fi

if [[ -z "$data_root" ]]; then
    err "gtdbtk: expected taxonomy sentinel not found under $d"
    err "check the command output above and retry with --redo"
    exit 1
fi

# Records the resolved data root for the container entrypoint.
printf '%s\n' "${data_root#$d/}" > "$d/.gtdbtk_data_root"

ok "gtdbtk database ready -> $data_root"
