# shellcheck shell=bash
# result-cache.sh — keeps a tool's results under the hash of its genome.
# Sourced after pipeline.conf.sh; thin wrapper around result_cache.py.
#
#   cache_enabled                     is the cache on, with a usable python
#   cache_fasta <organism>            the genome file a hash is taken of
#   cache_restore <tool> <org> <dir>  0 if <dir> was filled from the cache
#   cache_store   <tool> <org> <dir>  keep <dir> for next time
#
# Every function is quiet and returns non-zero rather than failing a run.
# bash 3.2 safe.

_CACHE_PY="${REPO_ROOT:-.}/processing/scripts/shared/result_cache.py"

# Prints a python3 that has sqlite3 (only the standard library is needed).
cache_python() {
    if [[ -n "${MARGIE_PYTHON:-}" ]] && "$MARGIE_PYTHON" -c 'import sqlite3' >/dev/null 2>&1; then
        echo "$MARGIE_PYTHON"; return 0
    fi
    local n
    for n in python3 python; do
        command -v "$n" >/dev/null 2>&1 || continue
        "$n" -c 'import sqlite3' >/dev/null 2>&1 && { command -v "$n"; return 0; }
    done
    return 1
}

# Succeeds when the cache is on and usable.
cache_enabled() {
    [[ "${USE_RESULT_CACHE:-1}" == "1" ]] || return 1
    [[ -n "${MARGIE_DB:-}" ]] || return 1
    [[ -f "$_CACHE_PY" ]] || return 1
    cache_python >/dev/null 2>&1
}

# Prints the genome FASTA the hash is taken of (the gene caller's prepared input).
cache_fasta() {
    local org="$1" f
    for f in "${gene_caller_input:-$INPUT_RASTTK}/$org.fna" \
             "${gene_caller_input:-$INPUT_RASTTK}/$org.fa" \
             "${gene_caller_input:-$INPUT_RASTTK}/$org.fasta"; do
        [[ -f "$f" ]] && { echo "$f"; return 0; }
    done
    return 1
}

# Fills <dir> from the cache; succeeds only if files were restored.
cache_restore() {
    local tool="$1" org="$2" dir="$3" py fasta n
    cache_enabled || return 1
    fasta="$(cache_fasta "$org")" || return 1
    py="$(cache_python)" || return 1
    n="$("$py" "$_CACHE_PY" get "$MARGIE_DB" "$fasta" "$tool" "$dir" 2>/dev/null)" || return 1
    [[ "$n" =~ ^[0-9]+$ ]] && (( n > 0 )) || return 1
    echo "[cache] $tool: $org already done — restored $n file(s), not run again" >&2
    return 0
}

# Stores <dir> in the cache for this genome and tool.
cache_store() {
    local tool="$1" org="$2" dir="$3" py fasta n
    cache_enabled || return 1
    [[ -d "$dir" ]] || return 1
    fasta="$(cache_fasta "$org")" || return 1
    py="$(cache_python)" || return 1
    n="$("$py" "$_CACHE_PY" put "$MARGIE_DB" "$fasta" "$tool" "$dir" 2>/dev/null)" || return 1
    [[ "$n" =~ ^[0-9]+$ ]] && (( n > 0 )) && echo "[cache] $tool: kept $n file(s) for $org" >&2
    return 0
}
