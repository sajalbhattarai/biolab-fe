#!/usr/bin/env bash
# setup-databases/lib.sh — shared helpers for the download-<db>.sh scripts:
# argument parsing, dry-run wrapper, curl-backed wget shim, skip checks, container runner.
set -euo pipefail

HERE_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT_DB="$(cd "$HERE_LIB/../../../.." && pwd)"
# shellcheck disable=SC1091
source "$REPO_ROOT_DB/pipeline.conf.sh"
# shellcheck disable=SC1091
source "$REPO_ROOT_DB/processing/scripts/shared/colors.sh"
# shellcheck disable=SC1091
source "$REPO_ROOT_DB/processing/scripts/shared/runtime.sh"
# shellcheck disable=SC1091
: "${LOG_DIR:=$REPO_ROOT_DB/logs/databases}"
# shellcheck disable=SC1091
source "$REPO_ROOT_DB/processing/scripts/shared/logging.sh"
# shellcheck disable=SC1091
source "$REPO_ROOT_DB/processing/scripts/shared/licence-gate.sh"
# shellcheck disable=SC1091
source "$REPO_ROOT_DB/processing/scripts/shared/license-agreement.sh"
log_invocation "$0" "$@"
# Asks for the pipeline licence agreement; a no-op when MARGIE_ACCEPT_TERMS=1.
pipeline_licence_agreement "" || exit 1

# Parses --redo / --dry-run / --db-dir <path>; leaves other args intact.
DB_REDO=0
DB_DRYRUN=0
db_parse_args() {
    local -a leftover=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --redo)                  DB_REDO=1; shift ;;
            --dry-run)               DB_DRYRUN=1; shift ;;
            --db-dir)                DB_ROOT="$2"; shift 2 ;;
            --hf-token-file)         export HF_TOKEN_FILE="$2"; shift 2 ;;
            --reset-hf-token)        export HF_RESET=1; shift ;;
            --accept-merops-licence|--accept-merops-license)
                                     export MEROPS_ACCEPT_LICENCE=1; shift ;;
            --accept-tcdb-licence|--accept-tcdb-license)
                                     export TCDB_ACCEPT_LICENCE=1; shift ;;
            --accept-tmbed-licence|--accept-tmbed-license)
                                     export TMBED_ACCEPT_LICENCE=1; shift ;;
            --accept-interpro-licence|--accept-interpro-license)
                                     export INTERPRO_ACCEPT_LICENCE=1; shift ;;
            --accept-all-licences|--accept-all-licenses)
                                     export LICENCE_ACCEPT_ALL=1
                                     export MEROPS_ACCEPT_LICENCE=1
                                     export TCDB_ACCEPT_LICENCE=1
                                     export TMBED_ACCEPT_LICENCE=1
                                     export INTERPRO_ACCEPT_LICENCE=1
                                     shift ;;
            *)                       leftover+=("$1"); shift ;;
        esac
    done
    REMAINING=("${leftover[@]+"${leftover[@]+"${leftover[@]}"}"}")
}

# Runs a command, or only prints it under --dry-run.
run() {
    if (( DB_DRYRUN )); then
        echo "  [dry-run] $*"
    else
        "$@"
    fi
}

# Defines a curl-backed wget shim when wget is absent; supports
# -q, -c, -qc/-cq, --show-progress, -P <dir>, -O <file>.
if ! command -v wget >/dev/null 2>&1; then
    if ! command -v curl >/dev/null 2>&1; then
        echo "lib.sh: neither wget nor curl is installed; cannot fetch databases" >&2
        return 1 2>/dev/null || exit 1
    fi
    wget() {
        local quiet=0 resume=0 show_progress=0
        local prefix="" outfile=""
        local -a urls=()
        while [[ $# -gt 0 ]]; do
            case "$1" in
                -q)              quiet=1; shift ;;
                -c)              resume=1; shift ;;
                -qc|-cq)         quiet=1; resume=1; shift ;;
                --show-progress) show_progress=1; shift ;;
                -P)              prefix="$2"; shift 2 ;;
                -O)              outfile="$2"; shift 2 ;;
                --)              shift; urls+=("$@"); break ;;
                -*)              shift ;;   # ignore unsupported flags
                *)               urls+=("$1"); shift ;;
            esac
        done
        local -a curl_opts=(--fail --location)
        # Shows a progress bar on a TTY even with -q; -q applies only to logs / CI.
        if [[ -t 2 ]]; then
            curl_opts+=(--progress-bar --show-error)
        elif (( quiet )) && (( ! show_progress )); then
            curl_opts+=(--silent --show-error)
        else
            curl_opts+=(--progress-bar --show-error)
        fi
        (( resume )) && curl_opts+=(-C -)
        local url target
        for url in "${urls[@]+"${urls[@]}"}"; do
            if [[ -n "$outfile" ]]; then
                target="$outfile"
            else
                target="${prefix:-.}/$(basename "${url%%\?*}")"
            fi
            mkdir -p "$(dirname "$target")"
            curl "${curl_opts[@]+"${curl_opts[@]}"}" -o "$target" "$url" || return $?
        done
    }
fi

# Prints the path to a per-tool DB directory.
db() { echo "$DB_ROOT/$1"; }

# skip <db> <sentinel> [<sentinel> ...]
# Returns 0 (skip) when every sentinel exists and is non-empty and no partial
# downloads (*.tmp / *.partial / *.crdownload) remain; --redo always returns 1.
skip() {
    local name="$1"; shift
    local d; d="$(db "$name")"
    (( DB_REDO == 0 )) || return 1
    [[ -d "$d" ]] || return 1

    local partial
    partial=$(find "$d" -maxdepth 2 \( -name "*.tmp" -o -name "*.partial" -o -name "*.crdownload" \) 2>/dev/null | head -1)
    if [[ -n "$partial" ]]; then
        warn "$name: incomplete download ($(basename "$partial")) — re-downloading"
        return 1
    fi

    local f
    for f in "$@"; do
        local fp="$d/$f"
        [[ -e "$fp" ]] || return 1
        if [[ -f "$fp" && ! -s "$fp" ]]; then return 1; fi
        if [[ -d "$fp" && -z "$(ls -A "$fp" 2>/dev/null)" ]]; then return 1; fi
    done
    return 0
}

# run_in_container <tool> --bind <host:cont> [--bind ...] [--entrypoint <ep>] -- <cmd> [args ...]
# Runs a containerised prep step (hmmpress, diamond, ...) with the detected runtime.
run_in_container() {
    local tool="$1"; shift
    local entrypoint=""
    local -a binds=()
    while [[ $# -gt 0 && "$1" != "--" ]]; do
        case "$1" in
            --bind)       binds+=("$2"); shift 2 ;;
            --entrypoint) entrypoint="$2"; shift 2 ;;
            *)            err "run_in_container: bad arg '$1'"; return 1 ;;
        esac
    done
    shift  # drop --
    local -a cmd=("$@")
    local rt; rt="$(detect_runtime)"

    if (( DB_DRYRUN )); then
        echo "  [dry-run] [$rt] $tool  binds=${binds[*]}  ep=${entrypoint:-<default>}  cmd=${cmd[*]}"
        return 0
    fi

    case "$rt" in
        docker)
            local img; img="$(docker_image "$tool")"
            local -a vols=(); for b in "${binds[@]+"${binds[@]}"}"; do vols+=(-v "$b"); done
            local -a ep=();   [[ -n "$entrypoint" ]] && ep=(--entrypoint "$entrypoint")
            # Uses a local image without --platform (it may be single-arch); pulls only when absent.
            local -a plat=()
            if docker image inspect "$img" >/dev/null 2>&1; then
                log "using local image: $img (skipping pull)"
            else
                log "local image $img not found; pulling for platform $PLATFORM ..."
                if ! docker pull --platform "$PLATFORM" "$img"; then
                    err "docker pull failed for $img on platform $PLATFORM."
                    err "hint: build it locally instead with ./setup.sh --from-source --tool $tool"
                    return 1
                fi
                plat=(--platform "$PLATFORM")
            fi
            docker run --rm "${plat[@]+"${plat[@]}"}" "${ep[@]+"${ep[@]}"}" "${vols[@]+"${vols[@]}"}" "$img" "${cmd[@]+"${cmd[@]}"}"
            ;;
        apptainer)
            local sif; sif="$(sif_path "$tool")"
            if [[ ! -f "$sif" ]]; then
                err "local SIF not found: $sif"
                err "hint: build it locally with ./setup.sh --from-source --tool $tool"
                err "       or pull it with processing/scripts/setup-scripts/setup-containers/pull-apptainer/pull-${tool}.sh"
                return 1
            fi
            log "using local SIF: $sif"
            local apc; apc="apptainer"; command -v apptainer >/dev/null 2>&1 || apc="singularity"
            local -a bf=(); for b in "${binds[@]+"${binds[@]}"}"; do bf+=(--bind "$b"); done
            # Runs through the container's /bin/sh so PATH lookup happens inside the image,
            # not on the host; adds --nv for GPU-capable tools when USE_GPU allows it.
            local -a nv_flag=()
            if [[ " ${gpu_capable_tools[*]-} " == *" $tool "* ]]; then
                case "${USE_GPU:-auto}" in
                    1|yes|true) nv_flag=(--nv) ;;
                    0|no|false) ;;
                    auto) nvidia-smi >/dev/null 2>&1 && nv_flag=(--nv) ;;
                esac
            fi
            if [[ -n "$entrypoint" ]]; then
                "$apc" exec "${nv_flag[@]+"${nv_flag[@]}"}" "${bf[@]+"${bf[@]}"}" "$sif" /bin/sh -c 'exec "$@"' -- "$entrypoint" "${cmd[@]+"${cmd[@]}"}"
            else
                "$apc" run  "${nv_flag[@]+"${nv_flag[@]}"}" "${bf[@]+"${bf[@]}"}" "$sif" "${cmd[@]+"${cmd[@]}"}"
            fi
            ;;
    esac
}
