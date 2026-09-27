#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# CONTAINER ENTRYPOINT — closest (AAI + ANI → top-N closest organisms)
# Installed at /usr/local/bin/run inside the container.
#
# Ranks the top-N closest organisms for each genome within the collection,
# using pre-computed all-vs-all AAI and/or ANI symmetric matrices produced by
# the 'aai' and 'ani' containers respectively.  No external database required.
#
# Pipeline-standard interface:
#   run -o /output/
#       [--aai /input/aai/processed/aai_results.tsv]
#       [--ani /input/ani/processed/ani_results.tsv]
#       [--top-n INT] [--weight-aai FLOAT] [--weight-ani FLOAT]
#       [--collection-name NAME]
#
# At least one of --aai or --ani must be provided.
#
# Output layout (under -o):
#   <OUTPUT>/closest/
#     ├── processed/
#     │     └── closest_organisms.tsv   Per-genome top-N rankings
#     └── closest-pipeline-log.txt
# ═══════════════════════════════════════════════════════════════════════════════
set -euo pipefail

# shellcheck source=scripts/pipeline_log.sh
source /opt/closest/scripts/pipeline_log.sh

# ── Usage ─────────────────────────────────────────────────────────────────────
usage() {
    cat <<'HELP_EOF'
closest — Rank top-N closest organisms per genome from AAI + ANI matrices

USAGE
  docker run ... annotation/closest:latest \
      -o /output/ \
      [--aai /input/aai/processed/aai_results.tsv] \
      [--ani /input/ani/processed/ani_results.tsv] \
      [--top-n INT] [--weight-aai FLOAT] [--weight-ani FLOAT]

REQUIRED MOUNTS
  /output/     Output root — writable

REQUIRED OPTIONS
  -o DIR       Output root directory

OPTIONAL OPTIONS (at least one of --aai / --ani is required)
  --aai FILE   Symmetric AAI matrix TSV from the 'aai' container
               (processed/aai_results.tsv)
  --ani FILE   Symmetric ANI matrix TSV from the 'ani' container
               (processed/ani_results.tsv)
  --top-n INT  Number of closest organisms to report per genome  [default: 5]
  --weight-aai FLOAT
               Weight for AAI signal in composite score           [default: 0.5]
  --weight-ani FLOAT
               Weight for ANI signal in composite score           [default: 0.5]
               (weights are renormalised when only one matrix is provided)
  --collection-name STR
               Collection label for provenance log  [default: "collection"]
  --help, -h   Show this help and exit

OUTPUTS (under <OUTPUT>/closest/)
  processed/closest_organisms.tsv
                 Per-genome top-N rankings with columns:
                   query_genome, rank, reference_genome, aai, ani,
                   composite_score
  closest-pipeline-log.txt
                 Pipeline run log

RANKING ALGORITHM
  composite_score = w_aai * (AAI/100) + w_ani * (ANI/100)
  Weights are automatically renormalised when only one signal is available.
  Self-comparisons are excluded from rankings.

HELP_EOF
}

# ── Argument parsing ───────────────────────────────────────────────────────────
OUTPUT_ROOT=""
AAI_MATRIX=""
ANI_MATRIX=""
TOP_N=5
WEIGHT_AAI=0.5
WEIGHT_ANI=0.5
COLLECTION_NAME="collection"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -o)                 OUTPUT_ROOT="$2";      shift 2 ;;
        --aai)              AAI_MATRIX="$2";       shift 2 ;;
        --ani)              ANI_MATRIX="$2";       shift 2 ;;
        --top-n)            TOP_N="$2";            shift 2 ;;
        --weight-aai)       WEIGHT_AAI="$2";       shift 2 ;;
        --weight-ani)       WEIGHT_ANI="$2";       shift 2 ;;
        --collection-name)  COLLECTION_NAME="$2";  shift 2 ;;
        --help|-h)          usage; exit 0 ;;
        *) printf '[closest] ERROR: unknown option: %s\n' "$1" >&2; usage >&2; exit 1 ;;
    esac
done

[[ -z "$OUTPUT_ROOT" ]] && { printf '[closest] ERROR: -o OUTPUT is required\n' >&2; exit 1; }
[[ -z "$AAI_MATRIX" && -z "$ANI_MATRIX" ]] && {
    printf '[closest] ERROR: at least one of --aai or --ani must be provided\n' >&2; exit 1; }
[[ -n "$AAI_MATRIX" && ! -f "$AAI_MATRIX" ]] && {
    printf '[closest] ERROR: AAI matrix file not found: %s\n' "$AAI_MATRIX" >&2; exit 1; }
[[ -n "$ANI_MATRIX" && ! -f "$ANI_MATRIX" ]] && {
    printf '[closest] ERROR: ANI matrix file not found: %s\n' "$ANI_MATRIX" >&2; exit 1; }

# ── Directory setup ────────────────────────────────────────────────────────────
OUTPUT_DIR="$OUTPUT_ROOT/closest"
PROCESSED_DIR="$OUTPUT_DIR/processed"

mkdir -p "$PROCESSED_DIR"

# ── Pipeline log init ──────────────────────────────────────────────────────────
pipeline_log_init closest "${COLLECTION_NAME}" "$OUTPUT_DIR" \
    "$OUTPUT_DIR/closest-pipeline-log.txt"

pipeline_log_section "INPUTS"
[[ -n "$AAI_MATRIX" ]] && pipeline_log_kv_path "AAI matrix" "$AAI_MATRIX"
[[ -n "$ANI_MATRIX" ]] && pipeline_log_kv_path "ANI matrix" "$ANI_MATRIX"
pipeline_log_kv "Top-N"          "$TOP_N"
pipeline_log_kv "Weight AAI"     "$WEIGHT_AAI"
pipeline_log_kv "Weight ANI"     "$WEIGHT_ANI"

RANKINGS_TSV="$PROCESSED_DIR/closest_organisms.tsv"

printf '[closest] Output root:   %s\n' "$OUTPUT_DIR"
printf '[closest] Top-N:         %d\n' "$TOP_N"
[[ -n "$AAI_MATRIX" ]] && printf '[closest] AAI matrix:    %s\n' "$AAI_MATRIX"
[[ -n "$ANI_MATRIX" ]] && printf '[closest] ANI matrix:    %s\n' "$ANI_MATRIX"

# ── Step 1: rank_closest.py ───────────────────────────────────────────────────
_rank_closest() {
    local args=(
        --output          "$RANKINGS_TSV"
        --top-n           "$TOP_N"
        --weight-aai      "$WEIGHT_AAI"
        --weight-ani      "$WEIGHT_ANI"
        --collection-name "$COLLECTION_NAME"
    )
    [[ -n "$AAI_MATRIX" ]] && args+=(--aai "$AAI_MATRIX")
    [[ -n "$ANI_MATRIX" ]] && args+=(--ani "$ANI_MATRIX")

    python3 /opt/closest/scripts/rank_closest.py "${args[@]}"
}

if [[ -s "$RANKINGS_TSV" ]]; then
    printf '[closest] Rankings already present; skipping.\n'
    pipeline_log_skipped "rank_closest.py" \
        "python3 /opt/closest/scripts/rank_closest.py ..." \
        "output already present"
else
    printf '[closest] Computing top-%d closest organisms per genome...\n' "$TOP_N"
    pipeline_log_step "rank_closest.py → processed/closest_organisms.tsv" _rank_closest
fi

pipeline_log_kv_path "Rankings TSV" "$RANKINGS_TSV"

# ── Done ──────────────────────────────────────────────────────────────────────
pipeline_log_close "OK"

printf '[closest] Done.\n'
printf '  processed/ : %s\n' "$PROCESSED_DIR"
set -euo pipefail

# shellcheck source=scripts/pipeline_log.sh
source /opt/closest/scripts/pipeline_log.sh

# ── Usage ─────────────────────────────────────────────────────────────────────
usage() {
    cat <<'HELP_EOF'
closest — Identify top-N closest organisms via GTDB-Tk + AAI + ANI ranking

USAGE
  docker run ... annotation/closest:latest \
      -i /input/ -o /output/ -d /db/gtdbtk \
      [--aai /input/aai/processed/aai_results.tsv] \
      [--ani /input/ani/processed/ani_results.tsv] \
      [-t THREADS] [--top-n INT] [--organism-name NAME]

REQUIRED MOUNTS
  /input/       Directory of nucleotide FASTA (.fna) files — one per genome
  /output/      Output root — writable
  /db/gtdbtk    GTDB-Tk reference data directory (r220, ~60 GB)

REQUIRED OPTIONS
  -i DIR        Directory containing .fna input files
  -o DIR        Output root directory
  -d DIR        GTDB-Tk reference data directory

OPTIONAL OPTIONS
  --aai FILE    AAI matrix TSV from the 'aai' container
                (processed/aai_results.tsv)
  --ani FILE    ANI matrix TSV from the 'ani' container
                (processed/ani_results.tsv)
  -t INT        CPU threads                              [default: 4]
  --top-n INT   Number of closest organisms to report   [default: 5]
  --organism-name STR
                Collection label for provenance log     [default: basename of input dir]
  --skip-gtdbtk Use existing GTDB-Tk output; skip classify_wf [default: false]
  --help, -h    Show this help and exit

OUTPUTS (under <OUTPUT>/closest/)
  gtdbtk/                          Full GTDB-Tk classify_wf output directory
  rankings/closest_organisms.tsv   Per-genome top-N rankings with columns:
                                     query_genome, rank, reference_genome,
                                     aai, ani, gtdbtk_ani, gtdbtk_taxonomy,
                                     composite_score
  closest-pipeline-log.txt         Pipeline run log

RANKING ALGORITHM
  composite_score = 0.4 * (AAI/100) + 0.4 * (ANI/100) + 0.2 * (gtdbtk_ani/100)
  When --aai or --ani are omitted, the missing component is excluded and the
  remaining weights are renormalised (e.g. 0.5/0.5 for GTDB-Tk + ANI only).

DATABASE SETUP
  Download the GTDB-Tk r220 reference data (~60 GB) using:
    processing/scripts/setup-scripts/setup-databases/download-gtdb.sh

HELP_EOF
}

# ── Argument parsing ───────────────────────────────────────────────────────────
INPUT=""
OUTPUT_ROOT=""
DB_DIR=""
AAI_MATRIX=""
ANI_MATRIX=""
THREADS=4
TOP_N=5
ORGANISM_NAME=""
SKIP_GTDBTK=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -i)               INPUT="$2";         shift 2 ;;
        -o)               OUTPUT_ROOT="$2";   shift 2 ;;
        -d)               DB_DIR="$2";        shift 2 ;;
        --aai)            AAI_MATRIX="$2";    shift 2 ;;
        --ani)            ANI_MATRIX="$2";    shift 2 ;;
        -t)               THREADS="$2";       shift 2 ;;
        --top-n)          TOP_N="$2";         shift 2 ;;
        --organism-name)  ORGANISM_NAME="$2"; shift 2 ;;
        --skip-gtdbtk)    SKIP_GTDBTK=1;      shift 1 ;;
        --help|-h)        usage; exit 0 ;;
        *) printf '[closest] ERROR: unknown option: %s\n' "$1" >&2; usage >&2; exit 1 ;;
    esac
done

[[ -z "$INPUT"       ]] && { printf '[closest] ERROR: -i INPUT is required\n'  >&2; exit 1; }
[[ -z "$OUTPUT_ROOT" ]] && { printf '[closest] ERROR: -o OUTPUT is required\n' >&2; exit 1; }
[[ -z "$DB_DIR"      ]] && { printf '[closest] ERROR: -d DB_DIR is required\n' >&2; exit 1; }
[[ ! -d "$INPUT"     ]] && { printf '[closest] ERROR: input directory not found: %s\n'  "$INPUT"  >&2; exit 1; }
[[ ! -d "$DB_DIR"    ]] && { printf '[closest] ERROR: database directory not found: %s\n' "$DB_DIR" >&2; exit 1; }

# ── Pre-flight checks ──────────────────────────────────────────────────────────
FNA_COUNT=$(find "$INPUT" -maxdepth 1 -name "*.fna" | wc -l)
[[ "$FNA_COUNT" -lt 1 ]] && {
    printf '[closest] ERROR: no .fna files found in %s\n' "$INPUT" >&2
    exit 1
}

[[ -z "$ORGANISM_NAME" ]] && ORGANISM_NAME="$(basename "$INPUT")"

# ── Directory setup ────────────────────────────────────────────────────────────
OUTPUT_DIR="$OUTPUT_ROOT/closest"
GTDBTK_DIR="$OUTPUT_DIR/gtdbtk"
RANKINGS_DIR="$OUTPUT_DIR/rankings"

mkdir -p "$GTDBTK_DIR" "$RANKINGS_DIR"

# ── Pipeline log init ──────────────────────────────────────────────────────────
pipeline_log_init closest "${ORGANISM_NAME}" "$OUTPUT_DIR" \
    "$OUTPUT_DIR/closest-pipeline-log.txt"

pipeline_log_section "INPUTS"
pipeline_log_kv_path "Input dir"    "$INPUT"
pipeline_log_kv      "FNA files"    "$FNA_COUNT"
pipeline_log_kv_path "DB dir"       "$DB_DIR"
pipeline_log_kv      "Threads"      "$THREADS"
pipeline_log_kv      "Top-N"        "$TOP_N"
[[ -n "$AAI_MATRIX" ]] && pipeline_log_kv_path "AAI matrix" "$AAI_MATRIX"
[[ -n "$ANI_MATRIX" ]] && pipeline_log_kv_path "ANI matrix" "$ANI_MATRIX"

RANKINGS_TSV="$RANKINGS_DIR/closest_organisms.tsv"

printf '[closest] Input dir:   %s (%d .fna files)\n' "$INPUT" "$FNA_COUNT"
printf '[closest] Output root: %s\n' "$OUTPUT_DIR"
printf '[closest] Threads:     %d\n' "$THREADS"
printf '[closest] Top-N:       %d\n' "$TOP_N"

# Set GTDB-Tk data path (can be overridden by env if needed)
export GTDBTK_DATA_PATH="${GTDBTK_DATA_PATH:-$DB_DIR}"

# ── Step 1: GTDB-Tk classify_wf ───────────────────────────────────────────────
_gtdbtk_classify() {
    gtdbtk classify_wf \
        --genome_dir "$INPUT" \
        --out_dir    "$GTDBTK_DIR" \
        --cpus       "$THREADS" \
  --extension  fna
}

if [[ "$SKIP_GTDBTK" -eq 1 ]] && [[ -d "$GTDBTK_DIR" ]]; then
    printf '[closest] --skip-gtdbtk: using existing GTDB-Tk output in %s\n' "$GTDBTK_DIR"
    pipeline_log_skipped "GTDB-Tk classify_wf" \
        "gtdbtk classify_wf --genome_dir $INPUT --out_dir $GTDBTK_DIR" \
        "--skip-gtdbtk flag set"
elif ls "$GTDBTK_DIR"/*.summary.tsv >/dev/null 2>&1; then
    printf '[closest] GTDB-Tk output already present; skipping classify_wf.\n'
    pipeline_log_skipped "GTDB-Tk classify_wf" \
        "gtdbtk classify_wf --genome_dir $INPUT --out_dir $GTDBTK_DIR" \
        "output already present"
else
    printf '[closest] Running GTDB-Tk classify_wf (%d threads)...\n' "$THREADS"
    pipeline_log_step "GTDB-Tk classify_wf" _gtdbtk_classify
fi

pipeline_log_kv_path "GTDB-Tk output" "$GTDBTK_DIR"

# ── Step 2: rank_closest.py ────────────────────────────────────────────────────
_rank_closest() {
    local args=(
        --gtdbtk     "$GTDBTK_DIR"
        --output     "$RANKINGS_TSV"
        --top-n      "$TOP_N"
        --collection-name "$ORGANISM_NAME"
    )
    [[ -n "$AAI_MATRIX" ]] && args+=(--aai "$AAI_MATRIX")
    [[ -n "$ANI_MATRIX" ]] && args+=(--ani "$ANI_MATRIX")

    python3 /opt/closest/scripts/rank_closest.py "${args[@]}"
}

printf '[closest] Computing top-%d closest organisms per genome...\n' "$TOP_N"
pipeline_log_step "rank_closest.py → rankings/closest_organisms.tsv" _rank_closest
pipeline_log_kv_path "Rankings TSV" "$RANKINGS_TSV"

# ── Done ──────────────────────────────────────────────────────────────────────
pipeline_log_close "OK"

printf '[closest] Done.\n'
printf '  gtdbtk/   : %s\n' "$GTDBTK_DIR"
printf '  rankings/ : %s\n' "$RANKINGS_DIR"
