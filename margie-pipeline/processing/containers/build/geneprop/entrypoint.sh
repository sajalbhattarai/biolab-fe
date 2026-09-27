#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# CONTAINER ENTRYPOINT — Genome Properties (whole-genome property assignment)
# Installed at /usr/local/bin/run inside the container.
#
# Pipeline-standard interface (single organism):
#   run -i /input/organism.faa -o /output -d /db [-t THREADS]
#       [--tigrfam-domtbl PATH] [--domain {Archaea,Bacteria,Eukaryota,Unknown}]
#       [--organism-name NAME]
#
# Directory mode (process all organisms from annotation output root):
#   run -i /annotation/output -o /output/geneprop -d /db [-t THREADS]
#   Scans for tigrfam domtbl files at <-i>/tigrfam/<organism>/raw/tigrfam_domtbl.out
#   and runs genome properties for each organism found.
#
# Inputs:
#   - /db/                  EBI genome-properties repo (contains flatfiles/)
#   - --tigrfam-domtbl PATH HMMER domtblout from the tigrfam stage.
#                           If not given in single-file mode, auto-located at:
#                             <OUTPUT>/tigrfam/raw/tigrfam_domtbl.out
#
# Output directory layout (under -o):
#   /output/<organism>/
#     ├── raw/
#     │     ├── geneprop_tigrfam_domtbl.txt  ← copy of input domtblout (provenance)
#     │     └── geneprop_inputs.txt          ← record of all inputs used
#     └── processed/
#           └── geneprop_results.tsv         ← one row per property (GENEPROP_ prefix)
# ═══════════════════════════════════════════════════════════════════════════════
set -euo pipefail


# >>> wired: pipeline_log helper <<<
# Shared provenance-log helper (synced into scripts/ by build-and-push.sh).
# Resolve own location even when invoked via symlink (e.g. /usr/local/bin/run).
_pl_self="${BASH_SOURCE[0]}"
while [[ -L "$_pl_self" ]]; do _pl_self="$(readlink "$_pl_self")"; done
# shellcheck source=/dev/null
source "$(cd "$(dirname "$_pl_self")" && pwd)/scripts/pipeline_log.sh"

usage() {
    cat <<'HELP_EOF'

Genome Properties — whole-genome biological property assignment

USAGE (single organism)
  run -i /input/organism.faa -o /output -d /db \
      [-t THREADS] [--tigrfam-domtbl PATH] \
      [--domain {Archaea,Bacteria,Eukaryota,Unknown}] [--organism-name NAME]

USAGE (directory — all organisms processed)
  run -i /annotation/output -o /output/geneprop -d /db [-t THREADS]
  When -i is a directory, scans for tigrfam domtbl files at:
    <-i>/tigrfam/<organism>/raw/tigrfam_domtbl.out
  and runs genome properties for each organism found.

REQUIRED MOUNTS
  /input/   Protein FASTA (.faa) or annotation output root directory — read-only
  /output/  Output root — writable
  /db/      Genome Properties repo (clone of ebi-pf-team/genome-properties; must contain flatfiles/)

REQUIRED OPTIONS
  -i FILE|DIR   Protein FASTA (single-file mode) or annotation output root (directory mode)
  -o DIR        Output root directory (container creates <out>/<organism>/{raw,processed}/)
  -d DIR        Genome Properties repo directory (with flatfiles/)

OPTIONAL OPTIONS
  -t INT              CPU threads                        [default: 1]
  --tigrfam-domtbl FILE  TIGRFAMs domtblout path (single-file mode; auto-located if absent)
  --domain STR        Archaea | Bacteria | Eukaryota | Unknown   [default: auto-detect]
  --organism-name STR Override organism name (single-file mode only)
  --help, -h          Show this help and exit

OUTPUTS  (under <OUTPUT>/<organism>/)
  raw/geneprop_tigrfam_domtbl.txt  Copy of the input TIGRFAMs domtblout
  raw/geneprop_inputs.txt          Record of all inputs used for provenance
  processed/geneprop_results.tsv   Normalised TSV — one row per genome property

HELP_EOF
}

# ── Argument parsing ──────────────────────────────────────────────────────────
INPUT=""
OUTPUT_ROOT=""
DBDIR=""
THREADS=1
TIGRFAM_DOMTBL=""
DOMAIN=""
ORGANISM_NAME=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -i)                INPUT="$2";          shift 2 ;;
        -o)                OUTPUT_ROOT="$2";    shift 2 ;;
        -d)                DBDIR="$2";          shift 2 ;;
        -t)                THREADS="$2";        shift 2 ;;
        --tigrfam-domtbl)  TIGRFAM_DOMTBL="$2"; shift 2 ;;
        --domain)          DOMAIN="$2";         shift 2 ;;
        --organism-name)   ORGANISM_NAME="$2";  shift 2 ;;
        --help|-h)         usage; exit 0 ;;
        *) echo "[geneprop] ERROR: unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

[[ -z "$OUTPUT_ROOT" ]] && { echo "[geneprop] ERROR: -o OUTPUT required" >&2; exit 1; }
[[ -z "$DBDIR"       ]] && { echo "[geneprop] ERROR: -d DBDIR required"  >&2; exit 1; }
[[ ! -d "$DBDIR"     ]] && { echo "[geneprop] ERROR: db dir not found: $DBDIR" >&2; exit 1; }

# Locate flatfiles/ directory inside DBDIR (top-level or nested)
FLATFILES_DIR=""
if [[ -d "$DBDIR/flatfiles" ]]; then
    FLATFILES_DIR="$DBDIR/flatfiles"
elif [[ -d "$DBDIR/genome-properties/flatfiles" ]]; then
    FLATFILES_DIR="$DBDIR/genome-properties/flatfiles"
else
    echo "[geneprop] ERROR: could not find flatfiles/ under $DBDIR" >&2
    exit 1
fi

# ── Single-organism processing function ──────────────────────────────────────
# Args: <tigrfam_domtbl_path> <organism_name> [<faa_path_for_provenance>]
run_one() {
    local _domtbl="$1"
    local _org="$2"
    local _faa="${3:-}"   # optional — used for provenance and domain detection only

    # Domain auto-detection from FAA path (if available) or domtbl path
    local _domain="$DOMAIN"
    if [[ -z "$_domain" ]]; then
        local _detect_path="${_faa:-$_domtbl}"
        local _input_lower _path_segs _seg _pi
        _input_lower="$(printf '%s' "$_detect_path" | tr '[:upper:]' '[:lower:]')"
        IFS='/' read -r -a _path_segs <<< "$_input_lower"
        for (( _pi=${#_path_segs[@]}-1; _pi>=0; _pi-- )); do
            _seg="${_path_segs[$_pi]}"
            case "$_seg" in
                gram-positive|gram-negative|gram-unknown|bacteria)
                    _domain="Bacteria"; break ;;
                archaea|arch)
                    _domain="Archaea"; break ;;
                eukaryota|eukaryote|eukaryotes)
                    _domain="Eukaryota"; break ;;
                unknown)
                    _domain="Unknown"; break ;;
            esac
        done
        if [[ -z "$_domain" && -n "$_faa" ]]; then
            case "$(basename "$_faa")" in
                *_bact_gram*.*|*_bact_gram*|*_bact.*|*_bact) _domain="Bacteria" ;;
                *_archaea.*|*_archaea|*_arch.*|*_arch)         _domain="Archaea"  ;;
                *_unknown.*|*_unknown)                          _domain="Unknown"  ;;
            esac
        fi
        _domain="${_domain:-Unknown}"
    fi

    # Output directory layout
    local _out_dir="$OUTPUT_ROOT/$_org"
    local _raw_dir="$_out_dir/raw"
    local _proc_dir="$_out_dir/processed"
    mkdir -p "$_raw_dir" "$_proc_dir"

    # >>> wired: pipeline_log_init <<<
    local _log_path="$_out_dir/geneprop-pipeline-log.txt"
    export PIPELINE_LOG_DOMAIN="${_domain}"
    pipeline_log_init geneprop "${_org}" "$_out_dir" "$_log_path"

    pipeline_log_section "INPUTS"
    pipeline_log_kv_path "Input (tigrfam domtbl)" "${_domtbl}"
    pipeline_log_kv_path "Database"               "${DBDIR}"
    pipeline_log_kv      "Threads"                "${THREADS}"

    local _raw_domtbl_copy="$_raw_dir/geneprop_tigrfam_domtbl.txt"
    local _raw_inputs_record="$_raw_dir/geneprop_inputs.txt"
    local _proc_tsv="$_proc_dir/geneprop_results.tsv"

    local _cmd="process_geneprop_raw_results.py --tigrfam-domtbl ${_domtbl} --flatfiles-dir ${FLATFILES_DIR}"

    echo "[geneprop] Organism:        $_org"
    echo "[geneprop] TIGRFAM domtbl:  $_domtbl"
    echo "[geneprop] Flatfiles dir:   $FLATFILES_DIR"
    echo "[geneprop] Output root:     $_out_dir"
    echo "[geneprop] Threads:         $THREADS (reserved; assignment is single-threaded)"

    # Stage raw inputs for provenance
    cp -f "$_domtbl" "$_raw_domtbl_copy"
    {
        echo "organism_name=$_org"
        echo "domain=$_domain"
        echo "tigrfam_domtbl=$_domtbl"
        echo "flatfiles_dir=$FLATFILES_DIR"
        echo "command=$_cmd"
    } > "$_raw_inputs_record"

    # Run the in-container processor
    run_geneprop_processor() {
        python3 /opt/geneprop/scripts/process_geneprop_raw_results.py \
            --tigrfam-domtbl  "$_domtbl" \
            --flatfiles-dir   "$FLATFILES_DIR" \
            --output          "$_proc_tsv" \
            --organism-name   "$_org" \
            --command-used    "$_cmd"
    }
    echo "[geneprop] Running property assignment ..."
    pipeline_log_step "property assignment → processed/geneprop_results.tsv" run_geneprop_processor
    pipeline_log_kv_path "Processed TSV" "$_proc_tsv"

    # >>> wired: pipeline_log_close <<<
    pipeline_log_close

    echo "[geneprop] Done: $_org"
    echo "  raw/       : $_raw_dir"
    echo "  processed/ : $_proc_dir"
}

# ── Main dispatch ─────────────────────────────────────────────────────────────
if [[ -n "$INPUT" && -d "$INPUT" ]]; then
    # Directory mode: scan for tigrfam domtbl files under the annotation output root.
    # Expected path pattern: <input>/tigrfam/<organism_rel>/raw/tigrfam_domtbl.out
    declare -A _seen=()
    mapfile -t _domtbls < <(find -L "$INPUT" -type f -name "tigrfam_domtbl.out" \
        -path "*/tigrfam/*/raw/*" | sort)
    (( ${#_domtbls[@]} )) || {
        echo "[geneprop] ERROR: no tigrfam_domtbl.out files found under $INPUT/tigrfam/" >&2
        exit 1
    }
    _ok=0; _fail=0; _total="${#_domtbls[@]}"
    for _i in "${!_domtbls[@]}"; do
        _domtbl="${_domtbls[$_i]}"
        # Extract organism_rel: the path between tigrfam/ and /raw/
        # e.g. .../tigrfam/gram-negative/E_coli/raw/tigrfam_domtbl.out → gram-negative/E_coli
        _rel="${_domtbl#*/tigrfam/}"
        _org_rel="${_rel%%/raw/*}"
        _org="$(basename "$_org_rel")"
        [[ -n "${_seen[$_org]+x}" ]] && continue
        _seen[$_org]=1
        # Try to find a FAA for this organism (for domain detection provenance)
        _faa="$(find -L "$INPUT" -type f -name "*.faa" -path "*/$_org/*" -print -quit 2>/dev/null || true)"
        echo "[$((  _i + 1 ))/$_total] Processing: $_org"
        if run_one "$_domtbl" "$_org" "$_faa"; then _ok=$(( _ok + 1 ))
        else                                         _fail=$(( _fail + 1 )); fi
    done
    echo "[geneprop] Batch complete: success=$_ok  failed=$_fail"
    (( _fail == 0 )) || exit 2
else
    # Single-file mode: auto-locate tigrfam domtbl if not supplied
    if [[ -z "$TIGRFAM_DOMTBL" ]]; then
        CANDIDATE_DOMTBL_PRIMARY="$OUTPUT_ROOT/tigrfam/raw/tigrfam_domtbl.out"
        CANDIDATE_DOMTBL_FALLBACK="$OUTPUT_ROOT/../tigrfam/raw/tigrfam_domtbl.out"
        if [[ -s "$CANDIDATE_DOMTBL_PRIMARY" ]]; then
            TIGRFAM_DOMTBL="$CANDIDATE_DOMTBL_PRIMARY"
        elif [[ -s "$CANDIDATE_DOMTBL_FALLBACK" ]]; then
            TIGRFAM_DOMTBL="$CANDIDATE_DOMTBL_FALLBACK"
        else
            echo "[geneprop] ERROR: --tigrfam-domtbl not given and no domtblout found at:" >&2
            echo "  $CANDIDATE_DOMTBL_PRIMARY" >&2
            echo "  $CANDIDATE_DOMTBL_FALLBACK" >&2
            echo "  Run the tigrfam stage first, or pass --tigrfam-domtbl explicitly." >&2
            exit 1
        fi
    fi
    [[ ! -f "$TIGRFAM_DOMTBL" ]] && { echo "[geneprop] ERROR: tigrfam domtblout not found: $TIGRFAM_DOMTBL" >&2; exit 1; }

    # Derive organism name
    if [[ -z "$ORGANISM_NAME" ]]; then
        if [[ -n "$INPUT" ]]; then
            ORGANISM_NAME="$(basename "${INPUT%.*}")"
        else
            ORGANISM_NAME="unknown_organism"
        fi
    fi

    run_one "$TIGRFAM_DOMTBL" "$ORGANISM_NAME" "${INPUT:-}"
fi
