#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# CONTAINER ENTRYPOINT — UniProt / Swiss-Prot (DIAMOND blastp)
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
#     │     ├── uniprot.tsv           DIAMOND -f 6 7-col tabular (qseqid sseqid pident length evalue bitscore stitle)
#     │     └── uniprot.stderr        captured stderr
#     └── processed/
#           ├── uniprot_results.tsv   normalised per-hit TSV (UNIPROT_ prefix; stitle parsed)
# ═══════════════════════════════════════════════════════════════════════════════
set -euo pipefail


# >>> wired: detailed-step <<<
# >>> wired: pipeline_log helper <<<
# Shared provenance-log helper (fixed in-container path).
# shellcheck source=/dev/null
source /opt/uniprot/scripts/pipeline_log.sh

usage() {
    cat <<'HELP_EOF'

UniProt / Swiss-Prot — Protein homology search via DIAMOND blastp

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
  /db/      UniProt database directory (must contain uniprot_sprot.dmnd)

REQUIRED OPTIONS
  -i FILE|DIR   Protein FASTA input file or input directory
  -o DIR        Output root directory (container creates <out>/<organism>/{raw,processed}/)
  -d DIR        UniProt database directory

OPTIONAL OPTIONS
  -t INT              CPU threads                       [default: 1]
  -e FLOAT            DIAMOND e-value cutoff            [default: 1e-5]
  --id FLOAT          DIAMOND percent-identity cutoff   [default: 30]
  --domain STR        Archaea | Bacteria | Eukaryota | Unknown   [default: auto-detect]
  --organism-name STR Override organism name (single-file mode only)
  --help, -h          Show this help and exit

OUTPUTS  (under <OUTPUT>/<organism>/)
  raw/uniprot.tsv                  DIAMOND -f 6 7-col tabular output (untouched)
  raw/uniprot.stderr               Captured stderr
  processed/uniprot_results.tsv    Normalised per-hit TSV (UNIPROT_ prefix; protein/gene/organism parsed from stitle)

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
        --domain)          DOMAIN="$2";             shift 2 ;;
        --organism-name)   ORGANISM_NAME="$2";      shift 2 ;;
        --help|-h)         usage; exit 0 ;;
        *) echo "[uniprot] ERROR: unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
done

[[ -z "$INPUT"       ]] && { echo "[uniprot] ERROR: -i INPUT required"  >&2; exit 1; }
[[ -z "$OUTPUT_ROOT" ]] && { echo "[uniprot] ERROR: -o OUTPUT required" >&2; exit 1; }
[[ -z "$DBDIR"       ]] && { echo "[uniprot] ERROR: -d DBDIR required"  >&2; exit 1; }
[[ ! -e "$INPUT"     ]] && { echo "[uniprot] ERROR: input not found: $INPUT" >&2; exit 1; }

DIAMOND_DB="$DBDIR/uniprot_sprot"
if [[ ! -f "${DIAMOND_DB}.dmnd" ]]; then
    echo "[uniprot] ERROR: DIAMOND database not found: ${DIAMOND_DB}.dmnd" >&2
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
            echo "[uniprot] Auto-detected --domain ${_domain} from ${_detected_from}"
    fi

    # Output directory layout
    local _out_dir="$OUTPUT_ROOT/$_org"
    local _raw_dir="$_out_dir/raw"
    local _proc_dir="$_out_dir/processed"
    mkdir -p "$_raw_dir" "$_proc_dir"

    # >>> wired: pipeline_log_init <<<
    local _log_path="$_out_dir/uniprot-pipeline-log.txt"
    export PIPELINE_LOG_DOMAIN="${_domain}"
    pipeline_log_init uniprot "${_org}" "$_out_dir" "$_log_path"

    pipeline_log_section "INPUTS"
    pipeline_log_kv_path "Input"    "${_faa}"
    pipeline_log_kv_path "Database" "${DBDIR}"
    pipeline_log_kv      "Threads"  "${THREADS:-1}"

    local _raw_tsv="$_raw_dir/uniprot.tsv"
    local _raw_err="$_raw_dir/uniprot.stderr"
    local _proc_tsv="$_proc_dir/uniprot_results.tsv"

    # Exact command we are about to run (recorded for provenance)
    local _uniprot_command="diamond blastp -q ${_faa} -d ${DIAMOND_DB} -o ${_raw_tsv} -f 6 qseqid sseqid pident length evalue bitscore stitle -p ${THREADS} -e ${EVALUE} --id ${PERCENT_IDENTITY} -k 1 --quiet"

    echo "[uniprot] Input:           $_faa ($_org)"
    echo "[uniprot] DB:              ${DIAMOND_DB}.dmnd"
    echo "[uniprot] Output root:     $_out_dir"
    echo "[uniprot] Threads:         $THREADS"
    echo "[uniprot] E-value:         $EVALUE"
    echo "[uniprot] % identity:      $PERCENT_IDENTITY"

    # ── Idempotency: skip DIAMOND if raw output already exists ──────────────────
    if [[ -s "$_raw_tsv" ]]; then
        echo "[uniprot] Raw output already exists ($_raw_tsv), skipping DIAMOND (delete manually to re-run)"
        pipeline_log_skipped "diamond blastp vs UniProt" "$_uniprot_command" "raw output already present"
    else
        echo "[uniprot] Running DIAMOND blastp ..."
        pipeline_log_run_logged "diamond blastp vs UniProt" "" "$_raw_err" \
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
        python3 /opt/uniprot/scripts/process_uniprot_raw_results.py \
            --input                            "$_raw_tsv" \
            --output                           "$_proc_tsv" \
            --organism-name                    "$_org" \
            --domain                           "$_domain" \
            --tool-used                        "DIAMOND 2.1.9" \
            --command-used                     "$_uniprot_command" \
            --database-used                    "${DIAMOND_DB}.dmnd" \
            --evalue-threshold-used            "$EVALUE" \
            --percent-identity-threshold-used  "$PERCENT_IDENTITY" \
            --input-path                       "$_faa" \
            --output-path                      "$_out_dir"
    }
    echo "[uniprot] Post-processing $_raw_tsv ..."
    pipeline_log_step "post-process -> processed/uniprot_results.tsv" run_postprocess
    pipeline_log_kv_path "Processed TSV" "$_proc_tsv"

    # >>> wired: pipeline_log_close <<<
    pipeline_log_close

    echo "[uniprot] Done: $_org"
    echo "  raw/       : $_raw_dir"
    echo "  processed/ : $_proc_dir"
}

# ── Main dispatch ─────────────────────────────────────────────────────────────
if [[ -d "$INPUT" ]]; then
    declare -A _seen=()
    mapfile -t _faas < <(find -L "$INPUT" -type f -name '*.faa' | sort)
    (( ${#_faas[@]} )) || { echo "[uniprot] ERROR: no .faa files found under $INPUT" >&2; exit 1; }
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
    echo "[uniprot] Batch complete: success=$_ok  failed=$_fail"
    (( _fail == 0 )) || exit 2
else
    run_one "$INPUT" "${ORGANISM_NAME:-$(basename "${INPUT%.*}")}"
fi
