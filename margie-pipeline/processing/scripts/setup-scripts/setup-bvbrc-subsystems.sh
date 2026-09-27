#!/usr/bin/env bash
# setup-bvbrc-subsystems.sh — fetches the BV-BRC PATRIC subsystem catalog
# (superclass/class/subclass/roles) with p3-all-subsystems inside the rasttk container
# and writes db/rasttk/subsystem_mapping_wide.tsv plus a .fetch provenance stamp.
# Safe to re-run; each run refreshes the table.

set -euo pipefail

here=$(cd "$(dirname "$0")/../.." && pwd)
if [ -f "$here/pipeline.conf.sh" ]; then
    . "$here/pipeline.conf.sh"
fi
db_dir="$here/db/rasttk"
mkdir -p "$db_dir"

image="${REGISTRY:-margie}/rasttk:latest"

echo "[bvbrc] fetching subsystem catalog from BV-BRC PATRIC via $image ..."
docker run --rm --entrypoint sh -v "$db_dir:/out" "$image" -c '
    set -e
    p3-all-subsystems -a subsystem_name -a superclass -a class -a subclass \
        > /out/_bvbrc_meta.tsv
    p3-all-subsystems -a subsystem_name -a role_name \
        > /out/_bvbrc_roles.tsv
'

python3 - "$db_dir" <<'PY'
import csv, datetime, pathlib, sys
db = pathlib.Path(sys.argv[1])

meta = {}
with (db / '_bvbrc_meta.tsv').open(encoding='utf-8') as f:
    for row in csv.DictReader(f, delimiter='\t'):
        sid = row['subsystem.subsystem_id']
        meta[sid] = {
            'name':       row.get('subsystem.subsystem_name','') or sid,
            'superclass': row.get('subsystem.superclass',''),
            'class':      row.get('subsystem.class',''),
            'subclass':   row.get('subsystem.subclass',''),
        }

roles = {}
with (db / '_bvbrc_roles.tsv').open(encoding='utf-8') as f:
    for row in csv.DictReader(f, delimiter='\t'):
        sid = row['subsystem.subsystem_id']
        roles[sid] = row.get('subsystem.role_name','')

assert set(meta) == set(roles), 'BV-BRC meta/roles mismatch'

out = db / 'subsystem_mapping_wide.tsv'
n = ns = nc = nsc = 0
with out.open('w', encoding='utf-8') as f:
    w = csv.writer(f, delimiter='\t', lineterminator='\n')
    w.writerow(['subsystem_id','roles','subsystem_name',
                'superclass','class','subclass'])
    for sid in sorted(meta):
        m = meta[sid]
        w.writerow([sid, roles[sid], m['name'],
                    m['superclass'], m['class'], m['subclass']])
        n += 1
        ns  += bool(m['superclass'])
        nc  += bool(m['class'])
        nsc += bool(m['subclass'])

(db / 'subsystem_mapping_wide.tsv.fetch').write_text(
    "# Source : BV-BRC PATRIC subsystem catalog\n"
    "# Method : p3-all-subsystems -a subsystem_name -a superclass -a class -a subclass -a role_name\n"
    f"# Fetched: {datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')}\n"
    f"# Rows   : {n} subsystems\n"
)

# cleanup temp dumps
(db / '_bvbrc_meta.tsv').unlink()
(db / '_bvbrc_roles.tsv').unlink()

print(f"[bvbrc] wrote {out}")
print(f"[bvbrc]   subsystems   : {n}")
print(f"[bvbrc]   with super   : {ns}  ({100*ns/n:.1f}%)")
print(f"[bvbrc]   with class   : {nc} ({100*nc/n:.1f}%)")
print(f"[bvbrc]   with subclass: {nsc}  ({100*nsc/n:.1f}%)")
PY

echo "[bvbrc] done. citable provenance written to $db_dir/subsystem_mapping_wide.tsv.fetch"
