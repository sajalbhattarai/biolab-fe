#!/usr/bin/env bash
# download-rasttk.sh — builds db/rasttk/: downloads the SEED database files, fetches the
# BV-BRC subsystem catalog through the rasttk container (skipped with a warning when no
# runtime or image is available), and merges them with merge-rasttk-db.py into
# seed_database_long.tsv and seed_database.json.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/lib.sh"
tag="download-rasttk"
db_parse_args "$@"

skip rasttk seed_database.json seed_database_long.tsv \
    && { ok "rasttk: already set up (use --redo to force)"; exit 0; }

d="$(db rasttk)"; run mkdir -p "$d"

# ── Step 1: download base SEED files ─────────────────────────────────────────
base="https://github.com/bhsajal/margie-annotation/releases/download/latest"
for f in seed_database.json seed_database_long.tsv; do
    if [[ -f "$d/$f" ]] && (( DB_REDO == 0 )); then
        warn "  $f already present — skipping"
        continue
    fi
    log "  → $f"
    wget -q --show-progress -O "$d/$f" "$base/$f"
done

# ── Step 2: fetch live BV-BRC subsystem catalog ───────────────────────────────
# Needs the rasttk container; without it the merge still runs but
# SEED_superclass / SEED_subsystem_id stay empty.
_fetch_bvbrc_catalog() {
    log "  fetching BV-BRC subsystem catalog (p3-all-subsystems) …"

    run_in_container rasttk \
        --bind "$d:/out" \
        --entrypoint sh \
        -- -c '
            set -e
            p3-all-subsystems -a subsystem_name -a superclass -a class -a subclass \
                > /out/_bvbrc_meta.tsv
            p3-all-subsystems -a subsystem_name -a role_name \
                > /out/_bvbrc_roles.tsv
        '

    python3 - "$d" <<'PY'
import csv, pathlib, sys
db = pathlib.Path(sys.argv[1])

meta = {}
with (db / '_bvbrc_meta.tsv').open(encoding='utf-8') as f:
    for row in csv.DictReader(f, delimiter='\t'):
        sid = row['subsystem.subsystem_id']
        meta[sid] = {
            'name':       row.get('subsystem.subsystem_name', '') or sid,
            'superclass': row.get('subsystem.superclass', ''),
            'class':      row.get('subsystem.class', ''),
            'subclass':   row.get('subsystem.subclass', ''),
        }

roles = {}
with (db / '_bvbrc_roles.tsv').open(encoding='utf-8') as f:
    for row in csv.DictReader(f, delimiter='\t'):
        sid = row['subsystem.subsystem_id']
        roles[sid] = row.get('subsystem.role_name', '')

out = db / 'subsystem_mapping_wide.tsv'
with out.open('w', encoding='utf-8') as f:
    w = csv.writer(f, delimiter='\t', lineterminator='\n')
    w.writerow(['subsystem_id', 'roles', 'subsystem_name', 'superclass', 'class', 'subclass'])
    for sid in sorted(meta):
        m = meta[sid]
        w.writerow([sid, roles.get(sid, ''), m['name'],
                    m['superclass'], m['class'], m['subclass']])

import datetime
(db / 'subsystem_mapping_wide.tsv.fetch').write_text(
    "# Source : BV-BRC PATRIC subsystem catalog\n"
    "# Method : p3-all-subsystems -a subsystem_name -a superclass -a class -a subclass -a role_name\n"
    f"# Fetched: {datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')}\n"
    f"# Rows   : {len(meta)} subsystems\n"
)

(db / '_bvbrc_meta.tsv').unlink()
(db / '_bvbrc_roles.tsv').unlink()
print(f"  subsystem catalog: {len(meta)} subsystems written to {out.name}")
PY
}

if [[ -f "$d/subsystem_mapping_wide.tsv" ]] && (( DB_REDO == 0 )); then
    warn "  subsystem_mapping_wide.tsv already present — skipping BV-BRC fetch"
elif rt="$(detect_runtime 2>/dev/null)"; then
    _fetch_bvbrc_catalog || warn "  BV-BRC catalog fetch failed — SEED_superclass will be empty (re-run with --redo to retry)"
else
    warn "  no container runtime found — skipping BV-BRC catalog fetch (SEED_superclass will be empty)"
    warn "  install Docker or Apptainer and re-run with --redo to populate superclass data"
fi

# ── Step 3: merge all inputs into the two canonical output files ──────────────
log "  merging db files …"
python3 "$here/merge-rasttk-db.py" "$d"

ok "rasttk ready → $d"
