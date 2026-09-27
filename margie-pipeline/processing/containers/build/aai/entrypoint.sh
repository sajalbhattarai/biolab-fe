#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# CONTAINER ENTRYPOINT — aai / EzAAI (Average Amino Acid Identity, all-vs-all)
# Installed at /usr/local/bin/run inside the container.
#
# Pipeline-standard interface:
#   run -i /input/ -o /output/ [-t THREADS] [--organism-name NAME]
#
# /input/ must contain two or more protein FASTA (.faa) files, one per genome.
#
# Output layout (under -o):
#   <OUTPUT>/aai/
#     ├── raw/
#     │     ├── aai_pairwise.tsv       Raw EzAAI pairwise results
#     │     └── aai.stderr             Captured stderr from EzAAI
#     └── processed/
#           └── aai_results.tsv        Normalised N×N symmetric matrix TSV
#                                      (consumed by the 'closest' container)
# ═══════════════════════════════════════════════════════════════════════════════
set -euo pipefail

# shellcheck source=scripts/pipeline_log.sh
source /opt/aai/scripts/pipeline_log.sh

# ── Usage ─────────────────────────────────────────────────────────────────────
usage() {
    cat <<'HELP_EOF'
aai — Average Amino Acid Identity via EzAAI (all-vs-all prokaryotic genomes)

USAGE
  docker run ... annotation/aai:latest \
      -i /input/ -o /output/ \
      [-t THREADS] [--organism-name NAME]

REQUIRED MOUNTS
  /input/    Directory of protein FASTA (.faa) files — one per genome
  /output/   Output root — writable

REQUIRED OPTIONS
  -i DIR     Directory containing .faa input files
  -o DIR     Output root directory

OPTIONAL OPTIONS
  -t INT     CPU threads to pass to EzAAI calculate   [default: 4]
  --organism-name STR
             Collection label for provenance log      [default: basename of input dir]
  --help, -h Show this help and exit

OUTPUTS (under <OUTPUT>/aai/)
  raw/aai_pairwise.tsv         Raw EzAAI tab-separated pairwise results
  raw/aai.stderr               Captured stderr from EzAAI
  processed/aai_results.tsv    Normalised N×N symmetric matrix (genome names
                               as row and column headers)

NOTES
  Requires ≥2 .faa files in -i for all-vs-all computation.
  EzAAI outputs are symmetric; the post-processing script deduplicates and
  produces a full square matrix with self-comparisons set to 100.0.
  The processed matrix is the input expected by the 'closest' container.

HELP_EOF
}

# ── Argument parsing ───────────────────────────────────────────────────────────
INPUT=""
OUTPUT_ROOT=""
THREADS=4
ORGANISM_NAME=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -i)               INPUT="$2";         shift 2 ;;
        -o)               OUTPUT_ROOT="$2";   shift 2 ;;
        -t)               THREADS="$2";       shift 2 ;;
        --organism-name)  ORGANISM_NAME="$2"; shift 2 ;;
        --help|-h)        usage; exit 0 ;;
        *) printf '[aai] ERROR: unknown option: %s\n' "$1" >&2; usage >&2; exit 1 ;;
    esac
done

[[ -z "$INPUT"       ]] && { printf '[aai] ERROR: -i INPUT is required\n'  >&2; exit 1; }
[[ -z "$OUTPUT_ROOT" ]] && { printf '[aai] ERROR: -o OUTPUT is required\n' >&2; exit 1; }
[[ ! -d "$INPUT"     ]] && { printf '[aai] ERROR: input directory not found: %s\n' "$INPUT" >&2; exit 1; }

# ── Pre-flight checks ──────────────────────────────────────────────────────────
FAA_COUNT=$(find "$INPUT" -maxdepth 1 -name "*.faa" | wc -l)
if [[ "$FAA_COUNT" -lt 2 ]]; then
    printf '[aai] ERROR: all-vs-all requires ≥2 .faa files in %s (found %d)\n' \
        "$INPUT" "$FAA_COUNT" >&2
    exit 1
fi

[[ -z "$ORGANISM_NAME" ]] && ORGANISM_NAME="$(basename "$INPUT")"

# ── Directory setup ────────────────────────────────────────────────────────────
OUTPUT_DIR="$OUTPUT_ROOT/aai"
RAW_DIR="$OUTPUT_DIR/raw"
PROCESSED_DIR="$OUTPUT_DIR/processed"
WORK_DIR="$OUTPUT_DIR/.work"

mkdir -p "$RAW_DIR" "$PROCESSED_DIR" "$WORK_DIR/dbs"

# ── Pipeline log init ──────────────────────────────────────────────────────────
pipeline_log_init aai "${ORGANISM_NAME}" "$OUTPUT_DIR" "$OUTPUT_DIR/aai-pipeline-log.txt"

pipeline_log_section "INPUTS"
pipeline_log_kv_path "Input dir"  "$INPUT"
pipeline_log_kv      "FAA files"  "$FAA_COUNT"
pipeline_log_kv      "Threads"    "$THREADS"

RAW_PAIRWISE="$RAW_DIR/aai_pairwise.tsv"
RAW_ERR="$RAW_DIR/aai.stderr"
PROCESSED_TSV="$PROCESSED_DIR/aai_results.tsv"

printf '[aai] Input dir:   %s (%d .faa files)\n' "$INPUT" "$FAA_COUNT"
printf '[aai] Output root: %s\n' "$OUTPUT_DIR"
printf '[aai] Threads:     %d\n' "$THREADS"

# ── Step 1: extract each .faa → EzAAI .db ─────────────────────────────────────
_extract_all() {
    local n=0
    while IFS= read -r -d '' faa; do
        local label db
        label="$(basename "$faa" .faa)"
        db="$WORK_DIR/dbs/${label}.db"
        if [[ -f "$db" ]]; then
            printf '[aai]   skip extract (already exists): %s\n' "$label"
        else
            printf '[aai]   extracting: %s\n' "$label"
            ezaai extract -i "$faa" -s protein -o "$db" -l "$label" \
                2>>"$RAW_ERR" \
                || { printf '[aai] ERROR: extract failed for %s\n' "$faa" >&2; exit 1; }
        fi
        (( n++ )) || true
    done < <(find "$INPUT" -maxdepth 1 -name "*.faa" -print0 | sort -z)
    printf '[aai]   %d genomes extracted.\n' "$n"
}

pipeline_log_step "extract .faa → EzAAI .db files" _extract_all

# ── Step 2: all-vs-all calculate ──────────────────────────────────────────────
_calculate() {
    ezaai calculate \
        -i "$WORK_DIR/dbs/" \
        -o "$RAW_PAIRWISE" \
        -t "$THREADS" \
        2>>"$RAW_ERR"
}

if [[ -s "$RAW_PAIRWISE" ]]; then
    printf '[aai] Raw pairwise output already present; skipping EzAAI calculate.\n'
    pipeline_log_skipped "EzAAI all-vs-all calculate" \
        "ezaai calculate -i $WORK_DIR/dbs/ -o $RAW_PAIRWISE -t $THREADS" \
        "output already present"
else
    printf '[aai] Running EzAAI all-vs-all calculate (%d threads)...\n' "$THREADS"
    pipeline_log_step "EzAAI all-vs-all calculate" _calculate
fi

pipeline_log_kv_path "Raw pairwise" "$RAW_PAIRWISE"

# ── Step 3: post-process → normalised symmetric matrix ────────────────────────
_postprocess() {
    python3 /opt/aai/scripts/process_aai_raw_results.py \
        --input           "$RAW_PAIRWISE" \
        --output          "$PROCESSED_TSV" \
        --collection-name "$ORGANISM_NAME"
}

printf '[aai] Post-processing raw results...\n'
pipeline_log_step "post-process → processed/aai_results.tsv" _postprocess
pipeline_log_kv_path "Processed matrix" "$PROCESSED_TSV"

# ── Done ──────────────────────────────────────────────────────────────────────
pipeline_log_close "OK"

printf '[aai] Done.\n'
printf '  raw/       : %s\n' "$RAW_DIR"
printf '  processed/ : %s\n' "$PROCESSED_DIR"
