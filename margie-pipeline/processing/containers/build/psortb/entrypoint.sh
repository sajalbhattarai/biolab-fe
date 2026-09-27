#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# CONTAINER ENTRYPOINT — PSORTb v3 (subcellular localization)
# Installed at /usr/local/bin/run inside the container.
#
# Pipeline-standard interface (single file):
#   run -i /input/organism.faa -o /output [-t THREADS] [-k n|p|a]
#       [--organism-name NAME]
#
# Directory mode (process all organisms under a directory):
#   run -i /input/rasttk_output -o /output [-t THREADS] [-k n|p|a]
#   All .faa files found recursively are processed; --organism-name is ignored.
#   Gram class is auto-detected per organism from its path hierarchy.
#
# Gram stain is auto-detected from the input path hierarchy:
#   gram-positive/ → -k p   gram-negative/ → -k n   archaea/ → -k a
#
# Output directory layout (under -o):
#   /output/psortb/
#     ├── raw/
#     │     ├── psortb.txt           ← untouched PSORTb terse predictions
#     │     └── psortb_err.txt       ← captured stderr
#     └── processed/
#           ├── psortb_results.tsv   ← one row per protein (PSORTB_ prefix)
# ═══════════════════════════════════════════════════════════════════════════════
set -euo pipefail


# >>> wired: detailed-step <<<
# >>> wired: pipeline_log helper <<<
# Shared provenance-log helper (synced into scripts/ by build-and-push.sh).
# Resolve own location even when invoked via symlink (e.g. /usr/local/bin/run).
_pl_self="${BASH_SOURCE[0]}"
while [[ -L "$_pl_self" ]]; do _pl_self="$(readlink "$_pl_self")"; done
# shellcheck source=/dev/null
_pl_dir="$(cd "$(dirname "$_pl_self")" && pwd)"
if [[ -f "$_pl_dir/pipeline_log.sh" ]]; then
    # shellcheck source=/dev/null
    source "$_pl_dir/pipeline_log.sh"
elif [[ -f "$_pl_dir/scripts/pipeline_log.sh" ]]; then
    # shellcheck source=/dev/null
    source "$_pl_dir/scripts/pipeline_log.sh"
elif [[ -f "/opt/psortb/pipeline_log.sh" ]]; then
    # shellcheck source=/dev/null
    source "/opt/psortb/pipeline_log.sh"
else
    # shellcheck source=/dev/null
    source "/opt/psortb/scripts/pipeline_log.sh"
fi

usage() {
    cat <<'HELP_EOF'

PSORTb v3 — prokaryote subcellular localization predictor

USAGE (single file)
  docker run ... annotation/psortb:latest \
    -i /input/organism.faa -o /output \
    [-t THREADS] [-k n|p|a] [--organism-name NAME]

USAGE (directory — all organisms processed)
  run -i /input/rasttk_output -o /output [-t THREADS] [-k n|p|a]
  All .faa files found recursively under -i are processed.
  --organism-name is ignored in directory mode (derived per file).
  Gram class is auto-detected per organism from its path hierarchy.

  Gram class (-k) is auto-detected from the input path hierarchy:
    gram-positive/ → p   gram-negative/ → n   archaea/ → a

REQUIRED MOUNTS
  /input/   Protein FASTA (.faa) or directory containing .faa files — read-only
  /output/  Output root directory — writable

REQUIRED OPTIONS
  -i FILE|DIR         Protein FASTA input file or input directory
  -o DIR              Output root directory (container creates <out>/<organism>/{raw,processed}/)

OPTIONAL OPTIONS
  -t INT              CPU threads                            [default: 4 — reserved]
  -k STR              Gram class: n (neg) | p (pos) | a (archaea)  [auto-detected from path]
  --organism-name STR Override organism name (single-file mode only)
  --help, -h          Show this help and exit

OUTPUTS  (under <OUTPUT>/<organism>/)
  raw/psortb.txt                PSORTb terse predictions (untouched)
  raw/psortb_err.txt            PSORTb stderr (untouched)
  processed/psortb_results.tsv  normalised TSV — one row per protein

HELP_EOF
}

# ── Argument parsing ──────────────────────────────────────────────────────────
INPUT=""
OUTPUT_ROOT=""
THREADS=4
GRAM=""                # no default; resolved from -k or path hierarchy inside run_one()
DOMAIN=""
ORGANISM_NAME=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -i)               INPUT="$2";          shift 2 ;;
        -o)               OUTPUT_ROOT="$2";    shift 2 ;;
        -t)               THREADS="$2";        shift 2 ;;
        -k)               GRAM="$2";           shift 2 ;;
        --domain)         DOMAIN="$2";         shift 2 ;;
        --organism-name)  ORGANISM_NAME="$2";  shift 2 ;;
        -d)               shift 2 ;;            # accepted for pipeline parity; no external DB needed
        --help|-h)        usage; exit 0 ;;
        *) echo "[psortb] ERROR: unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

[[ -z "$INPUT"       ]] && { echo "[psortb] ERROR: -i INPUT required"  >&2; exit 1; }
[[ -z "$OUTPUT_ROOT" ]] && { echo "[psortb] ERROR: -o OUTPUT required" >&2; exit 1; }
[[ ! -e "$INPUT"     ]] && { echo "[psortb] ERROR: input not found: $INPUT" >&2; exit 1; }

export BLASTDIR="${BLASTDIR:-/usr/bin}"

# ── Single-organism processing function ──────────────────────────────────────
# Args: <faa_path> <organism_name>
run_one() {
    local _faa="$1"
    local _org="$2"

    # Gram-class detection — inherit top-level override if user passed -k,
    # otherwise auto-detect from the per-organism input path hierarchy.
    local _gram="$GRAM"
    if [[ -z "$_gram" ]]; then
        local _ip_lower
        _ip_lower="$(echo "$_faa" | tr '[:upper:]' '[:lower:]')"
        if   echo "$_ip_lower" | grep -qE '(^|/)gram-positive(/|$)'; then _gram="p"
        elif echo "$_ip_lower" | grep -qE '(^|/)gram-negative(/|$)'; then _gram="n"
        elif echo "$_ip_lower" | grep -qE '(^|/)archaea(/|$)';       then _gram="a"
        elif echo "$_ip_lower" | grep -qE '(^|/)unknown(/|$)';       then _gram="n"
        elif echo "$_ip_lower" | grep -qE '(^|/)bacteria(/|$)';      then _gram="n"
        fi
        [[ -n "$_gram" ]] && echo "[psortb] Auto-detected gram from input path: -k $_gram"
    fi
    if [[ -z "$_gram" ]]; then
        echo "[psortb] ERROR: gram class unresolved. Provide -k {n|p|a}, OR place genome in" >&2
        echo "         input/gram-positive, input/gram-negative, input/archaea, or input/unknown subfolder." >&2
        return 1
    fi
    case "$_gram" in
        n|p|a) ;;
        *) echo "[psortb] ERROR: -k must be n, p, or a (got: $_gram)" >&2; return 1 ;;
    esac

    # Output directory layout
    local _out_dir="$OUTPUT_ROOT/$_org"
    local _raw_dir="$_out_dir/raw"
    local _proc_dir="$_out_dir/processed"
    mkdir -p "$_raw_dir" "$_proc_dir"

    # >>> wired: pipeline_log_init <<<
    local _log_path="$_out_dir/psortb-pipeline-log.txt"
    pipeline_log_init psortb "${_org}" "$_out_dir" "$_log_path"
    if command -v pipeline_log_legal_preamble >/dev/null 2>&1; then
        pipeline_log_legal_preamble
    fi

    local _raw_txt="$_raw_dir/psortb.txt"
    local _raw_err="$_raw_dir/psortb_err.txt"
    local _proc_tsv="$_proc_dir/psortb_results.tsv"

    local _tool_used="PSORTb 3.0.3"
    local _db_used="PSORTb bundled models | Source: https://www.psort.org/psortb/ | path(container): /usr/local/bin"
    local _psortb_cmd="perl /usr/local/bin/psortb3_patched.pl -${_gram} -o terse ${_faa}"

    pipeline_log_section "psortb annotation"
    pipeline_log_kv      "Tool"                 "$_tool_used"
    pipeline_log_kv_path "Input (host)"         "${_faa}"
    pipeline_log_kv      "Input (container)"    "${_faa}"
    pipeline_log_kv_path "Database (host)"      "/usr/local/bin"
    pipeline_log_kv      "Database (container)" "/usr/local/bin"
    pipeline_log_kv_path "Output (host)"        "$_out_dir"
    pipeline_log_kv      "Output (container)"   "$_out_dir"
    pipeline_log_kv      "Threads"              "${THREADS:-1}"

    echo "[psortb] Input:        $_faa ($_org)"
    echo "[psortb] Gram class:   $_gram"
    echo "[psortb] Output root:  $_out_dir"
    echo "[psortb] Threads:      $THREADS (reserved; psortb is single-threaded)"

    # ── Idempotency: skip the prediction step if raw output already exists ───
    if [[ -s "$_raw_txt" ]]; then
        echo "[psortb] Raw output already exists ($_raw_txt), skipping psortb (delete manually to re-run)"
        pipeline_log_skipped "PSORTb subcellular localization" "$_psortb_cmd" "raw output already present"
    else
        echo "[psortb] Running PSORTb ..."
        # psortb often exits non-zero with warnings even on success → tolerate
        # failure (|| true) and capture stderr separately, but still record the
        # exit code in the provenance log.
        pipeline_log_section "PSORTb subcellular localization"
        pipeline_log_kv      "Command"    "$_psortb_cmd"
        pipeline_log_kv_path "Raw stdout" "$_raw_txt"
        pipeline_log_kv_path "Raw stderr" "$_raw_err"
        local _psortb_start _psortb_end _psortb_rc
        _psortb_start="$(date +%s)"
        set +e
        perl /usr/local/bin/psortb3_patched.pl \
            -"${_gram}" -o terse "${_faa}" \
            > "$_raw_txt" 2> "$_raw_err"
        _psortb_rc=$?
        set -e
        _psortb_end="$(date +%s)"
        pipeline_log_kv "Elapsed (s)" "$(( _psortb_end - _psortb_start ))"
        pipeline_log_kv "Exit code"   "$_psortb_rc"
        if [[ "$_psortb_rc" -ne 0 ]]; then
            pipeline_log_kv "Status" "non-zero exit tolerated (psortb often warns); continuing"
        fi
    fi

    # ── Post-process raw TSV into the normalised TSV(s) ──────────────────────
    run_postprocess() {
        local _py=""
        if command -v python3 >/dev/null 2>&1; then
            _py="python3"
        elif [[ -x "/opt/conda/bin/python3" ]]; then
            _py="/opt/conda/bin/python3"
        else
            echo "[psortb] python3 not found in container PATH; TSV generation deferred to host-side postproc" >&2
            return 0
        fi
        if [[ ! -f "/opt/psortb/scripts/process_psortb_raw_results.py" ]]; then
            echo "[psortb] process_psortb_raw_results.py not found in container; TSV generation deferred to host-side postproc" >&2
            return 0
        fi
        "$_py" /opt/psortb/scripts/process_psortb_raw_results.py \
            --input          "$_raw_txt" \
            --output         "$_proc_tsv" \
            --organism-name  "$_org" \
            --domain         "$DOMAIN" \
            --tool-used      "$_tool_used" \
            --command-used   "$_psortb_cmd" \
            --database-used  "$_db_used" \
            --gram-class     "$_gram" \
            --input-path     "$_faa" \
            --output-path    "$_out_dir"
    }
    echo "[psortb] Post-processing $_raw_txt ..."
    pipeline_log_step "post-process -> processed/psortb_results.tsv" run_postprocess
    pipeline_log_kv_path "Processed TSV" "$_proc_tsv"

    # >>> wired: pipeline_log_close <<<
    pipeline_log_close

    echo "[psortb] Done: $_org"
    echo "  raw/       : $_raw_dir"
    echo "  processed/ : $_proc_dir"
}

# ── Main dispatch ─────────────────────────────────────────────────────────────
if [[ -d "$INPUT" ]]; then
    declare -A _seen=()
    mapfile -t _faas < <(find -L "$INPUT" -type f -name '*.faa' | sort)
    (( ${#_faas[@]} )) || { echo "[psortb] ERROR: no .faa files found under $INPUT" >&2; exit 1; }
    _ok=0; _fail=0; _total="${#_faas[@]}"
    for _i in "${!_faas[@]}"; do
        _faa="${_faas[$_i]}"
        _parent="$(dirname "$_faa")"
        [[ "$(basename "$_parent")" == "gene_calls" ]] && _parent="$(dirname "$_parent")"
        _org="$(basename "$_parent")"
        [[ -n "${_seen[$_org]+x}" ]] && continue
        _seen[$_org]=1
        echo "[$(( _i + 1 ))/$_total] Processing: $_org"
        if run_one "$_faa" "$_org"; then _ok=$(( _ok + 1 ))
        else                              _fail=$(( _fail + 1 )); fi
    done
    echo "[psortb] Batch complete: success=$_ok  failed=$_fail"
    (( _fail == 0 )) || exit 2
else
    run_one "$INPUT" "${ORGANISM_NAME:-$(basename "${INPUT%.*}")}"
fi
