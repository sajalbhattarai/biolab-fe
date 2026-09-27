#!/usr/bin/env bash
# run-prodigal.sh — gene-call the genomes whose gene caller is prodigal in
# $GENOMES_TABLE (no genetic code known, so RASTtk cannot be used). Writes the
# same layout RASTtk does, into its own folder: $OUTPUT_ROOT/prodigal/<genome>/.
# Usage: ./run-prodigal.sh  |  --list  |  --force
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=pipeline.conf.sh
source "$here/../../../pipeline.conf.sh"
# shellcheck source=lib/pipeline-lib.sh
source "$here/lib/pipeline-lib.sh"

TOOL=prodigal
FORCE=0
case "${1:-}" in
    --list)    print_tool_config "$TOOL"; exit 0 ;;
    --force)   FORCE=1 ;;
    -h|--help) sed -n '2,5p' "$0"; exit 0 ;;
esac

[[ -s "$GENOMES_TABLE" ]] || { echo "[prodigal] ERROR: no genome table ($GENOMES_TABLE); run run-prepare-genomes.sh first" >&2; exit 1; }
image="$(tool_image "$TOOL")"

n=0
while IFS= read -r g; do
    [[ -n "${PIPELINE_ORGANISM_FILTER:-}" && "$g" != "$PIPELINE_ORGANISM_FILTER" ]] && continue
    [[ "$(genome_field "$g" gene_caller)" == prodigal ]] || continue
    dst="$(gene_calls_root prodigal)/$g"
    reset_if_gene_caller_changed "$g" prodigal
    if (( ! FORCE )) && [[ "$(cat "$dst/gene_caller.txt" 2>/dev/null)" == prodigal && -s "$dst/gene_calls/genome.faa" ]]; then
        echo "[prodigal] $g: already gene-called, skipping (use --force to redo)"
        continue
    fi
    mkdir -p "$dst"
    code="$(genome_field "$g" genetic_code)"
    MOUNTS=(
        "$INPUT_RASTTK:/input:ro"
        "$dst:/output:rw"
    )
    run_container "$image" -i "/input/$(genome_field "$g" fasta)" -o /output \
        -g "${code:-11}" --domain "$(genome_domain "$g")" --organism-name "$g" --force
    echo prodigal > "$dst/gene_caller.txt"
    (( n++ )) || true
done < <(genome_list)

echo "[prodigal] $n genome(s) gene-called with Prodigal"
