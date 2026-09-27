#!/usr/bin/env bash
# download-type_strains.sh — fetches FASTA files for the GTDB type / representative genomes
# referenced in input/classification_report.tsv (does nothing without that report).
# TYPE_STRAINS_SCOPE=all fetches every genome in the manifest.

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/lib.sh"
tag="download-type_strains"
db_parse_args "$@"

classification_report="${TYPE_STRAINS_REPORT:-$INPUT_RASTTK/classification_report.tsv}"
scope="${TYPE_STRAINS_SCOPE:-report}"
max_downloads="${TYPE_STRAINS_MAX_DOWNLOADS:-0}"

manifest_dir="$(db type_strains)"
manifest_tsv="$manifest_dir/type_strain_genomes.tsv"
index_tsv="$manifest_dir/type_strain_index.tsv"
genomes_dir="$manifest_dir/genomes"

if [[ ! -s "$manifest_tsv" || ! -s "$index_tsv" ]]; then
    err "type_strains: manifest/index missing. Run download-taxonomy.sh first."
    exit 1
fi

run mkdir -p "$genomes_dir"

if [[ "$scope" == "report" && ! -s "$classification_report" ]]; then
    warn "type_strains: classification report not found at $classification_report — nothing to download"
    ok "type_strains: skipped (no report yet)"
    exit 0
fi

if [[ "$scope" == "report" ]]; then
    if skip type_strains type_strain_genomes.tsv type_strain_index.tsv && [[ -n "$(find "$genomes_dir" -maxdepth 1 -type f -name '*.fna.gz' -print -quit 2>/dev/null)" ]]; then
        ok "type_strains: genomes already present (use --redo to force)"
        exit 0
    fi
fi

if (( ! DB_DRYRUN )); then
python3 - "$manifest_tsv" "$classification_report" "$scope" "$genomes_dir" "$max_downloads" << 'PYEOF'
import csv
import os
import subprocess
import sys
from pathlib import Path

manifest_tsv = Path(sys.argv[1])
report_tsv = Path(sys.argv[2])
scope = sys.argv[3]
genomes_dir = Path(sys.argv[4])
max_downloads = int(sys.argv[5])

# Shard mode: if TYPE_STRAINS_SHARD_INDEX and TYPE_STRAINS_SHARD_TOTAL are set,
# this instance only downloads rows where (global_row_index % shard_total == shard_index).
# In shard mode the manifest TSV is NOT rewritten — a separate reconcile pass does that.
shard_index = int(os.environ.get("TYPE_STRAINS_SHARD_INDEX", "-1"))
shard_total = int(os.environ.get("TYPE_STRAINS_SHARD_TOTAL", "1"))
shard_mode  = shard_index >= 0

genomes_dir.mkdir(parents=True, exist_ok=True)

def clean_acc(acc: str) -> str:
    acc = (acc or "").strip()
    if acc.startswith("RS_") or acc.startswith("GB_"):
        acc = acc[3:]
    return acc

required = set()
if scope == "report":
    with open(report_tsv, newline="", encoding="utf-8") as fh:
        rdr = csv.DictReader(fh, delimiter="\t")
        for row in rdr:
            for col in (
                "gtdb_species_representative",
                "gtdb_closest_genome_reference",
                "gtdb_closest_placement_reference",
            ):
                acc = clean_acc(row.get(col, ""))
                if acc and acc != "N/A":
                    required.add(acc)

def download_one(fasta_path, url):
    fasta_path.parent.mkdir(parents=True, exist_ok=True)
    cmd = ["wget", "-q", "-O", str(fasta_path), url]
    try:
        rc = subprocess.run(cmd, timeout=3600).returncode
        if rc == 0 and fasta_path.exists() and fasta_path.stat().st_size > 0:
            return "downloaded"
        try:
            fasta_path.unlink(missing_ok=True)
        except (TypeError, FileNotFoundError):
            pass
        return "failed"
    except Exception:
        try:
            fasta_path.unlink(missing_ok=True)
        except (TypeError, FileNotFoundError):
            pass
        return "failed"

# -----------------------------------------------------------------
# Shard mode: each shard reads the manifest, downloads its slice,
# and writes nothing back — a separate reconcile step updates statuses.
# -----------------------------------------------------------------
if shard_mode:
    downloaded = skipped = failed = missing_url = row_n = 0
    with open(manifest_tsv, newline="", encoding="utf-8") as fh:
        rdr = csv.DictReader(fh, delimiter="\t")
        for row in rdr:
            acc = clean_acc(row.get("accession", ""))
            if not acc:
                continue
            should_process = (scope == "all") or (scope == "report" and acc in required)
            if not should_process:
                continue
            if row_n % shard_total != shard_index:
                row_n += 1
                continue
            row_n += 1

            fasta_path = Path(row.get("fasta_path", ""))
            if fasta_path.exists() and fasta_path.stat().st_size > 0:
                skipped += 1
                continue
            url = row.get("download_url", "")
            if not url:
                missing_url += 1
                continue
            status = download_one(fasta_path, url)
            if status == "downloaded":
                downloaded += 1
            else:
                failed += 1
    print(f"[type_strains] shard={shard_index}/{shard_total} downloaded={downloaded} skipped_existing={skipped} failed={failed} missing_url={missing_url}")

# -----------------------------------------------------------------
# Single-process mode: stream through manifest, update it in place.
# -----------------------------------------------------------------
else:
    fieldnames = None
    temp_manifest = str(manifest_tsv) + ".tmp"
    downloaded = skipped = failed = missing_url = dl_count = 0

    with open(manifest_tsv, newline="", encoding="utf-8") as fh_in, \
         open(temp_manifest, "w", newline="", encoding="utf-8") as fh_out:

        rdr = csv.DictReader(fh_in, delimiter="\t")
        fieldnames = rdr.fieldnames or ["accession", "fasta_path", "download_url", "status", "source_db"]
        w = csv.DictWriter(fh_out, delimiter="\t", fieldnames=fieldnames)
        w.writeheader()

        for row in rdr:
            acc = clean_acc(row.get("accession", ""))
            if not acc:
                w.writerow(row)
                continue
            should_process = (scope == "all") or (scope == "report" and acc in required)
            if not should_process:
                w.writerow(row)
                continue
            if max_downloads > 0 and dl_count >= max_downloads:
                w.writerow(row)
                continue

            fasta_path = Path(row.get("fasta_path", ""))
            if fasta_path.exists() and fasta_path.stat().st_size > 0:
                row["status"] = "downloaded"
                skipped += 1
                dl_count += 1
                w.writerow(row)
                continue

            url = row.get("download_url", "")
            if not url:
                row["status"] = "missing_url"
                missing_url += 1
                dl_count += 1
                w.writerow(row)
                continue

            status = download_one(fasta_path, url)
            row["status"] = status
            if status == "downloaded":
                downloaded += 1
            else:
                failed += 1
            dl_count += 1
            w.writerow(row)

    import shutil
    shutil.move(temp_manifest, str(manifest_tsv))
    print(f"[type_strains] selected={dl_count} downloaded={downloaded} skipped_existing={skipped} failed={failed} missing_url={missing_url}")
PYEOF
else
    echo "  [dry-run] type_strains scope=$scope report=$classification_report"
fi

ok "type_strains genomes ready → $genomes_dir"
