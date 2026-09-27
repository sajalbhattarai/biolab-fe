#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# CONTAINER ENTRYPOINT — TMbed (deep-learning transmembrane predictor, Apache-2.0)
# Installed at /usr/local/bin/run inside the container.
#
# Pipeline-standard interface (single file):
#   run -i /input/organism.faa -o /output [-t THREADS]
#       [--domain {Archaea,Bacteria,Eukaryota,Unknown}] [--organism-name NAME] [--use-gpu]
#
# Directory mode (process all organisms under a directory):
#   run -i /input/rasttk_output -o /output [-t THREADS]
#   All .faa files found recursively are processed; --organism-name is ignored.
#
# Output directory layout (under -o):
#   /output/<organism>/
#     ├── raw/
#     │     └── tmbed.pred           ← untouched TMbed predictions (3-line format)
#     └── processed/
#           ├── tmbed_results.tsv    ← one row per topology segment
#
# On first run TMbed downloads the ProtT5-XL-U50 encoder (~2.25 GB) into
# /models — mount a persistent host directory there to avoid re-downloading.
# ═══════════════════════════════════════════════════════════════════════════════
set -euo pipefail


# >>> wired: detailed-step <<<
# >>> wired: pipeline_log helper <<<
# Shared provenance-log helper (fixed in-container path).
# shellcheck source=/dev/null
source /opt/tmbed/scripts/pipeline_log.sh

usage() {
    cat <<'HELP_EOF'

TMbed — deep-learning transmembrane segment + signal peptide predictor

USAGE (single file)
  run -i /input/organism.faa -o /output \
      [-t THREADS] [--use-gpu] \
      [--domain {Archaea,Bacteria,Eukaryota,Unknown}] [--organism-name NAME]

USAGE (directory — all organisms processed)
  run -i /input/rasttk_output -o /output [-t THREADS]
  All .faa files found recursively under -i are processed.
  --organism-name is ignored in directory mode (derived per file).

REQUIRED MOUNTS
  /input/   Protein FASTA (.faa) or directory containing .faa files — read-only
  /output/  Output root directory — writable
  /models/  Persistent dir for ProtT5 model (~2.25 GB; downloaded on first run)

REQUIRED OPTIONS
  -i FILE|DIR   Protein FASTA input file or input directory
  -o DIR        Output root directory (container creates <out>/<organism>/{raw,processed}/)

OPTIONAL OPTIONS
  -t INT              CPU threads                            [default: 4]
  --use-gpu           Enable GPU inference                   [default: CPU only]
  --domain STR        Archaea | Bacteria | Eukaryota | Unknown   [default: auto-detect]
  --organism-name STR Override organism name (single-file mode only)
  -d DIR              Model directory for ProtT5 weights     [default: /models]
  --help, -h          Show this help and exit

OUTPUTS  (under <OUTPUT>/<organism>/)
  raw/tmbed.pred              TMbed 3-line predictions (untouched)
  processed/tmbed_results.tsv normalised TSV — one row per topology segment

HELP_EOF
}

# ── Argument parsing ──────────────────────────────────────────────────────────
INPUT=""
OUTPUT_ROOT=""
MODEL_DIR="/models"
THREADS=4
USE_GPU=0
DOMAIN=""
ORGANISM_NAME=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -i)               INPUT="$2";          shift 2 ;;
        -o)               OUTPUT_ROOT="$2";    shift 2 ;;
        -d)               MODEL_DIR="$2";      shift 2 ;;
        -t)               THREADS="$2";        shift 2 ;;
        --use-gpu)        USE_GPU=1;           shift   ;;
        --domain)         DOMAIN="$2";         shift 2 ;;
        --organism-name)  ORGANISM_NAME="$2";  shift 2 ;;
        --help|-h)        usage; exit 0 ;;
        *) echo "[tmbed] ERROR: unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

[[ -z "$INPUT"       ]] && { echo "[tmbed] ERROR: -i INPUT required"  >&2; exit 1; }
[[ -z "$OUTPUT_ROOT" ]] && { echo "[tmbed] ERROR: -o OUTPUT required" >&2; exit 1; }
[[ ! -e "$INPUT"     ]] && { echo "[tmbed] ERROR: input not found: $INPUT" >&2; exit 1; }

# ── GPU flag mapping (top-level; shared across all run_one calls) ─────────────
if [[ "$USE_GPU" -eq 1 ]]; then
    GPU_FLAG=""
    TMBED_MODE="gpu"
else
    GPU_FLAG="--no-use-gpu"
    TMBED_MODE="cpu"
fi

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
            echo "[tmbed] Auto-detected --domain ${_domain} from ${_detected_from}"
    fi

    # Output directory layout
    local _out_dir="$OUTPUT_ROOT/$_org"
    local _raw_dir="$_out_dir/raw"
    local _proc_dir="$_out_dir/processed"
    mkdir -p "$_raw_dir" "$_proc_dir"
    mkdir -p "$MODEL_DIR" 2>/dev/null || true

    # >>> wired: pipeline_log_init <<<
    local _log_path="$_out_dir/tmbed-pipeline-log.txt"
    export PIPELINE_LOG_DOMAIN="${_domain}"
    pipeline_log_init tmbed "${_org}" "$_out_dir" "$_log_path"
    if command -v pipeline_log_legal_preamble >/dev/null 2>&1; then
        pipeline_log_legal_preamble
    fi

    local _raw_pred="$_raw_dir/tmbed.pred"
    local _proc_tsv="$_proc_dir/tmbed_results.tsv"

    # HF_HOME/TRANSFORMERS_CACHE tells the ProtT5 loader where to find/store the
    # cached model weights; --model-dir was removed from the tmbed CLI in v1.0.0.
    export HF_HOME="${MODEL_DIR}"
    export TRANSFORMERS_CACHE="${MODEL_DIR}"
    local _tmbed_command="tmbed predict -f ${_faa} -p ${_raw_pred} ${GPU_FLAG} --out-format 1"
    local _tmbed_model_used="ProtT5-XL-U50"
    local _tool_used="TMbed 1.0.0"
    local _database_used="TMbed ProtT5-XL-U50 model cache | Source: https://github.com/BernhoferM/TMbed/releases/tag/v1.0.0 | path(container): ${MODEL_DIR}"

    pipeline_log_section "tmbed annotation"
    pipeline_log_kv      "Tool"                 "$_tool_used"
    pipeline_log_kv_path "Input (host)"         "${_faa}"
    pipeline_log_kv      "Input (container)"    "${_faa}"
    pipeline_log_kv_path "Database (host)"      "${MODEL_DIR}"
    pipeline_log_kv      "Database (container)" "${MODEL_DIR}"
    pipeline_log_kv_path "Output (host)"        "$_out_dir"
    pipeline_log_kv      "Output (container)"   "$_out_dir"
    pipeline_log_kv      "Threads"              "${THREADS:-1}"

    echo "[tmbed] Input:        $_faa ($_org)"
    echo "[tmbed] Mode:         $TMBED_MODE"
    echo "[tmbed] Output root:  $_out_dir"
    echo "[tmbed] Model dir:   $MODEL_DIR"
    echo "[tmbed] Threads:      $THREADS"

    # ── Idempotency: skip the prediction step if raw output already exists ───────
    if [[ -s "$_raw_pred" ]]; then
        echo "[tmbed] Raw output already exists ($_raw_pred), skipping tmbed (delete manually to re-run)"
        pipeline_log_skipped "tmbed predict" "$_tmbed_command" "raw output already present"
    else
        echo "[tmbed] Running tmbed predict ..."
        pipeline_log_run_logged "tmbed predict" "" "" \
            tmbed predict \
                -f "$_faa" \
                -p "$_raw_pred" \
                $GPU_FLAG \
                --out-format 1
        pipeline_log_kv_path "Raw predictions" "$_raw_pred"
    fi

    # ── Post-process raw predictions into the normalised TSV(s) ──────────────────
    run_postprocess() {
        python3 /opt/tmbed/scripts/process_tmbed_raw_results.py \
            --input          "$_raw_pred" \
            --output         "$_proc_tsv" \
            --organism-name  "$_org" \
            --domain         "$_domain" \
            --tool-used      "$_tool_used" \
            --command-used   "$_tmbed_command" \
            --database-used  "$_database_used" \
            --model-used     "$_tmbed_model_used" \
            --input-path     "$_faa" \
            --output-path    "$_out_dir"
    }
    echo "[tmbed] Post-processing $_raw_pred ..."
    pipeline_log_step "post-process -> processed/tmbed_results.tsv" run_postprocess
    pipeline_log_kv_path "Processed TSV" "$_proc_tsv"

    # >>> wired: pipeline_log_close <<<
    pipeline_log_close

    echo "[tmbed] Done: $_org"
    echo "  raw/       : $_raw_dir"
    echo "  processed/ : $_proc_dir"
}

# ── Main dispatch ─────────────────────────────────────────────────────────────
if [[ -d "$INPUT" ]]; then
    declare -A _seen=()
    mapfile -t _faas < <(find -L "$INPUT" -type f -name '*.faa' | sort)
    (( ${#_faas[@]} )) || { echo "[tmbed] ERROR: no .faa files found under $INPUT" >&2; exit 1; }
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
    echo "[tmbed] Batch complete: success=$_ok  failed=$_fail"
    (( _fail == 0 )) || exit 2
else
    run_one "$INPUT" "${ORGANISM_NAME:-$(basename "${INPUT%.*}")}"
fi
