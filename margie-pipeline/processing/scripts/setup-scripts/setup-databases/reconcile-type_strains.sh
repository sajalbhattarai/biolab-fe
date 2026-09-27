#!/usr/bin/env bash
# reconcile-type_strains.sh — updates the type-strain manifest statuses from the files on disk,
# typically after a shard-array download finishes.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/lib.sh"
tag="reconcile-type_strains"
db_parse_args "$@"

manifest_dir="$(db type_strains)"
manifest_tsv="$manifest_dir/type_strain_genomes.tsv"

if [[ ! -s "$manifest_tsv" ]]; then
    err "reconcile-type_strains: manifest not found at $manifest_tsv"
    exit 1
fi

log "reconcile-type_strains: scanning manifest and filesystem..."

python3 - "$manifest_tsv" << 'PYEOF'
import csv, sys, shutil
from pathlib import Path

manifest_tsv = Path(sys.argv[1])
temp = str(manifest_tsv) + ".reconcile.tmp"

downloaded = skipped = not_downloaded = 0

with open(manifest_tsv, newline="", encoding="utf-8") as fh_in, \
     open(temp, "w", newline="", encoding="utf-8") as fh_out:
    rdr = csv.DictReader(fh_in, delimiter="\t")
    fieldnames = rdr.fieldnames or ["accession", "fasta_path", "download_url", "status", "source_db"]
    w = csv.DictWriter(fh_out, delimiter="\t", fieldnames=fieldnames)
    w.writeheader()
    for row in rdr:
        fasta_path = Path(row.get("fasta_path", ""))
        if fasta_path.exists() and fasta_path.stat().st_size > 0:
            if row.get("status") != "downloaded":
                row["status"] = "downloaded"
                downloaded += 1
            else:
                skipped += 1
        else:
            if row.get("status") != "not_downloaded":
                row["status"] = "not_downloaded"
                not_downloaded += 1
            else:
                not_downloaded += 1
        w.writerow(row)

shutil.move(temp, str(manifest_tsv))
print(f"[reconcile] updated_to_downloaded={downloaded} already_downloaded={skipped} not_downloaded={not_downloaded}")
PYEOF

ok "reconcile-type_strains: manifest updated → $manifest_tsv"
