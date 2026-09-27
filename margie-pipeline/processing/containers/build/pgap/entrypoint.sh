#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# CONTAINER ENTRYPOINT — PGAP HMM annotation (HMMER hmmscan against hmm_PGAP.LIB)
# Installed at /usr/local/bin/run inside the container.
#
# Pipeline-standard interface (single file):
#   run -i /input/organism.faa -o /output -d /db [-t THREADS] [--domain D]
#
# Directory mode (process all organisms under a directory):
#   run -i /input/rasttk_output -o /output -d /db [-t THREADS]
#   All .faa files found recursively are processed; --organism-name is ignored.
#
# Output directory layout (under -o):
#   /output/<organism>/
#     ├── raw/
#     │     ├── pgap_domtbl.out  ← untouched hmmscan --domtblout
#     │     └── pgap.out         ← full hmmscan stdout (with summary)
#     └── processed/
#           ├── pgap_results.tsv ← normalised TSV, one row per domain hit
# ═══════════════════════════════════════════════════════════════════════════════
set -euo pipefail


# >>> wired: detailed-step <<<
# >>> wired: pipeline_log helper <<<
# Shared provenance-log helper (fixed in-container path).
# shellcheck source=/dev/null
source /opt/pgap/scripts/pipeline_log.sh

usage() {
    cat <<'HELP_EOF'

PGAP — NCBI Prokaryotic Genome Annotation HMM library (hmm_PGAP.LIB)

USAGE (single file)
  run -i /input/organism.faa -o /output -d /db \
    [-t THREADS] [--domain {Archaea,Bacteria,Eukaryota,Unknown}]

USAGE (directory — all organisms processed)
  run -i /input/rasttk_output -o /output -d /db [-t THREADS]
  All .faa files found recursively under -i are processed.
  --organism-name is ignored in directory mode (derived per file).

REQUIRED MOUNTS
  /input/   Protein FASTA (.faa) or directory containing .faa files — read-only
  /output/  Output directory — writable
  /db/      PGAP HMM dir containing hmm_PGAP.LIB + .h3* index files

REQUIRED OPTIONS
  -i FILE|DIR   Protein FASTA input file or input directory (inside container)
  -o DIR        Output root directory   (inside container, usually /output)
  -d DIR        PGAP HMM database dir   (inside container, usually /db)

OPTIONAL OPTIONS
  -t INT              CPU threads                              [default: 4]
  --domain STR        Archaea | Bacteria | Eukaryota | Unknown   [default: auto-detect]
  --organism-name STR Override organism name (single-file mode only)
  --help, -h          Show this help and exit

OUTPUTS  (under <OUTPUT>/<organism>/)
  raw/pgap_domtbl.out         hmmscan domain-table (untouched)
  raw/pgap.out                hmmscan stdout (per-protein hit summary)
  processed/pgap_results.tsv  normalised TSV — one row per domain hit

THRESHOLD
  Uses HMMER's trusted-cutoff thresholds (--cut_tc). Per-model bit-score
  cutoffs curated by NCBI. No arbitrary e-value cutoff needed.

HELP_EOF
}

# ── Argument parsing ──────────────────────────────────────────────────────────
INPUT=""
OUTPUT_ROOT=""
DBDIR=""
THREADS=4
DOMAIN=""
ORGANISM_NAME=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -i)               INPUT="$2";          shift 2 ;;
        -o)               OUTPUT_ROOT="$2";    shift 2 ;;
        -d)               DBDIR="$2";          shift 2 ;;
        -t)               THREADS="$2";        shift 2 ;;
        --domain)         DOMAIN="$2";         shift 2 ;;
        --organism-name)  ORGANISM_NAME="$2";  shift 2 ;;
        --help|-h)        usage; exit 0 ;;
        *) echo "[pgap] ERROR: unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

[[ -z "$INPUT"       ]] && { echo "[pgap] ERROR: -i INPUT required" >&2; exit 1; }
[[ -z "$OUTPUT_ROOT" ]] && { echo "[pgap] ERROR: -o OUTPUT required" >&2; exit 1; }
[[ -z "$DBDIR"       ]] && { echo "[pgap] ERROR: -d DBDIR required" >&2; exit 1; }
[[ ! -e "$INPUT"     ]] && { echo "[pgap] ERROR: input not found: $INPUT" >&2; exit 1; }

HMM_LIB="$DBDIR/hmm_PGAP.LIB"
[[ ! -f "$HMM_LIB"   ]] && { echo "[pgap] ERROR: hmm_PGAP.LIB not found in $DBDIR" >&2; exit 1; }

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
            echo "[pgap] Auto-detected --domain ${_domain} from ${_detected_from}"
    fi

    # Output directory layout
    local _out_dir="$OUTPUT_ROOT/$_org"
    local _raw_dir="$_out_dir/raw"
    local _proc_dir="$_out_dir/processed"
    mkdir -p "$_raw_dir" "$_proc_dir"

    # >>> wired: pipeline_log_init <<<
    local _log_path="$_out_dir/pgap-pipeline-log.txt"
    export PIPELINE_LOG_DOMAIN="${_domain}"
    pipeline_log_init pgap "${_org}" "$_out_dir" "$_log_path"
    pipeline_log_legal_preamble

    local _raw_domtbl="$_raw_dir/pgap_domtbl.out"
    local _raw_hmmscan_out="$_raw_dir/pgap.out"
    local _proc_tsv="$_proc_dir/pgap_results.tsv"

    # ── Threshold used (kept in a variable so we can pass the exact text to
    #    the processor, which records it in the PGAP_threshold_considered col)
    local _threshold_considered="--cut_tc"

    # ── Exact command we are about to run (recorded for provenance) ──────────
    local _hmmscan_command="hmmscan --cpu ${THREADS} ${_threshold_considered} --domtblout ${_raw_domtbl} --noali -o ${_raw_hmmscan_out} ${HMM_LIB} ${_faa}"
    local _tool_used="HMMER hmmscan 3.3.2 | PGAP profile assignment"
    local _database_used="PGAP HMM library | Source: https://ftp.ncbi.nlm.nih.gov/hmm/PGAP/ | path(container): ${HMM_LIB}"

    pipeline_log_section "hmmscan annotation"
    pipeline_log_kv      "Tool"                 "$_tool_used"
    pipeline_log_kv_path "Input (host)"         "${_faa}"
    pipeline_log_kv      "Input (container)"    "${_faa}"
    pipeline_log_kv_path "Database (host)"      "${HMM_LIB}"
    pipeline_log_kv      "Database (container)" "${HMM_LIB}"
    pipeline_log_kv_path "Output (host)"        "$_out_dir"
    pipeline_log_kv      "Output (container)"   "$_out_dir"
    pipeline_log_kv      "Threads"              "${THREADS:-1}"
    pipeline_log_kv      "Threshold considered" "$_threshold_considered"

    echo "[pgap] Input:        $_faa ($_org)"
    echo "[pgap] Database:     $HMM_LIB"
    echo "[pgap] Threads:      $THREADS"
    echo "[pgap] Output root:  $_out_dir"

    # ── Press the HMM database if not already pressed ────────────────────────
    if [[ ! -f "${HMM_LIB}.h3i" ]]; then
        echo "[pgap] HMM database not pressed — running hmmpress..."
        hmmpress -f "$HMM_LIB"
    fi

    # ── Idempotency: skip the heavy hmmscan step if raw output already exists ─
    if [[ -s "$_raw_domtbl" ]]; then
        echo "[pgap] Raw output already exists ($_raw_domtbl), skipping hmmscan (delete manually to re-run)"
        pipeline_log_skipped "hmmscan vs PGAP HMMs" "$_hmmscan_command" "raw output already present"
    else
        echo "[pgap] Running hmmscan ($_threshold_considered --noali --cpu $THREADS)..."
        pipeline_log_run_logged "hmmscan vs PGAP HMMs" "" "" \
            hmmscan \
                --cpu "$THREADS" \
                $_threshold_considered \
                --domtblout "$_raw_domtbl" \
                --noali \
                -o "$_raw_hmmscan_out" \
                "$HMM_LIB" \
                "$_faa"
        pipeline_log_kv_path "Raw domtbl" "$_raw_domtbl"
    fi

    # ── Post-process raw hmmscan output into the normalised TSV(s) ───────────
    run_postprocess() {
        python3 /opt/pgap/scripts/process_pgap_raw_results.py \
            --input                 "$_raw_domtbl" \
            --output                "$_proc_tsv" \
            --organism-name         "$_org" \
            --domain                "$_domain" \
            --tool-used             "$_tool_used" \
            --command-used          "$_hmmscan_command" \
            --database-used         "$_database_used" \
            --threshold-considered="$_threshold_considered" \
            --input-path            "$_faa" \
            --output-path           "$_out_dir"
    }
    echo "[pgap] Post-processing $_raw_domtbl ..."
    pipeline_log_step "post-process -> processed/pgap_results.tsv" run_postprocess
    pipeline_log_kv_path "Processed TSV" "$_proc_tsv"

    # >>> wired: pipeline_log_close <<<
    pipeline_log_close

    echo "[pgap] Done: $_org"
    echo "  raw/       : $_raw_dir"
    echo "  processed/ : $_proc_dir"
}

# ── Main dispatch ─────────────────────────────────────────────────────────────
if [[ -d "$INPUT" ]]; then
    declare -A _seen=()
    mapfile -t _faas < <(find -L "$INPUT" -type f -name '*.faa' | sort)
    (( ${#_faas[@]} )) || { echo "[pgap] ERROR: no .faa files found under $INPUT" >&2; exit 1; }
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
    echo "[pgap] Batch complete: success=$_ok  failed=$_fail"
    (( _fail == 0 )) || exit 2
else
    run_one "$INPUT" "${ORGANISM_NAME:-$(basename "${INPUT%.*}")}"
fi
