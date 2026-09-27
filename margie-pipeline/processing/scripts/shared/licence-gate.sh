#!/usr/bin/env bash
# licence-gate.sh — asks for the licence statement before a restricted tool or
# database (MEROPS, TCDB, TMbed, Phobius, parts of InterPro, PSORTb) is fetched.
# It prints the notice, requires $LICENCE_REQUIRED_STATEMENT to be typed (or given
# via LICENCE_STATEMENT for CI / SLURM), and records every accept and skip.
#
# Usage from a per-tool download / build script:
#
#     licence_gate <tool> <ENV_VAR> <flag-name> <rerun-hint> <<'NOTICE'
#       ... multi-line licence notice text ...
#     NOTICE
#
# Returns 0 when accepted; 1 when declined, timed out or without a TTY (callers
# `exit 0` so setup continues; the skip goes to $LICENCE_SKIP_LEDGER).
#
# Environment:
#   LICENCE_SKIP_LEDGER   path to a TSV file that setup.sh truncates at
#                         the start of each invocation. Each licence_gate
#                         skip appends one TAB-separated row:
#                             <iso-ts>\t<tool>\t<reason>\t<rerun-hint>
#                         If unset, the skip is logged but not appended.
#   LICENCE_GATE_TIMEOUT  seconds to wait for an answer (default 300).
#   LICENCE_ACCEPT_ALL    if "1", behaves as if every per-tool env var
#                         were set. Set by --accept-all-licences in setup.sh.
#   LICENCE_STATEMENT     the licence statement, for every route that does
#                         not type it at a prompt. Set by --licence-statement.
#   LICENCE_SESSION_FILE  set by setup.sh: once the statement is typed at one
#                         prompt, later tools in the same run ask yes/no.

# Sources once.
if [[ -n "${_LICENCE_GATE_SOURCED:-}" ]]; then return 0 2>/dev/null || true; fi
_LICENCE_GATE_SOURCED=1

# Minimal fallbacks when colors.sh has not been sourced.
command -v log  >/dev/null 2>&1 || log()  { printf '[log]  %s\n' "$*" >&2; }
command -v warn >/dev/null 2>&1 || warn() { printf '[warn] %s\n' "$*" >&2; }
command -v ok   >/dev/null 2>&1 || ok()   { printf '[ok]   %s\n' "$*" >&2; }

: "${LICENCE_GATE_TIMEOUT:=300}"   # 5 minutes
: "${LICENCE_ACCEPT_ALL:=0}"

# The statement typed to accept a gated licence; identical copies live in
# margie-build (build-lib.sh, build-databases/lib.sh) and gui/src/lib/licence.ts.
LICENCE_REQUIRED_STATEMENT="I accept that I am using these tools for non-commercial purposes and have received all permissions from the upstream developers."
LICENCE_LEGAL_NOTICE="This is a legally binding agreement. Once you accept, your use of these tools and their databases is entirely your own responsibility."

# _licence_normalise <text> -- lower-cases, squeezes spaces and drops a final full stop.
_licence_normalise() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -s '[:space:]' ' ' \
        | sed -e 's/^ //' -e 's/ $//' -e 's/\.$//'
}

# licence_statement_matches <text> -- succeeds if <text> is the required statement.
licence_statement_matches() {
    [[ -n "${1:-}" ]] || return 1
    [[ "$(_licence_normalise "$1")" == "$(_licence_normalise "$LICENCE_REQUIRED_STATEMENT")" ]]
}

# _licence_statement_given -- succeeds if the statement is in LICENCE_STATEMENT or
# was typed earlier in this setup run.
_licence_statement_given() {
    licence_statement_matches "${LICENCE_STATEMENT:-}" && return 0
    [[ -n "${LICENCE_SESSION_FILE:-}" && -s "$LICENCE_SESSION_FILE" ]] || return 1
    licence_statement_matches "$(cat "$LICENCE_SESSION_FILE" 2>/dev/null)"
}

# _licence_print_statement -- prints the legal notice and the statement to type.
_licence_print_statement() {
    {
        printf '\n  %s\n' "$LICENCE_LEGAL_NOTICE"
        printf '  To accept, type this statement (anything else skips the tool):\n\n'
        printf '    %s\n\n' "$LICENCE_REQUIRED_STATEMENT"
    } >&2
}

# Append-only acceptance ledger kept across runs, one row per acceptance:
#     <iso-ts>\t<tool>\t<source>\t<intended_use>\tuser=\tpipeline=\tstatement=yes
# Only statement=yes rows count.
: "${LICENCE_ACCEPTANCE_LEDGER:=${LOG_ROOT:-${LOG_DIR:-/tmp}}/licence-acceptances.tsv}"
mkdir -p "$(dirname "$LICENCE_ACCEPTANCE_LEDGER")" 2>/dev/null || true

# _licence_record_accept <tool> <source> <notice> <detail> -- appends a ledger row,
# writes a full-text record under logs/licensing/ (copied to the depot) and
# prints an acceptance block to stderr. <detail> says how acceptance was given.
_licence_record_accept() {
    local tool=$1 source=$2 notice=${3:-} detail=${4:-$2}
    local ts ts_compact use user ip pipeline_ver
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)
    ts_compact=$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || echo unknown)
    use=${LICENCE_INTENDED_USE:-<not declared>}
    pipeline_ver=$(git -C "${REPO_ROOT:-$(pwd)}" rev-parse --short HEAD 2>/dev/null || echo unknown)
    user=$(id -un 2>/dev/null || echo "${PIPELINE_USER:-${USER:-unknown}}")
    ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    [[ -z "$ip" ]] && ip="unavailable"

    # ── 1. TSV ledger ──
    printf '%s\t%s\t%s\t%s\tuser=%s\tpipeline=%s\tstatement=yes\n' "$ts" "$tool" "$source" "$use" "$user" "$pipeline_ver" \
        >> "$LICENCE_ACCEPTANCE_LEDGER" 2>/dev/null || true

    # ── 2. full-text record → local logs/licensing/ and depot ──
    local _depot_file="${LICENCE_SHARED_LOG_DIR:+${LICENCE_SHARED_LOG_DIR%/}/${user}-${tool}-${ts_compact}.txt}"
    local _local_file="${LOG_ROOT:-${LOG_DIR:-logs}}/licensing/${user}-${tool}-${ts_compact}.txt"
    if [[ -n "$_depot_file" ]]; then mkdir -p "$(dirname "$_depot_file")" 2>/dev/null || true; fi
    mkdir -p "$(dirname "$_local_file")" 2>/dev/null || true
    {
        printf '================================================================\n'
        printf 'margie — Prokaryotic Genome Annotation Pipeline\n'
        printf 'Per-Tool Licence Acceptance Record\n'
        printf '================================================================\n'
        printf '\n'
        printf '%s accepted the following licence terms for %s\n' "$user" "$tool"
        printf 'via %s.\n' "$detail"
        printf '\n'
        printf 'Date/Time (UTC):   %s\n' "$ts"
        printf 'Pipeline Version:  %s\n' "$pipeline_ver"
        printf 'IP Address:        %s\n' "$ip"
        printf 'Declared Use:      %s\n' "$use"
        printf 'Statement:         %s\n' "$LICENCE_REQUIRED_STATEMENT"
        printf '\n'
        printf '%s\n' "$LICENCE_LEGAL_NOTICE"
        printf '\n'
        printf '================================================================\n'
        printf 'The licence terms stated:\n'
        printf '================================================================\n'
        printf '\n'
        if [[ -n "$notice" ]]; then
            printf '%s\n' "$notice"
        else
            printf '(notice text not captured for this acceptance path)\n'
        fi
        printf '\n'
        printf '================================================================\n'
        printf 'End of Licence Acceptance Record\n'
        printf '================================================================\n'
        printf '\n'
    } >> "$_local_file" 2>/dev/null || true
    if [[ -n "$_depot_file" ]]; then cp "$_local_file" "$_depot_file" 2>/dev/null || true; fi

    # ── 3. terminal block ──
    local bar
    bar=$(printf '%.0s=' {1..72})
    {
        printf '\n%s%s%s\n' "${C_BOLD:-}${C_YELLOW:-}" "$bar" "${C_NC:-}"
        printf '%s== LICENCE ACCEPTED — %s%s\n' "${C_BOLD:-}${C_YELLOW:-}" "$tool" "${C_NC:-}"
        printf '%s%s%s\n' "${C_BOLD:-}${C_YELLOW:-}" "$bar" "${C_NC:-}"
        printf '  tool          : %s\n' "$tool"
        printf '  accepted by   : %s\n' "$user"
        printf '  via           : %s\n' "$detail"
        printf '  timestamp     : %s\n' "$ts"
        printf '  pipeline ver  : %s\n' "$pipeline_ver"
        printf '  declared use  : %s\n' "$use"
        printf '  audit trail   : %s\n' "$LICENCE_ACCEPTANCE_LEDGER"
        printf '  local copy    : %s\n' "${LOG_ROOT:-${LOG_DIR:-logs}}/licensing/"
        printf '  statement     : %s\n' "$LICENCE_REQUIRED_STATEMENT"
        printf '  NOTE: %s\n' "$LICENCE_LEGAL_NOTICE"
        printf '        The margie pipeline does not grant any rights beyond those\n'
        printf '        conferred directly by the upstream rights holder.\n'
        printf '%s%s%s\n\n' "${C_BOLD:-}${C_YELLOW:-}" "$bar" "${C_NC:-}"
    } >&2
}

# _licence_record_skip <tool> <reason> <rerun-hint> -- appends a row to the skip ledger.
_licence_record_skip() {
    local tool=$1 reason=$2 rerun=$3
    local ts user
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)
    user=$(id -un 2>/dev/null || echo "${PIPELINE_USER:-${USER:-unknown}}")
    if [[ -n "${LICENCE_SKIP_LEDGER:-}" ]]; then
        printf '%s\t%s\t%s\t%s\tuser=%s\n' "$ts" "$tool" "$reason" "$rerun" "$user" \
            >> "$LICENCE_SKIP_LEDGER" 2>/dev/null || true
    fi
}

# licence_gate <tool> <ENV_VAR> <flag-name> <rerun-hint> (notice on stdin)
# Acceptance precedence (highest first). Routes 1-3 count only when the
# licence statement is in LICENCE_STATEMENT (or was typed earlier this run):
#   1. LICENCE_AGREED_<TOOL>=1 in pipeline.conf.sh (config-time consent)
#      -- requires LICENCE_INTENDED_USE to be non-empty.
#   2. LICENCE_ACCEPT_ALL=1                       (--accept-all-licences)
#   3. <ENV_VAR>=1 / --accept-<tool>-licence flag (CI / SLURM)
#   4. Interactive: type the statement (5-minute timeout); once typed, later
#      tools in the same setup run ask yes/no.
licence_gate() {
    local tool=$1 env_var=$2 flag=$3 rerun=$4
    local notice
    notice=$(cat)
    local conf_var="LICENCE_AGREED_$(printf "%s" "$tool" | tr a-z A-Z)"
    local pre=""    # pre-acceptance route still missing the statement

    # 1. pipeline.conf.sh declaration.
    if [[ "${!conf_var:-0}" == "1" ]]; then
        if [[ -z "${LICENCE_INTENDED_USE:-}" ]]; then
            warn "$tool: $conf_var=1 in pipeline.conf.sh but LICENCE_INTENDED_USE is empty."
            warn "      Set LICENCE_INTENDED_USE to a truthful description of your use,"
            warn "      otherwise the config-time acceptance is ignored."
        elif _licence_statement_given; then
            local _detail="pipeline.conf.sh (${conf_var}=1; LICENCE_INTENDED_USE=\"${LICENCE_INTENDED_USE}\"; the licence statement in LICENCE_STATEMENT)"
            _licence_record_accept "$tool" "pipeline.conf" "$notice" "$_detail"
            return 0
        else
            pre="$conf_var=1"
        fi
    fi

    # 2. master --accept-all-licences.
    if (( LICENCE_ACCEPT_ALL == 1 )); then
        if _licence_statement_given; then
            local _detail
            if [[ -n "${SLURM_JOB_ID:-}" ]]; then
                _detail="the --accept-all-licences flag with the licence statement, in SLURM batch job ${SLURM_JOB_ID} (job name: ${SLURM_JOB_NAME:-not set}, non-interactive)"
            else
                _detail="the --accept-all-licences flag passed to setup.sh with the licence statement"
            fi
            _licence_record_accept "$tool" "accept-all-licences" "$notice" "$_detail"
            return 0
        fi
        pre="--accept-all-licences"
    fi

    # 3. per-tool env var / CLI flag.
    if [[ "${!env_var:-0}" == "1" ]]; then
        if _licence_statement_given; then
            local _detail
            if [[ -n "${SLURM_JOB_ID:-}" ]]; then
                _detail="${flag} with the licence statement, in SLURM batch job ${SLURM_JOB_ID} (job name: ${SLURM_JOB_NAME:-not set}, non-interactive)"
            else
                _detail="${flag} passed to setup.sh with the licence statement"
            fi
            _licence_record_accept "$tool" "cli-flag ($flag)" "$notice" "$_detail"
            return 0
        fi
        pre="$flag"
    fi

    # The notice is always printed so the log keeps it, even on a skip.
    printf '\n%s\n' "$notice" >&2
    if [[ -n "$pre" ]]; then
        warn "$tool: $pre alone does not accept a licence; the licence statement is needed too."
    fi

    # stdin is the notice, so the check is for a controlling terminal (none in SLURM or the GUI).
    if ! ( : </dev/tty ) 2>/dev/null; then
        warn "$tool: licence statement not given and no interactive terminal."
        warn "      to enable $tool, run ./setup.sh at a terminal and type the statement,"
        warn "      or give it for this run:"
        warn "        $rerun --licence-statement \"$LICENCE_REQUIRED_STATEMENT\""
        warn "      (or set LICENCE_STATEMENT, with LICENCE_INTENDED_USE and $conf_var=1)"
        _licence_record_skip "$tool" "no TTY and licence statement not given" "$rerun"
        return 1
    fi

    # 4. Interactive. Anything but the statement (or yes, once typed), Ctrl+C or a timeout skips.
    local ans="" rc=0 typed_before=0 prompt
    _licence_statement_given && typed_before=1
    if (( typed_before )); then
        prompt=$(printf '  >> You typed the licence statement earlier in this run. Accept %s under it too? [yes/no] (%ss timeout = no): ' \
            "$tool" "$LICENCE_GATE_TIMEOUT")
    else
        _licence_print_statement
        prompt='  > '
    fi
    trap 'rc=130' INT
    printf '%s' "$prompt" >/dev/tty
    read -r -t "$LICENCE_GATE_TIMEOUT" ans </dev/tty || rc=$?
    trap - INT
    printf '\n' >&2

    if (( rc == 130 )); then
        warn "$tool: cancelled by user (Ctrl+C). Not downloaded / not built."
        warn "      to enable $tool later, re-run with: $rerun"
        _licence_record_skip "$tool" "user cancelled (Ctrl+C)" "$rerun"
        return 1
    fi
    if (( rc != 0 )); then
        warn "$tool: no response within ${LICENCE_GATE_TIMEOUT}s -- skipping."
        warn "      to enable $tool later, re-run with: $rerun"
        _licence_record_skip "$tool" "timeout (${LICENCE_GATE_TIMEOUT}s)" "$rerun"
        return 1
    fi

    if (( typed_before )); then
        case "$(printf '%s' "$ans" | tr '[:upper:]' '[:lower:]')" in
            y|yes)
                _licence_record_accept "$tool" "interactive-setup" "$notice" \
                    "interactive confirmation at the terminal prompt -- the user typed the licence statement earlier in this setup run, was shown this tool's notice, and entered 'yes'"
                return 0
                ;;
        esac
    elif licence_statement_matches "$ans"; then
        if [[ -n "${LICENCE_SESSION_FILE:-}" ]]; then
            ( umask 077; printf '%s\n' "$ans" > "$LICENCE_SESSION_FILE" ) 2>/dev/null || true
        fi
        _licence_record_accept "$tool" "interactive-setup" "$notice" \
            "interactive confirmation at the terminal prompt -- the user was shown the full licence notice and typed the licence statement"
        return 0
    fi

    warn "$tool: licence NOT accepted -- skipping. Nothing downloaded / built."
    warn "      to enable $tool later, re-run with: $rerun"
    _licence_record_skip "$tool" "licence statement not typed" "$rerun"
    return 1
}

# licence_is_accepted <tool> -- succeeds if pipeline.conf.sh accepts it (flag,
# intended use and statement) or the ledger has a statement=yes row for it.
# annotate.sh uses it to skip restricted tools that were never enabled.
licence_is_accepted() {
    local tool=$1
    local conf_var="LICENCE_AGREED_$(printf "%s" "$tool" | tr a-z A-Z)"
    if [[ "${!conf_var:-0}" == "1" && -n "${LICENCE_INTENDED_USE:-}" ]] \
       && licence_statement_matches "${LICENCE_STATEMENT:-}"; then
        return 0
    fi
    if [[ -s "${LICENCE_ACCEPTANCE_LEDGER:-/dev/null}" ]] \
       && grep $'\t'"$tool"$'\t' "$LICENCE_ACCEPTANCE_LEDGER" 2>/dev/null | grep -q $'\t''statement=yes'; then
        return 0
    fi
    return 1
}

# licence_print_run_banner <tool> -- prints when and how a restricted tool's
# licence was accepted, at the start of its runner; silent if never accepted.
licence_print_run_banner() {
    local tool=$1
    local conf_var="LICENCE_AGREED_$(printf "%s" "$tool" | tr a-z A-Z)"
    local conf_ts=""
    local last_source="" last_ts="" last_use=""

    # Most recent acceptance row in the ledger.
    if [[ -s "${LICENCE_ACCEPTANCE_LEDGER:-/dev/null}" ]]; then
        local row
        row=$(grep $'\t'"$tool"$'\t' "$LICENCE_ACCEPTANCE_LEDGER" 2>/dev/null | grep $'\t''statement=yes' | tail -1)
        if [[ -n "$row" ]]; then
            IFS=$'\t' read -r last_ts _ last_source last_use <<<"$row"
        fi
    fi

    local conf_accepted=no
    if [[ "${!conf_var:-0}" == "1" && -n "${LICENCE_INTENDED_USE:-}" ]] \
       && licence_statement_matches "${LICENCE_STATEMENT:-}"; then
        conf_accepted=yes
    fi

    if [[ "$conf_accepted" != yes && -z "$last_source" ]]; then
        return 0
    fi

    printf '\n'                                                                   >&2
    printf '============================================================\n'      >&2
    printf '  LICENCE ACCEPTANCE -- %s\n' "$tool"                                  >&2
    printf '============================================================\n'      >&2
    if [[ "$conf_accepted" == yes ]]; then
        printf '  source         : pipeline.conf.sh (%s=1)\n' "$conf_var"        >&2
        printf '  intended use   : %s\n' "$LICENCE_INTENDED_USE"                 >&2
    fi
    if [[ -n "$last_source" ]]; then
        printf '  last recorded  : %s\n' "$last_ts"                              >&2
        printf '  via            : %s\n' "$last_source"                          >&2
        printf '  declared use   : %s\n' "$last_use"                             >&2
    fi
    printf '  audit trail    : %s\n' "${LICENCE_ACCEPTANCE_LEDGER:-<unset>}"     >&2
    printf '  statement      : %s\n' "$LICENCE_REQUIRED_STATEMENT"             >&2
    printf '  NOTE: %s\n' "$LICENCE_LEGAL_NOTICE"                                   >&2
    printf '        The margie pipeline does not grant any rights beyond those\n'         >&2
    printf '        conferred directly by the upstream rights holder.\n'                   >&2
    printf '============================================================\n\n'               >&2
}

# print_licence_skip_report -- prints, at the end of setup.sh, which tools the
# skip ledger lists, why, and how to re-enable them.
print_licence_skip_report() {
    local ledger=${LICENCE_SKIP_LEDGER:-}
    [[ -n "$ledger" && -s "$ledger" ]] || return 0

    printf '\n'
    printf '============================================================\n' >&2
    printf '  WARNING -- SOME TOOLS WERE SKIPPED (licence not confirmed)\n' >&2
    printf '============================================================\n' >&2
    printf '  The pipeline can still run, but these tools / databases\n'    >&2
    printf '  will not be available during annotation:\n\n'                 >&2
    local ts tool reason rerun
    while IFS=$'\t' read -r ts tool reason rerun; do
        [[ -z "$tool" ]] && continue
        printf '   * %-12s  reason: %s\n'        "$tool" "$reason"  >&2
        printf '                  re-run: %s\n\n' "$rerun"           >&2
    done < "$ledger"
    printf '  To enable any of the above, re-run the suggested command\n'   >&2
    printf '  and type the licence statement at the prompt (or give it\n'   >&2
    printf '  with --licence-statement for a non-interactive run).\n'      >&2
    printf '  Full audit trail: %s\n' "$ledger"                             >&2
    printf '============================================================\n\n' >&2
}
