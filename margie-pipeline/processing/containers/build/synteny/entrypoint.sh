#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# CONTAINER ENTRYPOINT — synteny / Liftoff (annotation transfer / gene rescue)
# Installed at /usr/local/bin/run inside the container.
#
# Pipeline-standard interface:
#   run -q /input/query.fna -r /input/references/ -o /output/
#       [-t THREADS] [--organism-name NAME] [--merge]
#
# /input/references/ must contain matching pairs of reference files:
#   <name>.fna   — reference genome assembly
#   <name>.gff3  — reference annotation (GFF3 format)
# The base name (stem) must match for each pair.
#
# Liftoff is run for each reference independently.  When --merge is specified
# (default: true), merge_liftoff.py deduplicates and merges all per-reference
# outputs into a single non-redundant GFF3.
#
# Output layout (under -o):
#   <OUTPUT>/synteny/
#     ├── <ref_name>/
#     │     ├── liftoff.gff3          Liftoff output for this reference
#     │     ├── unmapped_features.txt Features that could not be transferred
#     │     └── liftoff_<ref>.log     Liftoff stderr
#     ├── merged/
#     │     └── merged_annotation.gff3  Non-redundant merge of all references
#     └── synteny-pipeline-log.txt
# ═══════════════════════════════════════════════════════════════════════════════
set -euo pipefail

# shellcheck source=scripts/pipeline_log.sh
source /opt/synteny/scripts/pipeline_log.sh

# ── Usage ─────────────────────────────────────────────────────────────────────
usage() {
    cat <<'HELP_EOF'
synteny — Annotation transfer / gene rescue via Liftoff

USAGE
  docker run ... annotation/synteny:latest \
      -q /input/query.fna -r /input/references/ -o /output/ \
      [-t THREADS] [--organism-name NAME] [--no-merge]

REQUIRED MOUNTS
  /input/         Contains the query genome and references/ subdirectory
  /output/        Output root — writable

REQUIRED OPTIONS
  -q FILE         Query genome FASTA (.fna) — the genome to be annotated
  -r DIR          References directory — contains <name>.fna + <name>.gff3 pairs
  -o DIR          Output root directory

OPTIONAL OPTIONS
  -t INT          CPU threads per Liftoff job              [default: 4]
  --organism-name STR
                  Organism label for provenance log        [default: query stem]
  --no-merge      Skip the merged GFF3 post-processing step
  --help, -h      Show this help and exit

INPUTS (in -r directory)
  Each reference must have a matching pair:
    <name>.fna    Assembly FASTA for the reference genome
    <name>.gff3   Annotation GFF3 for the reference genome
  The 'closest' container produces a closest_organisms.tsv that tells you
  which genomes to use as references.  Download those assemblies and
  annotations from NCBI/GTDB before running this container.

OUTPUTS (under <OUTPUT>/)
  <ref_label>/liftoff.gff3          Transferred annotation for this reference
  <ref_label>/unmapped_features.txt   Features Liftoff could not transfer
  <ref_label>/liftoff_<ref>.log     Liftoff stderr log
  merged/merged_annotation.gff3   Non-redundant merge across all references
                                  (best-coverage feature kept per locus)

NOTES
  Liftoff maps annotation features from reference to query using minimap2
  alignments.  A feature is transferred when the alignment coverage of the
  reference exon exceeds the coverage_threshold (Liftoff default: 50%).
  For gene rescue purposes, features transferred from multiple references
  for the same locus are deduplicated in the merge step; the best-coverage
  hit per locus is retained.

HELP_EOF
}

# ── Argument parsing ───────────────────────────────────────────────────────────
QUERY=""
REFS_DIR=""
OUTPUT_ROOT=""
THREADS=4
ORGANISM_NAME=""
DO_MERGE=1

while [[ $# -gt 0 ]]; do
    case "$1" in
        -q)               QUERY="$2";         shift 2 ;;
        -r)               REFS_DIR="$2";      shift 2 ;;
        -o)               OUTPUT_ROOT="$2";   shift 2 ;;
        -t)               THREADS="$2";       shift 2 ;;
        --organism-name)  ORGANISM_NAME="$2"; shift 2 ;;
        --no-merge)       DO_MERGE=0;         shift 1 ;;
        --help|-h)        usage; exit 0 ;;
        *) printf '[synteny] ERROR: unknown option: %s\n' "$1" >&2; usage >&2; exit 1 ;;
    esac
done

[[ -z "$QUERY"       ]] && { printf '[synteny] ERROR: -q QUERY is required\n'    >&2; exit 1; }
[[ -z "$REFS_DIR"    ]] && { printf '[synteny] ERROR: -r REFS_DIR is required\n' >&2; exit 1; }
[[ -z "$OUTPUT_ROOT" ]] && { printf '[synteny] ERROR: -o OUTPUT is required\n'   >&2; exit 1; }
[[ ! -f "$QUERY"     ]] && { printf '[synteny] ERROR: query file not found: %s\n'  "$QUERY"    >&2; exit 1; }
[[ ! -d "$REFS_DIR"  ]] && { printf '[synteny] ERROR: references dir not found: %s\n' "$REFS_DIR" >&2; exit 1; }

# ── Pre-flight checks ──────────────────────────────────────────────────────────
# Collect references — must have matching .fna + .gff3
declare -a REF_NAMES=()
while IFS= read -r fna; do
    stem="$(basename "$fna" .fna)"
    gff3="$REFS_DIR/${stem}.gff3"
    if [[ -f "$gff3" ]]; then
        REF_NAMES+=("$stem")
    else
        printf '[synteny] WARNING: no matching .gff3 for %s — skipping\n' "$stem" >&2
    fi
done < <(find "$REFS_DIR" -maxdepth 1 -name "*.fna" | sort)

if [[ "${#REF_NAMES[@]}" -eq 0 ]]; then
    printf '[synteny] ERROR: no valid .fna/.gff3 pairs found in %s\n' "$REFS_DIR" >&2
    exit 1
fi

QUERY_STEM="$(basename "$QUERY" .fna)"
[[ -z "$ORGANISM_NAME" ]] && ORGANISM_NAME="$QUERY_STEM"

# ── Directory setup ────────────────────────────────────────────────────────────
# The runner mounts a per-query directory as /output, so we write directly
# into $OUTPUT_ROOT (no extra 'synteny/' subdirectory) to keep paths clean:
#   /output/<ref_name>/liftoff.gff3
#   /output/merged/merged_annotation.gff3
OUTPUT_DIR="$OUTPUT_ROOT"
MERGED_DIR="$OUTPUT_DIR/merged"

mkdir -p "$MERGED_DIR"

# ── Pipeline log init ──────────────────────────────────────────────────────────
pipeline_log_init synteny "${ORGANISM_NAME}" "$OUTPUT_DIR" \
    "$OUTPUT_DIR/synteny-pipeline-log.txt"

pipeline_log_section "INPUTS"
pipeline_log_kv_path "Query genome" "$QUERY"
pipeline_log_kv_path "References"   "$REFS_DIR"
pipeline_log_kv      "References found" "${#REF_NAMES[@]}"
pipeline_log_kv      "Threads"      "$THREADS"

printf '[synteny] Query:        %s\n'    "$QUERY"
printf '[synteny] References:   %s (%d valid pairs)\n' "$REFS_DIR" "${#REF_NAMES[@]}"
printf '[synteny] Output root:  %s\n'   "$OUTPUT_DIR"
printf '[synteny] Threads:      %d\n'   "$THREADS"

# ── Step 1: run Liftoff for each reference ────────────────────────────────────
pipeline_log_section "LIFTOFF RUNS"

for ref_name in "${REF_NAMES[@]}"; do
    ref_fna="$REFS_DIR/${ref_name}.fna"
    ref_gff="$REFS_DIR/${ref_name}.gff3"
    ref_out_dir="$OUTPUT_DIR/${ref_name}"
    liftoff_gff="$ref_out_dir/liftoff.gff3"
    unmapped="$ref_out_dir/unmapped_features.txt"
    liftoff_log="$ref_out_dir/liftoff_${ref_name}.log"
    liftoff_tmp="$ref_out_dir/.liftoff_tmp"

    mkdir -p "$ref_out_dir" "$liftoff_tmp"

    _run_liftoff() {
        liftoff \
            -g  "$ref_gff" \
            -o  "$liftoff_gff" \
            -u  "$unmapped" \
            -dir "$liftoff_tmp" \
            -p  "$THREADS" \
            "$QUERY" \
            "$ref_fna" \
            2>"$liftoff_log"
    }

    if [[ -s "$liftoff_gff" ]]; then
        printf '[synteny] %s: already done (skipping)\n' "$ref_name"
        pipeline_log_skipped \
            "Liftoff ${ref_name}" \
            "liftoff -g $ref_gff -o $liftoff_gff $QUERY $ref_fna" \
            "output already present"
    else
        printf '[synteny] %s: running Liftoff...\n' "$ref_name"
        pipeline_log_step "Liftoff ${ref_name}" _run_liftoff
        pipeline_log_kv_path "  GFF3 output" "$liftoff_gff"
    fi
done

# ── Step 2: merge all per-reference GFF3 outputs ──────────────────────────────
if [[ "$DO_MERGE" -eq 1 ]]; then
    MERGED_GFF3="$MERGED_DIR/merged_annotation.gff3"

    _merge_liftoff() {
        python3 /opt/synteny/scripts/merge_liftoff.py \
            --synteny-dir "$OUTPUT_DIR" \
            --output      "$MERGED_GFF3" \
            --query-name  "$QUERY_STEM"
    }

    printf '[synteny] Merging %d per-reference GFF3 outputs...\n' "${#REF_NAMES[@]}"
    pipeline_log_section "MERGE"
    pipeline_log_step "merge_liftoff.py → merged/merged_annotation.gff3" _merge_liftoff
    pipeline_log_kv_path "Merged GFF3" "$MERGED_GFF3"
else
    printf '[synteny] --no-merge specified; skipping merge step.\n'
fi

# ── Done ──────────────────────────────────────────────────────────────────────
pipeline_log_close "OK"

printf '[synteny] Done.\n'
for ref_name in "${REF_NAMES[@]}"; do
    printf '  %s/  : %s/%s/\n' "$ref_name" "$OUTPUT_DIR" "$ref_name"
done
[[ "$DO_MERGE" -eq 1 ]] && printf '  merged/  : %s\n' "$MERGED_DIR"
