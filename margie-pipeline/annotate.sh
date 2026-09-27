#!/usr/bin/env bash
# annotate.sh — orchestrates the annotation pipeline for every genome.
#
# GENOMES
#   run-prepare-genomes.sh copies user-input/*.fna to input/<genome>.fna and lists
#   each genome's domain, genetic code and gene caller in input/genomes.tsv
#   (domain and code from GTDB-Tk and/or $GENOME_METADATA). Every stage writes
#   output/<tool>/<genome>/.
#
# GRAM STAIN comes from the envelope stage, which runs after the annotation
#   tools (from tigrfam, pgap, pfam, uniprot); psortb, deepsig and signalp4 run after it.
#
# RUNTIME MODES
#   local  (no SLURM_JOB_ID): one genome at a time, end to end:
#            gene calling → annotation tools → envelope → gram-dependent tools
#            → per-genome results (run-meta.sh). Once the scored pool reaches
#            MIN_PHASE2_ORGS, Phase 2 (aai / ani / closest / synteny) runs
#            before the next genome starts.
#
#   hpc    (SLURM_JOB_ID set): gene calling runs one genome at a time; each
#            called genome's tools then run in the background in a sliding
#            window of PARALLEL_TOOLS. Phase 2 runs under flock, so a later
#            trigger sees the larger pool.
#
# USAGE
#   ./annotate.sh                    run full pipeline (all annotation tools)
#   ./annotate.sh --tool kegg        limit annotation phase to kegg only
#   ./annotate.sh --genes-only       gene calling only, no annotation tools
#   ./annotate.sh --prepare-only     GTDB-Tk (if on) + genome table, then stop
#   ./annotate.sh --list             dry-run: show config + genome table
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
. "$here/pipeline.conf.sh"
. "$here/processing/scripts/shared/colors.sh"
. "$here/processing/scripts/shared/help-render.sh"
LOG_DIR="${REPO_ROOT}/logs/annotation"
. "$here/processing/scripts/shared/logging.sh"
. "$here/processing/scripts/run-individual-containers/lib/pipeline-lib.sh"
. "$here/processing/scripts/shared/licence-gate.sh"
. "$here/processing/scripts/shared/result-cache.sh"
. "$here/processing/scripts/shared/protein-cache.sh"
. "$here/processing/scripts/help/annotate-help.sh"

tag=annotate
log_invocation "$0" "$@"

runner_dir="$here/processing/scripts/run-individual-containers"

# ── Annotation tools (Phase 1b) ──
# Gene calling and envelope are fixed stages; operon always runs because
# scoring (run-meta.sh) reads it. Phase 1b is split around the envelope:
#   Phase 1b-pre  — gram-agnostic tools
#   envelope      — infers diderm / monoderm / archaea
#   Phase 1b-post — PSORTb, DeepSig, SignalP4, which pick models by envelope
annotation_tools_default=(
    # Stage C — general functional annotation (gram-agnostic)
    kegg cog pfam pgap tigrfam dbcan eggnog merops tcdb uniprot interpro geneprop
    # Stage C — localization, gram-agnostic predictors
    tmbed phobius
    # Stage C — operonic structure
    operon
    # envelope runs automatically between pre and post phases (not listed here)
    # Stage C — localization, gram-dependent predictors (run after envelope)
    psortb deepsig signalp4
)

# Gram-dependent tools (run after envelope); all others are Phase 1b-pre.
_gram_post_tools_default=(psortb deepsig signalp4)

# Tools the envelope reads; added whenever a gram-dependent tool is selected.
_envelope_input_tools=(tigrfam pgap pfam uniprot)

# ── Pipeline mode ──
[[ -n "${SLURM_JOB_ID:-}" ]] && pipeline_mode=hpc || pipeline_mode=local

# ── CLI ──
annotation_tools=()
list_only=no
prepare_only=no
genes_only=no

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)  shift; print_help_annotate "${1:-main}"; exit 0 ;;
        --list)     list_only=yes; shift ;;
        --prepare-only) prepare_only=yes; shift ;;
        --genes-only) genes_only=yes; shift ;;
        --tool)     [[ $# -ge 2 ]] || { err "--tool needs a value"; exit 2; }
                    annotation_tools+=("$2"); shift 2 ;;
        --tool=*)   annotation_tools+=("${1#--tool=}"); shift ;;
        *) err "unknown option: $1 (see --help)"; exit 2 ;;
    esac
done

# No --tool means the default set; --genes-only means no tools at all.
if [[ "$genes_only" == yes ]]; then
    (( ${#annotation_tools[@]} )) && { err "--genes-only runs no annotation tools, so it takes no --tool"; exit 2; }
else
    [[ ${#annotation_tools[@]} -eq 0 ]] && annotation_tools=("${annotation_tools_default[@]+"${annotation_tools_default[@]}"}")
fi

# ── Licence pre-flight: drops gated tools whose licence is not accepted ──
gated_tools=("${LICENCE_GATED_TOOLS[@]:-merops tcdb tmbed interpro phobius psortb}")
_is_gated() {
    local t=$1 g
    for g in "${gated_tools[@]+"${gated_tools[@]}"}"; do [[ "$g" == "$t" ]] && return 0; done
    return 1
}

gram_post_tools=("${_gram_post_tools_default[@]+"${_gram_post_tools_default[@]}"}")
_is_gram_post() {
    local t=$1 g
    for g in "${gram_post_tools[@]+"${gram_post_tools[@]}"}"; do [[ "$g" == "$t" ]] && return 0; done
    return 1
}
filtered=()
skipped_no_licence=()
for t in "${annotation_tools[@]+"${annotation_tools[@]}"}"; do
    if _is_gated "$t" && ! licence_is_accepted "$t"; then
        skipped_no_licence+=("$t")
    else
        filtered+=("$t")
    fi
done
if (( ${#skipped_no_licence[@]} )); then
    warn "skipping ${#skipped_no_licence[@]} restricted tool(s) — licence not accepted: ${skipped_no_licence[*]}"
    warn "  to enable: set LICENCE_AGREED_<TOOL>=1 in pipeline.conf.sh  or  ./setup.sh --tool <tool>"
fi
annotation_tools=("${filtered[@]+"${filtered[@]}"}")

# ── Implied tools: operon for scoring, the envelope inputs for gram-dependent tools ──
_has_tool() {
    local t=$1 x
    for x in "${annotation_tools[@]+"${annotation_tools[@]}"}"; do [[ "$x" == "$t" ]] && return 0; done
    return 1
}
_wants_envelope=no
for t in "${annotation_tools[@]+"${annotation_tools[@]}"}"; do
    _is_gram_post "$t" && _wants_envelope=yes
done
[[ "$genes_only" == yes ]] || _has_tool operon || annotation_tools+=(operon)

if [[ "$_wants_envelope" == yes ]]; then
    _added=()
    for t in "${_envelope_input_tools[@]}"; do
        _has_tool "$t" || { annotation_tools=("$t" "${annotation_tools[@]}"); _added+=("$t"); }
    done
    (( ${#_added[@]} )) && log "gram-dependent tools selected: also running ${_added[*]} (the envelope stage reads them)"
fi

if [[ "$prepare_only" == no && "$list_only" == no && "$genes_only" == no ]] && (( ${#annotation_tools[@]} == 0 )); then
    err "no annotation tools to run after licence pre-flight."
    exit 1
fi

# ── Database pre-flight ──
# Stops before gene calling, listing every selected tool whose database folder is missing.
if [[ "$prepare_only" == no && "$list_only" == no ]]; then
    _no_db=()
    for t in "${annotation_tools[@]+"${annotation_tools[@]}"}"; do
        _runner="$runner_dir/run-${t}.sh"
        [[ -f "$_runner" ]] && grep -q 'run_downstream_tool' "$_runner" || continue
        # Data inside the image: the runner creates the folder itself.
        grep -q "mkdir -p \"\$DB_ROOT/${t}\"" "$_runner" && continue
        _db_dir="$(tool_db "$t")"
        [[ -d "$_db_dir" ]] || _no_db+=("$t  ->  $_db_dir")
    done
    if (( ${#_no_db[@]} )); then
        err "no database for ${#_no_db[@]} of the tool(s) asked for:"
        printf '  %s\n' "${_no_db[@]}" >&2
        err "set them up (./setup.sh --tool <tool>), or leave them out of --tool."
        exit 1
    fi
fi

if [[ "$genes_only" == yes && "$list_only" == no && "$prepare_only" == no ]]; then
    warn "no annotation tools chosen — this run calls genes and stops there"
fi

# ── Phase 2 state (flock-protected shared files) ──
_state_dir="$OUTPUT_ROOT/.pipeline-state"
_pool_file="$_state_dir/scored_organisms.txt"
_pool_lock="$_state_dir/.pool.lock"
_phase2_lock="$_state_dir/.phase2.lock"

# Adds $1 to the scored pool under flock (unlocked on macOS) and prints the pool size.
_atomic_add_scored() {
    local org="$1" count
    mkdir -p "$_state_dir"
    touch "$_pool_file" "$_pool_lock"
    {
        command -v flock >/dev/null 2>&1 && flock -x 200
        grep -qxF "$org" "$_pool_file" 2>/dev/null || echo "$org" >> "$_pool_file"
        count=$(wc -l < "$_pool_file")
        echo "$count"
    } 200>>"$_pool_lock"
}

# Prints the scored pool, one genome per line.
_get_pool_list() {
    [[ -f "$_pool_file" ]] && cat "$_pool_file" || true
}

# ── Phase 2 runner ──
# Runs the comparative tools over the pool under flock, so simultaneous
# triggers run one after the other, the later with the larger pool.
_run_phase2() {
    mkdir -p "$_state_dir"
    touch "$_phase2_lock"
    (
        command -v flock >/dev/null 2>&1 && flock -x 9
        local pool_orgs count
        pool_orgs="$(_get_pool_list)"
        count=$(printf '%s\n' "$pool_orgs" | grep -c '[^[:space:]]' 2>/dev/null || echo 0)
        if (( count < ${MIN_PHASE2_ORGS:-2} )); then
            echo "[annotate] Phase 2: skipped — pool has $count organism(s), need ${MIN_PHASE2_ORGS:-2}"
            exit 0
        fi
        echo "════════════════════════════════════════════════════════════"
        echo "[annotate] Phase 2  (scored pool: $count organism(s))"
        printf '  %s\n' $pool_orgs
        echo "════════════════════════════════════════════════════════════"
        local _tool _r
        for _tool in "${all_comparative_tools[@]:-aai ani closest synteny}"; do
            _r="$runner_dir/run-${_tool}.sh"
            if [[ ! -x "$_r" ]]; then
                echo "[annotate] Phase 2: WARN — no runner for '$_tool' at $_r; skipping" >&2
                continue
            fi
            echo "──── Phase 2: $_tool ────"
            "$_r"
        done
        echo "[annotate] Phase 2 complete."
    ) 9>>"$_phase2_lock"
}

# ── Per-organism: run one annotation tool ──
# Restores the tool from the result cache, else runs it through the protein cache and stores it.
_run_one_tool() {
    local t="$1"
    local org="${PIPELINE_ORGANISM_FILTER:-}"
    local out="${annotation_output_root:-$OUTPUT_ROOT}/$t/$org"
    if [[ -n "$org" ]] && cache_restore "$t" "$org" "$out"; then
        return 0
    fi
    echo "════════════════════════════════════════════════════════════"
    log "$t"
    echo "════════════════════════════════════════════════════════════"
    _is_gated "$t" && licence_print_run_banner "$t"
    if [[ -n "$org" ]]; then
        pc_run "$t" "$org" "$out" "$runner_dir/run-${t}.sh" || return $?
    else
        "$runner_dir/run-${t}.sh" || return $?
    fi
    [[ -n "$org" ]] && cache_store "$t" "$org" "$out"
    return 0
}

# ── Per-organism Phase 1 pipeline ──
# Runs the given tools in a sliding window: PARALLEL_TOOLS wide on HPC,
# LOCAL_PARALLEL_TOOLS locally.
_run_tools() {
    local max_jobs t
    if [[ "$pipeline_mode" == hpc ]]; then
        max_jobs="${PARALLEL_TOOLS:-6}"
    else
        max_jobs="${LOCAL_PARALLEL_TOOLS:-1}"
    fi
    if (( max_jobs > 1 )); then
        for t in "$@"; do
            while (( $(jobs -rp | wc -l) >= max_jobs )); do
                wait -n 2>/dev/null || sleep 0.1
            done
            _run_one_tool "$t" &
        done
        wait
    else
        for t in "$@"; do
            _run_one_tool "$t"
        done
    fi
}

# Runs one genome's 1b-pre tools, envelope, 1b-post tools, per-genome results and
# the Phase 2 check. Needs PIPELINE_ORGANISM_FILTER exported; backgrounded on HPC.
_run_org_pipeline() {
    local org="$1"
    echo "════════════════════════════════════════════════════════════"
    echo "[annotate] organism pipeline start: $org"
    echo "════════════════════════════════════════════════════════════"

    local pre_tools=() post_tools=()
    local t
    for t in "${annotation_tools[@]+"${annotation_tools[@]}"}"; do
        if _is_gram_post "$t"; then post_tools+=("$t"); else pre_tools+=("$t"); fi
    done

    # Phase 1b-pre: gram-agnostic tools.
    (( ${#pre_tools[@]} )) && _run_tools "${pre_tools[@]}"

    if (( ${#post_tools[@]} )); then
        # Phase 1b-mid: envelope inference.
        echo "════════════════════════════════════════════════════════════"
        echo "[annotate] Phase 1b-mid envelope: $org"
        echo "════════════════════════════════════════════════════════════"
        "$runner_dir/run-envelope.sh"

        # Phase 1b-post: gram-dependent tools, reading the envelope result.
        _run_tools "${post_tools[@]}"
    fi

    # Phase 1c: per-genome results (consolidation → labeling → scoring →
    # fingerprint → evidence → viewer → figures)
    echo "[annotate] Phase 1c per-genome results: $org"
    "$runner_dir/run-meta.sh" --organism "$org"

    # Phase 1d: update scored pool; trigger Phase 2 if pool ≥ MIN_PHASE2_ORGS
    local count
    count=$(_atomic_add_scored "$org")
    echo "[annotate] $org scored. Pool size: $count organism(s)."
    if (( count >= ${MIN_PHASE2_ORGS:-2} )); then
        _run_phase2
    fi
}

# ── Genome preparation: GTDB-Tk (optional) + genome table ──
# Succeeds when some genome lacks a domain or genetic code and has not been
# through GTDB-Tk yet.
_needs_gtdbtk() {
    local n
    n="$(awk -F'\t' 'NR > 1 && $5 == "prodigal" && $6 !~ /gtdbtk/' "$GENOMES_TABLE" 2>/dev/null | wc -l | tr -d ' ')"
    if (( n > 0 )); then
        echo "[annotate] gtdbtk: $n genome(s) without a known domain and genetic code — running GTDB-Tk" >&2
        return 0
    fi
    return 1
}

# Checks up front that GTDB-Tk's image and reference tree are present.
_gtdbtk_ready() {
    local missing=() rt image
    rt="$(detect_runtime)"
    image="$(docker_image gtdbtk)"
    if [[ "$rt" == "apptainer" || "$rt" == "singularity" ]]; then
        [[ -f "$(sif_path gtdbtk)" ]] || missing+=("its image ($(sif_path gtdbtk))")
    elif [[ -n "$rt" ]]; then
        "$rt" image inspect "$image" >/dev/null 2>&1 || missing+=("its image ($image)")
    fi
    [[ -n "$(find "$DB_ROOT/gtdbtk" -maxdepth 1 -type d -name 'release*' -print -quit 2>/dev/null)" ]] \
        || missing+=("its reference tree ($DB_ROOT/gtdbtk)")
    (( ${#missing[@]} == 0 )) && return 0
    local list
    if (( ${#missing[@]} == 1 )); then list="${missing[0]} is missing"
    else list="${missing[0]} and ${missing[1]} are missing"; fi
    err "GTDB-Tk is on (RUN_GTDBTK=1) but is not set up: $list."
    err "  Build it:    ./setup.sh --containers-only --tool gtdbtk"
    err "  Download it: ./setup.sh --databases-only --tool gtdbtk   (about 150 GB)"
    err "  Or switch GTDB-Tk off and give each genome a domain and genetic code in the genome table."
    return 1
}

# Writes the genome table, running GTDB-Tk first when needed.
_prepare_genomes() {
    echo "════════════════════════════════════════════════════════════"
    log "genomes"
    echo "════════════════════════════════════════════════════════════"
    migrate_gene_call_folders
    "$runner_dir/run-prepare-genomes.sh"
    if [[ "${RUN_GTDBTK:-1}" == 1 ]]; then
        if _needs_gtdbtk; then
            _gtdbtk_ready || exit 1
            TOOL_gtdbtk_INPUT="$USER_INPUT_DIR" "$runner_dir/run-gtdbtk.sh"
            "$runner_dir/run-prepare-genomes.sh"
        fi
        # Taxonomy report (input/classification_report.tsv); nothing reads it.
        "$runner_dir/run-classify.sh" || warn "classification report not written (see above)"
    else
        log "GTDB-Tk off (RUN_GTDBTK=0): genomes without a domain and genetic code in ${GENOME_METADATA#$REPO_ROOT/} are gene-called with Prodigal"
    fi
}

# ── --list ──
if [[ "$list_only" == yes ]]; then
    echo "mode:            $pipeline_mode"
    echo "PARALLEL_TOOLS:  ${PARALLEL_TOOLS:-6}  (HPC sliding-window width)"
    echo "MIN_PHASE2_ORGS: ${MIN_PHASE2_ORGS:-2}"
    echo "RUN_GTDBTK:      ${RUN_GTDBTK:-1}"
    echo ""
    echo "annotation tools (${#annotation_tools[@]}):"
    if (( ${#annotation_tools[@]} )); then
        printf '  %s\n' "${annotation_tools[@]}"
    else
        echo "  (none — gene calling only)"
    fi
    echo ""
    echo "genome table ($GENOMES_TABLE):"
    if [[ -s "$GENOMES_TABLE" ]]; then
        genome_table_print '  '
    else
        echo "  (not written yet — ./annotate.sh --prepare-only builds it from user-input/)"
    fi
    exit 0
fi

_prepare_genomes
[[ "$prepare_only" == yes ]] && { ok "genome table ready: ${GENOMES_TABLE#$REPO_ROOT/}"; exit 0; }

# ── Genomes ──
organisms=()
while IFS= read -r _org; do
    [[ -n "$_org" ]] && organisms+=("$_org")
done < <(genome_list)

if (( ${#organisms[@]} == 0 )); then
    err "no genomes found in $USER_INPUT_DIR (*.fna, *.fa, *.fasta)"
    exit 1
fi

echo "[annotate] ${#organisms[@]} genome(s): ${organisms[*]}"
if [[ "$pipeline_mode" == hpc ]]; then
    echo "[annotate] mode=$pipeline_mode  parallel_tools=${PARALLEL_TOOLS:-6}  min_phase2=${MIN_PHASE2_ORGS:-2}"
else
    echo "[annotate] mode=$pipeline_mode  ${LOCAL_PARALLEL_TOOLS:-1} tool(s) at once, ${LOCAL_TOOL_CORES:-?} core(s) and ${LOCAL_TOOL_MEMORY_GB:-?} GB each (of ${LOCAL_MAX_CORES:-?} cores, ${LOCAL_MAX_MEMORY_GB:-?} GB)  min_phase2=${MIN_PHASE2_ORGS:-2}"
fi

# Each run starts with an empty Phase 2 pool.
mkdir -p "$_state_dir"
rm -f "$_pool_file" "$_pool_lock" "$_phase2_lock"

# Gene-calls one genome with the caller its table row names.
_gene_call() {
    local org="$1" caller
    caller="$(genome_field "$org" gene_caller)"
    echo "════════════════════════════════════════════════════════════"
    echo "[annotate] gene calling ($caller): $org"
    echo "════════════════════════════════════════════════════════════"
    "$runner_dir/run-${caller}.sh"
}

# ── Main orchestration loop ──
if [[ "$genes_only" == yes ]]; then
    # Without annotation results nothing downstream can run, so this ends at gene calls.
    for org in "${organisms[@]+"${organisms[@]}"}"; do
        export PIPELINE_ORGANISM_FILTER="$org"
        _gene_call "$org"
        unset PIPELINE_ORGANISM_FILTER
    done
    ok "gene calls complete for ${#organisms[@]} genome(s) -> $(gene_call_roots | sed "s|^$REPO_ROOT/||" | tr '\n' ' ')(<genome>/gene_calls/)"
    warn "only the gene caller ran: no annotation tools were chosen, so there are no annotation results for this run"
    exit 0
elif [[ "$pipeline_mode" == hpc ]]; then
    # HPC: sequential gene calling; each genome's downstream pipeline runs in the background.
    for org in "${organisms[@]+"${organisms[@]}"}"; do
        export PIPELINE_ORGANISM_FILTER="$org"
        _gene_call "$org"
        _run_org_pipeline "$org" &
    done
    unset PIPELINE_ORGANISM_FILTER
    wait
else
    # Local: each genome finishes, Phase 2 included, before the next starts.
    for org in "${organisms[@]+"${organisms[@]}"}"; do
        export PIPELINE_ORGANISM_FILTER="$org"
        _gene_call "$org"
        _run_org_pipeline "$org"
        unset PIPELINE_ORGANISM_FILTER
    done
fi

# Pangenome figures and the final per-genome folder layout, after every genome.
"$runner_dir/run-meta.sh" --finalize

ok "all organisms complete. — sb"
