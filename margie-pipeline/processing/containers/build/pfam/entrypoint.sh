#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# CONTAINER ENTRYPOINT — Pfam (HMMER hmmscan against Pfam-A)
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
#     ├── pfam-pipeline-log.txt   ← structured provenance log
#     ├── raw/
#     │     ├── pfam_domtbl.out   ← untouched hmmscan --domtblout
#     │     └── pfam.log          ← hmmscan stdout+stderr
#     └── processed/
#           ├── pfam_results.tsv  ← normalised TSV, one row per domain hit
# ══════════════════════════════════════════════════════════════════════════════════════════════════
set -euo pipefail

# Shared provenance-log helper. Lives at a fixed path inside the container.
# shellcheck source=/dev/null
source /opt/pfam/scripts/pipeline_log.sh

usage() {
    cat <<'HELP_EOF'

Pfam — Protein domain annotation via HMMER hmmscan against Pfam-A

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
  /db/      Pfam database dir containing Pfam-A.hmm + .h3* index files

REQUIRED OPTIONS
  -i FILE|DIR   Protein FASTA input file or input directory (inside container)
  -o DIR        Output root directory   (inside container, usually /output)
  -d DIR        Pfam database directory (inside container, usually /db)

OPTIONAL OPTIONS
  -t INT              CPU threads                              [default: 1]
  --domain STR        Archaea | Bacteria | Eukaryota | Unknown   [default: auto-detect]
  --organism-name STR Override organism name (single-file mode only)
  --help, -h          Show this help and exit

OUTPUTS  (under <OUTPUT>/<organism>/)
  pfam-pipeline-log.txt     structured provenance log
  raw/pfam_domtbl.out       hmmscan domain-table (untouched)
  raw/pfam.log              hmmscan log
  processed/pfam_results.tsv normalised TSV — one row per domain hit

THRESHOLD
  Uses Pfam curated gathering thresholds (--cut_ga). Per-family bit-score
  cutoffs set by Pfam curators. No arbitrary e-value cutoff needed.

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
        -i)               INPUT="$2";          shift 2 ;;
        -o)               OUTPUT_ROOT="$2";    shift 2 ;;
        -d)               DBDIR="$2";          shift 2 ;;
        -t)               THREADS="$2";        shift 2 ;;
        --domain)         DOMAIN="$2";         shift 2 ;;
        --organism-name)  ORGANISM_NAME="$2";  shift 2 ;;
        --help|-h)        usage; exit 0 ;;
        *) echo "[pfam] ERROR: unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

if [[ -z "$INPUT" || -z "$OUTPUT_ROOT" || -z "$DBDIR" ]]; then
    echo "[pfam] ERROR: -i INPUT, -o OUTPUT, and -d DBDIR are required" >&2
    usage
    exit 1
fi

[[ ! -e "$INPUT" ]] && { echo "[pfam] ERROR: input not found: $INPUT" >&2; exit 1; }

HMM="$DBDIR/Pfam-A.hmm"
if [[ ! -f "$HMM" ]]; then
    echo "[pfam] ERROR: Pfam-A.hmm not found in $DBDIR" >&2
    exit 1
fi

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
            echo "[pfam] Auto-detected --domain ${_domain} from ${_detected_from}"
    fi

    # Output directory layout
    local _out_dir="$OUTPUT_ROOT/$_org"
    local _raw_dir="$_out_dir/raw"
    local _proc_dir="$_out_dir/processed"
    mkdir -p "$_raw_dir" "$_proc_dir"

    local _host_input_path _host_output_path _host_db_path
    _host_input_path="$(resolve_host_path "$_faa")"
    _host_output_path="$(resolve_host_path "$_out_dir")"
    _host_db_path="$(resolve_host_path "$DBDIR")"

    local _raw_domtbl="$_raw_dir/pfam_domtbl.out"
    local _raw_log="$_raw_dir/pfam.log"
    local _proc_tsv="$_proc_dir/pfam_results.tsv"

    # ── Threshold used (kept in a variable so we can pass the exact text to
    #    the processor, which records it in the PFAM_threshold_considered col)
    local _threshold_considered="--cut_ga"

    # ── Exact command we are about to run (recorded for provenance) ──────────
    local _hmmscan_command="hmmscan ${_threshold_considered} --nobias --F1 0.005 --F2 1e-5 --domtblout ${_raw_domtbl} --noali --cpu ${THREADS} ${HMM} ${_faa}"
    local _tool_used="HMMER hmmscan 3.4"
    local _database_used="Pfam-A 37.0 | Source: https://ftp.ebi.ac.uk/pub/databases/Pfam/releases/Pfam37.0/ | path(container): ${HMM}"

    # ── Initialise the provenance log ────────────────────────────────────────
    local _log_path="$_out_dir/pfam-pipeline-log.txt"
    export PIPELINE_LOG_TOOL_VERSION="$(hmmscan -h 2>/dev/null | awk '/^# HMMER/ {print $3; exit}') (Pfam-A in $DBDIR)"
    export PIPELINE_LOG_DOMAIN="${_domain}"
    export PIPELINE_LOG_OPERATOR="${USER:-${LOGNAME:-unknown}}"
    pipeline_log_init pfam "$_org" "$_out_dir" "$_log_path"
    pipeline_log_legal_preamble

    pipeline_log_section "INPUTS"
    pipeline_log_kv      "Tool"          "$_tool_used"
    pipeline_log_kv_path "Input"         "$_faa"
    pipeline_log_kv_path "Input (host)"  "$_host_input_path"
    pipeline_log_kv_path "Database"      "$DBDIR"
    pipeline_log_kv_path "Database (host)" "$_host_db_path"
    pipeline_log_kv_path "Output"        "$_out_dir"
    pipeline_log_kv_path "Output (host)" "$_host_output_path"
    pipeline_log_kv      "Threads"       "$THREADS"
    pipeline_log_kv      "Threshold"     "$_threshold_considered"

    # ── Idempotency: skip the heavy hmmscan step if raw output already exists ─
    if [[ -s "$_raw_domtbl" ]]; then
        echo "[pfam] Raw output already exists ($_raw_domtbl), skipping hmmscan (delete manually to re-run)"
        pipeline_log_section "hmmscan vs Pfam-A"
        pipeline_log_kv "Command"     "$_hmmscan_command"
        pipeline_log_kv "Elapsed (s)" "0"
        pipeline_log_kv "Status"      "SKIPPED (raw output already present)"
    else
        echo "[pfam] Running hmmscan with $THREADS threads ($_threshold_considered --nobias --F1 0.005 --F2 1e-5)..."
        pipeline_log_section "hmmscan vs Pfam-A"
        pipeline_log_kv "Command" "$_hmmscan_command"
        local _hmmscan_start _hmmscan_end _hmmscan_rc
        _hmmscan_start="$(date +%s)"
        set +e
        hmmscan \
            $_threshold_considered \
            --nobias \
            --F1 0.005 \
            --F2 1e-5 \
            --domtblout "$_raw_domtbl" \
            --noali \
            --cpu "$THREADS" \
            "$HMM" \
            "$_faa" \
            > "$_raw_log" 2>&1
        _hmmscan_rc=$?
        set -e
        _hmmscan_end="$(date +%s)"
        pipeline_log_kv "Elapsed (s)" "$(( _hmmscan_end - _hmmscan_start ))"
        pipeline_log_kv      "Exit code"   "$_hmmscan_rc"
        pipeline_log_kv_path "Raw log"     "$_raw_log"
        pipeline_log_kv_path "Raw domtbl"  "$_raw_domtbl"
        if [[ "$_hmmscan_rc" -ne 0 ]]; then
            pipeline_log_kv "Status" "FAILED"
            pipeline_log_close "FAILED at hmmscan"
            return "$_hmmscan_rc"
        fi
    fi

    # ── Post-process raw hmmscan output into the normalised TSV(s) ───────────
    run_postprocess() {
        python3 /opt/pfam/scripts/process_pfam_raw_results.py \
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
    echo "[pfam] Post-processing $_raw_domtbl ..."
    pipeline_log_step "post-process domtbl -> processed/pfam_results.tsv" run_postprocess

    pipeline_log_close

    echo "[pfam] Done: $_org"
    echo "  raw/       : $_raw_dir"
    echo "  processed/ : $_proc_dir"
    echo "  log        : $_log_path"
}

# ── Main dispatch ─────────────────────────────────────────────────────────────
if [[ -d "$INPUT" ]]; then
    declare -A _seen=()
    mapfile -t _faas < <(find -L "$INPUT" -type f -name '*.faa' | sort)
    (( ${#_faas[@]} )) || { echo "[pfam] ERROR: no .faa files found under $INPUT" >&2; exit 1; }
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
    echo "[pfam] Batch complete: success=$_ok  failed=$_fail"
    (( _fail == 0 )) || exit 2
else
    run_one "$INPUT" "${ORGANISM_NAME:-$(basename "${INPUT%.*}")}"
fi
