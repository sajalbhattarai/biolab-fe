#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# CONTAINER ENTRYPOINT — KEGG / KofamScan (KEGG Orthology annotation)
# Installed at /usr/local/bin/run inside the container.
#
# Pipeline-standard interface (single file):
#   run -i /input/organism.faa -o /output -d /db [-t THREADS]
#       [--organism-name NAME] [--domain D]
#
# Directory mode (process all organisms under a directory):
#   run -i /input/rasttk_output -o /output -d /db [-t THREADS]
#   All .faa files found recursively are processed; --organism-name is ignored.
#
# Output directory layout (under -o):
#   /output/<organism>/
#     ├── raw/
#     │     ├── kegg.txt            ← KofamScan detail-format output (untouched)
#     │     └── kegg.stderr         ← captured stderr
#     └── processed/
#           └── kegg_results.tsv    ← one row per HMM hit (KEGG_ prefix)
# ═══════════════════════════════════════════════════════════════════════════════
set -euo pipefail


# >>> wired: detailed-step <<<
# >>> wired: pipeline_log helper <<<
# Shared provenance-log helper (fixed in-container path).
# shellcheck source=/dev/null
source /opt/kegg/scripts/pipeline_log.sh

usage() {
    cat <<'HELP_EOF'

KEGG Orthology annotation via KofamScan

USAGE (single file)
  run -i /input/organism.faa -o /output -d /db \
      [-t THREADS] [--organism-name NAME] [--domain {Archaea,Bacteria,Eukaryota,Unknown}]

USAGE (directory — all organisms processed)
  run -i /input/rasttk_output -o /output -d /db [-t THREADS]
  All .faa files found recursively under -i are processed.
  --organism-name is ignored in directory mode (derived per file).

REQUIRED MOUNTS
  /input/   Protein FASTA (.faa) or directory containing .faa files — read-only
  /output/  Output root — writable
  /db/      KEGG database directory (must contain profiles/ and ko_list)

REQUIRED OPTIONS
  -i FILE|DIR   Protein FASTA input file or input directory
  -o DIR        Output root directory (container creates <out>/<organism>/{raw,processed}/)
  -d DIR        KEGG database directory

OPTIONAL OPTIONS
  -t INT              CPU threads                            [default: 1]
  --organism-name STR Override organism name (single-file mode only)
  --domain STR        Archaea | Bacteria | Eukaryota | Unknown  [default: auto-detect]
                      (recorded for provenance; does not affect KofamScan)
  --help, -h          Show this help and exit

OUTPUTS  (under <OUTPUT>/<organism>/)
  raw/kegg.txt                 KofamScan detail-format output (untouched)
  raw/kegg.stderr              captured stderr
  processed/kegg_results.tsv   normalised TSV — one row per HMM hit

HELP_EOF
}

# ── Argument parsing ──────────────────────────────────────────────────────────
INPUT=""
OUTPUT_ROOT=""
DBDIR=""
THREADS=1
ORGANISM_NAME=""
DOMAIN=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -i)                INPUT="$2";          shift 2 ;;
        -o)                OUTPUT_ROOT="$2";    shift 2 ;;
        -d)                DBDIR="$2";          shift 2 ;;
        -t)                THREADS="$2";        shift 2 ;;
        --organism-name)   ORGANISM_NAME="$2";  shift 2 ;;
        --domain)          DOMAIN="$2";         shift 2 ;;
        --help|-h)         usage; exit 0 ;;
        *) echo "[kegg] ERROR: unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

[[ -z "$INPUT"       ]] && { echo "[kegg] ERROR: -i INPUT required"  >&2; exit 1; }
[[ -z "$OUTPUT_ROOT" ]] && { echo "[kegg] ERROR: -o OUTPUT required" >&2; exit 1; }
[[ -z "$DBDIR"       ]] && { echo "[kegg] ERROR: -d DBDIR required"  >&2; exit 1; }
[[ ! -e "$INPUT"     ]] && { echo "[kegg] ERROR: input not found: $INPUT" >&2; exit 1; }

if [[ ! -d "$DBDIR/profiles" || ! -f "$DBDIR/ko_list" ]]; then
    echo "[kegg] ERROR: KEGG DB not found at $DBDIR (need profiles/ and ko_list)" >&2
    exit 1
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
            echo "[kegg] Auto-detected --domain ${_domain} from ${_detected_from}"
    fi

    # Output directory layout
    local _out_dir="$OUTPUT_ROOT/$_org"
    local _raw_dir="$_out_dir/raw"
    local _proc_dir="$_out_dir/processed"
    mkdir -p "$_raw_dir" "$_proc_dir"

    # >>> wired: pipeline_log_init <<<
    local _log_path="$_out_dir/kegg-pipeline-log.txt"
    export PIPELINE_LOG_DOMAIN="${_domain}"
    pipeline_log_init kegg "${_org}" "$_out_dir" "$_log_path"
    pipeline_log_legal_preamble

    local _raw_txt="$_raw_dir/kegg.txt"
    local _raw_err="$_raw_dir/kegg.stderr"
    local _proc_tsv="$_proc_dir/kegg_results.tsv"

    local _cfg="/tmp/kofamscan_config_$$.yml"
    cat > "$_cfg" <<YMLEOF
profile: ${DBDIR}/profiles
ko_list: ${DBDIR}/ko_list
cpu: ${THREADS}
format: detail
YMLEOF

    local _cmd="exec_annotation --config ${_cfg} -o ${_raw_txt} ${_faa}"

    pipeline_log_section "KofamScan annotation (exec_annotation)"
    pipeline_log_kv      "Tool"                  "KofamScan 1.3.0"
    pipeline_log_kv_path "Input (host)"           "${_faa}"
    pipeline_log_kv      "Input (container)"      "${_faa}"
    pipeline_log_kv_path "Database (host)"        "${DBDIR}"
    pipeline_log_kv      "Database (container)"   "${DBDIR}"
    pipeline_log_kv_path "Output (host)"          "$_out_dir"
    pipeline_log_kv      "Output (container)"     "$_out_dir"
    pipeline_log_kv      "Threshold considered"   "adaptive threshold from ko_list"
    pipeline_log_kv      "Threads"                "${THREADS}"

    echo "[kegg] Input:        $_faa ($_org)"
    echo "[kegg] DB dir:       $DBDIR"
    echo "[kegg] Output root:  $_out_dir"
    echo "[kegg] Threads:      $THREADS"

    # ── Idempotency: skip KofamScan if raw output already exists ────────────
    if [[ -s "$_raw_txt" ]]; then
        echo "[kegg] Raw output already exists ($_raw_txt), skipping KofamScan"
        pipeline_log_skipped "KofamScan annotation" "$_cmd" "raw output already present"
    else
        echo "[kegg] Running KofamScan ..."
        pipeline_log_run_logged "KofamScan annotation" "" "$_raw_err" \
            exec_annotation \
                --config "$_cfg" \
                -o       "$_raw_txt" \
                "$_faa"
        pipeline_log_kv_path "Raw TXT" "$_raw_txt"
    fi

    rm -f "$_cfg"

    # ── Post-process raw detail-format file → normalised per-hit TSV ────────
    run_postprocess() {
        python3 /opt/kegg/scripts/process_kegg_raw_results.py \
            --input         "$_raw_txt" \
            --output        "$_proc_tsv" \
            --organism-name "$_org" \
            --domain        "$_domain" \
            --tool-used     "KofamScan 1.3.0" \
            --command-used  "$_cmd" \
            --database-used "$DBDIR" \
            --threshold-considered "adaptive threshold from ko_list" \
            --input-path    "$_faa" \
            --output-path   "$_out_dir"
    }
    echo "[kegg] Post-processing $_raw_txt ..."
    pipeline_log_step "post-process -> processed/kegg_results.tsv" run_postprocess
    pipeline_log_kv_path "Processed TSV" "$_proc_tsv"

    # >>> wired: pipeline_log_close <<<
    pipeline_log_close

    echo "[kegg] Done: $_org"
    echo "  raw/       : $_raw_dir"
    echo "  processed/ : $_proc_dir"
}

# ── Main dispatch ─────────────────────────────────────────────────────────────
if [[ -d "$INPUT" ]]; then
    declare -A _seen=()
    mapfile -t _faas < <(find -L "$INPUT" -type f -name '*.faa' | sort)
    (( ${#_faas[@]} )) || { echo "[kegg] ERROR: no .faa files found under $INPUT" >&2; exit 1; }
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
    echo "[kegg] Batch complete: success=$_ok  failed=$_fail"
    (( _fail == 0 )) || exit 2
else
    run_one "$INPUT" "${ORGANISM_NAME:-$(basename "${INPUT%.*}")}"
fi
