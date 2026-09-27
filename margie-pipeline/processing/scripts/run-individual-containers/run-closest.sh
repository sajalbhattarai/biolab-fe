#!/usr/bin/env bash
# Runner for closest (AAI + ANI → top-N closest organisms ranking).
#
# Reads the processed symmetric matrices produced by run-aai.sh and
# run-ani.sh, then runs the closest container once over the whole collection.
# At least one of the two matrices must exist before running this script.
#
# Default input paths:
#   $annotation_output_root/aai/processed/aai_results.tsv   (AAI matrix)
#   $annotation_output_root/ani/processed/ani_results.tsv   (ANI matrix)
# Override via TOOL_closest_AAI_MATRIX and TOOL_closest_ANI_MATRIX env vars.
#
# Usage:
#   ./run-closest.sh
#   ./run-closest.sh --list
#   ./run-closest.sh -- --top-n 10 --weight-aai 0.6   # extra args → container

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/../../../pipeline.conf.sh"
source "$here/lib/pipeline-lib.sh"

TOOL=closest
EXTRA_ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --list)    echo "Tool=closest  image=$(tool_image closest)  out=$(tool_output closest)"; exit 0 ;;
        --help|-h) sed -n '2,14p' "$0"; exit 0 ;;
        --runtime) RUNTIME="$2"; shift 2 ;;
        --)        shift; EXTRA_ARGS+=("$@"); break ;;
        *)         EXTRA_ARGS+=("$1"); shift ;;
    esac
done

image="$(tool_image "$TOOL")"
out="$(tool_output "$TOOL")"

# ── Resolve matrix paths ───────────────────────────────────────────────────────
AAI_MATRIX="${TOOL_closest_AAI_MATRIX:-$annotation_output_root/aai/processed/aai_results.tsv}"
ANI_MATRIX="${TOOL_closest_ANI_MATRIX:-$annotation_output_root/ani/processed/ani_results.tsv}"

[[ ! -f "$AAI_MATRIX" && ! -f "$ANI_MATRIX" ]] && {
    printf '[run-closest] ERROR: at least one matrix file must exist before running closest.\n' >&2
    printf '  AAI: %s\n' "$AAI_MATRIX" >&2
    printf '  ANI: %s\n' "$ANI_MATRIX" >&2
    printf '  Run ./run-aai.sh and/or ./run-ani.sh first.\n' >&2
    exit 1
}

mkdir -p "$out"

printf '[run-closest] image=%s  out=%s\n' "$image" "$out"
[[ -f "$AAI_MATRIX" ]] && printf '[run-closest] AAI matrix: %s\n' "$AAI_MATRIX"
[[ -f "$ANI_MATRIX" ]] && printf '[run-closest] ANI matrix: %s\n' "$ANI_MATRIX"

# ── Build container argument list ─────────────────────────────────────────────
# Mounts annotation_output_root read-only and passes matrix paths relative to it.
container_args=(-o /output)
[[ -f "$AAI_MATRIX" ]] && container_args+=(--aai "/input/aai/processed/aai_results.tsv")
[[ -f "$ANI_MATRIX" ]] && container_args+=(--ani "/input/ani/processed/ani_results.tsv")

MOUNTS=(
    "$annotation_output_root:/input:ro"
    "$out:/output:rw"
)
run_container "$image" \
    "${container_args[@]+"${container_args[@]}"}" \
    ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}"}

printf '[run-closest] Done — results in %s/closest/\n' "$out"
