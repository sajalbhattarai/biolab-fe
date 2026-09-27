#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# CONTAINER ENTRYPOINT — DeepSig (signal peptide predictor, GPL-3)
# Installed at /usr/local/bin/run inside the container.
#
# Pipeline-standard interface (single file):
#   run -i /input/organism.faa -o /output [-t THREADS] [-k GRAM-|GRAM+|ARCH]
#       [--organism-name NAME]
#
# Directory mode (process all organisms under a directory):
#   run -i /input/rasttk_output -o /output [-t THREADS] [-k GRAM-|GRAM+|ARCH]
#   All .faa files found recursively are processed; --organism-name is ignored.
#   Organism class is auto-detected per organism from its path hierarchy.
#
# Organism class (-k) is auto-detected from the input path hierarchy:
#   gram-positive/ → GRAM+   gram-negative/ → GRAM-   archaea/ → ARCH
#
# Output directory layout (under -o):
#   /output/deepsig/
#     ├── raw/
#     │     └── deepsig.gff3        ← untouched DeepSig GFF3 output
#     └── processed/
#           ├── deepsig_results.tsv ← one row per GFF3 feature
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
elif [[ -f "/opt/deepsig/pipeline_log.sh" ]]; then
    # shellcheck source=/dev/null
    source "/opt/deepsig/pipeline_log.sh"
else
    # shellcheck source=/dev/null
    source "/opt/deepsig/scripts/pipeline_log.sh"
fi

usage() {
    cat <<'HELP_EOF'

DeepSig — signal peptide prediction (prokaryotes + archaea)

USAGE (single file)
  docker run ... annotation/deepsig:latest \
    -i /input/organism.faa -o /output \
    [-t THREADS] [-k GRAM-|GRAM+|ARCH] [--organism-name NAME]

USAGE (directory — all organisms processed)
  run -i /input/rasttk_output -o /output [-t THREADS] [-k GRAM-|GRAM+|ARCH]
  All .faa files found recursively under -i are processed.
  --organism-name is ignored in directory mode (derived per file).
  Organism class is auto-detected per organism from its path hierarchy.

  Organism class (-k) is auto-detected from the input path hierarchy:
    gram-positive/ → GRAM+   gram-negative/ → GRAM-   archaea/ → ARCH

REQUIRED MOUNTS
  /input/   Protein FASTA (.faa) or directory containing .faa files — read-only
  /output/  Output root directory — writable

REQUIRED OPTIONS
  -i FILE|DIR         Protein FASTA input file or input directory
  -o DIR              Output root directory (container creates <out>/<organism>/{raw,processed}/)

OPTIONAL OPTIONS
  -t INT              CPU threads                            [default: 4 — reserved]
  -k STR              Organism class: GRAM- | GRAM+ | ARCH   [auto-detected from path]
  --organism-name STR Override organism name (single-file mode only)
  --help, -h          Show this help and exit

OUTPUTS  (under <OUTPUT>/<organism>/)
  raw/deepsig.gff3              GFF3 predictions (untouched DeepSig output)
  processed/deepsig_results.tsv normalised TSV — one row per GFF3 feature

HELP_EOF
}

# ── Argument parsing ──────────────────────────────────────────────────────────
INPUT=""
OUTPUT_ROOT=""
THREADS=4
ORG=""                 # no default; resolved from -k or path hierarchy inside run_one()
DOMAIN=""
ORGANISM_NAME=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -i)               INPUT="$2";          shift 2 ;;
        -o)               OUTPUT_ROOT="$2";    shift 2 ;;
        -t)               THREADS="$2";        shift 2 ;;
        -k)               ORG="$2";            shift 2 ;;
        --domain)         DOMAIN="$2";         shift 2 ;;
        --organism-name)  ORGANISM_NAME="$2";  shift 2 ;;
        -d)               shift 2 ;;            # accepted for pipeline parity; no external DB needed
        --help|-h)        usage; exit 0 ;;
        *) echo "[deepsig] ERROR: unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

[[ -z "$INPUT"       ]] && { echo "[deepsig] ERROR: -i INPUT required"  >&2; exit 1; }
[[ -z "$OUTPUT_ROOT" ]] && { echo "[deepsig] ERROR: -o OUTPUT required" >&2; exit 1; }
[[ ! -e "$INPUT"     ]] && { echo "[deepsig] ERROR: input not found: $INPUT" >&2; exit 1; }

# ── Single-organism processing function ──────────────────────────────────────
# Args: <faa_path> <organism_name>
run_one() {
    local _faa="$1"
    local _org="$2"

    # Organism-class detection — inherit top-level override if user passed -k,
    # otherwise auto-detect from the per-organism input path hierarchy.
    local _org_class="$ORG"
    if [[ -z "$_org_class" ]]; then
        local _ip_lower
        _ip_lower="$(echo "$_faa" | tr '[:upper:]' '[:lower:]')"
        if   echo "$_ip_lower" | grep -qE '(^|/)gram-positive(/|$)'; then _org_class="GRAM+"
        elif echo "$_ip_lower" | grep -qE '(^|/)gram-negative(/|$)'; then _org_class="GRAM-"
        elif echo "$_ip_lower" | grep -qE '(^|/)archaea(/|$)';       then _org_class="ARCH"
        elif echo "$_ip_lower" | grep -qE '(^|/)unknown(/|$)';       then _org_class="GRAM-"
        elif echo "$_ip_lower" | grep -qE '(^|/)bacteria(/|$)';      then _org_class="GRAM-"
        fi
        if [[ -n "$_org_class" ]]; then
            echo "[deepsig] Auto-detected organism class from input path: -k $_org_class"
        fi
    fi
    if [[ -z "$_org_class" ]]; then
        echo "[deepsig] ERROR: organism class unresolved. Provide -k {GRAM-|GRAM+|ARCH}, OR place genome in" >&2
        echo "         input/gram-positive, input/gram-negative, input/archaea, or input/unknown subfolder." >&2
        return 1
    fi

    # Map pipeline gram convention to deepsig -k values
    local _deepsig_class
    case "$_org_class" in
        GRAM-|gramn) _deepsig_class="gramn" ;;
        GRAM+|gramp) _deepsig_class="gramp" ;;
        ARCH|euk)    _deepsig_class="euk"   ;;
        *) echo "[deepsig] ERROR: -k must be GRAM-, GRAM+, or ARCH (got: $_org_class)" >&2; return 1 ;;
    esac

    # Output directory layout
    local _out_dir="$OUTPUT_ROOT/$_org"
    local _raw_dir="$_out_dir/raw"
    local _proc_dir="$_out_dir/processed"
    mkdir -p "$_raw_dir" "$_proc_dir"

    # >>> wired: pipeline_log_init <<<
    local _log_path="$_out_dir/deepsig-pipeline-log.txt"
    pipeline_log_init deepsig "${_org}" "$_out_dir" "$_log_path"
    if command -v pipeline_log_legal_preamble >/dev/null 2>&1; then
        pipeline_log_legal_preamble
    fi

    local _raw_gff3="$_raw_dir/deepsig.gff3"
    local _proc_tsv="$_proc_dir/deepsig_results.tsv"

    local _tool_used="DeepSig 1.2.5"
    local _db_used="DeepSig bundled models | Source: https://github.com/BolognaBiocomp/deepsig-biocomp | path(container): /opt/venv"
    local _deepsig_cmd="deepsig -f ${_faa} -o ${_raw_gff3} -k ${_deepsig_class}"

    pipeline_log_section "deepsig annotation"
    pipeline_log_kv      "Tool"                 "$_tool_used"
    pipeline_log_kv_path "Input (host)"         "${_faa}"
    pipeline_log_kv      "Input (container)"    "${_faa}"
    pipeline_log_kv_path "Database (host)"      "/opt/venv"
    pipeline_log_kv      "Database (container)" "/opt/venv"
    pipeline_log_kv_path "Output (host)"        "$_out_dir"
    pipeline_log_kv      "Output (container)"   "$_out_dir"
    pipeline_log_kv      "Threads"              "${THREADS:-1}"

    echo "[deepsig] Input:           $_faa ($_org)"
    echo "[deepsig] Organism class:  $_deepsig_class"
    echo "[deepsig] Output root:     $_out_dir"
    echo "[deepsig] Threads:         $THREADS (reserved; deepsig is single-threaded)"

    # ── Idempotency: skip the prediction step if raw output already exists ───
    if [[ -s "$_raw_gff3" ]]; then
        echo "[deepsig] Raw output already exists ($_raw_gff3), skipping deepsig (delete manually to re-run)"
        pipeline_log_skipped "deepsig signal-peptide prediction" "$_deepsig_cmd" "raw output already present"
    else
        echo "[deepsig] Running deepsig ..."
        pipeline_log_run_logged "deepsig signal-peptide prediction" "" "" \
            deepsig -f "$_faa" -o "$_raw_gff3" -k "$_deepsig_class"
        pipeline_log_kv_path "Raw GFF3" "$_raw_gff3"
    fi

    # ── Post-process raw GFF3 into the normalised TSV(s) ─────────────────────
    run_postprocess() {
        python3 /opt/deepsig/scripts/process_deepsig_raw_results.py \
            --input            "$_raw_gff3" \
            --output           "$_proc_tsv" \
            --organism-name    "$_org" \
            --domain           "$DOMAIN" \
            --tool-used        "$_tool_used" \
            --command-used     "$_deepsig_cmd" \
            --database-used    "$_db_used" \
            --organism-class   "$_deepsig_class" \
            --input-path       "$_faa" \
            --output-path      "$_out_dir"
    }
    echo "[deepsig] Post-processing $_raw_gff3 ..."
    pipeline_log_step "post-process -> processed/deepsig_results.tsv" run_postprocess
    pipeline_log_kv_path "Processed TSV" "$_proc_tsv"

    # >>> wired: pipeline_log_close <<<
    pipeline_log_close

    echo "[deepsig] Done: $_org"
    echo "  raw/       : $_raw_dir"
    echo "  processed/ : $_proc_dir"
}

# ── Main dispatch ─────────────────────────────────────────────────────────────
if [[ -d "$INPUT" ]]; then
    declare -A _seen=()
    mapfile -t _faas < <(find -L "$INPUT" -type f -name '*.faa' | sort)
    (( ${#_faas[@]} )) || { echo "[deepsig] ERROR: no .faa files found under $INPUT" >&2; exit 1; }
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
    echo "[deepsig] Batch complete: success=$_ok  failed=$_fail"
    (( _fail == 0 )) || exit 2
else
    run_one "$INPUT" "${ORGANISM_NAME:-$(basename "${INPUT%.*}")}"
fi
