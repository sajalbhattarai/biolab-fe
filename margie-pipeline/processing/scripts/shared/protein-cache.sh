# shellcheck shell=bash
# protein-cache.sh — keeps each tool's rows per protein so a protein is annotated
# once (wraps protein_cache.py). Sourced after result-cache.sh and pipeline-lib.sh.
#
#   pc_run <tool> <genome> <tool-output-dir> <runner>
#       Runs <runner> on only the proteins not yet cached (skips it when none),
#       merges in the cached rows and stores the new ones. USE_PROTEIN_CACHE=0
#       turns it off. bash 3.2 safe.

_PC_PY="${REPO_ROOT:-.}/processing/scripts/shared/protein_cache.py"
# Tools whose rows depend only on the protein (not on the envelope or genome context).
PC_TOOLS=" cog kegg eggnog uniprot pfam merops tcdb dbcan pgap tmbed tigrfam phobius interpro "

# Succeeds when the protein cache is on and covers this tool.
pc_applies() {
    [[ "${USE_PROTEIN_CACHE:-1}" == "1" && "$PC_TOOLS" == *" $1 "* && -f "$_PC_PY" ]] && cache_enabled
}

# Prints the cache key: a hash of the tool's image, SIF, database and settings.
pc_key() {
    local t="$1" py img rt info=""
    py="$(cache_python)" || return 1
    img="$(tool_image "$t")"
    rt="$(detect_runtime 2>/dev/null || true)"
    case "$rt" in
        docker|podman|container) info="$("$rt" image inspect "$img" 2>/dev/null | "$py" -c 'import hashlib,sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())')" ;;
    esac
    "$py" "$_PC_PY" key "$t" "$img" "image=$info" "${SIF_DIR:-}/$t.sif" "$(tool_db "$t")" \
        "apps=$(tool_apps "$t")"
}

# Runs a tool through the protein cache (see header).
pc_run() {
    local t="$1" org="$2" out="$3"; shift 3
    local py faa work key counts ran=1
    if ! pc_applies "$t" || ! py="$(cache_python)"; then
        "$@"; return $?
    fi
    faa="$(genome_calls_dir "$org" 2>/dev/null)/gene_calls/genome.faa"
    work="$OUTPUT_ROOT/.pipeline-state/protein-cache/$t/$org"
    if [[ ! -s "$faa" ]] || ! key="$(pc_key "$t")" \
        || ! counts="$("$py" "$_PC_PY" split "$MARGIE_DB" "$faa" "$work" "$org" "$t" "$key")"; then
        "$@"; return $?
    fi
    echo "[protein-cache] $t: $org — ${counts% *} protein(s) done before, ${counts#* } to annotate" >&2
    if [[ -s "$work/input/$org/gene_calls/genome.faa" ]]; then
        env "TOOL_${t}_INPUT=$work/input" "$@" || return $?
    else
        ran=0   # every protein's rows come from the cache
    fi
    "$py" "$_PC_PY" merge "$work" "$out" "$t" "$ran" || return 1
    counts="$("$py" "$_PC_PY" store "$MARGIE_DB" "$faa" "$out" "$t" "$key" 2>/dev/null)" \
        && [[ "$counts" =~ ^[1-9][0-9]*$ ]] && echo "[protein-cache] $t: kept $counts new protein(s) of $org" >&2
    return 0
}
