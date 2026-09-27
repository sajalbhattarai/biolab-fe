# shared/genomes.sh — reads the per-genome table every stage uses. Sourced
# after pipeline.conf.sh.
#
# Genomes live flat in $INPUT_RASTTK (input/<genome>.fna) and every tool writes
# to <tool>/<genome>/. Per-genome facts come from:
#
#   $GENOMES_TABLE (input/genomes.tsv, written by run-prepare-genomes.sh)
#     genome  fasta  domain  genetic_code  gene_caller  source
#       genome        key used for every output folder (FASTA stem, sanitised)
#       domain        Bacteria | Archaea | Unknown
#       genetic_code  NCBI translation table, or empty when not known
#       gene_caller   rasttk (needs domain AND genetic code) | prodigal
#       source        gtdbtk | user | gtdbtk+user | none
#
#   the envelope stage (run-envelope.sh), after annotation
#     $annotation_output_root/envelope/<genome>/processed/envelope_summary.tsv
#     envelope_type: diderm-gram-negative-like | monoderm-gram-positive-like | archaea
#
# Gram stain is not decided up front: psortb, deepsig and signalp4 take it
# from the envelope stage.
#
# All helpers are bash 3.2 safe (no associative arrays).

: "${GENOMES_TABLE:=$INPUT_RASTTK/genomes.tsv}"

# genome_key <fasta file name> -> the genome's key (stem, safe for folder names)
genome_key() {
    local stem="${1##*/}"
    stem="${stem%.*}"
    printf '%s' "$stem" | tr -c 'A-Za-z0-9._-' '_'
}

# genome_table_print [indent] -> the table aligned for reading (blank cells
# print as '-' so column(1) does not collapse them)
genome_table_print() {
    [[ -s "$GENOMES_TABLE" ]] || return 0
    awk -F'\t' -v OFS='\t' '{ for (i = 1; i <= NF; i++) if ($i == "") $i = "-"; print }' "$GENOMES_TABLE" \
        | { column -t -s $'\t' 2>/dev/null || cat; } | sed "s/^/${1:-}/"
}

# genome_list -> every genome key in the table, one per line
genome_list() {
    [[ -s "$GENOMES_TABLE" ]] || return 0
    awk -F'\t' 'NR > 1 && $1 != "" { print $1 }' "$GENOMES_TABLE"
}

# genome_field <genome> <column> -> that column's value ('' if absent)
genome_field() {
    [[ -s "$GENOMES_TABLE" ]] || return 0
    awk -F'\t' -v g="$1" -v col="$2" '
        NR == 1 { for (i = 1; i <= NF; i++) if ($i == col) c = i; next }
        c && $1 == g { print $c; exit }
    ' "$GENOMES_TABLE"
}

# genome_domain <genome> -> Bacteria | Archaea | Unknown
genome_domain() {
    local d; d="$(genome_field "$1" domain)"
    printf '%s' "${d:-Unknown}"
}

# envelope_type <genome> -> the inferred envelope, or '' before the envelope stage
envelope_type() {
    local f="$annotation_output_root/envelope/$1/processed/envelope_summary.tsv"
    [[ -s "$f" ]] || return 0
    awk -F'\t' '
        NR == 1 { for (i = 1; i <= NF; i++) if ($i == "envelope_type") c = i; next }
        c { print $c; exit }
    ' "$f"
}

# envelope_flag <genome> <psortb|deepsig|signalp4> -> the tool's gram argument,
# or '' when the envelope is not known (callers skip the tool then).
envelope_flag() {
    local env; env="$(envelope_type "$1")"
    [[ -n "$env" ]] || return 0
    case "$2:$env" in
        psortb:monoderm*)   echo p ;;
        psortb:archaea)     echo a ;;
        psortb:*)           echo n ;;
        deepsig:monoderm*)  echo GRAM+ ;;
        deepsig:archaea)    echo ARCH ;;
        deepsig:*)          echo GRAM- ;;
        signalp4:monoderm*) echo gram+ ;;
        signalp4:*)         echo gram- ;;   # archaea too
    esac
}

# envelope_gram <genome> -> positive | negative | unknown (for tables and logs)
envelope_gram() {
    case "$(envelope_type "$1")" in
        monoderm*) echo positive ;;
        diderm*)   echo negative ;;
        *)         echo unknown ;;
    esac
}
