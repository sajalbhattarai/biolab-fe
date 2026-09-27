#!/usr/bin/env bash
# Runner for ani (FastANI — all-vs-all Average Nucleotide Identity).
#
# Collects all .fna files from the gene-caller input directory
# (gene_caller_input), creates a flat staging directory (one .fna per genome
# labelled <genome>.fna), and runs the ani container ONCE over the
# whole collection.  Requires ≥2 input genomes.
#
# The genome label scheme matches run-aai.sh:
#   gene_caller_input/organism1.fna → staging/organism1.fna
#
# Usage:
#   ./run-ani.sh
#   ./run-ani.sh --list
#   ./run-ani.sh -- --min-fraction 0.3   # extra args → container

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/../../../pipeline.conf.sh"
source "$here/lib/pipeline-lib.sh"

TOOL=ani
EXTRA_ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --list)    echo "Tool=ani  image=$(tool_image ani)  out=$(tool_output ani)"; exit 0 ;;
        --help|-h) sed -n '2,12p' "$0"; exit 0 ;;
        --runtime) RUNTIME="$2"; shift 2 ;;
        --)        shift; EXTRA_ARGS+=("$@"); break ;;
        *)         EXTRA_ARGS+=("$1"); shift ;;
    esac
done

image="$(tool_image "$TOOL")"
out="$(tool_output "$TOOL")"

# ── Stage a flat directory of .fna files ──────────────────────────────────────
# Links each $gene_caller_input/<genome>.fna into the staging dir; labels match run-aai.sh.
staging_dir="${TMPDIR:-/tmp}/margie-ani-staging-$$"
mkdir -p "$staging_dir" "$out"
trap 'rm -rf "$staging_dir"' EXIT

n=0
while IFS= read -r -d '' fna; do
    label="$(basename "${fna%.fna}")"
    ln -sf "$fna" "$staging_dir/${label}.fna"
    (( n++ )) || true
done < <(find -L "$gene_caller_input" -maxdepth 1 -type f -name '*.fna' -print0 2>/dev/null | sort -z)

if [[ "$n" -lt 2 ]]; then
    printf '[run-ani] ERROR: all-vs-all requires ≥2 genomes; found %d under %s\n' \
        "$n" "$gene_caller_input" >&2
    exit 1
fi

printf '[run-ani] Staged %d genomes → %s\n' "$n" "$staging_dir"
printf '[run-ani] image=%s  out=%s\n' "$image" "$out"

# ── Run the container ─────────────────────────────────────────────────────────
MOUNTS=(
    "$staging_dir:/input:ro"
    "$out:/output:rw"
)
run_container "$image" \
    -i /input -o /output -t "$THREADS" \
    --organism-name "collection" \
    ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}

printf '[run-ani] Done — results in %s/ani/\n' "$out"
