#!/usr/bin/env bash
# normalize_rasttk_output.sh — renames rasttk run folders, rast*.tsv files and gene_calls
# files to the canonical "<sci>-<timestamp>{_arch|_bact_gramN|_bact_gramP|_bact_gramU|_unknown}"
# suffix taken from the path (same rules as containers/build/rasttk/entrypoint.sh::compose_full_suffix).
# Idempotent, and only moves files (never deletes).
set -euo pipefail

ROOT="${1:?usage: normalize_rasttk_output.sh <output/rasttk-root>}"

if [[ ! -d "$ROOT" ]]; then
    echo "[normalize] not a directory: $ROOT" >&2
    exit 2
fi

# ---- canonical suffix for a run-folder path ----
suffix_for() {
    local p="$1"
    case "$p" in
        */archaea/*)                printf '_arch' ;;
        */bacteria/gram-negative/*) printf '_bact_gramN' ;;
        */bacteria/gram-positive/*) printf '_bact_gramP' ;;
        */bacteria/unknown/*)       printf '_bact_gramU' ;;
        */bacteria/*)               printf '_bact' ;;
        */unknown/*)                printf '_unknown' ;;
        *)                          printf '' ;;
    esac
}

# Strips any known suffix from the end of a folder name or file stem.
strip_known_suffix() {
    local s="$1"
    # Longest first, so '_bact_gramN' goes before '_bact'.
    s="${s%_bact_gramN}"; s="${s%_bact_gramP}"; s="${s%_bact_gramU}"
    s="${s%_bacteria_gramN}"; s="${s%_bacteria_gramP}"; s="${s%_bacteria_gramU}"
    s="${s%_archaea}";    s="${s%_bacteria}"
    s="${s%_bact}";       s="${s%_arch}";       s="${s%_unknown}"
    s="${s%_gramN}";      s="${s%_gramP}";      s="${s%_gramU}"
    printf '%s' "$s"
}

# rename_rast_file <path> <suffix> — renames a rast*.tsv (or .bak / .legacy.tsv sibling) to end with <suffix>.
rename_rast_file() {
    local path="$1" suf="$2"
    local dir base stem ext_chain new_base new_path

    dir="$(dirname  "$path")"
    base="$(basename "$path")"

    # Splits off compound extensions: .tsv, .tsv.bak, .legacy.tsv.
    case "$base" in
        rast*.legacy.tsv) ext_chain='.legacy.tsv' ;;
        rast*.tsv.bak)    ext_chain='.tsv.bak'   ;;
        rast*.tsv)        ext_chain='.tsv'       ;;
        *) return 0 ;;
    esac
    stem="${base%${ext_chain}}"
    # Collapses only stems that start with 'rast'.
    [[ "$stem" == rast* ]] || return 0

    stem="$(strip_known_suffix "$stem")"
    new_base="${stem}${suf}${ext_chain}"
    new_path="${dir}/${new_base}"

    [[ "$path" == "$new_path" ]] && return 0
    if [[ -e "$new_path" ]]; then
        echo "[normalize]   skip (target exists): $new_path" >&2
        return 0
    fi
    echo "[normalize]   mv $base -> $new_base"
    mv -- "$path" "$new_path"
}

# rename_gene_calls_file <path> <suffix> — renames gene_calls/<sci>_<old>.{faa,ffn,fna,gbk,gff} to end with <suffix>.
rename_gene_calls_file() {
    local path="$1" suf="$2"
    local dir base stem ext new_base new_path
    dir="$(dirname  "$path")"
    base="$(basename "$path")"
    case "$base" in
        *.faa|*.ffn|*.fna|*.gbk|*.gff) ext=".${base##*.}" ;;
        *) return 0 ;;
    esac
    stem="${base%${ext}}"
    stem="$(strip_known_suffix "$stem")"
    new_base="${stem}${suf}${ext}"
    new_path="${dir}/${new_base}"
    [[ "$path" == "$new_path" ]] && return 0
    if [[ -e "$new_path" ]]; then
        echo "[normalize]   skip (target exists): $new_path" >&2
        return 0
    fi
    echo "[normalize]   mv $base -> $new_base"
    mv -- "$path" "$new_path"
}

# ---- walk every run folder (leaf folders under archaea/, bacteria/<gram>/, unknown/) ----
while IFS= read -r run_dir; do
    suf="$(suffix_for "$run_dir/")"
    [[ -z "$suf" ]] && { echo "[normalize] no suffix rule for $run_dir — skipping" >&2; continue; }

    parent="$(dirname  "$run_dir")"
    cur="$(basename "$run_dir")"
    desired="$(strip_known_suffix "$cur")${suf}"

    if [[ "$cur" != "$desired" ]]; then
        new_dir="${parent}/${desired}"
        if [[ -e "$new_dir" ]]; then
            echo "[normalize] skip folder rename (target exists): $new_dir" >&2
        else
            echo "[normalize] rename folder: $cur -> $desired"
            mv -- "$run_dir" "$new_dir"
            run_dir="$new_dir"
        fi
    fi

    # Renames rast*.tsv (+ .bak + .legacy.tsv) under the possibly renamed run_dir.
    while IFS= read -r f; do
        rename_rast_file "$f" "$suf"
    done < <(find "$run_dir" -type f \( -name 'rast*.tsv' -o -name 'rast*.tsv.bak' -o -name 'rast*.legacy.tsv' \) | sort)

    # Renames gene_calls files so cog/kegg/pfam/... find the canonical <sci>_<suffix>.faa input.
    if [[ -d "$run_dir/gene_calls" ]]; then
        while IFS= read -r f; do
            rename_gene_calls_file "$f" "$suf"
        done < <(find "$run_dir/gene_calls" -type f \( -name '*.faa' -o -name '*.ffn' -o -name '*.fna' -o -name '*.gbk' -o -name '*.gff' \) | sort)
    fi

done < <(
    # Leaf run folders: one level below archaea/, bacteria/<gram>/ or unknown/.
    find "$ROOT" -mindepth 2 -maxdepth 3 -type d \( \
            -path "*/archaea/*"  -not -path "*/archaea/*/*" \
         -o -path "*/bacteria/gram-negative/*" -not -path "*/bacteria/gram-negative/*/*" \
         -o -path "*/bacteria/gram-positive/*" -not -path "*/bacteria/gram-positive/*/*" \
         -o -path "*/bacteria/unknown/*"       -not -path "*/bacteria/unknown/*/*" \
         -o -path "*/unknown/*"                -not -path "*/unknown/*/*" \
        \) | sort
)

echo "[normalize] done."
