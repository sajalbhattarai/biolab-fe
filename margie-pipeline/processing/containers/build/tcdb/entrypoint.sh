#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# CONTAINER ENTRYPOINT — TCDB (Transporter Classification Database)
# Installed at /usr/local/bin/run inside the container.
#
# Pipeline-standard interface (single file):
#   run -i /input/organism.faa -o /output -d /db [-t THREADS] [-e EVALUE] [--id PCT]
#       [--domain {Archaea,Bacteria,Eukaryota,Unknown}] [--organism-name NAME]
#
# Directory mode (process all organisms under a directory):
#   run -i /input/rasttk_output -o /output -d /db [-t THREADS] [-e EVALUE] [--id PCT]
#   All .faa files found recursively are processed; --organism-name is ignored.
#
# Output directory layout (under -o):
#   /output/<organism>/
#     ├── raw/
#     │     ├── tcdb.tsv              DIAMOND -f 6 tabular (qseqid sseqid pident length evalue bitscore stitle)
#     │     └── tcdb.stderr           captured stderr
#     └── processed/
#           ├── tcdb_results.tsv      normalised per-hit TSV (TCDB_ prefix)
# ═══════════════════════════════════════════════════════════════════════════════
set -euo pipefail


# >>> wired: detailed-step <<<
# >>> wired: pipeline_log helper <<<
# Shared provenance-log helper (fixed in-container path).
# shellcheck source=/dev/null
source /opt/tcdb/scripts/pipeline_log.sh

usage() {
    cat <<'HELP_EOF'

TCDB — Transporter Classification Database search via DIAMOND blastp

USAGE (single file)
  run -i /input/organism.faa -o /output -d /db \
      [-t THREADS] [-e EVALUE] [--id PCT] \
      [--domain {Archaea,Bacteria,Eukaryota,Unknown}] [--organism-name NAME]

USAGE (directory — all organisms processed)
  run -i /input/rasttk_output -o /output -d /db [-t THREADS] [-e EVALUE] [--id PCT]
  All .faa files found recursively under -i are processed.
  --organism-name is ignored in directory mode (derived per file).

REQUIRED MOUNTS
  /input/   Protein FASTA (.faa) or directory containing .faa files — read-only
  /output/  Output root — writable
  /db/      TCDB database directory (must contain tcdb.dmnd; optional families.tsv)

REQUIRED OPTIONS
  -i FILE|DIR   Protein FASTA input file or input directory
  -o DIR        Output root directory (container creates <out>/<organism>/{raw,processed}/)
  -d DIR        TCDB database directory

OPTIONAL OPTIONS
  -t INT              CPU threads                       [default: 1]
  -e FLOAT            DIAMOND e-value cutoff            [default: 1e-5]
  --id FLOAT          DIAMOND percent-identity cutoff   [default: 30]
  --domain STR        Archaea | Bacteria | Eukaryota | Unknown   [default: auto-detect]
  --organism-name STR Override organism name (single-file mode only)
  --help, -h          Show this help and exit

OUTPUTS  (under <OUTPUT>/<organism>/)
  raw/tcdb.tsv               DIAMOND -f 6 7-col tabular output (untouched)
  raw/tcdb.stderr            Captured stderr
  processed/tcdb_results.tsv Normalised per-hit TSV (TCDB_ prefix; TC id parsed from sseqid)

HELP_EOF
}

# ── Argument parsing ──────────────────────────────────────────────────────────
INPUT=""
OUTPUT_ROOT=""
DBDIR=""
THREADS=1
EVALUE="1e-5"
PERCENT_IDENTITY="30"
DOMAIN=""
ORGANISM_NAME=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -i)                INPUT="$2";              shift 2 ;;
        -o)                OUTPUT_ROOT="$2";        shift 2 ;;
        -d)                DBDIR="$2";              shift 2 ;;
        -t)                THREADS="$2";            shift 2 ;;
        -e)                EVALUE="$2";             shift 2 ;;
        --id)              PERCENT_IDENTITY="$2";   shift 2 ;;
        --domain)         DOMAIN="$2";         shift 2 ;;
        --organism-name)   ORGANISM_NAME="$2";      shift 2 ;;
        --help|-h)         usage; exit 0 ;;
        *) echo "[tcdb] ERROR: unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
done

[[ -z "$INPUT"       ]] && { echo "[tcdb] ERROR: -i INPUT required"  >&2; exit 1; }
[[ -z "$OUTPUT_ROOT" ]] && { echo "[tcdb] ERROR: -o OUTPUT required" >&2; exit 1; }
[[ -z "$DBDIR"       ]] && { echo "[tcdb] ERROR: -d DBDIR required"  >&2; exit 1; }
[[ ! -e "$INPUT"     ]] && { echo "[tcdb] ERROR: input not found: $INPUT" >&2; exit 1; }

DIAMOND_DB="$DBDIR/tcdb"
if [[ ! -f "${DIAMOND_DB}.dmnd" ]]; then
    echo "[tcdb] ERROR: DIAMOND database not found: ${DIAMOND_DB}.dmnd" >&2
    exit 1
fi

# Optional family-description lookup table
FAMILIES_TSV=""
if [[ -f "$DBDIR/families.tsv" ]]; then
    FAMILIES_TSV="$DBDIR/families.tsv"
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
            echo "[tcdb] Auto-detected --domain ${_domain} from ${_detected_from}"
    fi

    # Output directory layout
    local _out_dir="$OUTPUT_ROOT/$_org"
    local _raw_dir="$_out_dir/raw"
    local _proc_dir="$_out_dir/processed"
    mkdir -p "$_raw_dir" "$_proc_dir"

    # >>> wired: pipeline_log_init <<<
    local _log_path="$_out_dir/tcdb-pipeline-log.txt"
    export PIPELINE_LOG_DOMAIN="${_domain}"
    pipeline_log_init tcdb "${_org}" "$_out_dir" "$_log_path"
    pipeline_log_legal_preamble

    local _raw_tsv="$_raw_dir/tcdb.tsv"
    local _raw_err="$_raw_dir/tcdb.stderr"
    local _proc_tsv="$_proc_dir/tcdb_results.tsv"

    # Exact command we are about to run (recorded for provenance)
    local _tcdb_command="diamond blastp -q ${_faa} -d ${DIAMOND_DB} -o ${_raw_tsv} -f 6 qseqid sseqid pident length evalue bitscore stitle -p ${THREADS} -e ${EVALUE} --id ${PERCENT_IDENTITY} -k 1 --quiet"
    local _tool_used="DIAMOND blastp 2.1.9 | TCDB assignment"
    local _database_used="TCDB 2025-03-06 | Source: https://www.tcdb.org/ | path(container): ${DIAMOND_DB}.dmnd"

    pipeline_log_section "diamond blastp annotation"
    pipeline_log_kv      "Tool"                     "$_tool_used"
    pipeline_log_kv_path "Input (host)"             "${_faa}"
    pipeline_log_kv      "Input (container)"        "${_faa}"
    pipeline_log_kv_path "Database (host)"          "${DIAMOND_DB}.dmnd"
    pipeline_log_kv      "Database (container)"     "${DIAMOND_DB}.dmnd"
    pipeline_log_kv_path "Output (host)"            "$_out_dir"
    pipeline_log_kv      "Output (container)"       "$_out_dir"
    pipeline_log_kv      "Threads"                  "${THREADS:-1}"
    pipeline_log_kv      "E-value threshold"        "$EVALUE"
    pipeline_log_kv      "Percent identity cutoff"  "$PERCENT_IDENTITY"

    echo "[tcdb] Input:           $_faa ($_org)"
    echo "[tcdb] DB:              ${DIAMOND_DB}.dmnd"
    echo "[tcdb] Output root:     $_out_dir"
    echo "[tcdb] Threads:         $THREADS"
    echo "[tcdb] E-value:         $EVALUE"
    echo "[tcdb] % identity:      $PERCENT_IDENTITY"

    # ── Idempotency: skip DIAMOND if raw output already exists ──────────────────
    if [[ -s "$_raw_tsv" ]]; then
        echo "[tcdb] Raw output already exists ($_raw_tsv), skipping DIAMOND (delete manually to re-run)"
        pipeline_log_skipped "diamond blastp vs TCDB" "$_tcdb_command" "raw output already present"
    else
        echo "[tcdb] Running DIAMOND blastp ..."
        pipeline_log_run_logged "diamond blastp vs TCDB" "" "$_raw_err" \
            diamond blastp \
                -q "$_faa" \
                -d "$DIAMOND_DB" \
                -o "$_raw_tsv" \
                -f 6 qseqid sseqid pident length evalue bitscore stitle \
                -p "$THREADS" \
                -e "$EVALUE" \
                --id "$PERCENT_IDENTITY" \
                -k 1 \
                --quiet
        pipeline_log_kv_path "Raw TSV" "$_raw_tsv"
    fi

    # ── Post-process raw tabular file → normalised per-hit TSV ──────────────────
    run_postprocess() {
        python3 /opt/tcdb/scripts/process_tcdb_raw_results.py \
            --input                            "$_raw_tsv" \
            --output                           "$_proc_tsv" \
            ${FAMILIES_TSV:+--families-tsv     "$FAMILIES_TSV"} \
            --organism-name                    "$_org" \
            --domain                           "$_domain" \
            --tool-used                        "$_tool_used" \
            --command-used                     "$_tcdb_command" \
            --database-used                    "$_database_used" \
            --evalue-threshold-used            "$EVALUE" \
            --percent-identity-threshold-used  "$PERCENT_IDENTITY" \
            --input-path                       "$_faa" \
            --output-path                      "$_out_dir"
    }
    echo "[tcdb] Post-processing $_raw_tsv ..."
    pipeline_log_step "post-process -> processed/tcdb_results.tsv" run_postprocess
    pipeline_log_kv_path "Processed TSV" "$_proc_tsv"

    # >>> wired: pipeline_log_close <<<
    pipeline_log_close

    echo "[tcdb] Done: $_org"
    echo "  raw/       : $_raw_dir"
    echo "  processed/ : $_proc_dir"
}

# ── Main dispatch ─────────────────────────────────────────────────────────────
if [[ -d "$INPUT" ]]; then
    declare -A _seen=()
    mapfile -t _faas < <(find -L "$INPUT" -type f -name '*.faa' | sort)
    (( ${#_faas[@]} )) || { echo "[tcdb] ERROR: no .faa files found under $INPUT" >&2; exit 1; }
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
    echo "[tcdb] Batch complete: success=$_ok  failed=$_fail"
    (( _fail == 0 )) || exit 2
else
    run_one "$INPUT" "${ORGANISM_NAME:-$(basename "${INPUT%.*}")}"
fi
