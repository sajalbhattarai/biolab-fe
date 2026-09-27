#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# CONTAINER ENTRYPOINT — COG / COGclassifier v2 (functional category annotation)
# Installed at /usr/local/bin/run inside the container.
#
# Pipeline-standard interface (single file):
#   run -i /input/organism.faa -o /output -d /db [-t THREADS] [-e EVALUE]
#       [--organism-name NAME] [--domain D]
#
# Directory mode (process all organisms under a directory):
#   run -i /input/rasttk_output -o /output -d /db [-t THREADS] [-e EVALUE]
#   All .faa files found recursively are processed; --organism-name is ignored.
#
# Output directory layout (under -o):
#   /output/<organism>/
#     ├── raw/
#     │     ├── rpsblast.tsv                Raw RPS-BLAST tabular results
#     │     ├── cog_classify.tsv            COGclassifier per-protein TSV
#     │     ├── cog_count.tsv               Per-category counts
#     │     ├── cog_count_barchart.{png,html}
#     │     ├── cog_count_piechart.{png,html}
#     │     ├── cogclassifier.log
#     │     └── cog.stderr                  captured stderr
#     └── processed/
#           ├── cog_results.tsv             one row per protein (COG_ prefix)
# ═══════════════════════════════════════════════════════════════════════════════
set -euo pipefail


# >>> wired: detailed-step <<<
# >>> wired: pipeline_log helper <<<
# Shared provenance-log helper (fixed in-container path).
# shellcheck source=/dev/null
source /opt/cog/scripts/pipeline_log.sh

usage() {
    cat <<'HELP_EOF'

COG — Functional category annotation via COGclassifier v2 (RPS-BLAST + CDD lookup)

USAGE (single file)
  run -i /input/organism.faa -o /output -d /db \
    [-t THREADS] [-e EVALUE] [--organism-name NAME] [--domain {Archaea,Bacteria,Eukaryota,Unknown}]

USAGE (directory — all organisms processed)
  run -i /input/rasttk_output -o /output -d /db [-t THREADS] [-e EVALUE]
  All .faa files found recursively under -i are processed.
  --organism-name is ignored in directory mode (derived per file).

REQUIRED MOUNTS
  /input/   Protein FASTA (.faa) or directory containing .faa files — read-only
  /output/  Output root — writable
  /db/      COG database directory (must contain cddid.tbl and Cog_LE/)

REQUIRED OPTIONS
  -i FILE|DIR   Protein FASTA input file or input directory
  -o DIR        Output root directory (container creates <out>/<organism>/{raw,processed}/)
  -d DIR        COG database directory

OPTIONAL OPTIONS
  -t INT              CPU threads                       [default: 1]
  -e FLOAT            RPS-BLAST e-value cutoff          [default: 1e-2]
  --organism-name STR Override organism name (single-file mode only)
  --domain STR        Archaea | Bacteria | Eukaryota | Unknown   [default: auto-detect from path]
                      (recorded for provenance; does not affect COG inference)
  --help, -h          Show this help and exit

OUTPUTS  (under <OUTPUT>/<organism>/)
  raw/rpsblast.tsv               Raw RPS-BLAST tabular hits
  raw/cog_classify.tsv           Per-protein COG annotation (untouched)
  raw/cog_count.tsv              Per-category protein counts (untouched)
  raw/cog_count_*.{png,html}     Bar / pie chart visualisations
  raw/cogclassifier.log          Full run log
  raw/cog.stderr                 Captured stderr
  processed/cog_results.tsv      Normalised per-protein TSV

HELP_EOF
}

# ── Argument parsing ──────────────────────────────────────────────────────────
INPUT=""
OUTPUT_ROOT=""
DBDIR=""
THREADS=1
EVALUE="1e-2"
ORGANISM_NAME=""
DOMAIN=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -i)                INPUT="$2";          shift 2 ;;
        -o)                OUTPUT_ROOT="$2";    shift 2 ;;
        -d)                DBDIR="$2";          shift 2 ;;
        -t)                THREADS="$2";        shift 2 ;;
        -e)                EVALUE="$2";          shift 2 ;;
        --organism-name)   ORGANISM_NAME="$2";  shift 2 ;;
        --domain)          DOMAIN="$2";         shift 2 ;;
        --help|-h)         usage; exit 0 ;;
        *) echo "[cog] ERROR: unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
done

[[ -z "$INPUT"       ]] && { echo "[cog] ERROR: -i INPUT required"  >&2; exit 1; }
[[ -z "$OUTPUT_ROOT" ]] && { echo "[cog] ERROR: -o OUTPUT required" >&2; exit 1; }
[[ -z "$DBDIR"       ]] && { echo "[cog] ERROR: -d DBDIR required"  >&2; exit 1; }
[[ ! -e "$INPUT"     ]] && { echo "[cog] ERROR: input not found: $INPUT" >&2; exit 1; }
[[ ! -f "$DBDIR/cddid.tbl" ]] && { echo "[cog] ERROR: cddid.tbl not found in $DBDIR" >&2; exit 1; }
[[ ! -d "$DBDIR/Cog_LE"    ]] && { echo "[cog] ERROR: Cog_LE/ not found in $DBDIR"   >&2; exit 1; }

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
            echo "[cog] Auto-detected --domain ${_domain} from ${_detected_from}"
    fi

    # Output directory layout
    local _out_dir="$OUTPUT_ROOT/$_org"
    local _raw_dir="$_out_dir/raw"
    local _proc_dir="$_out_dir/processed"
    mkdir -p "$_raw_dir" "$_proc_dir"

    # Resolve host paths
    local _host_input_path _host_output_path _host_db_path
    _host_input_path="$(resolve_host_path "$_faa")"
    _host_output_path="$(resolve_host_path "$_out_dir")"
    _host_db_path="$(resolve_host_path "$DBDIR")"

    # >>> wired: pipeline_log_init <<<
    local _log_path="$_out_dir/cog-pipeline-log.txt"
    export PIPELINE_LOG_DOMAIN="${_domain}"
    export PIPELINE_LOG_OPERATOR="${USER:-${LOGNAME:-unknown}}"
    pipeline_log_init cog "${_org}" "$_out_dir" "$_log_path"
    pipeline_log_legal_preamble

    pipeline_log_section "INPUTS"
    pipeline_log_kv      "Tool"     "COGclassifier 2.0.0 (https://github.com/moshi4/COGclassifier) | NCBI BLAST+ 2.16.0"
    pipeline_log_kv_path "Input"    "${_faa}"
    pipeline_log_kv_path "Input (host)" "${_host_input_path}"
    pipeline_log_kv_path "Database" "${DBDIR}"
    pipeline_log_kv_path "Database (host)" "${_host_db_path}"
    pipeline_log_kv_path "Output (host)" "${_host_output_path}"
    pipeline_log_kv      "Threads"  "${THREADS:-1}"
    pipeline_log_kv      "E-value"  "${EVALUE}"

    local _raw_classify="$_raw_dir/cog_classify.tsv"
    local _raw_err="$_raw_dir/cog.stderr"
    local _proc_tsv="$_proc_dir/cog_results.tsv"

    # ── Exact command summary for output provenance ───────────────────────────
    local _evalue_for_command="$EVALUE"
    if [[ "$EVALUE" == "1e-2" || "$EVALUE" == "1E-2" ]]; then
        _evalue_for_command="0.01"
    fi
    local _cog_command="COGclassifier -i <input-faa-file-path> -o <output-folder-path> -d <database-path> -t ${THREADS} -e ${_evalue_for_command}"

    echo "[cog] Input:        $_faa ($_org)"
    echo "[cog] Input host:   $_host_input_path"
    echo "[cog] DB dir:       $DBDIR"
    echo "[cog] DB host:      $_host_db_path"
    echo "[cog] Output root:  $_out_dir"
    echo "[cog] Output host:  $_host_output_path"
    echo "[cog] Threads:      $THREADS"
    echo "[cog] E-value:      $EVALUE"

    # ── Idempotency: skip COGclassifier if classify.tsv already exists ────────
    if [[ -s "$_raw_classify" ]]; then
        echo "[cog] Raw output already exists ($_raw_classify), skipping COGclassifier (delete manually to re-run)"
        pipeline_log_skipped "COGclassifier run" "$_cog_command" "raw output already present"
    else
        echo "[cog] Running COGclassifier ..."
        pipeline_log_run_logged "COGclassifier run" "" "$_raw_err" \
            COGclassifier \
                -i "$_faa" \
                -o "$_raw_dir" \
                -d "$DBDIR" \
                -t "$THREADS" \
                -e "$EVALUE"
        pipeline_log_kv_path "Raw classify output" "$_raw_classify"
    fi

    # ── Provenance metadata strings for processed TSV ──────────────────────────
    local _cog_tool_used="COGclassifier 2.0.0 (https://github.com/moshi4/COGclassifier) | Uses: NCBI BLAST+ 2.16.0 (https://ftp.ncbi.nlm.nih.gov/blast/executables/blast+/2.16.0/)"
    local _cog_database_info="NCBI COG 2024 | Source: https://ftp.ncbi.nlm.nih.gov/pub/COG/COG2024/data/ | Files used (host): ${_host_db_path}/cddid.tbl (COG ID-to-function metadata map), ${_host_db_path}/Cog_LE/ (RPS-BLAST CDD profiles) | path(container): ${DBDIR}/cddid.tbl, ${DBDIR}/Cog_LE/"

    # ── Post-process cog_classify.tsv → normalised per-protein TSV ─────────────
    run_postprocess() {
        python3 - "$_raw_classify" "$_proc_tsv" "$_org" "$_domain" "$_cog_tool_used" "$_cog_command" "$_cog_database_info" "$EVALUE" "$_host_input_path" "$_host_output_path" <<'PY_EOF'
import csv
import sys
from pathlib import Path

input_path = Path(sys.argv[1])
output_path = Path(sys.argv[2])
organism_name = sys.argv[3]
domain = sys.argv[4]
tool_used = sys.argv[5]
command_used = sys.argv[6]
database_used = sys.argv[7]
evalue_threshold = sys.argv[8]
input_host_path = sys.argv[9]
output_host_path = sys.argv[10]

if not input_path.exists():
    print(f"[process_cog] ERROR: input not found: {input_path}", file=sys.stderr)
    raise SystemExit(1)

with input_path.open() as handle:
    header = handle.readline().rstrip("\n")
    if not header:
        records = []
    else:
        cols = [c.strip().upper() for c in header.split("\t")]
        def idx(*names):
            for n in names:
                if n.upper() in cols:
                    return cols.index(n.upper())
            return -1

        i_query = idx("QUERY_ID", "QUERY")
        i_cog = idx("COG_ID")
        i_cdd = idx("CDD_ID")
        i_eval = idx("EVALUE", "E_VALUE", "E-VALUE")
        i_ident = idx("IDENTITY", "%IDENTITY", "PIDENT")
        i_gene = idx("GENE_NAME", "GENE")
        i_name = idx("COG_NAME")
        i_func_l = idx("COG_FUNC_LETTER", "FUNC_LETTER", "COG_LETTER", "LETTER")
        i_func_d = idx("COG_FUNC_DESC", "FUNC_DESC", "COG_DESCRIPTION", "DESCRIPTION")

        if i_query < 0:
            print("[process_cog] WARNING: could not find QUERY_ID column in cog_classify.tsv", file=sys.stderr)
            records = []
        else:
            def safe(row, i):
                if i < 0 or i >= len(row):
                    return ""
                return row[i].strip()

            def safe_float(s):
                if s in ("", ".", "-"):
                    return 0.0
                try:
                    return float(s)
                except ValueError:
                    return 0.0

            records = []
            for raw in handle:
                row = raw.rstrip("\n")
                if not row:
                    continue
                parts = row.split("\t")
                feature_id = safe(parts, i_query)
                if not feature_id:
                    continue
                records.append((
                    feature_id,
                    safe(parts, i_cog),
                    safe(parts, i_cdd),
                    safe(parts, i_name),
                    safe(parts, i_func_d),
                    safe(parts, i_gene),
                    safe_float(safe(parts, i_eval)),
                    safe_float(safe(parts, i_ident)),
                    safe(parts, i_func_l),
                ))

records.sort(key=lambda x: x[0])
output_path.parent.mkdir(parents=True, exist_ok=True)

header = [
    "organism_name", "domain", "feature_id",
    "COG_id", "COG_cdd_id",
    "COG_description", "COG_function_description",
    "COG_gene_name", "COG_evalue", "COG_identity",
    "COG_func_letter",
    "COG_tool_used",
    "COG_command_used", "COG_database_used", "COG_evalue_threshold_used",
    "input_path", "output_path",
]

with output_path.open("w", newline="") as out:
    writer = csv.writer(out, delimiter="\t")
    writer.writerow(header)
    for rec in records:
        writer.writerow([
            organism_name, domain, rec[0],
            rec[1], rec[2],
            rec[3], rec[4],
            rec[5], f"{rec[6]:.3e}", f"{rec[7]:.4f}",
            rec[8],
            tool_used,
            command_used, database_used, evalue_threshold,
            input_host_path, output_host_path,
        ])

print(f"[process_cog] Wrote {len(records)} rows -> {output_path}")
PY_EOF
    }
    echo "[cog] Post-processing $_raw_classify ..."
    pipeline_log_step "post-process -> processed/cog_results.tsv" run_postprocess
    pipeline_log_kv_path "Processed TSV" "$_proc_tsv"

    # >>> wired: pipeline_log_close <<<
    pipeline_log_close

    echo "[cog] Done: $_org"
    echo "  raw/       : $_raw_dir"
    echo "  processed/ : $_proc_dir"
}

# ── host-path resolution helpers ─────────────────────────────────────────────
decode_mountinfo_field() {
    local raw="$1"
    raw="${raw//\\040/ }"
    raw="${raw//\\011/$'\t'}"
    raw="${raw//\\012/$'\n'}"
    raw="${raw//\\134/\\}"
    printf '%s' "$raw"
}

resolve_from_bind_env() {
    local container_path="$1"
    local binds_csv="$2"
    local IFS=','
    local spec src dest opts
    local best_src=""
    local best_dest=""
    local best_len=0

    [[ -n "$binds_csv" ]] || return 1

    for spec in $binds_csv; do
        spec="${spec# }"
        spec="${spec% }"
        [[ -n "$spec" ]] || continue

        # Source-less entries like "/input,/output,/db" carry no host-path
        # information; skip them and let mountinfo-based reconstruction handle it.
        [[ "$spec" == *:* ]] || continue

        src="${spec%%:*}"
        if [[ "$spec" == *:* ]]; then
            dest="${spec#*:}"
            if [[ "$dest" == *:* ]]; then
                opts="${dest#*:}"
                dest="${dest%%:*}"
            else
                opts=""
            fi
        else
            dest="$src"
            opts=""
        fi

        [[ "$src" == /* && "$dest" == /* ]] || continue

        if [[ "$container_path" == "$dest" || "$container_path" == "$dest/"* ]]; then
            if (( ${#dest} > best_len )); then
                best_src="$src"
                best_dest="$dest"
                best_len=${#dest}
            fi
        fi
    done

    if [[ -n "$best_dest" ]]; then
        local suffix="${container_path#"$best_dest"}"
        if [[ -z "$suffix" ]]; then
            printf '%s\n' "$best_src"
        else
            printf '%s%s\n' "$best_src" "$suffix"
        fi
        return 0
    fi
    return 1
}

resolve_host_path() {
    local container_path="$1"
    local bind_source

    case "$container_path" in
        /input)    [[ -n "${PIPELINE_HOST_INPUT:-}"  ]] && { printf '%s\n' "$PIPELINE_HOST_INPUT"; return 0; } ;;
        /input/*)  [[ -n "${PIPELINE_HOST_INPUT:-}"  ]] && { printf '%s%s\n' "$PIPELINE_HOST_INPUT" "${container_path#/input}"; return 0; } ;;
        /output)   [[ -n "${PIPELINE_HOST_OUTPUT:-}" ]] && { printf '%s\n' "$PIPELINE_HOST_OUTPUT"; return 0; } ;;
        /output/*) [[ -n "${PIPELINE_HOST_OUTPUT:-}" ]] && { printf '%s%s\n' "$PIPELINE_HOST_OUTPUT" "${container_path#/output}"; return 0; } ;;
        /db)       [[ -n "${PIPELINE_HOST_DB:-}"     ]] && { printf '%s\n' "$PIPELINE_HOST_DB"; return 0; } ;;
        /db/*)     [[ -n "${PIPELINE_HOST_DB:-}"     ]] && { printf '%s%s\n' "$PIPELINE_HOST_DB" "${container_path#/db}"; return 0; } ;;
    esac

    bind_source="${APPTAINER_BIND:-${APPTAINER_BINDPATH:-${SINGULARITY_BINDPATH:-}}}"
    if resolve_from_bind_env "$container_path" "$bind_source"; then
        return 0
    fi

    local best_mount=""
    local best_source=""
    local best_len=0
    local line left right root_raw mp_raw src_raw
    local root_path mount_point source source_base

    while IFS= read -r line; do
        [[ "$line" == *" - "* ]] || continue
        left="${line%% - *}"
        right="${line#* - }"

        root_raw="$(printf '%s' "$left" | awk '{print $4}')"
        mp_raw="$(printf '%s' "$left" | awk '{print $5}')"
        src_raw="$(printf '%s' "$right" | awk '{print $2}')"
        [[ -n "$root_raw" && -n "$mp_raw" && -n "$src_raw" ]] || continue

        root_path="$(decode_mountinfo_field "$root_raw")"
        mount_point="$(decode_mountinfo_field "$mp_raw")"
        source="$(decode_mountinfo_field "$src_raw")"

        if [[ "$source" == /* ]]; then
            if [[ "$root_path" == "/" ]]; then
                source_base="$source"
            else
                source_base="${source%/}${root_path}"
            fi
        elif [[ "$source" == *:/* ]]; then
            # Filesystems like Lustre may expose source as "host:/mountroot".
            local fs_root="${source##*:}"
            if [[ "$root_path" == "/" ]]; then
                source_base="$fs_root"
            else
                source_base="${fs_root%/}${root_path}"
            fi
        else
            continue
        fi

        if [[ "$container_path" == "$mount_point" || "$container_path" == "$mount_point/"* ]]; then
            if (( ${#mount_point} > best_len )); then
                best_mount="$mount_point"
                best_source="$source_base"
                best_len=${#mount_point}
            fi
        fi
    done < /proc/self/mountinfo

    if [[ -n "$best_mount" ]]; then
        local suffix="${container_path#"$best_mount"}"
        if [[ -z "$suffix" ]]; then
            printf '%s\n' "$best_source"
        else
            printf '%s%s\n' "$best_source" "$suffix"
        fi
    else
        printf '%s\n' "$container_path"
    fi
}

# ── Main dispatch ─────────────────────────────────────────────────────────────
if [[ -d "$INPUT" ]]; then
    declare -A _seen=()
    mapfile -t _faas < <(find -L "$INPUT" -type f -name '*.faa' | sort)
    (( ${#_faas[@]} )) || { echo "[cog] ERROR: no .faa files found under $INPUT" >&2; exit 1; }
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
    echo "[cog] Batch complete: success=$_ok  failed=$_fail"
    (( _fail == 0 )) || exit 2
else
    run_one "$INPUT" "${ORGANISM_NAME:-$(basename "${INPUT%.*}")}"
fi
