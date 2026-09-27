#!/usr/bin/env bash
# postproc.sh — rasttk host-side post-processing (archived).
# Called by pipeline-lib.sh::run_postproc with the rasttk group output dir; normalises
# folder / file suffixes, then enriches every rast*.tsv with SEED database fields.
set -euo pipefail

OUT_DIR="${1:?usage: postproc.sh <rasttk-group-output-dir>}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# DB dir: TOOL_rasttk_DB, else $DB_ROOT/rasttk, else the repo default.
DB_DIR="${TOOL_rasttk_DB:-${DB_ROOT:-}/rasttk}"
if [[ -z "${DB_ROOT:-}" || ! -d "$DB_DIR" ]]; then
    DB_DIR="$here/../../../../db/rasttk"
fi

if [[ ! -f "$DB_DIR/seed_database_long.tsv" ]]; then
    echo "[postproc/rasttk] WARN: seed_database_long.tsv not in $DB_DIR — skipping SEED enrichment" >&2
    exit 0
fi

PY="${PYTHON:-python3}"
if ! command -v "$PY" >/dev/null 2>&1; then
    echo "[postproc/rasttk] WARN: $PY not found — skipping SEED enrichment" >&2
    exit 0
fi

# Step 1: normalises run-folder and rast*.tsv suffixes (normalize_rasttk_output.sh; idempotent).
normalize_sh="$here/normalize_rasttk_output.sh"
if [[ -x "$normalize_sh" ]]; then
    echo "[postproc/rasttk] normalising folder/file suffixes under: $OUT_DIR"
    bash "$normalize_sh" "$OUT_DIR" || \
        echo "[postproc/rasttk] WARN: normalisation step returned non-zero" >&2
fi

# Step 2: SEED enrichment of every rast*.tsv variant.
echo "[postproc/rasttk] SEED-enriching rast*.tsv files under: $OUT_DIR"
echo "[postproc/rasttk] SEED column legend: see <run>/pipeline-log.txt"
echo "[postproc/rasttk]   join key      : (RAST_BVBRC_Name, RAST_description) -> role-only fallback"
echo "[postproc/rasttk]   variant_code  : SEED variant ID (1.1, 2.0, ...); -1 = role exists but variant NOT implemented; * = uncertain"
echo "[postproc/rasttk]   presence      : present|likely|absent in SEED reference genomes (NOT in this genome)"
echo "[postproc/rasttk]   genome_count  : # of SEED reference organisms carrying this variant"
echo "[postproc/rasttk]   role_count    : # of distinct roles MAKING UP this variant (gene-set size)"
echo "[postproc/rasttk]   reactions     : ModelSEED rxnNNNNN IDs + equations (cpdNNNNN, [c]=cytosol, [e]=extracellular)"
echo "[postproc/rasttk]   kegg_*        : KEGG cross-references mapped from ModelSEED reactions"
echo "[postproc/rasttk]   multi-variant : columns are pipe-separated -- i-th '|' segment lines up across all SEED_* cols"
"$PY" "$here/enrich-rast-tsv.py" \
    --db    "$DB_DIR" \
    --root  "$OUT_DIR"
