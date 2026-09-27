#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# CONTAINER ENTRYPOINT — dbCAN (run_dbcan v5, CAZyme annotation)
# Installed at /usr/local/bin/run inside the container.
#
# Pipeline-standard interface (single file):
#   run -i /input/organism.faa -o /output -d /db [-t THREADS]
#       [--domain {Archaea,Bacteria,Eukaryota,Unknown}] [--organism-name NAME]
#
# Directory mode (process all organisms under a directory):
#   run -i /input/rasttk_output -o /output -d /db [-t THREADS]
#   All .faa files found recursively are processed; --organism-name is ignored.
#
# Output directory layout (under -o):
#   /output/<organism>/
#     ├── raw/
#     │     ├── overview.tsv           ← dbCAN consensus per-gene table (untouched)
#     │     ├── diamond.out            ← DIAMOND vs CAZy.dmnd hits (untouched)
#     │     ├── hmmer.out              ← HMMER vs dbCAN.hmm hits (untouched)
#     │     ├── dbCAN-sub.out          ← (optional) sub-family HMM hits
#     │     └── dbcan.stderr           ← captured stderr
#     └── processed/
#           ├── dbcan_results.tsv      ← one row per protein (DBCAN_ prefix)
# ═══════════════════════════════════════════════════════════════════════════════
set -euo pipefail


# >>> wired: detailed-step <<<
# >>> wired: pipeline_log helper <<<
# Shared provenance-log helper (fixed in-container path).
# shellcheck source=/dev/null
source /opt/dbcan/scripts/pipeline_log.sh

usage() {
    cat <<'HELP_EOF'

dbCAN (run_dbcan v5) — CAZyme annotation pipeline (HMMER + DIAMOND + sub-family HMM)

USAGE (single file)
  run -i /input/organism.faa -o /output -d /db \
      [-t THREADS] \
      [--domain {Archaea,Bacteria,Eukaryota,Unknown}] [--organism-name NAME]

USAGE (directory — all organisms processed)
  run -i /input/rasttk_output -o /output -d /db [-t THREADS]
  All .faa files found recursively under -i are processed.
  --organism-name is ignored in directory mode (derived per file).

REQUIRED MOUNTS
  /input/   Protein FASTA (.faa) or directory containing .faa files — read-only
  /output/  Output root — writable
  /db/      dbCAN database directory — must contain:
              CAZy.dmnd
              dbCAN.hmm
              (optional) dbCAN-sub.hmm or dbCAN_sub.hmm

REQUIRED OPTIONS
  -i FILE|DIR   Protein FASTA input file or input directory
  -o DIR        Output root directory (container creates <out>/<organism>/{raw,processed}/)
  -d DIR        dbCAN database directory

OPTIONAL OPTIONS
  -t INT              CPU threads                       [default: 1]
  --domain STR        Archaea | Bacteria | Eukaryota | Unknown   [default: auto-detect]
  --organism-name STR Override organism name (single-file mode only)
  --help, -h          Show this help and exit

OUTPUTS  (under <OUTPUT>/<organism>/)
  raw/overview.tsv               dbCAN consensus table (untouched)
  raw/diamond.out                DIAMOND hits (untouched)
  raw/hmmer.out                  HMMER hits (untouched)
  raw/dbCAN-sub.out              (optional) sub-family HMM hits
  raw/dbcan.stderr               captured stderr
  processed/dbcan_results.tsv    normalised TSV — one row per protein

HELP_EOF
}

# ── Argument parsing ──────────────────────────────────────────────────────────
INPUT=""
OUTPUT_ROOT=""
DBDIR=""
THREADS=1
DOMAIN=""
ORGANISM_NAME=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -i)                INPUT="$2";          shift 2 ;;
        -o)                OUTPUT_ROOT="$2";    shift 2 ;;
        -d)                DBDIR="$2";          shift 2 ;;
        -t)                THREADS="$2";        shift 2 ;;
        --domain)         DOMAIN="$2";         shift 2 ;;
        --organism-name)   ORGANISM_NAME="$2";  shift 2 ;;
        --help|-h)         usage; exit 0 ;;
        *) echo "[dbcan] ERROR: unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

[[ -z "$INPUT"       ]] && { echo "[dbcan] ERROR: -i INPUT required"  >&2; exit 1; }
[[ -z "$OUTPUT_ROOT" ]] && { echo "[dbcan] ERROR: -o OUTPUT required" >&2; exit 1; }
[[ -z "$DBDIR"       ]] && { echo "[dbcan] ERROR: -d DBDIR required"  >&2; exit 1; }
[[ ! -e "$INPUT"     ]] && { echo "[dbcan] ERROR: input not found: $INPUT" >&2; exit 1; }
[[ ! -f "$DBDIR/CAZy.dmnd" ]] && { echo "[dbcan] ERROR: CAZy.dmnd not found in $DBDIR" >&2; exit 1; }
[[ ! -f "$DBDIR/dbCAN.hmm"  ]] && { echo "[dbcan] ERROR: dbCAN.hmm not found in $DBDIR" >&2; exit 1; }

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
            echo "[dbcan] Auto-detected --domain ${_domain} from ${_detected_from}"
    fi

    # Output directory layout
    local _out_dir="$OUTPUT_ROOT/$_org"
    local _raw_dir="$_out_dir/raw"
    local _proc_dir="$_out_dir/processed"
    mkdir -p "$_raw_dir" "$_proc_dir"

    # >>> wired: pipeline_log_init <<<
    local _log_path="$_out_dir/dbcan-pipeline-log.txt"
    export PIPELINE_LOG_DOMAIN="${_domain}"
    pipeline_log_init dbcan "${_org}" "$_out_dir" "$_log_path"
    pipeline_log_legal_preamble

    local _raw_overview="$_raw_dir/overview.tsv"
    local _raw_err="$_raw_dir/dbcan.stderr"
    local _proc_tsv="$_proc_dir/dbcan_results.tsv"

    # run_dbcan looks for dbCAN-sub.hmm (dash); create alias if only underscore variant exists.
    if [[ -f "$DBDIR/dbCAN_sub.hmm" && ! -f "$DBDIR/dbCAN-sub.hmm" ]]; then
        cp -f "$DBDIR/dbCAN_sub.hmm" "$DBDIR/dbCAN-sub.hmm" 2>/dev/null || true
    fi

    # Enable sub-family HMM method if its database file is present and non-empty.
    local _methods="diamond,hmm"
    if [[ -s "$DBDIR/dbCAN-sub.hmm" || -s "$DBDIR/dbCAN_sub.hmm" ]]; then
        echo "[dbcan] Sub-family HMM found: enabling dbCANsub"
        _methods="diamond,hmm,dbCANsub"
    fi

    # Exact command we are about to run (recorded for provenance)
    local _dbcan_command="run_dbcan CAZyme_annotation --mode protein --input_raw_data ${_faa} --db_dir ${DBDIR} --output_dir ${_raw_dir} --threads ${THREADS} --methods ${_methods}"
    local _tool_used="run_dbcan 5.1.2 | Uses: HMMER 3.4, DIAMOND 2.1.9"
    local _database_used="dbCAN v13 data bundle | Source: https://bcb.unl.edu/dbCAN2/download/Databases/ | path(container): ${DBDIR}/dbCAN.hmm, ${DBDIR}/CAZy.dmnd"
    if [[ "$_methods" == *"dbCANsub"* ]]; then
        _database_used+=" , ${DBDIR}/dbCAN-sub.hmm"
    fi

    pipeline_log_section "run_dbcan CAZyme annotation"
    pipeline_log_kv      "Tool"                 "$_tool_used"
    pipeline_log_kv_path "Input (host)"         "${_faa}"
    pipeline_log_kv      "Input (container)"    "${_faa}"
    pipeline_log_kv_path "Database (host)"      "${DBDIR}"
    pipeline_log_kv      "Database (container)" "${DBDIR}"
    pipeline_log_kv_path "Output (host)"        "$_out_dir"
    pipeline_log_kv      "Output (container)"   "$_out_dir"
    pipeline_log_kv      "Methods considered"   "$_methods"
    pipeline_log_kv      "Threads"              "${THREADS:-1}"

    echo "[dbcan] Input:        $_faa ($_org)"
    echo "[dbcan] DB dir:       $DBDIR"
    echo "[dbcan] Output root:  $_out_dir"
    echo "[dbcan] Methods:      $_methods"
    echo "[dbcan] Threads:      $THREADS"

    # ── Idempotency: skip the dbCAN step if overview.tsv already exists ─────────
    if [[ -s "$_raw_overview" ]]; then
        echo "[dbcan] Raw output already exists ($_raw_overview), skipping run_dbcan (delete manually to re-run)"
        pipeline_log_skipped "run_dbcan CAZyme annotation" "$_dbcan_command" "raw output already present"
    else
        echo "[dbcan] Running run_dbcan ..."
        pipeline_log_run_logged "run_dbcan CAZyme annotation" "" "$_raw_err" \
            run_dbcan CAZyme_annotation \
                --mode           protein \
                --input_raw_data "$_faa" \
                --db_dir         "$DBDIR" \
                --output_dir     "$_raw_dir" \
                --threads        "$THREADS" \
                --methods        "$_methods"
        pipeline_log_kv_path "Raw overview" "$_raw_overview"
    fi

    # ── Post-process overview.tsv → normalised per-protein TSV ───────────────────
    run_postprocess() {
        python3 /opt/dbcan/scripts/process_dbcan_raw_results.py \
            --input         "$_raw_overview" \
            --output        "$_proc_tsv" \
            --organism-name "$_org" \
            --domain        "$_domain" \
            --tool-used     "$_tool_used" \
            --command-used  "$_dbcan_command" \
            --database-used "$_database_used" \
            --methods-used  "$_methods" \
            --input-path    "$_faa" \
            --output-path   "$_out_dir"
    }
    echo "[dbcan] Post-processing $_raw_overview ..."
    pipeline_log_step "post-process -> processed/dbcan_results.tsv" run_postprocess
    pipeline_log_kv_path "Processed TSV" "$_proc_tsv"

    # >>> wired: pipeline_log_close <<<
    pipeline_log_close

    echo "[dbcan] Done: $_org"
    echo "  raw/       : $_raw_dir"
    echo "  processed/ : $_proc_dir"
}

# ── Main dispatch ─────────────────────────────────────────────────────────────
if [[ -d "$INPUT" ]]; then
    declare -A _seen=()
    mapfile -t _faas < <(find -L "$INPUT" -type f -name '*.faa' | sort)
    (( ${#_faas[@]} )) || { echo "[dbcan] ERROR: no .faa files found under $INPUT" >&2; exit 1; }
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
    echo "[dbcan] Batch complete: success=$_ok  failed=$_fail"
    (( _fail == 0 )) || exit 2
else
    run_one "$INPUT" "${ORGANISM_NAME:-$(basename "${INPUT%.*}")}"
fi
