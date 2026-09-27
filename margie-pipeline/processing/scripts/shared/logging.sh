# logging.sh — per-invocation logging: a JSONL index plus one full log per run.
#
# Outputs:
#   logs/commands.log                                    global JSONL index (all stages)
#   logs/<stage>/NNNNNNN-<user>-<name>-<ts>.log          per-invocation full output
#
# Stage subdirs (set LOG_DIR before sourcing this file):
#   logs/pre-setup/    check.sh
#   logs/setup/        setup.sh orchestrator
#   logs/containers/   container build / pull
#   logs/databases/    database downloads
#   logs/databases/llm/ LLM model download
#   logs/annotation/   annotate.sh
#
# Usage:
#   LOG_DIR="$REPO_ROOT/logs/<stage>"
#   source "$REPO_ROOT/processing/scripts/shared/logging.sh"
#   log_invocation "$0" "$@"
# Safe to source from libraries: log_invocation is a no-op once already called.

# LOG_ROOT = base logs/ dir; holds commands.log and the global TSV ledger.
: "${LOG_ROOT:=${REPO_ROOT:-$(pwd)}/logs}"
# LOG_DIR = stage-specific subdir; default = LOG_ROOT when not set by caller.
: "${LOG_DIR:=$LOG_ROOT}"
# Global JSONL index always lives at the root, regardless of stage.
: "${LOG_FILE:=$LOG_ROOT/commands.log}"

mkdir -p "$LOG_DIR" "$LOG_ROOT"
export LOG_ROOT

# Escapes a string for a JSON value.
_log_json_escape() {
    local s=${1//\\/\\\\}
    s=${s//\"/\\\"}
    s=${s//$'\n'/\\n}
    s=${s//$'\r'/\\r}
    s=${s//$'\t'/\\t}
    printf '%s' "$s"
}

# _log_next_seq <dir> -- increments a per-directory counter under flock and
# prints it zero-padded to 7 digits (no lock on macOS, which lacks flock).
_log_next_seq() {
    local dir=$1
    mkdir -p "$dir"
    local counter="$dir/.log_seq"
    local lock="$dir/.log_seq.lock"
    local n
    {
        command -v flock >/dev/null 2>&1 && flock -x 9
        n=$(cat "$counter" 2>/dev/null || echo -1)
        n=$(( n + 1 ))
        printf '%d\n' "$n" > "$counter"
        printf '%07d' "$n"
    } 9>"$lock"
}

# Records the start in the JSONL index and tees stdout/stderr into a new run log;
# only the first call in a process does anything.
log_invocation() {
    [[ -n "${LOG_INVOCATION_ID:-}" ]] && return 0

    local script_path=$1; shift
    local script_base ts_iso ts_file ts_compact pid user host argv
    script_base=$(basename "$script_path" .sh)
    ts_iso=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    ts_file=$(date +%Y%m%d-%H%M%S)
    ts_compact=$(date -u +%Y%m%dT%H%M%SZ)
    pid=$$
    user=${USER:-unknown}
    host=$(hostname -s 2>/dev/null || echo unknown)
    argv=$(printf '%q ' "$@"); argv=${argv% }

    LOG_INVOCATION_ID="${ts_file}-${pid}"
    LOG_INVOCATION_START=$(date +%s)
    LOG_INVOCATION_SCRIPT=$(basename "$script_path")
    local _seq _slurm_part
    _seq=$(_log_next_seq "$LOG_DIR")
    # Include SLURM job ID in filename when running inside a job
    if [[ -n "${SLURM_JOB_ID:-}" ]]; then
        _slurm_part="-job${SLURM_JOB_ID}"
    else
        _slurm_part=""
    fi
    LOG_RUN_FILE="$LOG_DIR/${_seq}-${user}${_slurm_part}-${script_base}-${ts_compact}.log"
    # Not exported, so child processes get their own log file.

    # Record relative path from LOG_ROOT so the JSONL index is meaningful
    local _log_rel="${LOG_RUN_FILE#$LOG_ROOT/}"

    local _slurm_job_json
    if [[ -n "${SLURM_JOB_ID:-}" ]]; then
        _slurm_job_json=',"slurm_job":"'"$SLURM_JOB_ID"'"'
    else
        _slurm_job_json=''
    fi
    printf '{"id":"%s","event":"start","ts":"%s","script":"%s","args":"%s","pid":%d,"user":"%s","host":"%s","cwd":"%s","log":"%s"%s}\n' \
        "$LOG_INVOCATION_ID" \
        "$ts_iso" \
        "$(_log_json_escape "$LOG_INVOCATION_SCRIPT")" \
        "$(_log_json_escape "$argv")" \
        "$pid" \
        "$(_log_json_escape "$user")" \
        "$(_log_json_escape "$host")" \
        "$(_log_json_escape "$PWD")" \
        "$(_log_json_escape "$_log_rel")" \
        "$_slurm_job_json" \
        >> "$LOG_FILE"

    echo "[log] $LOG_RUN_FILE" >&2

    # tee stdout + stderr to the per-invocation log file
    exec > >(tee -a "$LOG_RUN_FILE") 2>&1

    trap '_log_finish $?' EXIT
}

# EXIT trap: records the end, exit code and duration in the JSONL index.
_log_finish() {
    local rc=$1 end ts duration
    end=$(date +%s)
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    duration=$(( end - ${LOG_INVOCATION_START:-end} ))
    local _log_rel="${LOG_RUN_FILE:-unknown}"
    _log_rel="${_log_rel#$LOG_ROOT/}"
    printf '{"id":"%s","event":"end","ts":"%s","script":"%s","exit":%d,"duration_s":%d,"log":"%s"}\n' \
        "${LOG_INVOCATION_ID:-unknown}" \
        "$ts" \
        "$(_log_json_escape "${LOG_INVOCATION_SCRIPT:-unknown}")" \
        "$rc" \
        "$duration" \
        "$(_log_json_escape "$_log_rel")" \
        >> "$LOG_FILE"
    exec 1>&- 2>&- || true
}
