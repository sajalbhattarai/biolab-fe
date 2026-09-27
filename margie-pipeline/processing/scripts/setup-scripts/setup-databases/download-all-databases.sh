#!/usr/bin/env bash
# download-all-databases.sh — runs every download-<db>.sh in all_dbs and prints a summary.
# Flags pass through to each per-db script (--redo, --dry-run, --db-dir).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/lib.sh"
tag="download-all"

usage() {
    cat <<'HELP'
download-all-databases.sh — download every database listed in all_dbs.

USAGE
  ./download-all-databases.sh                # all
  ./download-all-databases.sh --redo         # force re-download
  ./download-all-databases.sh --dry-run      # plan only
  ./download-all-databases.sh pfam kegg      # subset
  ./download-all-databases.sh --tool pfam    # equivalent subset
  DB_ROOT=/scratch/dbs ./download-all-databases.sh
HELP
}

ONLY=()
PASSTHROUGH=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --tool)             ONLY+=("$2"); shift 2 ;;
        --redo|--dry-run)   PASSTHROUGH+=("$1"); shift ;;
        --db-dir)           PASSTHROUGH+=("$1" "$2"); shift 2 ;;
        --hf-token-file)    PASSTHROUGH+=("$1" "$2"); shift 2 ;;
        --reset-hf-token)   PASSTHROUGH+=("$1"); shift ;;
        --accept-merops-licence|--accept-merops-license)
                            PASSTHROUGH+=("$1"); shift ;;
        --accept-tcdb-licence|--accept-tcdb-license)
                            PASSTHROUGH+=("$1"); shift ;;
        --accept-tmbed-licence|--accept-tmbed-license)
                            PASSTHROUGH+=("$1"); shift ;;
        --accept-interpro-licence|--accept-interpro-license)
                            PASSTHROUGH+=("$1"); shift ;;
        --accept-all-licences|--accept-all-licenses)
                            PASSTHROUGH+=("$1"); shift ;;
        -h|--help)          usage; exit 0 ;;
        *)                  ONLY+=("$1"); shift ;;
    esac
done

TARGETS=( "${ONLY[@]:-${all_dbs[@]}}" )

log "DB_ROOT = $DB_ROOT"
log "targets = ${TARGETS[*]}"
hr

failed=()
succeeded=()
skipped_licence=()
# Per-database status / size / elapsed, stored in dynamic variables (bash 3.2 has no associative arrays).
_dbkey() { printf '_db_%s_%s' "$1" "$(printf '%s' "$2" | tr -c 'A-Za-z0-9_' '_')"; }
_dbset() { printf -v "$(_dbkey "$1" "$2")" '%s' "$3"; }
_dbget() { local v; v="$(_dbkey "$1" "$2")"; printf '%s' "${!v:-$3}"; }
total=${#TARGETS[@]}
i=0
_wall_start=$(date +%s)

for db_name in "${TARGETS[@]+"${TARGETS[@]}"}"; do
    i=$((i+1))
    script="$here/download-${db_name}.sh"
    if [[ ! -x "$script" ]]; then
        warn "no script for '$db_name' (expected $script) — skipping"
        failed+=("$db_name")
        _dbset status "$db_name" "NO_SCRIPT"
        _dbset size "$db_name" "-"
        _dbset elapsed "$db_name" "-"
        continue
    fi

    if [[ "$db_name" == "type_strains" && "${TYPE_STRAINS_SCOPE:-report}" == "report" ]]; then
        report_path="${TYPE_STRAINS_REPORT:-$INPUT_RASTTK/classification_report.tsv}"
        if [[ ! -s "$report_path" ]]; then
            double_hr "download [$i/$total] :: $db_name"
            warn "type_strains: deferred until classification report exists at $report_path"
            succeeded+=("$db_name")
            _dbset status "$db_name" "SKIPPED"
            _dbset size "$db_name" "-"
            _dbset elapsed "$db_name" "0s"
            continue
        fi
    fi

    double_hr "download [$i/$total] :: $db_name"
    log "── $db_name"
    _t0=$(date +%s)
    _exit=0
    "$script" ${PASSTHROUGH[@]+"${PASSTHROUGH[@]+"${PASSTHROUGH[@]}"}"} || _exit=$?
    _t1=$(date +%s)
    _secs=$(( _t1 - _t0 ))

    # Formats elapsed time as "Xm Ys" or "Xs".
    if (( _secs >= 60 )); then
        _elapsed_str="$(( _secs / 60 ))m $(( _secs % 60 ))s"
    else
        _elapsed_str="${_secs}s"
    fi
    _dbset elapsed "$db_name" "$_elapsed_str"

    # Disk usage of the database directory (best-effort).
    _db_dir="$DB_ROOT/$db_name"
    if [[ -d "$_db_dir" ]]; then
        _sz=$(du -sh "$_db_dir" 2>/dev/null | awk '{print $1}')
        _dbset size "$db_name" "${_sz:-?}"
    else
        _dbset size "$db_name" "-"
    fi

    if (( _exit == 0 )); then
        succeeded+=("$db_name")
        _dbset status "$db_name" "OK"
        ok "$db_name  ✓  (${_elapsed_str}, $(_dbget size "$db_name"))"
    else
        failed+=("$db_name")
        _dbset status "$db_name" "FAILED"
        err "$db_name failed (exit $_exit)"
    fi
done

_wall_end=$(date +%s)
_total_secs=$(( _wall_end - _wall_start ))
if (( _total_secs >= 60 )); then
    _total_elapsed="$(( _total_secs / 60 ))m $(( _total_secs % 60 ))s"
else
    _total_elapsed="${_total_secs}s"
fi

# ── Final summary ──────────────────────────────────────────────────────────
printf '\n'
double_hr "DATABASE DOWNLOAD SUMMARY"
printf '%-18s  %-8s  %8s  %10s\n' "DATABASE" "STATUS" "ELAPSED" "DISK SIZE"
printf '%.0s─' {1..52}; printf '\n'
for db_name in "${TARGETS[@]+"${TARGETS[@]}"}"; do
    _st="$(_dbget status "$db_name" "UNKNOWN")"
    _el="$(_dbget elapsed "$db_name" "?")"
    _sz="$(_dbget size "$db_name" "?")"
    case "$_st" in
        OK)        _color="${C_GREEN:-}" ;;
        SKIPPED)   _color="${C_YELLOW:-}" ;;
        FAILED)    _color="${C_RED:-}"   ;;
        *)         _color="${C_YELLOW:-}" ;;
    esac
    printf "${_color}%-18s  %-8s  %8s  %10s${C_NC:-}\n" \
        "$db_name" "$_st" "$_el" "$_sz"
done
printf '%.0s─' {1..52}; printf '\n'
printf 'Total elapsed: %s\n' "$_total_elapsed"
printf '\n'

# ── Outcome ────────────────────────────────────────────────────────────────
hr
if (( ${#failed[@]} )); then
    err "FAILED (${#failed[@]}/${total}): ${failed[*]}"
    exit 1
fi
ok "All ${total} databases provisioned successfully."
