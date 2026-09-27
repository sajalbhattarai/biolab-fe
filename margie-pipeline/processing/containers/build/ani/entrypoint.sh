#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# CONTAINER ENTRYPOINT — ani / FastANI (Average Nucleotide Identity, all-vs-all)
# Installed at /usr/local/bin/run inside the container.
#
# Pipeline-standard interface:
#   run -i /input/ -o /output/ [-t THREADS]
#       [--min-fraction FLOAT] [--kmer INT] [--frag-len INT]
#       [--organism-name NAME]
#
# /input/ must contain two or more nucleotide FASTA (.fna) files, one per genome.
#
# Output layout (under -o):
#   <OUTPUT>/ani/
#     ├── raw/
#     │     ├── ani_pairwise.tsv      Raw FastANI pairwise results
#     │     ├── ani_matrix.tsv        FastANI lower-triangular matrix output
#     │     └── ani.stderr            Captured stderr from FastANI
#     └── processed/
#           └── ani_results.tsv       Normalised N×N symmetric matrix TSV
#                                     (consumed by the 'closest' container)
# ═══════════════════════════════════════════════════════════════════════════════
set -euo pipefail

# shellcheck source=scripts/pipeline_log.sh
source /opt/ani/scripts/pipeline_log.sh

# ── Usage ─────────────────────────────────────────────────────────────────────
usage() {
    cat <<'HELP_EOF'
ani — Average Nucleotide Identity via FastANI (all-vs-all prokaryotic genomes)

USAGE
  docker run ... annotation/ani:latest \
      -i /input/ -o /output/ \
      [-t THREADS] [--min-fraction FLOAT] [--kmer INT] [--frag-len INT]
      [--organism-name NAME]

REQUIRED MOUNTS
  /input/    Directory of nucleotide FASTA (.fna) files — one per genome
  /output/   Output root — writable

REQUIRED OPTIONS
  -i DIR         Directory containing .fna input files
  -o DIR         Output root directory

OPTIONAL OPTIONS
  -t INT         CPU threads                              [default: 4]
  --min-fraction FLOAT
                 Minimum fraction of genome covered to   [default: 0.2]
                 report an ANI value (FastANI --minFraction)
  --kmer INT     k-mer size for FastANI sketching         [default: 16]
  --frag-len INT Fragment length for alignment            [default: 3000]
  --organism-name STR
                 Collection label for provenance log      [default: basename of input dir]
  --help, -h     Show this help and exit

OUTPUTS (under <OUTPUT>/ani/)
  raw/ani_pairwise.tsv         Raw FastANI 3-column output (query ref ANI)
  raw/ani_matrix.tsv           FastANI lower-triangular matrix (--matrix flag)
  raw/ani.stderr               Captured stderr from FastANI
  processed/ani_results.tsv   Normalised N×N symmetric matrix (genome names
                               as row and column headers; NA for pairs below
                               --min-fraction threshold)

NOTES
  Requires ≥2 .fna files in -i.
  The species boundary threshold is conventionally ANI ≥ 95% for prokaryotes
  (Jain et al. 2018).  The processed matrix is the input expected by the
  'closest' container.

HELP_EOF
}

# ── Argument parsing ───────────────────────────────────────────────────────────
INPUT=""
OUTPUT_ROOT=""
THREADS=4
MIN_FRACTION=0.2
KMER=16
FRAG_LEN=3000
ORGANISM_NAME=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -i)               INPUT="$2";         shift 2 ;;
        -o)               OUTPUT_ROOT="$2";   shift 2 ;;
        -t)               THREADS="$2";       shift 2 ;;
        --min-fraction)   MIN_FRACTION="$2";  shift 2 ;;
        --kmer)           KMER="$2";          shift 2 ;;
        --frag-len)       FRAG_LEN="$2";      shift 2 ;;
        --organism-name)  ORGANISM_NAME="$2"; shift 2 ;;
        --help|-h)        usage; exit 0 ;;
        *) printf '[ani] ERROR: unknown option: %s\n' "$1" >&2; usage >&2; exit 1 ;;
    esac
done

[[ -z "$INPUT"       ]] && { printf '[ani] ERROR: -i INPUT is required\n'  >&2; exit 1; }
[[ -z "$OUTPUT_ROOT" ]] && { printf '[ani] ERROR: -o OUTPUT is required\n' >&2; exit 1; }
[[ ! -d "$INPUT"     ]] && { printf '[ani] ERROR: input directory not found: %s\n' "$INPUT" >&2; exit 1; }

# ── Pre-flight checks ──────────────────────────────────────────────────────────
FNA_COUNT=$(find "$INPUT" -maxdepth 1 -name "*.fna" | wc -l)
if [[ "$FNA_COUNT" -lt 2 ]]; then
    printf '[ani] ERROR: all-vs-all requires ≥2 .fna files in %s (found %d)\n' \
        "$INPUT" "$FNA_COUNT" >&2
    exit 1
fi

[[ -z "$ORGANISM_NAME" ]] && ORGANISM_NAME="$(basename "$INPUT")"

# ── Directory setup ────────────────────────────────────────────────────────────
OUTPUT_DIR="$OUTPUT_ROOT/ani"
RAW_DIR="$OUTPUT_DIR/raw"
PROCESSED_DIR="$OUTPUT_DIR/processed"

mkdir -p "$RAW_DIR" "$PROCESSED_DIR"

# ── Pipeline log init ──────────────────────────────────────────────────────────
pipeline_log_init ani "${ORGANISM_NAME}" "$OUTPUT_DIR" "$OUTPUT_DIR/ani-pipeline-log.txt"

pipeline_log_section "INPUTS"
pipeline_log_kv_path "Input dir"    "$INPUT"
pipeline_log_kv      "FNA files"    "$FNA_COUNT"
pipeline_log_kv      "Threads"      "$THREADS"
pipeline_log_kv      "Min fraction" "$MIN_FRACTION"
pipeline_log_kv      "k-mer size"   "$KMER"
pipeline_log_kv      "Frag length"  "$FRAG_LEN"

GENOME_LIST="$RAW_DIR/genome_list.txt"
RAW_PAIRWISE="$RAW_DIR/ani_pairwise.tsv"
RAW_MATRIX="$RAW_DIR/ani_matrix.tsv"
RAW_ERR="$RAW_DIR/ani.stderr"
PROCESSED_TSV="$PROCESSED_DIR/ani_results.tsv"

printf '[ani] Input dir:   %s (%d .fna files)\n' "$INPUT" "$FNA_COUNT"
printf '[ani] Output root: %s\n' "$OUTPUT_DIR"
printf '[ani] Threads:     %d\n' "$THREADS"

# ── Step 1: build genome list ──────────────────────────────────────────────────
_build_list() {
    find "$INPUT" -maxdepth 1 -name "*.fna" | sort > "$GENOME_LIST"
    printf '[ani] Genome list: %s (%d entries)\n' "$GENOME_LIST" "$(wc -l < "$GENOME_LIST")"
}

pipeline_log_step "build genome list" _build_list
pipeline_log_kv_path "Genome list" "$GENOME_LIST"

# ── Step 2: FastANI all-vs-all ─────────────────────────────────────────────────
_fastani() {
    fastANI \
        --ql   "$GENOME_LIST" \
        --rl   "$GENOME_LIST" \
        -o     "$RAW_PAIRWISE" \
        -t     "$THREADS" \
        -k     "$KMER" \
        --fragLen    "$FRAG_LEN" \
        --minFraction "$MIN_FRACTION" \
        --matrix \
        2>"$RAW_ERR"
    # FastANI --matrix writes a separate file <output>.matrix
    if [[ -f "${RAW_PAIRWISE}.matrix" ]]; then
        mv "${RAW_PAIRWISE}.matrix" "$RAW_MATRIX"
    fi
}

if [[ -s "$RAW_PAIRWISE" ]]; then
    printf '[ani] Raw pairwise output already present; skipping FastANI.\n'
    pipeline_log_skipped "FastANI all-vs-all" \
        "fastANI --ql ... --rl ... -o $RAW_PAIRWISE --matrix" \
        "output already present"
else
    printf '[ani] Running FastANI all-vs-all (%d threads)...\n' "$THREADS"
    pipeline_log_step "FastANI all-vs-all" _fastani
fi

pipeline_log_kv_path "Raw pairwise"      "$RAW_PAIRWISE"
pipeline_log_kv_path "Raw matrix"        "$RAW_MATRIX"

# ── Step 3: post-process → normalised symmetric matrix ────────────────────────
_postprocess() {
    python3 /opt/ani/scripts/process_ani_raw_results.py \
        --input           "$RAW_PAIRWISE" \
        --output          "$PROCESSED_TSV" \
        --collection-name "$ORGANISM_NAME"
}

printf '[ani] Post-processing raw results...\n'
pipeline_log_step "post-process → processed/ani_results.tsv" _postprocess
pipeline_log_kv_path "Processed matrix" "$PROCESSED_TSV"

# ── Done ──────────────────────────────────────────────────────────────────────
pipeline_log_close "OK"

printf '[ani] Done.\n'
printf '  raw/       : %s\n' "$RAW_DIR"
printf '  processed/ : %s\n' "$PROCESSED_DIR"
