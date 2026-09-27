#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════════════
# CONTAINER ENTRYPOINT — Phobius 1.01 (combined TM + signal-peptide predictor)
# Installed at /usr/local/bin/run inside the image.
#
# Pipeline-standard interface (single file):
#   run -i /input/organism.faa -o /output [-t THREADS]
#
# Directory mode (process all organisms under a directory):
#   run -i /input/rasttk_output -o /output [-t THREADS]
#   All .faa files found recursively are processed; --organism-name is ignored.
#
# Output directory layout (under -o):
#   /output/<organism>/
#     ├── raw/
#     │     ├── phobius.long.txt      ← phobius -long (per-protein FT records)
#     │     └── phobius.short.tsv     ← phobius -short (one line per protein)
#     └── processed/
#           ├── phobius_results.tsv   ← one row per topology segment
#           └── phobius_top1.tsv      ← one row per protein (summary)
# ════════════════════════════════════════════════════════════════════════════
set -euo pipefail

# >>> wired: pipeline_log helper <<<
_pl_self="${BASH_SOURCE[0]}"
while [[ -L "$_pl_self" ]]; do _pl_self="$(readlink "$_pl_self")"; done
# shellcheck source=/dev/null
source "$(cd "$(dirname "$_pl_self")" && pwd)/scripts/pipeline_log.sh"

usage() {
    cat <<'HELP_EOF'

Phobius 1.01 — combined transmembrane topology and signal peptide predictor.

USAGE (single file)
  run -i /input/organism.faa -o /output [-t THREADS] \
      [--domain {Archaea,Bacteria,Eukaryota,Unknown}] [--organism-name NAME]

USAGE (directory — all organisms processed)
  run -i /input/rasttk_output -o /output [-t THREADS]
  All .faa files found recursively under -i are processed.
  --organism-name is ignored in directory mode (derived per file).

REQUIRED MOUNTS
  /input/   Protein FASTA (.faa) or directory containing .faa files — read-only
  /output/  Output root directory — writable

REQUIRED OPTIONS
  -i FILE|DIR   Protein FASTA input file or input directory
  -o DIR        Output root directory (container creates <out>/<organism>/{raw,processed}/)

OPTIONAL OPTIONS
  -t INT              CPU threads (reserved; phobius is single-threaded)  [default: 4]
  --domain STR        Archaea | Bacteria | Eukaryota | Unknown            [default: auto-detect]
  --organism-name STR Override organism name (single-file mode only)
  -d DIR              Accepted for pipeline parity; no DB needed (ignored)
  --help, -h          Show this help and exit

OUTPUTS  (under <OUTPUT>/<organism>/)
  raw/phobius.long.txt        per-protein FT records (Phobius -long format)
  raw/phobius.short.tsv       one line per protein  (Phobius -short format)
  processed/phobius_results.tsv  normalised TSV — one row per topology segment
  processed/phobius_top1.tsv     one row per protein (summary stats)

HELP_EOF
}

# ── Argument parsing ─────────────────────────────────────────────────────────
INPUT=""
OUTPUT_ROOT=""
THREADS=4
DOMAIN=""
ORGANISM_NAME=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -i)               INPUT="$2";          shift 2 ;;
        -o)               OUTPUT_ROOT="$2";    shift 2 ;;
        -d)               shift 2 ;;            # accepted for pipeline parity; no DB needed
        -t)               THREADS="$2";        shift 2 ;;
        --domain)         DOMAIN="$2";         shift 2 ;;
        --organism-name)  ORGANISM_NAME="$2";  shift 2 ;;
        --help|-h)        usage; exit 0 ;;
        *) echo "[phobius] ERROR: unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

[[ -z "$INPUT"       ]] && { echo "[phobius] ERROR: -i INPUT required"  >&2; exit 1; }
[[ -z "$OUTPUT_ROOT" ]] && { echo "[phobius] ERROR: -o OUTPUT required" >&2; exit 1; }
[[ ! -e "$INPUT"     ]] && { echo "[phobius] ERROR: input not found: $INPUT" >&2; exit 1; }

# ── Single-organism processing function ──────────────────────────────────────
# Args: <faa_path> <organism_name>
run_one() {
    local _faa="$1"
    local _org="$2"

    # Domain auto-detection from the FAA file's path hierarchy
    local _domain="$DOMAIN"
    local _detected_from=""
    if [[ -z "$_domain" ]]; then
        local _input_lower _path_segs _seg _pi
        _input_lower="$(printf '%s' "$_faa" | tr '[:upper:]' '[:lower:]')"
        IFS='/' read -r -a _path_segs <<< "$_input_lower"
        for (( _pi=${#_path_segs[@]}-1; _pi>=0; _pi-- )); do
            _seg="${_path_segs[$_pi]}"
            case "$_seg" in
                gram-positive|gram-negative|gram-unknown|bacteria)
                    _domain="Bacteria"; _detected_from="path segment '$_seg'"; break ;;
                archaea|arch)
                    _domain="Archaea";  _detected_from="path segment '$_seg'"; break ;;
                eukaryota|eukaryote|eukaryotes)
                    _domain="Eukaryota"; _detected_from="path segment '$_seg'"; break ;;
                unknown)
                    _domain="Unknown";  _detected_from="path segment '$_seg'"; break ;;
            esac
        done
        if [[ -z "$_domain" ]]; then
            case "$(basename "$_faa")" in
                *_bact_gram*.*|*_bact_gram*|*_bact.*|*_bact) _domain="Bacteria" ;;
                *_archaea.*|*_archaea|*_arch.*|*_arch)         _domain="Archaea"  ;;
                *_unknown.*|*_unknown)                          _domain="Unknown"  ;;
            esac
        fi
        _domain="${_domain:-Unknown}"
        [[ -n "$_detected_from" ]] && \
            echo "[phobius] Auto-detected --domain ${_domain} from ${_detected_from}"
    fi

    # Output directory layout
    local _out_dir="$OUTPUT_ROOT/$_org"
    local _raw_dir="$_out_dir/raw"
    local _proc_dir="$_out_dir/processed"
    mkdir -p "$_raw_dir" "$_proc_dir"

    # >>> wired: pipeline_log_init <<<
    local _log_path="$_out_dir/phobius-pipeline-log.txt"
    pipeline_log_init phobius "${_org}" "$_out_dir" "$_log_path"
    if command -v pipeline_log_legal_preamble >/dev/null 2>&1; then
        pipeline_log_legal_preamble
    fi

    local _raw_long="$_raw_dir/phobius.long.txt"
    local _raw_short="$_raw_dir/phobius.short.tsv"
    local _proc_tsv="$_proc_dir/phobius_results.tsv"
    local _proc_top1="$_proc_dir/phobius_top1.tsv"

    local _phobius_command="phobius.pl -long ${_faa}  (and -short)"
    local _phobius_model_used="phobius.model (Phobius 1.01)"
    local _tool_used="Phobius 1.01"
    local _database_used="Phobius bundled model | Source: https://phobius.sbc.su.se/ | path(container): /usr/local/bin"

    pipeline_log_section "phobius annotation"
    pipeline_log_kv      "Tool"                 "$_tool_used"
    pipeline_log_kv_path "Input (host)"         "${_faa}"
    pipeline_log_kv      "Input (container)"    "${_faa}"
    pipeline_log_kv_path "Database (host)"      "/usr/local/bin"
    pipeline_log_kv      "Database (container)" "/usr/local/bin"
    pipeline_log_kv_path "Output (host)"        "$_out_dir"
    pipeline_log_kv      "Output (container)"   "$_out_dir"
    pipeline_log_kv      "Threads"              "${THREADS:-1}"

    echo "[phobius] Input:        $_faa ($_org)"
    echo "[phobius] Output root:  $_out_dir"
    echo "[phobius] Threads:      $THREADS (reserved; phobius is single-threaded)"

    # ── Idempotency: skip the prediction step if raw output already exists ───────
    if [[ -s "$_raw_long" && -s "$_raw_short" ]]; then
        echo "[phobius] Raw output already exists, skipping (delete manually to re-run)"
        pipeline_log_skipped "phobius prediction" "$_phobius_command" "raw output already present"
    else
        echo "[phobius] Running phobius -long ..."
        pipeline_log_section "phobius prediction"
        pipeline_log_kv "Command" "$_phobius_command"
        pipeline_log_kv_path "Raw long output"  "$_raw_long"
        pipeline_log_kv_path "Raw short output" "$_raw_short"
        local _phobius_start _phobius_end _phobius_rc_long _phobius_rc_short
        _phobius_start="$(date +%s)"
        set +e
        /usr/local/bin/phobius -long  "$_faa" > "$_raw_long"  2> "$_raw_dir/phobius.long.stderr"
        _phobius_rc_long=$?
        /usr/local/bin/phobius -short "$_faa" > "$_raw_short" 2> "$_raw_dir/phobius.short.stderr"
        _phobius_rc_short=$?
        set -e
        _phobius_end="$(date +%s)"
        pipeline_log_kv "Elapsed (s)"     "$(( _phobius_end - _phobius_start ))"
        pipeline_log_kv "Exit code long"  "$_phobius_rc_long"
        pipeline_log_kv "Exit code short" "$_phobius_rc_short"
        if [[ "$_phobius_rc_long" -ne 0 || "$_phobius_rc_short" -ne 0 ]]; then
            pipeline_log_kv "Status" "FAILED"
            pipeline_log_close "FAILED at phobius prediction"
            return 1
        fi
    fi

    # ── Post-process raw FT records into normalised TSVs ─────────────────────────
    run_postprocess() {
        python3 /opt/phobius/scripts/process_phobius_raw_results.py \
            --input-long     "$_raw_long" \
            --input-short    "$_raw_short" \
            --output         "$_proc_tsv" \
            --output-top1    "$_proc_top1" \
            --organism-name  "$_org" \
            --domain         "$_domain" \
            --tool-used      "$_tool_used" \
            --command-used   "$_phobius_command" \
            --database-used  "$_database_used" \
            --model-used     "$_phobius_model_used" \
            --input-path     "$_faa" \
            --output-path    "$_out_dir"
    }
    echo "[phobius] Post-processing $_raw_long ..."
    pipeline_log_step "post-process -> processed/phobius_results.tsv" run_postprocess
    pipeline_log_kv_path "Processed TSV"  "$_proc_tsv"
    pipeline_log_kv_path "Processed top1" "$_proc_top1"

    # >>> wired: pipeline_log_close <<<
    pipeline_log_close

    echo "[phobius] Done: $_org"
    echo "  raw/       : $_raw_dir"
    echo "  processed/ : $_proc_dir"
}

# ── Main dispatch ─────────────────────────────────────────────────────────────
if [[ -d "$INPUT" ]]; then
    declare -A _seen=()
    mapfile -t _faas < <(find -L "$INPUT" -type f -name '*.faa' | sort)
    (( ${#_faas[@]} )) || { echo "[phobius] ERROR: no .faa files found under $INPUT" >&2; exit 1; }
    _ok=0; _fail=0; _total="${#_faas[@]}"
    for _i in "${!_faas[@]}"; do
        _faa="${_faas[$_i]}"
        _parent="$(dirname "$_faa")"
        [[ "$(basename "$_parent")" == "gene_calls" ]] && _parent="$(dirname "$_parent")"
        _org="$(basename "$_parent")"
        [[ -n "${_seen[$_org]+x}" ]] && continue
        _seen[$_org]=1
        echo "[$((  _i + 1 ))/$_total] Processing: $_org"
        if run_one "$_faa" "$_org"; then _ok=$(( _ok + 1 ))
        else                              _fail=$(( _fail + 1 )); fi
    done
    echo "[phobius] Batch complete: success=$_ok  failed=$_fail"
    (( _fail == 0 )) || exit 2
else
    run_one "$INPUT" "${ORGANISM_NAME:-$(basename "${INPUT%.*}")}"
fi
