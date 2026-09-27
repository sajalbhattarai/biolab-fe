#!/usr/bin/env bash
# Runner for aai (EzAAI — all-vs-all Average Amino Acid Identity).
#
# Collects all gene_calls/genome.faa files from the gene-caller output
# (annotation_input), creates a flat staging directory (one .faa per genome
# labelled <genome>.faa), and runs the aai container ONCE over the
# whole collection.  Requires ≥2 annotated genomes.
#
# Usage:
#   ./run-aai.sh
#   ./run-aai.sh --list
#   ./run-aai.sh -- --organism-name my-project   # extra args → container

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/../../../pipeline.conf.sh"
source "$here/lib/pipeline-lib.sh"

TOOL=aai
EXTRA_ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --list)    echo "Tool=aai  image=$(tool_image aai)  out=$(tool_output aai)"; exit 0 ;;
        --help|-h) sed -n '2,12p' "$0"; exit 0 ;;
        --runtime) RUNTIME="$2"; shift 2 ;;
        --)        shift; EXTRA_ARGS+=("$@"); break ;;
        *)         EXTRA_ARGS+=("$1"); shift ;;
    esac
done

image="$(tool_image "$TOOL")"
out="$(tool_output "$TOOL")"

# ── Stage a flat directory of .faa files ──────────────────────────────────────
# Links each $annotation_input/<genome>/gene_calls/genome.faa as $staging/<genome>.faa,
# so matrix labels match run-ani.sh.
staging_dir="${TMPDIR:-/tmp}/margie-aai-staging-$$"
mkdir -p "$staging_dir" "$out"
trap 'rm -rf "$staging_dir"' EXIT

n=0
while IFS= read -r -d '' faa; do
    label="$(basename "$(dirname "$(dirname "$faa")")")"   # <genome>/gene_calls/genome.faa
    ln -sf "$faa" "$staging_dir/${label}.faa"
    (( n++ )) || true
done < <(gene_call_roots | while IFS= read -r _root; do
    find -L "$_root" -mindepth 3 -maxdepth 3 -type f -path '*/gene_calls/genome.faa' -not -path '*/.staging-*' -print0 2>/dev/null
done | sort -z)

if [[ "$n" -lt 2 ]]; then
    printf '[run-aai] ERROR: all-vs-all requires ≥2 genomes; found %d under %s\n' \
        "$n" "$(gene_call_roots | tr '\n' ' ')" >&2
    exit 1
fi

printf '[run-aai] Staged %d genomes → %s\n' "$n" "$staging_dir"
printf '[run-aai] image=%s  out=%s\n' "$image" "$out"

# ── Run the container ─────────────────────────────────────────────────────────
MOUNTS=(
    "$staging_dir:/input:ro"
    "$out:/output:rw"
)
run_container "$image" \
    -i /input -o /output -t "$THREADS" \
    --organism-name "collection" \
    ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}

printf '[run-aai] Done — results in %s/aai/\n' "$out"
