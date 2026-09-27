#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# CONTAINER ENTRYPOINT — eggNOG-mapper (orthology-based functional annotation)
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
#     │     ├── eggnog_out.emapper.annotations   per-protein annotations TSV (untouched)
#     │     ├── eggnog_out.emapper.seed_orthologs (if produced)
#     │     ├── eggnog_out.emapper.hits           (if produced)
#     │     ├── tmp/                              scratch dir (kept for debug)
#     │     └── eggnog.stderr                     captured stderr
#     └── processed/
#           ├── eggnog_results.tsv                normalised per-protein TSV (EGGNOG_ prefix)
# ═══════════════════════════════════════════════════════════════════════════════
set -euo pipefail


# >>> wired: detailed-step <<<
# >>> wired: pipeline_log helper <<<
# Shared provenance-log helper (fixed in-container path).
# shellcheck source=/dev/null
source /opt/eggnog/scripts/pipeline_log.sh

usage() {
    cat <<'HELP_EOF'

eggNOG-mapper — orthology-based functional annotation

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
  /db/      eggNOG data directory (must contain eggnog.db; eggnog_proteins.dmnd for diamond mode)

REQUIRED OPTIONS
  -i FILE|DIR   Protein FASTA input file or input directory
  -o DIR        Output root directory (container creates <out>/<organism>/{raw,processed}/)
  -d DIR        eggNOG data directory

OPTIONAL OPTIONS
  -t INT              CPU threads                       [default: 1]
  --domain STR        Archaea | Bacteria | Eukaryota | Unknown   [default: auto-detect]
  --organism-name STR Override organism name (single-file mode only)
  --help, -h          Show this help and exit

MODES
  Uses DIAMOND mode if $DBDIR/eggnog_proteins.dmnd exists; falls back to
  HMMER/Bacteria mode if only $DBDIR/Bacteria.hmm is present.

OUTPUTS  (under <OUTPUT>/<organism>/)
  raw/eggnog_out.emapper.annotations    per-protein annotation TSV (untouched)
  raw/eggnog_out.emapper.seed_orthologs (if produced)
  raw/eggnog_out.emapper.hits           (if produced)
  raw/eggnog.stderr                     Captured stderr
  processed/eggnog_results.tsv          Normalised per-protein TSV (EGGNOG_ prefix)

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
        *) echo "[eggnog] ERROR: unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
done

[[ -z "$INPUT"       ]] && { echo "[eggnog] ERROR: -i INPUT required"  >&2; exit 1; }
[[ -z "$OUTPUT_ROOT" ]] && { echo "[eggnog] ERROR: -o OUTPUT required" >&2; exit 1; }
[[ -z "$DBDIR"       ]] && { echo "[eggnog] ERROR: -d DBDIR required"  >&2; exit 1; }
[[ ! -e "$INPUT"     ]] && { echo "[eggnog] ERROR: input not found: $INPUT" >&2; exit 1; }
[[ ! -f "$DBDIR/eggnog.db" ]] && { echo "[eggnog] ERROR: eggnog.db not found in $DBDIR" >&2; exit 1; }

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
            echo "[eggnog] Auto-detected --domain ${_domain} from ${_detected_from}"
    fi

    # Output directory layout
    local _out_dir="$OUTPUT_ROOT/$_org"
    local _raw_dir="$_out_dir/raw"
    local _proc_dir="$_out_dir/processed"
    mkdir -p "$_raw_dir" "$_proc_dir"

    # >>> wired: pipeline_log_init <<<
    local _log_path="$_out_dir/eggnog-pipeline-log.txt"
    export PIPELINE_LOG_DOMAIN="${_domain}"
    pipeline_log_init eggnog "${_org}" "$_out_dir" "$_log_path"
    pipeline_log_legal_preamble

    local _annotations="$_raw_dir/eggnog_out.emapper.annotations"
    local _raw_err="$_raw_dir/eggnog.stderr"
    local _proc_tsv="$_proc_dir/eggnog_results.tsv"

    # DIAMOND tmpdir lives inside the raw/ dir
    local _tmpdir="$_raw_dir/tmp"
    mkdir -p "$_tmpdir"
    export TMPDIR="$_tmpdir"

    # Pick search mode based on which database files are present.
    # DIAMOND is the default/recommended mode (much faster, comparable accuracy).
    # HMMER/Bacteria is a fallback when only HMM profiles are available.
    local _emapper_mode_args=""
    local _mode_used=""
    if [[ -f "$DBDIR/eggnog_proteins.dmnd" ]]; then
        _emapper_mode_args="-m diamond --dmnd_db $DBDIR/eggnog_proteins.dmnd"
        _mode_used="diamond"
    elif [[ -f "$DBDIR/hmmer/Bacteria/Bacteria.hmm.h3f" ]] || [[ -f "$DBDIR/Bacteria.hmm" ]] || [[ -f "$DBDIR/Bacteria.hmm.h3f" ]]; then
        _emapper_mode_args="-m hmmer -d Bacteria"
        _mode_used="hmmer/Bacteria"
    else
        echo "[eggnog] ERROR: no eggNOG search database found in $DBDIR" >&2
        echo "[eggnog]   expected one of:" >&2
        echo "[eggnog]     $DBDIR/eggnog_proteins.dmnd            (DIAMOND mode, recommended)" >&2
        echo "[eggnog]     $DBDIR/hmmer/Bacteria/Bacteria.hmm.h3f (HMMER fallback)" >&2
        return 1
    fi

    # Exact command we are about to run (recorded for provenance)
    # DIAMOND tuning: block_size x ~6 ~= RAM per chunk. block_size=6.0 / chunks=1 ~= ~36 GB RSS,
    # single pass over the ~9 GB eggNOG db. Drops bacterial-genome runtime from ~60 min to
    # ~5-10 min vs emapper's default 0.5/4 (which forces 4+ passes). Tuned for HPC nodes;
    # override via env on memory-constrained hosts:
    #   EGGNOG_BLOCK_SIZE=2.0 EGGNOG_INDEX_CHUNKS=1  (~12 GB RSS)
    #   EGGNOG_BLOCK_SIZE=1.0 EGGNOG_INDEX_CHUNKS=2  (~6 GB RSS)
    #   EGGNOG_BLOCK_SIZE=0.5 EGGNOG_INDEX_CHUNKS=4  (~3 GB RSS, emapper default)
    local _block_size="${EGGNOG_BLOCK_SIZE:-6.0}"
    local _index_chunks="${EGGNOG_INDEX_CHUNKS:-1}"
    local _eggnog_command="emapper.py ${_emapper_mode_args} --data_dir ${DBDIR} -i ${_faa} -o eggnog_out --output_dir ${_raw_dir} --cpu ${THREADS} --scratch_dir ${_tmpdir} --block_size ${_block_size} --index_chunks ${_index_chunks}"
    local _tool_used="eggNOG-mapper 2.1.12 | Mode: ${_mode_used} | Uses: DIAMOND/HMMER"
    local _database_used="eggNOG 5.0.2 data directory | Source: http://eggnogdb.embl.de/download/emapperdb-5.0.2/ | path(container): ${DBDIR}"

    pipeline_log_section "emapper.py annotation"
    pipeline_log_kv      "Tool"                 "$_tool_used"
    pipeline_log_kv_path "Input (host)"         "${_faa}"
    pipeline_log_kv      "Input (container)"    "${_faa}"
    pipeline_log_kv_path "Database (host)"      "${DBDIR}"
    pipeline_log_kv      "Database (container)" "${DBDIR}"
    pipeline_log_kv_path "Output (host)"        "$_out_dir"
    pipeline_log_kv      "Output (container)"   "$_out_dir"
    pipeline_log_kv      "Mode considered"      "$_mode_used"
    pipeline_log_kv      "Threads"              "${THREADS:-1}"

    echo "[eggnog] Input:        $_faa ($_org)"
    echo "[eggnog] DB dir:       $DBDIR"
    echo "[eggnog] Mode:         $_mode_used"
    echo "[eggnog] Output root:  $_out_dir"
    echo "[eggnog] Threads:      $THREADS"

    # ── Idempotency: skip emapper if annotations file already non-empty ─────────
    if [[ -f "$_annotations" ]] && grep -q "^[^#]" "$_annotations" 2>/dev/null; then
        echo "[eggnog] Raw annotations already exist ($_annotations), skipping emapper (delete manually to re-run)"
        pipeline_log_skipped "emapper.py annotation" "$_eggnog_command" "raw output already present"
    else
        rm -f "$_raw_dir/eggnog_out.emapper.hits" \
              "$_raw_dir/eggnog_out.emapper.seed_orthologs" \
              "$_annotations" 2>/dev/null || true
        echo "[eggnog] Running emapper.py ..."
        # shellcheck disable=SC2086
        pipeline_log_run_logged "emapper.py annotation" "" "$_raw_err" \
            emapper.py \
                $_emapper_mode_args \
                --data_dir "$DBDIR" \
                -i "$_faa" \
                -o eggnog_out \
                --output_dir "$_raw_dir" \
                --cpu "$THREADS" \
                --scratch_dir "$_tmpdir" \
                --block_size "$_block_size" \
                --index_chunks "$_index_chunks"
        pipeline_log_kv_path "Raw annotations" "$_annotations"
    fi

    # ── Post-process annotations file → normalised per-protein TSV ──────────────
    run_postprocess() {
        python3 /opt/eggnog/scripts/process_eggnog_raw_results.py \
            --input         "$_annotations" \
            --output        "$_proc_tsv" \
            --organism-name "$_org" \
            --domain        "$_domain" \
            --tool-used     "$_tool_used" \
            --command-used  "$_eggnog_command" \
            --database-used "$_database_used" \
            --mode-used     "$_mode_used" \
            --input-path    "$_faa" \
            --output-path   "$_out_dir"
    }
    echo "[eggnog] Post-processing $_annotations ..."
    pipeline_log_step "post-process -> processed/eggnog_results.tsv" run_postprocess
    pipeline_log_kv_path "Processed TSV" "$_proc_tsv"

    # >>> wired: pipeline_log_close <<<
    pipeline_log_close

    echo "[eggnog] Done: $_org"
    echo "  raw/       : $_raw_dir"
    echo "  processed/ : $_proc_dir"
}

# ── Main dispatch ─────────────────────────────────────────────────────────────
if [[ -d "$INPUT" ]]; then
    declare -A _seen=()
    mapfile -t _faas < <(find -L "$INPUT" -type f -name '*.faa' | sort)
    (( ${#_faas[@]} )) || { echo "[eggnog] ERROR: no .faa files found under $INPUT" >&2; exit 1; }
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
    echo "[eggnog] Batch complete: success=$_ok  failed=$_fail"
    (( _fail == 0 )) || exit 2
else
    run_one "$INPUT" "${ORGANISM_NAME:-$(basename "${INPUT%.*}")}"
fi
