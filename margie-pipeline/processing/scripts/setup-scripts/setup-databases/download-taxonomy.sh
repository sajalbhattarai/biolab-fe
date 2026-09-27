#!/usr/bin/env bash
# download-taxonomy.sh — builds the taxonomy / type-strain tables for classification and
# novelty triage: GTDB bac120/ar53 metadata, NCBI assembly summaries, the GTDB–NCBI
# crosswalk (db/taxonomy/) and the type-strain index and genome manifest (db/type_strains/).

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/lib.sh"
tag="download-taxonomy"
db_parse_args "$@"

skip taxonomy gtdb_ncbi_crosswalk.tsv \
    && [[ -s "$DB_ROOT/type_strains/type_strain_index.tsv" ]] \
    && [[ -s "$DB_ROOT/type_strains/type_strain_genomes.tsv" ]] \
    && { ok "taxonomy: already set up (use --redo to force)"; exit 0; }

tax_dir="$(db taxonomy)"
gtdb_dir="$tax_dir/gtdb"
ncbi_dir="$tax_dir/ncbi"
type_dir="$DB_ROOT/type_strains"

run mkdir -p "$gtdb_dir" "$ncbi_dir" "$type_dir"

GTDB_RELEASE="${GTDB_RELEASE:-232}"
GTDB_SERIES="${GTDB_SERIES:-${GTDB_RELEASE}.0}"
GTDB_BASE="${GTDB_BASE:-https://data.gtdb.ecogenomic.org/releases/release${GTDB_RELEASE}/${GTDB_SERIES}}"

bac_meta_gz="$gtdb_dir/bac120_metadata_r${GTDB_RELEASE}.tsv.gz"
arc_meta_gz="$gtdb_dir/ar53_metadata_r${GTDB_RELEASE}.tsv.gz"

log "downloading GTDB metadata release r${GTDB_RELEASE} ..."
run wget -q --show-progress -O "$bac_meta_gz" "$GTDB_BASE/bac120_metadata_r${GTDB_RELEASE}.tsv.gz"
run wget -q --show-progress -O "$arc_meta_gz" "$GTDB_BASE/ar53_metadata_r${GTDB_RELEASE}.tsv.gz"

for f in "$bac_meta_gz" "$arc_meta_gz"; do
    if (( DB_DRYRUN )); then
        continue
    fi
    gzip -t "$f"
done

log "downloading NCBI assembly summaries ..."
run wget -q --show-progress -O "$ncbi_dir/assembly_summary_refseq.txt" \
    "https://ftp.ncbi.nlm.nih.gov/genomes/refseq/assembly_summary_refseq.txt"
run wget -q --show-progress -O "$ncbi_dir/assembly_summary_genbank.txt" \
    "https://ftp.ncbi.nlm.nih.gov/genomes/genbank/assembly_summary_genbank.txt"

if (( ! DB_DRYRUN )); then
python3 - "$DB_ROOT" "$GTDB_RELEASE" << 'PYEOF'
import csv
import gzip
import os
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
release = sys.argv[2]

tax_dir = root / "taxonomy"
gtdb_dir = tax_dir / "gtdb"
ncbi_dir = tax_dir / "ncbi"
type_dir = root / "type_strains"

bac_meta = gtdb_dir / f"bac120_metadata_r{release}.tsv.gz"
arc_meta = gtdb_dir / f"ar53_metadata_r{release}.tsv.gz"
radii_tsv = root / "gtdbtk" / "release232" / "radii" / "gtdb_radii.tsv"
gtdb_tax_tsv = root / "gtdbtk" / "release232" / "taxonomy" / "gtdb_taxonomy.tsv"

crosswalk_tsv = tax_dir / "gtdb_ncbi_crosswalk.tsv"
type_index_tsv = type_dir / "type_strain_index.tsv"
type_genomes_tsv = type_dir / "type_strain_genomes.tsv"

assembly_summary_refseq = ncbi_dir / "assembly_summary_refseq.txt"
assembly_summary_genbank = ncbi_dir / "assembly_summary_genbank.txt"

def clean_acc(acc: str) -> str:
    if not acc:
        return ""
    acc = acc.strip()
    for p in ("RS_", "GB_"):
        if acc.startswith(p):
            return acc[len(p):]
    return acc

def species_from_taxonomy(tax: str) -> str:
    if not tax:
        return ""
    for part in tax.split(";"):
        part = part.strip()
        if part.startswith("s__"):
            return part
    return ""

def detect_cols(headers):
    m = {h.lower(): h for h in headers}
    def find(*names, contains=None):
        for n in names:
            if n.lower() in m:
                return m[n.lower()]
        if contains:
            for h in headers:
                hl = h.lower()
                if all(c in hl for c in contains):
                    return h
        return None

    return {
        "accession": find("accession", "genome", "genome_id", contains=["accession"]),
        "gtdb_taxonomy": find("gtdb_taxonomy", contains=["gtdb", "taxonomy"]),
        "ncbi_taxonomy": find("ncbi_taxonomy", contains=["ncbi", "taxonomy"]),
        "gtdb_type": find("gtdb_type_designation", contains=["gtdb", "type"]),
        "ncbi_type": find("ncbi_type_material_designation", "ncbi_type_strain", contains=["ncbi", "type"]),
        "ncbi_org": find("ncbi_organism_name", contains=["ncbi", "organism"]),
    }

def load_ftp_paths(path: Path):
    mapping = {}
    if not path.exists():
        return mapping
    with open(path, encoding="utf-8", newline="") as fh:
        header = None
        for raw in fh:
            if raw.startswith("##"):
                continue
            if raw.startswith("#"):
                header = raw[1:].rstrip("\n").split("\t")
                continue
            if header is None:
                continue
            parts = raw.rstrip("\n").split("\t")
            if len(parts) != len(header):
                continue
            row = dict(zip(header, parts))
            acc = row.get("assembly_accession", "")
            ftp = row.get("ftp_path", "")
            if acc and ftp and ftp != "na":
                mapping[acc] = ftp
    return mapping

ftp_paths = {}
ftp_paths.update(load_ftp_paths(assembly_summary_genbank))
ftp_paths.update(load_ftp_paths(assembly_summary_refseq))

crosswalk = {}
type_rows = {}

for meta in (bac_meta, arc_meta):
    if not meta.exists():
        continue
    with gzip.open(meta, "rt", encoding="utf-8", newline="") as fh:
        rdr = csv.DictReader(fh, delimiter="\t")
        cols = detect_cols(rdr.fieldnames or [])
        if not cols["accession"]:
            continue
        for row in rdr:
            acc_raw = row.get(cols["accession"], "")
            acc = clean_acc(acc_raw)
            if not acc:
                continue
            gtdb_tax = row.get(cols["gtdb_taxonomy"], "") if cols["gtdb_taxonomy"] else ""
            ncbi_tax = row.get(cols["ncbi_taxonomy"], "") if cols["ncbi_taxonomy"] else ""
            gtdb_sp = species_from_taxonomy(gtdb_tax)
            ncbi_org = row.get(cols["ncbi_org"], "") if cols["ncbi_org"] else ""
            gtdb_type = row.get(cols["gtdb_type"], "") if cols["gtdb_type"] else ""
            ncbi_type = row.get(cols["ncbi_type"], "") if cols["ncbi_type"] else ""

            if gtdb_sp:
                crosswalk[acc] = {
                    "accession": acc,
                    "gtdb_taxonomy": gtdb_tax,
                    "gtdb_species": gtdb_sp,
                    "ncbi_taxonomy": ncbi_tax,
                    "ncbi_organism_name": ncbi_org,
                }

            type_flag = ""
            type_source = ""
            for src, val in (("gtdb", gtdb_type), ("ncbi", ncbi_type)):
                if val and val.strip() and val.strip().lower() not in ("none", "na", "n/a"):
                    type_flag = val.strip()
                    type_source = src
                    break
            if gtdb_sp and type_flag:
                type_rows[acc] = {
                    "species_name": gtdb_sp,
                    "type_strain_accession": acc,
                    "source_db": f"{type_source}_metadata_r{release}",
                    "type_designation": type_flag,
                    "priority": "type_metadata",
                }

# Fallback: populate representative mapping from GTDB radii for species lacking explicit type rows.
if radii_tsv.exists():
    with open(radii_tsv, encoding="utf-8", newline="") as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not line:
                continue
            parts = line.split("\t")
            if len(parts) < 3:
                continue
            species, rep, radius = parts[0], parts[1], parts[2]
            acc = clean_acc(rep)
            if acc in type_rows:
                continue
            type_rows[acc] = {
                "species_name": species,
                "type_strain_accession": acc,
                "source_db": f"gtdb_radii_r{release}",
                "type_designation": "representative_cluster_genome",
                "priority": "species_representative",
                "gtdb_species_ani_threshold": radius,
            }

# Ensure all GTDB taxonomy entries have at least a crosswalk skeleton row.
if gtdb_tax_tsv.exists():
    with open(gtdb_tax_tsv, encoding="utf-8", newline="") as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not line:
                continue
            try:
                acc, tax = line.split("\t", 1)
            except ValueError:
                continue
            clean = clean_acc(acc)
            if clean in crosswalk:
                continue
            crosswalk[clean] = {
                "accession": clean,
                "gtdb_taxonomy": tax,
                "gtdb_species": species_from_taxonomy(tax),
                "ncbi_taxonomy": "",
                "ncbi_organism_name": "",
            }

# Write crosswalk.
with open(crosswalk_tsv, "w", encoding="utf-8", newline="") as out:
    fields = [
        "accession",
        "gtdb_taxonomy",
        "gtdb_species",
        "ncbi_taxonomy",
        "ncbi_organism_name",
    ]
    w = csv.DictWriter(out, delimiter="\t", fieldnames=fields)
    w.writeheader()
    for acc in sorted(crosswalk):
        w.writerow(crosswalk[acc])

# Write type strain index.
with open(type_index_tsv, "w", encoding="utf-8", newline="") as out:
    fields = [
        "species_name",
        "type_strain_accession",
        "source_db",
        "type_designation",
        "priority",
        "gtdb_species_ani_threshold",
    ]
    w = csv.DictWriter(out, delimiter="\t", fieldnames=fields)
    w.writeheader()
    for acc in sorted(type_rows):
        row = dict(type_rows[acc])
        row.setdefault("gtdb_species_ani_threshold", "")
        w.writerow(row)

# Write genome manifest (download targets for optional future fetch step).
with open(type_genomes_tsv, "w", encoding="utf-8", newline="") as out:
    fields = [
        "accession",
        "fasta_path",
        "download_url",
        "status",
        "source_db",
    ]
    w = csv.DictWriter(out, delimiter="\t", fieldnames=fields)
    w.writeheader()
    for acc in sorted(type_rows):
        ftp_path = ftp_paths.get(acc, "")
        download_url = ""
        if ftp_path:
            asm_name = ftp_path.rstrip("/").split("/")[-1]
            download_url = f"{ftp_path.rstrip('/')}/{asm_name}_genomic.fna.gz"
        w.writerow({
            "accession": acc,
            "fasta_path": str(type_dir / "genomes" / f"{acc}.fna.gz"),
            "download_url": download_url,
            "status": "not_downloaded",
            "source_db": type_rows[acc].get("source_db", ""),
        })

print(f"[taxonomy] wrote {crosswalk_tsv}")
print(f"[taxonomy] wrote {type_index_tsv}")
print(f"[taxonomy] wrote {type_genomes_tsv}")
PYEOF
fi

ok "taxonomy support databases ready → $tax_dir"
ok "  gtdb_ncbi_crosswalk.tsv         (GTDB↔NCBI taxonomy mapping)"
ok "  type_strains/type_strain_index.tsv   (species→type/representative accession index)"
ok "  type_strains/type_strain_genomes.tsv (type-strain genome download manifest)"
