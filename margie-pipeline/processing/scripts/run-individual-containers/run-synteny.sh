#!/usr/bin/env bash
# Runner for synteny (Liftoff — annotation transfer / gene rescue).
#
# Reads the closest_organisms.tsv produced by run-closest.sh, then for each
# unique query genome runs the synteny container once (transferring annotations
# from the top-N closest reference genomes within the collection).
#
# Output layout per query genome:
#   $annotation_output_root/synteny/<query_label>/<ref_label>/liftoff.gff3
#   $annotation_output_root/synteny/<query_label>/merged/merged_annotation.gff3
#
# Override the closest TSV path via TOOL_synteny_CLOSEST_TSV.
# Genome labels are the genome keys (input/<genome>.fna); a reference's GFF3
# is <caller folder>/<genome>/rast.gff, else its gene_calls/genome.gff
# (RASTtk or Prodigal).
#
# Usage:
#   ./run-synteny.sh
#   ./run-synteny.sh --list
#   ./run-synteny.sh --query org1   # single query
#   ./run-synteny.sh -- --no-merge   # extra args → container

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/../../../pipeline.conf.sh"
source "$here/lib/pipeline-lib.sh"

TOOL=synteny
EXTRA_ARGS=()
SINGLE_QUERY=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --list)    echo "Tool=synteny  image=$(tool_image synteny)  out=$(tool_output synteny)"; exit 0 ;;
        --help|-h) sed -n '2,18p' "$0"; exit 0 ;;
        --runtime) RUNTIME="$2"; shift 2 ;;
        --query)   SINGLE_QUERY="$2"; shift 2 ;;
        --)        shift; EXTRA_ARGS+=("$@"); break ;;
        *)         EXTRA_ARGS+=("$1"); shift ;;
    esac
done

image="$(tool_image "$TOOL")"
out="$(tool_output "$TOOL")"

CLOSEST_TSV="${TOOL_synteny_CLOSEST_TSV:-$annotation_output_root/closest/processed/closest_organisms.tsv}"

if [[ ! -f "$CLOSEST_TSV" ]]; then
    printf '[run-synteny] ERROR: closest organisms TSV not found: %s\n' "$CLOSEST_TSV" >&2
    printf '  Run ./run-closest.sh first.\n' >&2
    exit 1
fi

# ── Helpers: genome label → files ─────────────────────────────────────────────
find_fna() {
    local label="$1"
    local candidate="$gene_caller_input/${label}.fna"
    if [[ -f "$candidate" ]]; then
        echo "$candidate"
        return 0
    fi
    printf '[run-synteny] WARNING: no .fna found for label=%s (tried %s)\n' \
        "$label" "$candidate" >&2
    return 1
}

find_gff() {
    local label="$1" orgdir candidate found
    orgdir="$(genome_calls_dir "$1" 2>/dev/null || echo "$annotation_input/$1")"
    for candidate in "$orgdir/rast.gff" "$orgdir/gene_calls/genome.gff"; do
        if [[ -s "$candidate" ]]; then
            echo "$candidate"
            return 0
        fi
    done
    # Falls back to any .gff or .gff3 in the organism directory.
    found="$(find -L "$orgdir" -maxdepth 1 \( -name '*.gff3' -o -name '*.gff' \) 2>/dev/null | head -1)"
    if [[ -n "$found" ]]; then
        echo "$found"
        return 0
    fi
    printf '[run-synteny] WARNING: no .gff/.gff3 found for label=%s under %s\n' \
        "$label" "$orgdir" >&2
    return 1
}

# ── Read the closest TSV ──────────────────────────────────────────────────────
# Columns: query_genome, rank, reference_genome, aai, ani, composite_score
# (bash 3.2 has no associative arrays, so references are looked up per query.)
queries=()
while IFS= read -r q; do
    queries+=("$q")
done < <(awk -F'\t' -v only="$SINGLE_QUERY" '
    $1 != "" && $1 != "query_genome" && (only == "" || $1 == only) && !seen[$1]++ { print $1 }
' "$CLOSEST_TSV")

# Prints a query's reference labels in rank order.
refs_for() {
    awk -F'\t' -v q="$1" '$1 == q && $3 != "" { print $3 }' "$CLOSEST_TSV"
}

if [[ "${#queries[@]}" -eq 0 ]]; then
    printf '[run-synteny] ERROR: no query genomes found in %s\n' "$CLOSEST_TSV" >&2
    [[ -n "$SINGLE_QUERY" ]] && printf '  (--query filter: %s)\n' "$SINGLE_QUERY" >&2
    exit 1
fi

printf '[run-synteny] %d query genomes to process\n' "${#queries[@]}"
mkdir -p "$out"

# ── Run synteny for each query ────────────────────────────────────────────────
ok=0; fail=0
for query_label in "${queries[@]}"; do
    query_fna="$(find_fna "$query_label")" || { (( fail++ )) || true; continue; }
    query_out="$out/${query_label}"

    # Staging refs/ directory for this query's top-N closest genomes.
    staging_dir="${TMPDIR:-/tmp}/margie-synteny-${query_label}-$$"
    mkdir -p "$staging_dir/refs"
    trap 'rm -rf "$staging_dir"' RETURN 2>/dev/null || true

    # The container expects the query at /staging/query.fna.
    ln -sf "$query_fna" "$staging_dir/query.fna"

    ref_count=0
    for ref_label in $(refs_for "$query_label"); do
        ref_fna="$(find_fna "$ref_label")"  || continue
        ref_gff="$(find_gff "$ref_label")"  || continue
        ln -sf "$ref_fna" "$staging_dir/refs/${ref_label}.fna"
        ln -sf "$ref_gff" "$staging_dir/refs/${ref_label}.gff3"
        (( ref_count++ )) || true
    done

    if [[ "$ref_count" -eq 0 ]]; then
        printf '[run-synteny] WARNING: no valid references for %s — skipping\n' "$query_label" >&2
        rm -rf "$staging_dir"
        (( fail++ )) || true
        continue
    fi

    mkdir -p "$query_out"
    printf '[run-synteny] query=%s  refs=%d\n' "$query_label" "$ref_count"

    MOUNTS=(
        "$staging_dir:/synteny_input:ro"
        "$query_out:/output:rw"
    )
    if run_container "$image" \
            -q /synteny_input/query.fna \
            -r /synteny_input/refs/ \
            -o /output \
            -t "$THREADS" \
            --organism-name "$query_label" \
            ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}; then
        (( ok++ )) || true
    else
        printf '[run-synteny] ERROR: container failed for %s\n' "$query_label" >&2
        (( fail++ )) || true
    fi
    rm -rf "$staging_dir"
done

printf '[run-synteny] Done — success=%d  failed=%d\n' "$ok" "$fail"
printf '  results in %s/synteny/\n' "$out"
[[ "$fail" -gt 0 ]] && exit 1 || exit 0
