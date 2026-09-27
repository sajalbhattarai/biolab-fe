#!/usr/bin/env bash
# run-rasttk.sh — call RASTtk on the genomes whose gene caller is rasttk in
# $GENOMES_TABLE (domain and genetic code both known), passing both, as
# margie_sb does. Each genome's result lands in $OUTPUT_ROOT/rasttk/<genome>/.
# Usage: ./run-rasttk.sh  |  --list  |  --force  |  -- <extra args for the container>
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=pipeline.conf.sh
source "$here/../../../pipeline.conf.sh"
# shellcheck source=lib/pipeline-lib.sh
source "$here/lib/pipeline-lib.sh"
# shellcheck source=../shared/bvbrc-env.sh
source "$here/../shared/bvbrc-env.sh"

TOOL=rasttk
EXTRA_ARGS=()
FORCE=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --list)      print_tool_config "$TOOL"; exit 0 ;;
        --help|-h)   sed -n '2,5p' "$0"; exit 0 ;;
        --runtime)   RUNTIME="$2"; shift 2 ;;
        --force)     FORCE=1; shift ;;
        --)          shift; EXTRA_ARGS+=("$@"); break ;;
        *)           EXTRA_ARGS+=("$1"); shift ;;
    esac
done

[[ -s "$GENOMES_TABLE" ]] || { echo "[rasttk] ERROR: no genome table ($GENOMES_TABLE); run run-prepare-genomes.sh first" >&2; exit 1; }
image="$(tool_image "$TOOL")"
db="$(tool_db "$TOOL")"

genomes=()
while IFS= read -r g; do
    [[ -n "${PIPELINE_ORGANISM_FILTER:-}" && "$g" != "$PIPELINE_ORGANISM_FILTER" ]] && continue
    [[ "$(genome_field "$g" gene_caller)" == rasttk ]] && genomes+=("$g")
done < <(genome_list)
echo "[rasttk] ${#genomes[@]} genome(s) to gene-call with RASTtk"
(( ${#genomes[@]} )) || exit 0

# BV-BRC login, once before the genome loop: prompts when BVBRC_LOGIN=1 and no session is
# cached; without a TTY (SLURM) it warns and runs without the session mount.
_bvbrc_session_mount=""
if [[ "${BVBRC_LOGIN:-0}" == "1" ]]; then
    bvbrc_env_activate "$image" || true
    # bvbrc-cli 1.048+ keeps the token in ~/.patric_token.
    _bvbrc_session_valid && _bvbrc_session_mount="${HOME}/.patric_token:/root/.patric_token:ro"
fi

for g in "${genomes[@]}"; do
    dst="$(gene_calls_root rasttk)/$g"
    reset_if_gene_caller_changed "$g" rasttk
    if (( ! FORCE )) && [[ "$(cat "$dst/gene_caller.txt" 2>/dev/null)" == rasttk && -s "$dst/gene_calls/genome.faa" ]]; then
        echo "[rasttk] $g: already gene-called, skipping (use --force to redo)"
        continue
    fi
    domain="$(genome_domain "$g")"
    code="$(genome_field "$g" genetic_code)"
    echo "[rasttk] $g  (domain=$domain, genetic code=$code)"

    # The container suffixes its output folder with the domain (_bact/_arch), so it runs in a
    # staging folder and the single result moves to <genome>/.
    staging="$(gene_calls_root rasttk)/.staging-$g"
    rm -rf "$staging"; mkdir -p "$staging"
    MOUNTS=(
        "$INPUT_RASTTK:/input:ro"
        "$staging:/output:rw"
    )
    [[ -d "$db" ]] && MOUNTS+=("$db:/db:ro")
    [[ -n "$_bvbrc_session_mount" ]] && MOUNTS+=("$_bvbrc_session_mount")
    run_container "$image" -i "/input/$(genome_field "$g" fasta)" -o /output \
        -t "${TOOL_RASTTK_THREADS:-${THREADS:-8}}" \
        --domain "$domain" --genetic-code "$code" --scientific "$g" \
        ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}

    result=("$staging"/*/)
    if (( ${#result[@]} != 1 )) || [[ ! -d "${result[0]}" ]]; then
        echo "[rasttk] ERROR: $g: expected one output folder in $staging" >&2
        exit 1
    fi
    rm -rf "$dst"
    mv "${result[0]%/}" "$dst"
    rmdir "$staging"
    echo rasttk > "$dst/gene_caller.txt"
    # Per-genome SEED enrichment (idempotent).
    run_postproc "$TOOL" "$dst"
done
