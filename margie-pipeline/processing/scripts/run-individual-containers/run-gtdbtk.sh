#!/usr/bin/env bash
# Runner for gtdbtk (collection-level taxonomy assignment).
#
# Stages all genome FASTA files from INPUT_RASTTK (default: input/) into a flat
# temporary directory and runs the gtdbtk container once over the collection.
#
# Usage:
#   ./run-gtdbtk.sh
#   ./run-gtdbtk.sh --list
#   ./run-gtdbtk.sh -- --extension fa

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/../../../pipeline.conf.sh"
source "$here/lib/pipeline-lib.sh"

TOOL=gtdbtk
EXTRA_ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --list)
            echo "Tool          = $TOOL"
            echo "Runtime       = $(detect_runtime)"
            echo "Image         = $(tool_image "$TOOL")"
            echo "DB            = $(tool_db "$TOOL")"
            echo "Input         = ${TOOL_gtdbtk_INPUT:-$gene_caller_input} (expects .fna/.fa/.fasta collection)"
            echo "Output        = $(tool_output "$TOOL")"
            echo "Threads       = $THREADS"
            exit 0
            ;;
        --help|-h)   sed -n '2,14p' "$0"; exit 0 ;;
        --runtime)   RUNTIME="$2"; shift 2 ;;
        --)          shift; EXTRA_ARGS+=("$@"); break ;;
        *)           EXTRA_ARGS+=("$1"); shift ;;
    esac
done

image="$(tool_image "$TOOL")"
out="$(tool_output "$TOOL")"
db="$(tool_db "$TOOL")"

[[ -d "$db" ]] || {
    echo "[run-gtdbtk] ERROR: DB for $TOOL not found: $db" >&2
    echo "[run-gtdbtk] Set TOOL_gtdbtk_DB or create $db with GTDB-Tk data package." >&2
    exit 1
}

input_root="${TOOL_gtdbtk_INPUT:-$gene_caller_input}"
[[ -d "$input_root" ]] || {
    echo "[run-gtdbtk] ERROR: input root not found: $input_root" >&2
    exit 1
}

staging_dir="${TMPDIR:-/tmp}/margie-gtdbtk-staging-$$"
mkdir -p "$staging_dir" "$out"
trap 'rm -rf "$staging_dir"' EXIT

n=0
while IFS= read -r -d '' fna; do
    rel="${fna#${input_root%/}/}"
    label="$(printf '%s' "${rel%.*}" | tr '/' '__')"
    # Copies into staging, since container-side checks need regular files.
    cp -f "$fna" "$staging_dir/${label}.fna"
    (( n++ )) || true
done < <(find -L "$input_root" -type f \( -name '*.fna' -o -name '*.fa' -o -name '*.fasta' \) -print0 2>/dev/null | sort -z)

if [[ "$n" -lt 1 ]]; then
    echo "[run-gtdbtk] ERROR: no genome FASTA files found under $input_root" >&2
    exit 1
fi

echo "[run-gtdbtk] Staged $n genomes -> $staging_dir"
echo "[run-gtdbtk] image=$image"
echo "[run-gtdbtk] db=$db"
echo "[run-gtdbtk] out=$out"

MOUNTS=(
    "$staging_dir:/input:ro"
    "$out:/output:rw"
    "$db:/db:ro"
)

# Disables --place_species: ANI screening already assigns species, and pplacer here
# hits a GTDB-Tk bug (UnboundLocalError: bac_ar_diff) on mixed bacterial/archaeal sets.
export APPTAINERENV_GTDBTK_PLACE_SPECIES=0
export SINGULARITYENV_GTDBTK_PLACE_SPECIES=0

run_container "$image" \
    -i /input -o /output -d /db -t "$THREADS" \
    --collection-name collection \
    ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}

echo "[run-gtdbtk] Done -> $out/gtdbtk"
