#!/usr/bin/env bash
# run-meta.sh — builds each genome's results with the host scripts in processing/host-scripts/
# (margie_sb's arguments, order and layout): gather, consolidation (phase 9), labeling (10),
# scoring (11), fingerprint (12), then the optional evidence, viewer and figures stages.
# --finalize runs once after every genome: pangenome figures, then each folder reduced to its final outputs.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/../../../pipeline.conf.sh"
source "$here/lib/pipeline-lib.sh"
source "$here/../shared/host-python.sh"

usage() {
    cat <<'HELP'
run-meta.sh — per-genome results from margie-backend's host scripts.

USAGE
  ./run-meta.sh                          # every gene-called genome, every stage
  ./run-meta.sh --organism NAME          # one genome
  ./run-meta.sh --stage labeling         # one stage (repeatable)
  ./run-meta.sh --finalize               # pangenome figures + final folder layout
  ./run-meta.sh --list                   # show settings and genomes

STAGES
  gather consolidation labeling scoring fingerprint evidence viewer figures
HELP
}

stages_all=(gather consolidation labeling scoring fingerprint evidence viewer figures)
org_filter=""
stages=()
finalize=no

HS="$REPO_ROOT/processing/host-scripts"
FP_DIR="$MARGIE_SHARED_DIR/fingerprint-database"
FP_DB="$FP_DIR/fingerprint-database.tsv"
OPERON_FP_EVIDENCE_ORDERED="$FP_DIR/operon-fingerprint-database-evidence-ordered.tsv"
OPERON_FP_EVIDENCE_COMPOSITION="$FP_DIR/operon-fingerprint-database-evidence-composition.tsv"
OPERON_FP_LABEL_ORDERED="$FP_DIR/operon-fingerprint-database-label-ordered.tsv"
OPERON_FP_LABEL_COMPOSITION="$FP_DIR/operon-fingerprint-database-label-composition.tsv"
OCC_REFERENCE="${OPERON_DB:-$MARGIE_SHARED_DIR/operon-database/occ_reference.pkl}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --organism) org_filter="$2"; shift 2 ;;
        --stage)    stages+=("$2"); shift 2 ;;
        --finalize) finalize=yes; shift ;;
        --runtime)  RUNTIME="$2"; shift 2 ;;   # accepted for symmetry; nothing here runs a container
        --list)
            echo "GENOME_RESULTS_DIR = $GENOME_RESULTS_DIR"
            echo "MARGIE_SHARED_DIR  = $MARGIE_SHARED_DIR"
            echo "host scripts       = $HS"
            echo "stages             = ${stages_all[*]}"
            echo "RUN_EVIDENCE=$RUN_EVIDENCE RUN_GENOME_VIEWER=$RUN_GENOME_VIEWER RUN_REPORT_FIGURES=$RUN_REPORT_FIGURES RUN_FULL_OPERON_MAP=$RUN_FULL_OPERON_MAP RUN_REORGANIZE_OUTPUTS=$RUN_REORGANIZE_OUTPUTS"
            echo "gene-called genomes (in $(gene_call_roots | tr '\n' ' ')):"
            while IFS= read -r _root; do
                for d in "$_root"/*/; do
                    [[ -s "${d}gene_calls/genome.faa" ]] && printf "  - %-40s %s\n" "$(basename "$d")" "$(basename "$_root")"
                done
            done < <(gene_call_roots)
            exit 0
            ;;
        --help|-h)  usage; exit 0 ;;
        *) echo "[run-meta] ERROR: unknown arg: $1" >&2; exit 1 ;;
    esac
done
(( ${#stages[@]} )) || stages=("${stages_all[@]}")
for s in "${stages[@]}"; do
    [[ " ${stages_all[*]} " == *" $s "* ]] || { echo "[run-meta] ERROR: unknown stage: $s" >&2; exit 1; }
done

PY="$(host_python)" || exit 1

# run <label> <script> [args...] — runs one host script, logging it like margie_sb.
run() {
    local label="$1" script="$2"; shift 2
    echo "[meta] $label: $(basename "$script")"
    "$PY" "$HS/$script" "$@"
}
# run_soft — like run, but a failure only warns (figures, viewer).
run_soft() {
    run "$@" || echo "[meta] WARN: $1: $(basename "$2") failed (non-fatal)" >&2
}

# ── gather ────────────────────────────────────────────────────────────────────
# Rebuilds the genome's folder from scratch out of the per-tool results.
stage_gather() {
    local g="$1" d="$GENOME_RESULTS_DIR/$1" gc table t src f
    gc="$(genome_calls_dir "$g" 2>/dev/null || true)"
    [[ -n "$gc" && -s "$gc/gene_calls/genome.faa" ]] \
        || { echo "[meta] ERROR: $g has no gene calls under $(gene_call_roots | tr '\n' ' ')" >&2; return 1; }
    rm -rf "$d"
    # Stages the gene calls under rasttk/ with RAST_* names whichever caller ran;
    # only the final table renames them to the actual caller.
    mkdir -p "$d/rasttk"

    # Gene calls under margie_sb's RASTtk names (Prodigal writes the same set).
    cp -p "$gc"/gene_calls/* "$d/rasttk/"
    cp -p "$gc/gene_calls/genome.faa" "$d/rasttk/rast.faa"
    cp -p "$gc/gene_calls/genome.gff" "$d/rasttk/rast.gff"
    table=""
    for f in "$gc"/processed/rast*.tsv "$gc/processed/prodigal_gene_calls.tsv"; do
        [[ -s "$f" ]] && { table="$f"; break; }
    done
    [[ -n "$table" ]] || { echo "[meta] ERROR: $g has no gene-call table in $gc/processed/" >&2; return 1; }
    cp -p "$table" "$d/rasttk/rast.tsv"

    # Every other tool's processed tables: <tool>/<genome>/processed/*.tsv -> <tool>/.
    for t in "$annotation_output_root"/*/; do
        t="$(basename "$t")"
        case "$t" in
            rasttk|genomes|gtdbtk|aai|ani|closest|synteny) continue ;;
        esac
        src="$annotation_output_root/$t/$g/processed"
        [[ -d "$src" ]] || continue
        for f in "$src"/*.tsv; do
            [[ -f "$f" ]] || continue
            mkdir -p "$d/$t"
            cp -p "$f" "$d/$t/"
        done
    done

    # Adds the envelope call to every row of the gram-dependent tools' results.
    if [[ -s "$d/envelope/envelope_summary.tsv" ]]; then
        for t in deepsig psortb signalp4; do
            f="$d/$t/${t}_results.tsv"
            [[ -s "$f" ]] || continue
            "$PY" "$HS/enrich_with_envelope.py" \
                --input "$f" --envelope-summary "$d/envelope/envelope_summary.tsv" --output "$f"
        done
    fi
    echo "[meta] gather: $g -> ${d#$REPO_ROOT/} ($(find "$d" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ') tools)"
}

# ── phase 9: consolidation ────────────────────────────────────────────────────
stage_consolidation() {
    local g="$1" d="$GENOME_RESULTS_DIR/$1" c="$GENOME_RESULTS_DIR/$1/consolidation"
    mkdir -p "$c"
    run consolidation consolidation/detect-columns.py \
        --input-root "$d" --organism-name "$g" --output "$c/detected-columns.json"
    run consolidation consolidation/merge-all-columns.py \
        --input-root "$d" --organism-name "$g" --domain "$(genome_domain "$g")" \
        --output "$c/consolidated-merged-all-columns.tsv" --manifest "$c/manifest.tsv"
    run consolidation consolidation/filter-no-stat.py \
        --input "$c/consolidated-merged-all-columns.tsv" --output "$c/consolidated-no-stat.tsv"
}

# ── phase 10: labeling ────────────────────────────────────────────────────────
stage_labeling() {
    local d="$GENOME_RESULTS_DIR/$1" l="$GENOME_RESULTS_DIR/$1/labeling"
    local merged="$d/consolidation/consolidated-merged-all-columns.tsv"
    mkdir -p "$l"
    run labeling labeling/assign-canonical-label.py --input "$merged" --output "$l/labeled-genes.tsv"
    run labeling labeling/add-ec-consensus.py \
        --labeled-input "$l/labeled-genes.tsv" --merged-input "$merged" --output "$l/labeled-genes-ec-consensus.tsv"
    run labeling labeling/add-operon-info.py \
        --labeled-input "$l/labeled-genes.tsv" --merged-input "$merged" --output "$l/labeled-genes-operon-info.tsv"
    run labeling labeling/add-cluster-agreement.py \
        --labeled-input "$l/labeled-genes.tsv" --merged-input "$merged" --output "$l/labeled-genes-cluster-agreement.tsv"
}

# ── phase 11: scoring ─────────────────────────────────────────────────────────
stage_scoring() {
    local g="$1" d="$GENOME_RESULTS_DIR/$1"
    local l="$d/labeling" s="$d/scoring" merged="$d/consolidation/consolidated-merged-all-columns.tsv"
    local operon="$d/operon/operon_results.tsv"
    [[ -s "$operon" ]] || { echo "[meta] ERROR: scoring needs operon's results ($operon); run the operon tool for $g" >&2; return 1; }
    mkdir -p "$s" "$(dirname "$OCC_REFERENCE")"
    run scoring scoring/update-occ-reference-depot.py \
        --organism "$g" --labeled-input "$l/labeled-genes.tsv" --operon-info-input "$l/labeled-genes-operon-info.tsv" \
        --reference "$OCC_REFERENCE" --output-token "$s/occ_reference_updated.tkn"
    run scoring scoring/score-hierarchy-tier.py \
        --labeled-input "$l/labeled-genes.tsv" --output "$s/scored-labeled-genes-annotation-tool-tier.tsv"
    run scoring scoring/score-confidence-tier.py \
        --hierarchy-tier-input "$s/scored-labeled-genes-annotation-tool-tier.tsv" \
        --ec-consensus-input "$l/labeled-genes-ec-consensus.tsv" \
        --output "$s/scored-labeled-genes-annotation-ec-tier.tsv"
    run scoring scoring/score-c1-tool-coverage.py \
        --labeled-input "$l/labeled-genes.tsv" --cluster-agreement-input "$l/labeled-genes-cluster-agreement.tsv" \
        --output "$s/scored-labeled-genes-c1-tool-coverage.tsv"
    run scoring scoring/score-c2-operon-probability.py \
        --operon-input "$l/labeled-genes-operon-info.tsv" --operon-results "$operon" \
        --output "$s/scored-labeled-genes-c2-operon-probability.tsv"
    run scoring scoring/c3_score_organism.py \
        --operon-info "$l/labeled-genes-operon-info.tsv" --genes-file "$l/labeled-genes.tsv" \
        --operon-results "$operon" --reference "$OCC_REFERENCE" \
        --output "$s/scored-labeled-genes-c3-operonic-context-confidence.tsv"
    run scoring scoring/score-c4-ec-agreement.py \
        --ec-consensus-input "$l/labeled-genes-ec-consensus.tsv" \
        --confidence-tier-input "$s/scored-labeled-genes-annotation-ec-tier.tsv" \
        --output "$s/scored-labeled-genes-c4-ec-agreement.tsv"
    run scoring scoring/score-confidence-final.py \
        --c1-input "$s/scored-labeled-genes-c1-tool-coverage.tsv" \
        --c2-input "$s/scored-labeled-genes-c2-operon-probability.tsv" \
        --c3-input "$s/scored-labeled-genes-c3-operonic-context-confidence.tsv" \
        --c4-input "$s/scored-labeled-genes-c4-ec-agreement.tsv" \
        --operon-input "$l/labeled-genes-operon-info.tsv" --merged-input "$merged" \
        --output "$s/scored-labeled-genes-confidence-final.tsv"
    run scoring scoring/make-final-annotation-with-confidence.py \
        --labeled-input "$l/labeled-genes.tsv" --operon-info-input "$l/labeled-genes-operon-info.tsv" \
        --operon-results-input "$operon" --merged-input "$merged" \
        --hierarchy-tier-input "$s/scored-labeled-genes-annotation-tool-tier.tsv" \
        --confidence-final-input "$s/scored-labeled-genes-confidence-final.tsv" \
        --c4-input "$s/scored-labeled-genes-c4-ec-agreement.tsv" \
        --occ-reference "$OCC_REFERENCE" \
        --gene-caller "$(genome_caller_ran "$g" 2>/dev/null || echo rasttk)" \
        --output "$s/FINAL_ANNOTATION_WITH_CONFIDENCE.tsv"
}

# ── phase 12: fingerprint ─────────────────────────────────────────────────────
stage_fingerprint() {
    local g="$1" d="$GENOME_RESULTS_DIR/$1"
    local l="$d/labeling" s="$d/scoring" f="$d/fingerprint" phobius="$d/phobius/phobius_top1.tsv"
    mkdir -p "$f" "$FP_DIR"
    run fingerprint fingerprint/add-gene-fingerprint.py \
        --labeled-input "$l/labeled-genes.tsv" --confidence-final-input "$s/scored-labeled-genes-confidence-final.tsv" \
        --output-hash-pattern "$f/labeled-genes-fingerprint-hash-pattern.tsv" \
        --output-hash-label "$f/labeled-genes-fingerprint-hash-label.tsv" \
        --output-label-pattern "$f/labeled-genes-fingerprint-label-pattern.tsv" \
        --output-full "$f/labeled-genes-fingerprint-full.tsv" \
        --output-full-with-scores "$f/labeled-genes-fingerprint-full-with-scores.tsv"
    run fingerprint fingerprint/update-fingerprint-database.py \
        --hash-label-input "$f/labeled-genes-fingerprint-hash-label.tsv" --organism "$g" --fingerprint-database "$FP_DB"
    run fingerprint fingerprint/add-operon-fingerprint.py \
        --operon-input "$l/labeled-genes-operon-info.tsv" --hash-label-input "$f/labeled-genes-fingerprint-hash-label.tsv" \
        --output "$f/labeled-genes-operon-fingerprint.tsv"
    run fingerprint fingerprint/add-fingerprint-to-final.py \
        --confidence-final-input "$s/scored-labeled-genes-confidence-final.tsv" \
        --fingerprint-hash-label-input "$f/labeled-genes-fingerprint-hash-label.tsv" \
        --operon-fingerprint-input "$f/labeled-genes-operon-fingerprint.tsv" \
        --fingerprint-database "$FP_DB" \
        --operon-fp-label-ordered-database "$OPERON_FP_LABEL_ORDERED" \
        --operon-fp-label-composition-database "$OPERON_FP_LABEL_COMPOSITION" \
        --ec-consensus-input "$l/labeled-genes-ec-consensus.tsv" \
        --output "$s/scored-raw-labeled-genes-final-annotated.tsv"
    # make-final-annotated.py needs a phobius summary; phobius is licence-gated, so an empty one stands in.
    if [[ ! -f "$phobius" ]]; then
        phobius="$f/phobius_top1.not-run.tsv"
        printf 'feature_id\n' > "$phobius"
    fi
    run fingerprint fingerprint/make-final-annotated.py \
        --full-evidence-input "$s/scored-raw-labeled-genes-final-annotated.tsv" \
        --labeling-genes-input "$l/labeled-genes.tsv" --phobius-top1-input "$phobius" \
        --fingerprint-full-input "$f/labeled-genes-fingerprint-full.tsv" \
        --output "$s/FINAL-scored-labeled-genes-annotated.tsv"
    run fingerprint fingerprint/update-operon-fingerprint-database.py \
        --operon-fingerprint-input "$f/labeled-genes-operon-fingerprint.tsv" --organism "$g" \
        --evidence-ordered-database "$OPERON_FP_EVIDENCE_ORDERED" \
        --evidence-composition-database "$OPERON_FP_EVIDENCE_COMPOSITION" \
        --label-ordered-database "$OPERON_FP_LABEL_ORDERED" \
        --label-composition-database "$OPERON_FP_LABEL_COMPOSITION"
}

# ── phase 14: evidence ────────────────────────────────────────────────────────
stage_evidence() {
    local g="$1" d="$GENOME_RESULTS_DIR/$1"
    [[ "$RUN_EVIDENCE" == 1 ]] || return 0
    run evidence evidence/build-gene-report.py \
        --consolidated "$d/consolidation/consolidated-merged-all-columns.tsv" \
        --confidence-final "$d/scoring/scored-labeled-genes-confidence-final.tsv" \
        --fingerprint-full "$d/fingerprint/labeled-genes-fingerprint-full.tsv" \
        --operon-fingerprint "$d/fingerprint/labeled-genes-operon-fingerprint.tsv" \
        --fingerprint-database "$FP_DB" \
        --operon-fingerprint-database-evidence-ordered "$OPERON_FP_EVIDENCE_ORDERED" \
        --operon-fingerprint-database-evidence-composition "$OPERON_FP_EVIDENCE_COMPOSITION" \
        --operon-fingerprint-database-label-ordered "$OPERON_FP_LABEL_ORDERED" \
        --operon-fingerprint-database-label-composition "$OPERON_FP_LABEL_COMPOSITION" \
        --organism-name "$g" --output-dir "$d/evidence/prepared"
}

# ── genome viewer (never fails the genome) ───────────────────────────────────
stage_viewer() {
    local g="$1" d="$GENOME_RESULTS_DIR/$1"
    local final="$d/scoring/FINAL_ANNOTATION_WITH_CONFIDENCE.tsv"
    [[ "$RUN_GENOME_VIEWER" == 1 ]] || return 0
    mkdir -p "$d/scoring/figures"
    run_soft viewer viz/gen_genome_viewer.py "$final" "$d/FINAL_GENOME_VIEWER.html" \
        --consolidated "$d/consolidation/consolidated-merged-all-columns.tsv"
    run_soft viewer viz/make_circular_genome.py "$final" "$d/scoring/figures/${g}_circular.png"
}

# ── report figures (never fail the genome) ───────────────────────────────────
stage_figures() {
    local g="$1" out="$GENOME_RESULTS_DIR/$1/scoring/figures"
    [[ "$RUN_REPORT_FIGURES" == 1 ]] || return 0
    run_soft figures scoring/analysis/report_figures/make_organism_report.py \
        --run-root "$GENOME_RESULTS_DIR" --organism "$g" --operon-db "$OPERON_FP_LABEL_ORDERED" --output-dir "$out"
    run_soft figures scoring/analysis/report_figures/verify_report.py \
        --run-root "$GENOME_RESULTS_DIR" --organism "$g" --figures-dir "$out"
    if [[ "$RUN_FULL_OPERON_MAP" == 1 ]]; then
        run_soft figures scoring/analysis/report_figures/make_complete_operon_diagrams.py \
            --run-root "$GENOME_RESULTS_DIR" --organism "$g" --operon-db "$OPERON_FP_LABEL_ORDERED" --output-dir "$out"
    fi
}

# ── finalize: once, after every genome ───────────────────────────────────────
if [[ "$finalize" == yes ]]; then
    genomes=()
    for d in "$GENOME_RESULTS_DIR"/*/; do
        [[ -d "$d" ]] || continue
        g="$(basename "$d")"
        [[ -f "$d/scoring/FINAL_ANNOTATION_WITH_CONFIDENCE.tsv" || -f "$d/FINAL_ANNOTATION_WITH_CONFIDENCE.tsv" ]] && genomes+=("$g")
    done
    (( ${#genomes[@]} )) || { echo "[run-meta] finalize: no scored genomes in $GENOME_RESULTS_DIR"; exit 0; }
    if [[ "$RUN_REPORT_FIGURES" == 1 ]]; then
        out="$GENOME_RESULTS_DIR/scoring/figures/global"
        run_soft figures scoring/analysis/report_figures/make_global_report.py \
            --run-root "$GENOME_RESULTS_DIR" --operon-db "$OPERON_FP_LABEL_ORDERED" --output-dir "$out"
        run_soft figures scoring/analysis/report_figures/verify_report.py \
            --run-root "$GENOME_RESULTS_DIR" --figures-dir "$out"
    fi
    if [[ "$RUN_REORGANIZE_OUTPUTS" == 1 ]]; then
        # Must follow the pangenome figures, which read every genome's scoring/.
        run_soft finalize reorganize_outputs.py \
            --run-root "$GENOME_RESULTS_DIR" --genomes "${genomes[@]}" --figures-dirname diagrams \
            --excel-script "$HS/fingerprint/make-final-excel.py" --python "$PY" \
            --workers "$(( ${#genomes[@]} < 4 ? ${#genomes[@]} : 4 ))"
    fi
    echo "[run-meta] finalize: ${#genomes[@]} genome(s) in ${GENOME_RESULTS_DIR#$REPO_ROOT/}"
    exit 0
fi

# ── per genome ────────────────────────────────────────────────────────────────
organisms=()
while IFS= read -r _root; do
    for d in "$_root"/*/; do
        g="$(basename "$d")"
        [[ -s "${d}gene_calls/genome.faa" ]] || continue
        [[ -n "$org_filter" && "$g" != "$org_filter" ]] && continue
        organisms+=("$g")
    done
done < <(gene_call_roots)
if (( ${#organisms[@]} == 0 )); then
    echo "[run-meta] ERROR: no gene-called genomes${org_filter:+ named $org_filter} in $(gene_call_roots | tr '\n' ' ')" >&2
    exit 1
fi

for g in "${organisms[@]}"; do
    echo "════════════════════════════════════════════════════════════"
    echo "[run-meta] $g  (domain=$(genome_domain "$g"), envelope=$(envelope_type "$g"))"
    echo "════════════════════════════════════════════════════════════"
    for s in "${stages[@]}"; do
        "stage_$s" "$g"
    done
done
echo "[run-meta] done: ${organisms[*]} -> ${GENOME_RESULTS_DIR#$REPO_ROOT/}"
