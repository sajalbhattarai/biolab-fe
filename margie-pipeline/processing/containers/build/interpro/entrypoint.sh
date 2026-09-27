#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# CONTAINER ENTRYPOINT — InterProScan (domain / family / GO / pathway annotation)
# Installed at /usr/local/bin/run inside the container.
#
# Pipeline-standard interface (single file):
#   run -i /input/organism.faa -o /output -d /db [-t THREADS] [-a APPS]
#       [--domain {Archaea,Bacteria,Eukaryota,Unknown}] [--organism-name NAME]
#
# Directory mode (process all organisms under a directory):
#   run -i /input/rasttk_output -o /output -d /db [-t THREADS] [-a APPS]
#   All .faa files found recursively are processed; --organism-name is ignored.
#
# Output directory layout (under -o):
#   /output/interpro/
#     ├── raw/
#     │     ├── input_clean.faa       sanitised input (stop codons stripped)
#     │     ├── interpro.tsv          InterProScan TSV (untouched)
#     │     └── interpro.stderr       captured stderr
#     └── processed/
#           ├── interpro_results.tsv  normalised per-domain TSV (INTERPRO_ prefix)
# ═══════════════════════════════════════════════════════════════════════════════
set -euo pipefail


# >>> wired: detailed-step <<<
# >>> wired: pipeline_log helper <<<
# Shared provenance-log helper — baked into the container at scripts/.
# shellcheck source=/dev/null
source /opt/interpro/scripts/pipeline_log.sh

usage() {
    cat <<'HELP_EOF'

InterProScan — domain / family / GO / pathway annotation

USAGE (single file)
  docker run ... annotation/interpro:latest \
    -i /input/organism.faa -o /output -d /db \
    [-t THREADS] [-a APPS] \
    [--domain {Archaea,Bacteria,Eukaryota,Unknown}] [--organism-name NAME]

USAGE (directory — all organisms processed)
  run -i /input/rasttk_output -o /output -d /db [-t THREADS] [-a APPS]
  All .faa files found recursively under -i are processed.
  --organism-name is ignored in directory mode (derived per file).

REQUIRED MOUNTS
  /input/   Protein FASTA (.faa) or directory containing .faa files — read-only
  /output/  Output root — writable
  /db/      Full InterProScan installation (contains interproscan.sh + data/)

REQUIRED OPTIONS
  -i FILE|DIR         Protein FASTA input file or input directory
  -o DIR              Output root directory (container creates <out>/<organism>/{raw,processed}/)
  -d DIR              InterProScan installation directory

OPTIONAL OPTIONS
  -t INT              CPU threads                       [default: 1]
  -a STR              Comma-separated --applications list
                      Recommended (prokaryote-relevant):
                        NCBIfam,PIRSF,HAMAP,Coils,CDD,SUPERFAMILY,Gene3D
                      Omit to run all available analyses (slower).
  --domain STR        Archaea | Bacteria | Eukaryota | Unknown   [default: auto-detect]
  --organism-name STR Override organism name (single-file mode only)
  --help, -h          Show this help and exit

OUTPUTS  (under <OUTPUT>/<organism>/)
  raw/input_clean.faa            FASTA with stop codons (*) stripped
  raw/interpro.tsv               InterProScan TSV (untouched)
  raw/interpro.stderr            Captured stderr
  processed/interpro_results.tsv Normalised per-domain TSV (INTERPRO_ prefix)

HELP_EOF
}

# ── Argument parsing ──────────────────────────────────────────────────────────
INPUT=""
OUTPUT_ROOT=""
DBDIR=""
THREADS=1
ANALYSES=""
DOMAIN=""
ORGANISM_NAME=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -i)                INPUT="$2";          shift 2 ;;
        -o)                OUTPUT_ROOT="$2";    shift 2 ;;
        -d)                DBDIR="$2";          shift 2 ;;
        -t)                THREADS="$2";        shift 2 ;;
        -a)                ANALYSES="$2";       shift 2 ;;
        --domain)          DOMAIN="$2";         shift 2 ;;
        --organism-name)   ORGANISM_NAME="$2";  shift 2 ;;
        --help|-h)         usage; exit 0 ;;
        *) echo "[interpro] ERROR: unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
done

[[ -z "$INPUT"       ]] && { echo "[interpro] ERROR: -i INPUT required"  >&2; exit 1; }
[[ -z "$OUTPUT_ROOT" ]] && { echo "[interpro] ERROR: -o OUTPUT required" >&2; exit 1; }
[[ -z "$DBDIR"       ]] && { echo "[interpro] ERROR: -d DBDIR required"  >&2; exit 1; }
[[ ! -e "$INPUT"     ]] && { echo "[interpro] ERROR: input not found: $INPUT" >&2; exit 1; }

INTERPROSCAN_SH=$(find "$DBDIR" -name "interproscan.sh" -maxdepth 3 ! -type l 2>/dev/null | head -1)
if [[ -z "$INTERPROSCAN_SH" || ! -x "$INTERPROSCAN_SH" ]]; then
    echo "[interpro] ERROR: interproscan.sh not found/executable under $DBDIR" >&2
    exit 1
fi

# Build optional --applications flag (global — same for all organisms).
APPS_FLAG=""
[[ -n "$ANALYSES" ]] && APPS_FLAG="--applications $ANALYSES"

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
            echo "[interpro] Auto-detected --domain ${_domain} from ${_detected_from}"
    fi

    # Output directory layout
    local _out_dir="$OUTPUT_ROOT/$_org"
    local _raw_dir="$_out_dir/raw"
    local _proc_dir="$_out_dir/processed"
    mkdir -p "$_raw_dir" "$_proc_dir"

    # >>> wired: pipeline_log_init <<<
    local _log_path="$_out_dir/interpro-pipeline-log.txt"
    export PIPELINE_LOG_DOMAIN="${_domain:-Unknown}"
    pipeline_log_init interpro "${_org}" "$_out_dir" "$_log_path"

    pipeline_log_section "INPUTS"
    pipeline_log_kv_path "Input"    "${_faa}"
    pipeline_log_kv_path "Database" "${DBDIR}"
    pipeline_log_kv      "Threads"  "${THREADS:-1}"

    local _clean_input="$_raw_dir/input_clean.faa"
    local _raw_tsv="$_raw_dir/interpro.tsv"
    local _raw_err="$_raw_dir/interpro.stderr"
    local _proc_tsv="$_proc_dir/interpro_results.tsv"

    # ── Exact command we are about to run (recorded for provenance) ──────────
    local _interpro_cmd="${INTERPROSCAN_SH} -i ${_clean_input} -o ${_raw_tsv} -f TSV -cpu ${THREADS} --goterms --iprlookup --pathways --disable-precalc ${APPS_FLAG}"

    echo "[interpro] Input:        $_faa ($_org)"
    echo "[interpro] InterProScan: $INTERPROSCAN_SH"
    echo "[interpro] Output root:  $_out_dir"
    echo "[interpro] Threads:      $THREADS"
    echo "[interpro] Analyses:     ${ANALYSES:-<all>}"

    # ── Idempotency: skip InterProScan if raw output already exists ──────────
    if [[ -s "$_raw_tsv" ]]; then
        echo "[interpro] Raw output already exists ($_raw_tsv), skipping InterProScan (delete manually to re-run)"
        pipeline_log_skipped "interproscan annotation" "$_interpro_cmd" "raw output already present"
    else
        echo "[interpro] Sanitising input (stripping stop codons *) ..."
        pipeline_log_step "sanitise input (strip *)" bash -c 'sed "s/\*//g" "$1" > "$2"' _ "$_faa" "$_clean_input"

        echo "[interpro] Running InterProScan ..."
        # shellcheck disable=SC2086
        pipeline_log_run_logged "interproscan annotation" "" "$_raw_err" \
            "$INTERPROSCAN_SH" \
                -i "$_clean_input" \
                -o "$_raw_tsv" \
                -f TSV \
                -cpu "$THREADS" \
                --goterms \
                --iprlookup \
                --pathways \
                --disable-precalc \
                $APPS_FLAG
        pipeline_log_kv_path "Raw TSV" "$_raw_tsv"
    fi

    # ── Post-process raw TSV → normalised per-domain TSV ────────────────────
    run_postprocess() {
        python3 /opt/interpro/scripts/process_interpro_raw_results.py \
            --input         "$_raw_tsv" \
            --output        "$_proc_tsv" \
            --output-dir    "$_proc_dir" \
            --organism-name "$_org" \
            --command-used  "$_interpro_cmd" \
            --database-used "$DBDIR" \
            --analyses-used "${ANALYSES:-all}" \
            --input-path    "$_raw_tsv" \
            --output-path   "$_proc_dir"
    }
    echo "[interpro] Post-processing $_raw_tsv ..."
    pipeline_log_step "post-process -> processed/interpro_results.tsv" run_postprocess
    pipeline_log_kv_path "Processed TSV" "$_proc_tsv"

    # >>> wired: pipeline_log_close <<<
    pipeline_log_close

    echo "[interpro] Done: $_org"
    echo "  raw/       : $_raw_dir"
    echo "  processed/ : $_proc_dir"
}

# ── Main dispatch ─────────────────────────────────────────────────────────────
if [[ -d "$INPUT" ]]; then
    declare -A _seen=()
    mapfile -t _faas < <(find -L "$INPUT" -type f -name '*.faa' | sort)
    (( ${#_faas[@]} )) || { echo "[interpro] ERROR: no .faa files found under $INPUT" >&2; exit 1; }
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
    echo "[interpro] Batch complete: success=$_ok  failed=$_fail"
    (( _fail == 0 )) || exit 2
else
    run_one "$INPUT" "${ORGANISM_NAME:-$(basename "${INPUT%.*}")}"
fi
