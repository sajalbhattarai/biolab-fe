#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# CONTAINER ENTRYPOINT — Operon prediction (UniOP)
# Installed at /usr/local/bin/run inside the container.
#
# Pipeline-standard interface (single file):
#   run -i /input/org.faa -g /input/org.gff -o /output \
#       [-t THREADS] [--gram-stain {positive,negative,unknown}]
#       [--domain {Archaea,Bacteria,Eukaryota,Unknown}] [--organism-name NAME]
#
# Directory mode (process all organisms):
#   run -i /input/rasttk_output -o /output [-t THREADS]
#   Scans for .faa files recursively; derives sibling .gff automatically.
#   Skips organisms where the .gff sibling is absent.
#
# Two steps run inside the container per organism:
#   1. Pre-processing: convert RAST GFF3 + FAA → Prodigal-style FAA
#                      (convert_rast_output_to_uniop_input.py)
#   2. UniOP: -a <converted.faa> -t <raw_dir> --operon_flag True
#   3. Post-processing: join UniOP cluster indices back to RAST gene IDs
#                       (process_operon_raw_results.py)
#
# Output directory layout (under -o):
#   /output/<organism>/
#     ├── raw/
#     │     ├── uniop_input.faa     Prodigal-style FAA fed to UniOP
#     │     ├── uniop.pred          UniOP pairwise scores
#     │     ├── uniop.operon        UniOP cluster assignments (gene indices)
#     │     └── uniop.stderr        captured stderr
#     └── processed/
#           └── operon_results.tsv  normalised per-gene TSV (OPERON_ prefix)
# ═══════════════════════════════════════════════════════════════════════════════
set -euo pipefail
export PYTHONNOUSERSITE=1


# >>> wired: pipeline_log helper <<<
# Shared provenance-log helper (fixed in-container path).
# shellcheck source=/dev/null
source /opt/operon/scripts/pipeline_log.sh

usage() {
    cat <<'HELP_EOF'

Operon Prediction — UniOP (intergenic-distance probabilistic model)

USAGE (single file)
  run -i /input/organism.faa -g /input/organism.gff -o /output \
      [-t THREADS] [--gram-stain {positive,negative,unknown}]
      [--domain {Archaea,Bacteria,Eukaryota,Unknown}] [--organism-name NAME]

USAGE (directory — all organisms processed)
  run -i /input/rasttk_output -o /output [-t THREADS]
  Scans recursively for .faa files; the sibling .gff file must be co-located.
  --organism-name and --gram-stain are ignored in directory mode (derived per file).

REQUIRED MOUNTS
  /input/   RAST protein FASTA (.faa) or directory — read-only
  /output/  Output root — writable

REQUIRED OPTIONS
  -i FILE|DIR   RAST protein FASTA or input directory
  -o DIR        Output root directory (container creates <out>/<organism>/{raw,processed}/)

SINGLE-FILE ONLY
  -g FILE             RAST GFF3 annotation (required in single-file mode)

OPTIONAL OPTIONS
  -t INT              CPU threads                       [default: 4]
  --gram-stain STR    positive | negative | unknown     [default: auto-detect]
  --domain STR        Archaea | Bacteria | Eukaryota | Unknown   [default: auto-detect]
  --organism-name STR Override organism name (single-file mode only)
  --help, -h          Show this help and exit

OUTPUTS  (under <OUTPUT>/<organism>/)
  raw/uniop_input.faa         Prodigal-style FAA converted from RAST input
  raw/uniop.pred              UniOP pairwise operon prediction scores
  raw/uniop.operon            UniOP operon cluster assignments (gene indices)
  raw/uniop.stderr            Captured stderr
  processed/operon_results.tsv  Normalised per-gene operon TSV (OPERON_ prefix)

HELP_EOF
}

# ── Argument parsing ──────────────────────────────────────────────────────────
FAA=""
GFF=""
OUTPUT_ROOT=""
THREADS=4
GRAM_STAIN=""
DOMAIN=""
ORGANISM_NAME=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -i)              FAA="$2";            shift 2 ;;
        -g)              GFF="$2";            shift 2 ;;
        -o)              OUTPUT_ROOT="$2";    shift 2 ;;
        -t)              THREADS="$2";        shift 2 ;;
        --gram-stain)    GRAM_STAIN="$2";     shift 2 ;;
        --domain)        DOMAIN="$2";         shift 2 ;;
        --organism-name) ORGANISM_NAME="$2";  shift 2 ;;
        --help|-h)       usage; exit 0 ;;
        *) echo "[operon] ERROR: unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
done

[[ -z "$FAA"         ]] && { echo "[operon] ERROR: -i required"       >&2; exit 1; }
[[ -z "$OUTPUT_ROOT" ]] && { echo "[operon] ERROR: -o OUTPUT required" >&2; exit 1; }
[[ ! -e "$FAA"       ]] && { echo "[operon] ERROR: input not found: $FAA" >&2; exit 1; }

# ── Single-organism processing function ──────────────────────────────────────
# Args: <faa_path> <gff_path> <organism_name>
run_one() {
    local _faa="$1"
    local _gff="$2"
    local _org="$3"

    # Gram stain auto-detection from FAA filename tokens
    local _gram_stain="$GRAM_STAIN"
    local _domain="$DOMAIN"
    if [[ -z "$_gram_stain" || -z "$_domain" ]]; then
        local _stem_lower
        _stem_lower="$(basename "$_faa" | tr '[:upper:]' '[:lower:]')"
        case "$_stem_lower" in
            *_bact_gramn.*|*_bact_gramn) _gram_stain="${_gram_stain:-negative}"; _domain="${_domain:-Bacteria}" ;;
            *_bact_gramp.*|*_bact_gramp) _gram_stain="${_gram_stain:-positive}"; _domain="${_domain:-Bacteria}" ;;
            *_bact_gramu.*|*_bact_gramu) _gram_stain="${_gram_stain:-unknown}";  _domain="${_domain:-Bacteria}" ;;
            *_bact.*|*_bact)             _gram_stain="${_gram_stain:-unknown}";  _domain="${_domain:-Bacteria}" ;;
            *_gramn.*|*_gramn) _gram_stain="${_gram_stain:-negative}"; _domain="${_domain:-Bacteria}" ;;
            *_gramp.*|*_gramp) _gram_stain="${_gram_stain:-positive}"; _domain="${_domain:-Bacteria}" ;;
            *_archaea.*|*_archaea|*_arch.*|*_arch) _gram_stain="${_gram_stain:-unknown}"; _domain="${_domain:-Archaea}" ;;
            *_unknown.*|*_unknown) _gram_stain="${_gram_stain:-unknown}"; _domain="${_domain:-Unknown}" ;;
        esac
    fi

    # Domain auto-detection from FAA path hierarchy
    if [[ -z "$_domain" ]]; then
        local _path_lower
        _path_lower="$(printf '%s' "$_faa" | tr '[:upper:]' '[:lower:]')"
        case "$_path_lower" in
            */archaea/*)                                      _domain="Archaea"   ;;
            */gram-positive/*|*/gram-negative/*|*/bacteria/*) _domain="Bacteria"  ;;
            */eukaryota/*|*/eukaryote/*|*/eukaryotes/*)       _domain="Eukaryota" ;;
        esac
    fi
    _gram_stain="${_gram_stain:-unknown}"
    _domain="${_domain:-Unknown}"

    # Output directory layout
    local _out_dir="$OUTPUT_ROOT/$_org"
    local _raw_dir="$_out_dir/raw"
    local _proc_dir="$_out_dir/processed"
    mkdir -p "$_raw_dir" "$_proc_dir"

    # >>> wired: pipeline_log_init <<<
    local _log_path="$_out_dir/operon-pipeline-log.txt"
    export PIPELINE_LOG_GRAM_STAIN="${_gram_stain}"
    export PIPELINE_LOG_DOMAIN="${_domain}"
    pipeline_log_init operon "${_org}" "$_out_dir" "$_log_path"

    pipeline_log_section "INPUTS"
    pipeline_log_kv_path "Input FAA"  "${_faa}"
    pipeline_log_kv_path "Input GFF"  "${_gff}"
    pipeline_log_kv      "Threads"    "${THREADS}"

    local _converted_faa="$_raw_dir/uniop_input.faa"
    local _raw_pred="$_raw_dir/uniop.pred"
    local _raw_operon="$_raw_dir/uniop.operon"
    local _raw_err="$_raw_dir/uniop.stderr"
    local _proc_tsv="$_proc_dir/operon_results.tsv"

    local _uniop_cmd="python3 $UNIOP_HOME/src/UniOP -a $_converted_faa -t $_raw_dir --operon_flag True"
    local _method="UniOP adjacent-gene pairwise model; OPERON_probability is geometric mean across adjacent links."

    echo "[operon] Input FAA:    $_faa"
    echo "[operon] Input GFF:    $_gff"
    echo "[operon] Organism:     $_org"
    echo "[operon] Output root:  $_out_dir"
    echo "[operon] Threads:      $THREADS"

    # ── Step 1: pre-processing — RAST → Prodigal-style FAA ──────────────────
    if [[ -s "$_converted_faa" ]]; then
        echo "[operon] Converted FAA already exists, skipping conversion"
    else
        echo "[operon] Step 1/3: Converting RAST GFF3 + FAA → Prodigal-style FAA ..."
        python3 /opt/operon/scripts/convert_rast_output_to_uniop_input.py \
            "$_gff" "$_faa" "$_converted_faa"
    fi
    local _gene_count
    _gene_count="$(grep -c '^>' "$_converted_faa" 2>/dev/null || echo 0)"
    echo "[operon] Converted FAA contains $_gene_count genes"

    # ── Step 2: UniOP ────────────────────────────────────────────────────────
    if [[ -s "$_raw_operon" ]]; then
        echo "[operon] Step 2/3: Raw UniOP output exists ($_raw_operon), skipping"
    else
        echo "[operon] Step 2/3: Running UniOP ..."
        python3 "$UNIOP_HOME/src/UniOP" \
            -a "$_converted_faa" \
            -t "$_raw_dir" \
            --operon_flag True \
            2> "$_raw_err"
    fi

    for _ep in "$_raw_pred" "$_raw_operon"; do
        if [[ ! -f "$_ep" ]]; then
            echo "[operon] ERROR: expected UniOP output not found: $_ep" >&2
            return 1
        fi
    done

    # ── Step 3: post-processing ──────────────────────────────────────────────
    local _pred_flag=""
    [[ -f "$_raw_pred" ]] && _pred_flag="--input-pred $_raw_pred"

    run_postprocess() {
        python3 /opt/operon/scripts/process_operon_raw_results.py \
            --input-faa     "$_converted_faa" \
            --input-operon  "$_raw_operon" \
            $_pred_flag \
            --output        "$_proc_tsv" \
            --organism-name "$_org" \
            --gram-stain    "$_gram_stain" \
            --command-used  "$_uniop_cmd" \
            --tool-used     "https://github.com/hongsua/UniOP" \
            --method-used   "$_method" \
            --input-path    "$_faa" \
            --output-path   "$_out_dir"
    }
    echo "[operon] Step 3/3: Post-processing UniOP output → $_proc_tsv ..."
    pipeline_log_step "post-process → processed/operon_results.tsv" run_postprocess
    pipeline_log_kv_path "Processed TSV" "$_proc_tsv"

    # >>> wired: pipeline_log_close <<<
    pipeline_log_inject_domain_column "$_proc_tsv"
    pipeline_log_close

    echo "[operon] Done: $_org"
    echo "  raw/       : $_raw_dir"
    echo "  processed/ : $_proc_dir"
}

# ── Main dispatch ─────────────────────────────────────────────────────────────
if [[ -d "$FAA" ]]; then
    declare -A _seen=()
    mapfile -t _faas < <(find -L "$FAA" -type f -name '*.faa' | sort)
    (( ${#_faas[@]} )) || { echo "[operon] ERROR: no .faa files found under $FAA" >&2; exit 1; }
    _ok=0; _fail=0; _total="${#_faas[@]}"
    for _i in "${!_faas[@]}"; do
        _faa="${_faas[$_i]}"
        _parent="$(dirname "$_faa")"
        [[ "$(basename "$_parent")" == "gene_calls" ]] && _parent="$(dirname "$_parent")"
        _org="$(basename "$_parent")"
        [[ -n "${_seen[$_org]+x}" ]] && continue
        _seen[$_org]=1
        # Derive sibling GFF — same stem as FAA, same directory
        _gff="${_faa%.faa}.gff"
        if [[ ! -f "$_gff" ]]; then
            echo "[operon] WARN: no sibling GFF for $_faa — skipping $_org" >&2
            _fail=$(( _fail + 1 ))
            continue
        fi
        echo "[$((  _i + 1 ))/$_total] Processing: $_org"
        if run_one "$_faa" "$_gff" "$_org"; then _ok=$(( _ok + 1 ))
        else                                      _fail=$(( _fail + 1 )); fi
    done
    echo "[operon] Batch complete: success=$_ok  failed=$_fail"
    (( _fail == 0 )) || exit 2
else
    # Single-file mode: GFF is required
    if [[ -z "$GFF" || -z "$FAA" ]]; then
        echo "[operon] ERROR: -i FAA, -g GFF, and -o OUTPUT are all required in single-file mode" >&2
        usage >&2; exit 1
    fi
    [[ ! -f "$FAA" ]] && { echo "[operon] ERROR: FAA not found: $FAA" >&2; exit 1; }
    [[ ! -f "$GFF" ]] && { echo "[operon] ERROR: GFF not found: $GFF" >&2; exit 1; }
    _org="${ORGANISM_NAME:-$(basename "${FAA%.*}")}"
    run_one "$FAA" "$GFF" "$_org"
fi
