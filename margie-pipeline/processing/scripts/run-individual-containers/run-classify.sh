#!/usr/bin/env bash
# Runner for classify — GTDB-Tk backed domain/gram-stain detector.
#
# Replaces the original rRNA/protein classify container with GTDB-Tk as the
# authoritative classifier.  Produces a GTDB-Tk-native classification_report.tsv.
#
# Schema (tab-separated):
#   genome  domain  gram_stain  confidence  method
#   gtdb_classification  gtdb_phylum  gtdb_genus  gtdb_species
#   gtdb_resolved_rank  gtdb_resolved_label
#   gtdb_taxonomy_source  gtdb_user_genome  gtdb_summary_domain
#   gtdb_classification_raw  gtdb_pplacer_taxonomy  gtdb_classification_method
#   gtdb_closest_genome_reference  gtdb_closest_genome_ani  gtdb_closest_genome_af
#   gtdb_closest_placement_reference  gtdb_closest_placement_ani  gtdb_closest_placement_af
#   gtdb_msa_percent  gtdb_translation_table  gtdb_red_value
#   gtdb_note  gtdb_warnings
#   gtdb_species_representative  gtdb_species_ani_threshold
#   gtdb_confirmation_status  gtdb_confirmation_basis
#   gtdb_final_confidence_tier
#   gtdb_final_call_rank  gtdb_final_call_label  gtdb_final_call_reason
#   gtdb_best_effort_species  gtdb_best_effort_reason
#
# Gram stain is derived from GTDB phylum using a curated monoderm/diderm table.
#
# The report is for reading only. The genome table (run-prepare-genomes.sh)
# takes domain and genetic code straight from the GTDB-Tk summaries, and the
# pipeline takes gram stain from the envelope stage, not from this column.
#
# Usage:
#   ./run-classify.sh
#   ./run-classify.sh --list
#   ./run-classify.sh --dry-run
#   TOOL_classify_USER_INPUT=/path/to/fastas ./run-classify.sh
#   TOOL_gtdbtk_RAW_DIR=/path/to/gtdbtk/raw ./run-classify.sh

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/../../../pipeline.conf.sh"
source "$here/lib/pipeline-lib.sh"

TOOL=classify
DRY_RUN=0
EXTRA_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --list)     echo "Tool=classify (GTDB-Tk backed)  image=$(tool_image gtdbtk)  user-input=${TOOL_classify_USER_INPUT:-$USER_INPUT_DIR}"; exit 0 ;;
        --help|-h)  sed -n '2,20p' "$0"; exit 0 ;;
        --runtime)  RUNTIME="$2"; shift 2 ;;
        --dry-run)  DRY_RUN=1; shift ;;
        --no-db|--confidence) shift; [[ $# -gt 0 && "${1:-}" != --* ]] && shift || true ;;
        --)         shift; EXTRA_ARGS+=("$@"); break ;;
        *)          EXTRA_ARGS+=("$1"); shift ;;
    esac
done

# ── Paths ──────────────────────────────────────────────────────────────────────
user_input_dir="${TOOL_classify_USER_INPUT:-$USER_INPUT_DIR}"
input_root="$gene_caller_input"
GTDBTK_RAW="${TOOL_gtdbtk_RAW_DIR:-$REPO_ROOT/output/gtdbtk/gtdbtk/raw}"
GTDBTK_DB_ROOT="${TOOL_gtdbtk_DB_DIR:-$REPO_ROOT/db/gtdbtk/release232}"
BAC_SUMMARY="$GTDBTK_RAW/gtdbtk.bac120.summary.tsv"
ARC_SUMMARY="$GTDBTK_RAW/gtdbtk.ar53.summary.tsv"
GTDB_RADII="$GTDBTK_DB_ROOT/radii/gtdb_radii.tsv"
FINAL_REPORT="$input_root/classification_report.tsv"
REQUIRE_ALIGNMENT="${GTDBTK_REQUIRE_ALIGNMENT:-0}"
CONFIRM_MIN_AF="${GTDBTK_CONFIRM_MIN_AF:-0.80}"
CONFIRM_ANI_MARGIN="${GTDBTK_CONFIRM_ANI_MARGIN:-0.00}"
NON_ALIGNMENT_ROWS=0

# ── Monoderm phyla (gram-positive) ────────────────────────────────────────────
MONODERM_PHYLA=(
    Bacillota Bacillota_A Bacillota_B Bacillota_C Bacillota_D Bacillota_E
    Bacillota_F Bacillota_G Bacillota_H Bacillota_I
    Actinomycetota Actinomycetota_A Actinomycetota_B
    Chloroflexota Eremiobacterota Thermosulfidibacterota
    Firmicutes Actinobacteria Tenericutes Mollicutes
)
_MONODERM_LOOKUP="|$(IFS='|'; echo "${MONODERM_PHYLA[*]}")|"
# GTDB lineage helpers: monoderm test and phylum / genus / species fields.
is_monoderm() { [[ "$_MONODERM_LOOKUP" == *"|${1}|"* ]]; }
gtdb_phylum()  { printf '%s' "$1" | cut -d';' -f2 | sed 's/^p__//'; }
gtdb_genus()   { printf '%s' "$1" | cut -d';' -f6 | sed 's/^g__//'; }
gtdb_species() { printf '%s' "$1" | cut -d';' -f7 | sed 's/^s__//'; }

is_ambiguous_species() {
    local species="$1"
    # Placeholder-like species labels count as genus-level calls.
    [[ -z "$species" || "$species" == "unclassified" || "$species" =~ (^|[[:space:]])sp[0-9]+$ ]]
}

# Maps a lineage to a gram stain via the monoderm phylum table.
gram_from_lineage() {
    local domain="$1" lineage="$2"
    case "$domain" in
        Archaea)   echo "unknown" ;;
        Bacteria)
            local phylum; phylum="$(gtdb_phylum "$lineage")"
            if is_monoderm "$phylum"; then echo "positive"
            elif [[ -n "$phylum" && "$phylum" != "unclassified" ]]; then echo "negative"
            else echo "unknown"
            fi ;;
        *) echo "unknown" ;;
    esac
}

# Strips the RS_ / GB_ prefix from a GTDB reference accession.
normalize_ref_accession() {
    local ref="$1"
    ref="${ref#RS_}"
    ref="${ref#GB_}"
    printf '%s' "$ref"
}

# Numeric helpers (awk): is_float, float_ge, float_add.
is_float() {
    [[ "$1" =~ ^[0-9]+([.][0-9]+)?$ ]]
}

float_ge() {
    awk -v a="$1" -v b="$2" 'BEGIN { exit !(a+0 >= b+0) }'
}

float_add() {
    awk -v a="$1" -v b="$2" 'BEGIN { printf "%.6f", (a+0)+(b+0) }'
}

# Returns the species name with an s__ prefix.
species_with_prefix() {
    local s="$1"
    [[ -z "$s" ]] && { printf '%s' ""; return; }
    if [[ "$s" == s__* ]]; then
        printf '%s' "$s"
    else
        printf 's__%s' "$s"
    fi
}

# radii_field <species> <col> — representative genome (col 2) or ANI radius (col 3) from the
# GTDB radii table; one awk pass per lookup (bash 3.2 has no associative arrays).
radii_field() {
    [[ -s "$GTDB_RADII" && -n "$1" ]] || return 0
    awk -F'\t' -v s="$1" -v c="$2" '$1 == s && $2 != "" && $3 != "" { print $c; exit }' "$GTDB_RADII"
}
# radii_lookup <col> <default> <species...> — first non-empty radii_field, else the default.
radii_lookup() {
    local col="$1" default="$2" v s; shift 2
    for s in "$@"; do
        v="$(radii_field "$s" "$col")"
        [[ -n "$v" ]] && { printf '%s' "$v"; return; }
    done
    printf '%s' "$default"
}
[[ -s "$GTDB_RADII" ]] || printf '[run-classify] WARNING: GTDB radii file not found: %s\n' "$GTDB_RADII" >&2

# ── Require GTDB-Tk summaries ─────────────────────────────────────────────────
if [[ ! -s "$BAC_SUMMARY" && ! -s "$ARC_SUMMARY" ]]; then
    printf '[run-classify] ERROR: GTDB-Tk summary files not found under %s\n' "$GTDBTK_RAW" >&2
    printf '[run-classify] Run GTDB-Tk first: sbatch accessory-files/slurm/gtdbtk-highmem.slurm\n' >&2
    exit 1
fi

# ── Build classification_report.tsv from GTDB-Tk summaries ───────────────────
tmp_report="${TMPDIR:-/tmp}/margie-gtdbtk-classify-report-$$.tsv"
trap 'rm -f "$tmp_report"' EXIT

printf 'genome\tdomain\tgram_stain\tconfidence\tmethod\tgtdb_classification\tgtdb_phylum\tgtdb_genus\tgtdb_species\tgtdb_resolved_rank\tgtdb_resolved_label\tgtdb_taxonomy_source\tgtdb_user_genome\tgtdb_summary_domain\tgtdb_classification_raw\tgtdb_pplacer_taxonomy\tgtdb_classification_method\tgtdb_closest_genome_reference\tgtdb_closest_genome_ani\tgtdb_closest_genome_af\tgtdb_closest_genome_taxonomy\tgtdb_closest_placement_reference\tgtdb_closest_placement_ani\tgtdb_closest_placement_af\tgtdb_msa_percent\tgtdb_translation_table\tgtdb_red_value\tgtdb_note\tgtdb_warnings\tgtdb_species_representative\tgtdb_species_ani_threshold\tgtdb_confirmation_status\tgtdb_confirmation_basis\tgtdb_final_confidence_tier\tgtdb_final_call_rank\tgtdb_final_call_label\tgtdb_final_call_reason\tgtdb_best_effort_species\tgtdb_best_effort_reason\n' > "$tmp_report"

# process_summary <tsv> <domain_label> <summary_domain> — appends one report row per genome of a GTDB-Tk summary.
process_summary() {
    local tsv="$1" domain_label="$2" summary_domain="$3"
    [[ -f "$tsv" ]] || return 0

    local header_line
    IFS= read -r header_line < "$tsv" || return 0

    local -a headers
    IFS=$'\t' read -r -a headers <<< "$header_line"

    local idx_name=-1 idx_class=-1 idx_pplacer=-1 idx_method=-1
    local idx_cgr=-1 idx_cgani=-1 idx_cgaf=-1 idx_cgtax=-1
    local idx_cpr=-1 idx_cpani=-1 idx_cpaf=-1
    local idx_msa=-1 idx_tt=-1 idx_red=-1 idx_note=-1 idx_warn=-1
    local i col
    for i in "${!headers[@]}"; do
        col="${headers[$i]}"
        case "$col" in
            user_genome) idx_name=$i ;;
            classification) idx_class=$i ;;
            pplacer_taxonomy) idx_pplacer=$i ;;
            classification_method) idx_method=$i ;;
            closest_genome_reference) idx_cgr=$i ;;
            closest_genome_ani) idx_cgani=$i ;;
            closest_genome_af) idx_cgaf=$i ;;
            closest_genome_taxonomy) idx_cgtax=$i ;;
            closest_placement_reference) idx_cpr=$i ;;
            closest_placement_ani) idx_cpani=$i ;;
            closest_placement_af) idx_cpaf=$i ;;
            msa_percent) idx_msa=$i ;;
            translation_table) idx_tt=$i ;;
            red_value) idx_red=$i ;;
            note) idx_note=$i ;;
            warnings) idx_warn=$i ;;
        esac
    done

    if (( idx_name < 0 || idx_class < 0 )); then
        printf '[run-classify] ERROR: missing required columns in %s\n' "$tsv" >&2
        return 1
    fi

    local alignment_rows=0
    local ani_rows=0

    while IFS=$'\t' read -r -a cols; do
        local name classification pplacer_tax class_method lineage report_method taxonomy_source
        local closest_genome_ref closest_genome_ani closest_genome_af closest_genome_taxonomy
        local closest_placement_ref closest_placement_ani closest_placement_af
        local msa_percent translation_table red_value note warnings
        name="${cols[$idx_name]:-}"
        classification="${cols[$idx_class]:-}"
        pplacer_tax=""
        class_method=""
        closest_genome_ref=""
        closest_genome_ani=""
        closest_genome_af=""
        closest_genome_taxonomy=""
        closest_placement_ref=""
        closest_placement_ani=""
        closest_placement_af=""
        msa_percent=""
        translation_table=""
        red_value=""
        note=""
        warnings=""
        (( idx_pplacer >= 0 )) && pplacer_tax="${cols[$idx_pplacer]:-}"
        (( idx_method >= 0 )) && class_method="${cols[$idx_method]:-}"
        (( idx_cgr >= 0 )) && closest_genome_ref="${cols[$idx_cgr]:-}"
        (( idx_cgani >= 0 )) && closest_genome_ani="${cols[$idx_cgani]:-}"
        (( idx_cgaf >= 0 )) && closest_genome_af="${cols[$idx_cgaf]:-}"
        (( idx_cgtax >= 0 )) && closest_genome_taxonomy="${cols[$idx_cgtax]:-}"
        (( idx_cpr >= 0 )) && closest_placement_ref="${cols[$idx_cpr]:-}"
        (( idx_cpani >= 0 )) && closest_placement_ani="${cols[$idx_cpani]:-}"
        (( idx_cpaf >= 0 )) && closest_placement_af="${cols[$idx_cpaf]:-}"
        (( idx_msa >= 0 )) && msa_percent="${cols[$idx_msa]:-}"
        (( idx_tt >= 0 )) && translation_table="${cols[$idx_tt]:-}"
        (( idx_red >= 0 )) && red_value="${cols[$idx_red]:-}"
        (( idx_note >= 0 )) && note="${cols[$idx_note]:-}"
        (( idx_warn >= 0 )) && warnings="${cols[$idx_warn]:-}"

        [[ -z "$name" || -z "$classification" ]] && continue

        # Prefers the alignment-derived placement taxonomy when GTDB provides it.
        lineage="$classification"
        report_method="gtdbtk"
        if [[ -n "$pplacer_tax" && "$pplacer_tax" != "N/A" ]]; then
            lineage="$pplacer_tax"
            report_method="gtdbtk_alignment"
            taxonomy_source="alignment_pplacer"
            (( alignment_rows++ )) || true
        else
            if [[ "$REQUIRE_ALIGNMENT" == "1" ]]; then
                printf '[run-classify] WARNING: %s has no alignment taxonomy (classification_method=%s)\n' \
                    "$name" "${class_method:-unknown}" >&2
                (( NON_ALIGNMENT_ROWS++ )) || true
                continue
            fi
            report_method="gtdbtk_ani_screen"
            taxonomy_source="ani_fallback"
            (( ani_rows++ )) || true
        fi

        local stem="${name#user-input_}"
        local fna_file=""
        for ext in fna fa fasta; do
            [[ -f "$user_input_dir/${stem}.${ext}" ]] && { fna_file="${stem}.${ext}"; break; }
        done
        if [[ -z "$fna_file" ]]; then
            fna_file="$(find "$user_input_dir" -maxdepth 1 -name "${stem}.*" \
                \( -name '*.fna' -o -name '*.fa' -o -name '*.fasta' \) \
                -printf '%f\n' 2>/dev/null | head -n 1 || true)"
        fi
        [[ -z "$fna_file" ]] && { printf '[run-classify] WARNING: FASTA not found for %s\n' "$name" >&2; continue; }
        local phylum genus species gram resolved_rank resolved_label
        local species_rep species_radius confirmation_status confirmation_basis final_confidence_tier
        local confidence_score norm_rep norm_closest
        local species_key species_from_closest_key closest_species
        local threshold_ani
        local final_call_rank final_call_label final_call_reason
        local best_effort_species best_effort_reason
        phylum="$(gtdb_phylum "$lineage")"
        genus="$(gtdb_genus "$lineage")"
        species="$(gtdb_species "$lineage")"
        gram="$(gram_from_lineage "$domain_label" "$lineage")"
        if is_ambiguous_species "$species"; then
            if [[ -n "$genus" && "$genus" != "unclassified" ]]; then
                resolved_rank="genus"
                resolved_label="$genus"
            else
                resolved_rank="phylum"
                resolved_label="$phylum"
            fi
        else
            resolved_rank="species"
            resolved_label="$species"
        fi

        if [[ -n "$species" ]]; then
            species_key="$(species_with_prefix "$species")"
            species_rep="$(radii_lookup 2 N/A "$species_key" "$species")"
            species_radius="$(radii_lookup 3 95.0 "$species_key" "$species")"
        else
            species_rep="N/A"
            species_radius="95.0"
        fi

        if [[ "$species_rep" == "N/A" && -n "$closest_genome_taxonomy" && "$closest_genome_taxonomy" != "N/A" ]]; then
            species_from_closest_key="$(species_with_prefix "$(gtdb_species "$closest_genome_taxonomy")")"
            if [[ -n "$species_from_closest_key" && "$species_from_closest_key" != "s__" ]]; then
                species_rep="$(radii_lookup 2 N/A "$species_from_closest_key")"
                species_radius="$(radii_lookup 3 95.0 "$species_from_closest_key")"
            fi
        fi

        closest_species=""
        if [[ -n "$closest_genome_taxonomy" && "$closest_genome_taxonomy" != "N/A" ]]; then
            closest_species="$(gtdb_species "$closest_genome_taxonomy")"
        fi

        confirmation_status="provisional_species"
        confirmation_basis="species assignment from GTDB marker-alignment placement; representative ANI confirmation not available"
        final_confidence_tier="medium"
        confidence_score="0.85"

        if [[ "$resolved_rank" != "species" ]]; then
            confirmation_status="genus_only"
            confirmation_basis="GTDB placement resolved to genus/phylum only; species not assigned"
            final_confidence_tier="medium"
            confidence_score="0.70"
        else
            if [[ "$species_rep" == "N/A" ]]; then
                confirmation_status="provisional_species"
                confirmation_basis="species not present in GTDB radii table; ANI-to-representative confirmation unavailable"
                final_confidence_tier="medium"
                confidence_score="0.80"
            else
                norm_rep="$(normalize_ref_accession "$species_rep")"
                norm_closest="$(normalize_ref_accession "$closest_genome_ref")"
                threshold_ani="$(float_add "$species_radius" "$CONFIRM_ANI_MARGIN")"
                if [[ "$norm_rep" == "$norm_closest" ]] && is_float "$closest_genome_ani" && is_float "$closest_genome_af"; then
                    if [[ -n "$closest_species" && "$closest_species" != "$species" ]]; then
                        confirmation_status="conflict_review"
                        confirmation_basis="closest reference taxonomy species conflicts with assigned species"
                        final_confidence_tier="low"
                        confidence_score="0.35"
                    elif float_ge "$closest_genome_ani" "$threshold_ani" && float_ge "$closest_genome_af" "$CONFIRM_MIN_AF"; then
                        confirmation_status="confirmed_species"
                        confirmation_basis="ANI/AF to GTDB species representative passed strict thresholds and taxonomy consistency checks"
                        final_confidence_tier="high"
                        confidence_score="0.99"
                    else
                        confirmation_status="conflict_review"
                        confirmation_basis="ANI/AF did not pass strict representative confirmation thresholds"
                        final_confidence_tier="low"
                        confidence_score="0.40"
                    fi
                else
                    if [[ "$report_method" == "gtdbtk_ani_screen" ]]; then
                        confirmation_status="provisional_species"
                        confirmation_basis="ANI screen provided taxonomy but ANI/AF to assigned species representative is not available in this run"
                        final_confidence_tier="medium"
                        confidence_score="0.80"
                    else
                        confirmation_status="provisional_species"
                        confirmation_basis="alignment placement assigned species; representative ANI confirmation not computed for this closest genome"
                        final_confidence_tier="medium"
                        confidence_score="0.85"
                    fi
                fi
            fi
        fi

        if [[ "$confirmation_status" == "confirmed_species" && -n "$species" ]]; then
            final_call_rank="species"
            final_call_label="$species"
            final_call_reason="species accepted: strict GTDB representative ANI/AF confirmation and taxonomy consistency"
        elif [[ -n "$genus" && "$genus" != "unclassified" ]]; then
            final_call_rank="genus"
            final_call_label="$genus"
            final_call_reason="conservative downgrade: species not robustly confirmed"
        elif [[ -n "$phylum" && "$phylum" != "unclassified" ]]; then
            final_call_rank="phylum"
            final_call_label="$phylum"
            final_call_reason="conservative downgrade: genus unresolved"
        else
            final_call_rank="domain"
            final_call_label="$domain_label"
            final_call_reason="insufficient resolution for lower ranks"
        fi

        # Always fills a best-effort species label.
        if [[ -n "$species" && "$species" != "unclassified" && ! "$species" =~ (^|[[:space:]])sp[0-9]+$ ]]; then
            best_effort_species="$species"
            best_effort_reason="from GTDB assigned species"
        elif [[ -n "$closest_species" && "$closest_species" != "unclassified" ]]; then
            best_effort_species="$closest_species"
            best_effort_reason="fallback: species from closest GTDB reference taxonomy"
        elif [[ -n "$genus" && "$genus" != "unclassified" ]]; then
            best_effort_species="$genus sp."
            best_effort_reason="fallback: genus-level only, species unresolved"
        else
            best_effort_species="$domain_label sp."
            best_effort_reason="fallback: insufficient lower-rank resolution"
        fi

        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$fna_file" "$domain_label" "$gram" "$confidence_score" "$report_method" "$lineage" "$phylum" "$genus" "$species" "$resolved_rank" "$resolved_label" "$taxonomy_source" "$name" "$summary_domain" "$classification" "$pplacer_tax" "$class_method" "$closest_genome_ref" "$closest_genome_ani" "$closest_genome_af" "$closest_genome_taxonomy" "$closest_placement_ref" "$closest_placement_ani" "$closest_placement_af" "$msa_percent" "$translation_table" "$red_value" "$note" "$warnings" "$species_rep" "$species_radius" "$confirmation_status" "$confirmation_basis" "$final_confidence_tier" "$final_call_rank" "$final_call_label" "$final_call_reason" "$best_effort_species" "$best_effort_reason" >> "$tmp_report"
    done < <(tail -n +2 "$tsv")

    printf '[run-classify] %s: alignment=%d, ani_fallback=%d\n' "$domain_label" "$alignment_rows" "$ani_rows"
}

process_summary "$BAC_SUMMARY" "Bacteria" "bac120"
process_summary "$ARC_SUMMARY" "Archaea" "ar53"

if [[ "$REQUIRE_ALIGNMENT" == "1" && "$NON_ALIGNMENT_ROWS" -gt 0 ]]; then
    printf '[run-classify] ERROR: %d genome(s) lacked alignment-based taxonomy; refusing ANI-only placement.\n' "$NON_ALIGNMENT_ROWS" >&2
    printf '[run-classify]        Re-run GTDB-Tk alignment/placement to completion, then run classify again.\n' >&2
    printf '[run-classify]        To override: GTDBTK_REQUIRE_ALIGNMENT=0 ./processing/scripts/run-individual-containers/run-classify.sh\n' >&2
    exit 1
fi

row_count=$(( $(wc -l < "$tmp_report") - 1 ))
printf '[run-classify] GTDB-Tk backed — classified %d genome(s)\n' "$row_count"
printf '[run-classify] Report preview:\n'
head -n 4 "$tmp_report" | column -t -s $'\t' 2>/dev/null || head -n 4 "$tmp_report"

if (( DRY_RUN )); then
    printf '[run-classify] dry-run — no files written\n'
    exit 0
fi

# ── Write report ──────────────────────────────────────────────────────────────
mkdir -p "$input_root"
cp "$tmp_report" "$FINAL_REPORT"
printf '[run-classify]   Report:   %s\n' "$FINAL_REPORT"
printf '[run-classify] Done.\n'
