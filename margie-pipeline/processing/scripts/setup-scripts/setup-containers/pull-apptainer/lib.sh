#!/usr/bin/env bash
# pull-apptainer/lib.sh — shared pull logic for Apptainer .sif images.
# Sourced by pull-all.sh and every pull-<tool>.sh in this directory.
set -euo pipefail

HERE_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT_PA="$(cd "$HERE_LIB/../../../../.." && pwd)"
# shellcheck disable=SC1091
source "$REPO_ROOT_PA/pipeline.conf.sh"
# shellcheck disable=SC1091
source "$REPO_ROOT_PA/processing/scripts/shared/colors.sh"
# shellcheck disable=SC1091
source "$REPO_ROOT_PA/processing/scripts/shared/runtime.sh"
# shellcheck disable=SC1091
: "${LOG_DIR:=$REPO_ROOT_PA/logs/containers}"
# shellcheck disable=SC1091
source "$REPO_ROOT_PA/processing/scripts/shared/logging.sh"
# shellcheck disable=SC1091
source "$REPO_ROOT_PA/processing/scripts/shared/licence-gate.sh"
# shellcheck disable=SC1091
source "$REPO_ROOT_PA/processing/scripts/shared/license-agreement.sh"
log_invocation "$0" "$@"
# Asks for the pipeline licence agreement; a no-op when MARGIE_ACCEPT_TERMS=1.
pipeline_licence_agreement "" || exit 1

tag="pull-apptainer"

_apptainer_cmd() {
    if   command -v apptainer   >/dev/null 2>&1; then echo apptainer
    elif command -v singularity >/dev/null 2>&1; then echo singularity
    else err "neither 'apptainer' nor 'singularity' in PATH"; exit 1
    fi
}

# pull_one <tool> [--redo] [--dry-run] — pulls one tool's .sif from its registry source.
pull_one() {
    local tool="$1"; shift
    local redo=0 dryrun=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --redo)    redo=1; shift ;;
            --dry-run) dryrun=1; shift ;;
            *) warn "ignoring unknown arg: $1"; shift ;;
        esac
    done

    # Restricted-licence tools are never pulled; they are built locally.
    case "$tool" in
        phobius)
            warn "$tool: redistribution is restricted by its upstream licence --"
            warn "      this tool is NEVER pulled from a registry. Build it locally:"
            warn "        ./setup.sh --containers-only --tool $tool"
            return 0
            ;;
    esac

    local sif; sif="$(sif_path "$tool")"
    local src; src="$(sif_source "$tool")"
    mkdir -p "$(dirname "$sif")"

    if (( ! redo )) && [[ -f "$sif" ]]; then
        warn "$tool — $sif already exists; pass --redo to force re-pull"
        return 0
    fi

    local apc; apc="$(_apptainer_cmd)"
    log "pulling $src  →  $sif"
    if (( dryrun )); then
        echo "  [dry-run] $apc pull $sif $src"
        return 0
    fi
    if (( redo )); then rm -f "$sif"; fi
    if ! "$apc" pull "$sif" "$src"; then
        err "$tool — pull failed for $src (image may not exist in registry; consider building locally)"
        rm -f "$sif"
        return 1
    fi
    ok "$tool ready ($sif)"
}

# pull_all [--redo] [--dry-run] [tool ...] — pulls the listed tools, or every tool.
pull_all() {
    local -a tools=()
    local -a passthrough=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --redo|--dry-run) passthrough+=("$1"); shift ;;
            *) tools+=("$1"); shift ;;
        esac
    done
    (( ${#tools[@]} )) || tools=( "${all_tools[@]+"${all_tools[@]}"}" )

    log "pulling ${#tools[@]} SIF image(s) from $REGISTRY → $SIF_DIR"
    local failed=()
    for t in "${tools[@]+"${tools[@]}"}"; do
        if ! pull_one "$t" ${passthrough[@]+"${passthrough[@]+"${passthrough[@]}"}"}; then
            failed+=("$t")
        fi
    done
    if (( ${#failed[@]} )); then
        err "FAILED: ${failed[*]}"
        return 1
    fi
    ok "all done"
}
