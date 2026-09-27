#!/usr/bin/env bash
# run-envelope.sh — infer each genome's cell envelope (margie_sb phase 7) from
# its tigrfam, pgap, pfam and uniprot results: diderm-gram-negative-like,
# monoderm-gram-positive-like, or archaea. psortb, deepsig and signalp4 read
# the result (shared/genomes.sh: envelope_flag); nothing else uses gram.
# Writes $annotation_output_root/envelope/<genome>/processed/envelope_summary.tsv.
# Usage: ./run-envelope.sh  |  --list
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=pipeline.conf.sh
source "$here/../../../pipeline.conf.sh"
# shellcheck source=lib/pipeline-lib.sh
source "$here/lib/pipeline-lib.sh"

TOOL=envelope
case "${1:-}" in
    --list)    print_tool_config "$TOOL"; exit 0 ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
esac

image="$(tool_image "$TOOL")"
out="$(tool_output "$TOOL")"

n=0
while IFS= read -r g; do
    [[ -n "${PIPELINE_ORGANISM_FILTER:-}" && "$g" != "$PIPELINE_ORGANISM_FILTER" ]] && continue
    dst="$out/$g"
    mkdir -p "$dst"
    # Mounts only this genome's four inputs, since the container scans all of /input/<tool>/.
    MOUNTS=("$dst:/output:rw")
    found=()
    for t in tigrfam pgap pfam uniprot; do
        p="$annotation_output_root/$t/$g/processed"
        if [[ -d "$p" ]]; then MOUNTS+=("$p:/input/$t/processed:ro"); found+=("$t"); fi
    done
    if (( ${#found[@]} == 0 )); then
        echo "[envelope] $g: no tigrfam/pgap/pfam/uniprot results; skipping" >&2
        continue
    fi
    (( ${#found[@]} < 4 )) && echo "[envelope] $g: using ${found[*]} (the others have no results)" >&2
    run_container "$image" -i /input -o /output --domain "$(genome_domain "$g")" --organism-name "$g"
    echo "[envelope] $g: $(envelope_type "$g")"
    (( n++ )) || true
done < <(genome_list)

echo "[envelope] $n genome(s) done"
