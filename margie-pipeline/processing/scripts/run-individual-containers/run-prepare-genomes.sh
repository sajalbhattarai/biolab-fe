#!/usr/bin/env bash
# run-prepare-genomes.sh — copy the genomes in $USER_INPUT_DIR flat into
# $INPUT_RASTTK (input/<genome>.fna) and write the per-genome table
# $GENOMES_TABLE that every later stage reads (see shared/genomes.sh).
#
# Each genome's domain and genetic code come from, in order:
#   1. GTDB-Tk, when RUN_GTDBTK=1 and its summaries are present
#      (domain from bac120/ar53, genetic code from translation_table), then
#   2. $GENOME_METADATA (genome<TAB>domain<TAB>genetic_code), which overrides
#      whatever it fills in.
# The gene caller is RASTtk when both are known, Prodigal otherwise (RASTtk
# needs a genetic code).
#
# Usage: ./run-prepare-genomes.sh | --list
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=pipeline.conf.sh
source "$here/../../../pipeline.conf.sh"
# shellcheck source=../shared/genomes.sh
source "$here/../shared/genomes.sh"

case "${1:-}" in
    --list) genome_table_print; exit 0 ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
esac

gtdbtk_raw="${GTDBTK_RAW_DIR:-$OUTPUT_ROOT/gtdbtk/gtdbtk/raw}"
mkdir -p "$INPUT_RASTTK"

# <stem> -> "domain<TAB>translation_table" from a GTDB-Tk summary (bac120 or ar53).
# GTDB-Tk names genomes after the staging copy: user-input_<stem>.
gtdbtk_lookup() {
    local stem="$1" f domain
    for f in "$gtdbtk_raw/gtdbtk.bac120.summary.tsv" "$gtdbtk_raw/gtdbtk.ar53.summary.tsv"; do
        [[ -s "$f" ]] || continue
        [[ "$f" == *ar53* ]] && domain=Archaea || domain=Bacteria
        awk -F'\t' -v s="$stem" -v d="$domain" '
            NR == 1 { for (i = 1; i <= NF; i++) if ($i == "translation_table") t = i; next }
            $1 == s || $1 == "user-input_" s { print d "\t" (t ? $t : ""); found = 1; exit }
            END { exit !found }
        ' "$f" && return 0
    done
    return 1
}

# <file name> -> "domain<TAB>genetic_code" from $GENOME_METADATA (first match wins)
metadata_lookup() {
    [[ -s "${GENOME_METADATA:-}" ]] || return 1
    awk -F'\t' -v n="$1" '
        NR > 1 { sub(/\r$/, ""); if ($1 == n) { print $2 "\t" $3; found = 1; exit } }
        END { exit !found }
    ' "$GENOME_METADATA"
}

tmp="$GENOMES_TABLE.tmp"
printf 'genome\tfasta\tdomain\tgenetic_code\tgene_caller\tsource\n' > "$tmp"

n=0 n_rasttk=0
while IFS= read -r src; do
    name="$(basename "$src")"
    key="$(genome_key "$name")"
    dest="$INPUT_RASTTK/$key.fna"
    # Copies when new or changed, so input/ always matches user-input/.
    if [[ ! -f "$dest" || "$src" -nt "$dest" ]]; then cp -p "$src" "$dest"; fi

    domain="" code="" source=none
    if [[ "${RUN_GTDBTK:-1}" == 1 ]] && row="$(gtdbtk_lookup "${name%.*}")"; then
        domain="${row%%$'\t'*}"; code="${row#*$'\t'}"; source=gtdbtk
    fi
    if row="$(metadata_lookup "$name")"; then
        m_domain="${row%%$'\t'*}"; m_code="${row#*$'\t'}"
        if [[ -n "$m_domain$m_code" ]]; then
            [[ -n "$m_domain" ]] && domain="$m_domain"
            [[ -n "$m_code" ]] && code="$m_code"
            [[ "$source" == gtdbtk ]] && source=gtdbtk+user || source=user
        fi
    fi
    case "$domain" in
        [Bb]acteria) domain=Bacteria ;;
        [Aa]rchaea)  domain=Archaea ;;
        *)           domain=Unknown ;;
    esac
    [[ "$code" =~ ^[0-9]+$ ]] || code=""

    # GENE_CALLER decides; rasttk still needs the domain and genetic code.
    if [[ "${GENE_CALLER:-prodigal}" == prodigal ]]; then
        caller=prodigal
    elif [[ "$domain" != Unknown && -n "$code" ]]; then
        caller=rasttk; (( n_rasttk++ )) || true
    else
        caller=prodigal
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$key" "$key.fna" "$domain" "$code" "$caller" "$source" >> "$tmp"
    (( n++ )) || true
done < <(find -L "$USER_INPUT_DIR" -maxdepth 1 -type f \( -name '*.fna' -o -name '*.fa' -o -name '*.fasta' \) | sort)

mv "$tmp" "$GENOMES_TABLE"
echo "[prepare-genomes] $n genome(s): $n_rasttk with RASTtk, $(( n - n_rasttk )) with Prodigal  ->  ${GENOMES_TABLE#$REPO_ROOT/}"
genome_table_print '  '
