#!/usr/bin/env bash
# pull-docker/lib.sh — shared pull logic for Docker images.
# Sourced by pull-all.sh and every pull-<tool>.sh in this directory.
set -euo pipefail

HERE_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT_PD="$(cd "$HERE_LIB/../../../../.." && pwd)"
# shellcheck disable=SC1091
source "$REPO_ROOT_PD/pipeline.conf.sh"
# shellcheck disable=SC1091
source "$REPO_ROOT_PD/processing/scripts/shared/colors.sh"
# shellcheck disable=SC1091
source "$REPO_ROOT_PD/processing/scripts/shared/runtime.sh"
# shellcheck disable=SC1091
: "${LOG_DIR:=$REPO_ROOT_PD/logs/containers}"
# shellcheck disable=SC1091
source "$REPO_ROOT_PD/processing/scripts/shared/logging.sh"
# shellcheck disable=SC1091
source "$REPO_ROOT_PD/processing/scripts/shared/licence-gate.sh"
# shellcheck disable=SC1091
source "$REPO_ROOT_PD/processing/scripts/shared/license-agreement.sh"
log_invocation "$0" "$@"
# Asks for the pipeline licence agreement; a no-op when MARGIE_ACCEPT_TERMS=1.
pipeline_licence_agreement "" || exit 1

tag="pull-docker"

_require_docker() {
    command -v docker >/dev/null 2>&1 || { err "docker not in PATH"; exit 1; }
    docker info --format '{{.ID}}' >/dev/null 2>&1 \
        || { err "docker daemon not running (start Docker Desktop)"; exit 1; }
}

# pull_one <tool> [--redo] [--dry-run] — pulls one tool's image from $REGISTRY.
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

    # Restricted-licence tools (Phobius) are never pulled or published; they are built locally.
    case "$tool" in
        phobius)
            warn "$tool: redistribution is restricted by its upstream licence --"
            warn "      this tool is NEVER pulled from a registry. Build it locally:"
            warn "        ./setup.sh --containers-only --tool $tool"
            return 0
            ;;
    esac

    _require_docker
    local image; image="$(docker_image "$tool")"

    if (( ! redo )) && docker image inspect "$image" >/dev/null 2>&1; then
        warn "$tool — image already present ($image); pass --redo to force re-pull"
        return 0
    fi

    log "pulling $image  (platform=$PLATFORM)"
    if (( dryrun )); then
        echo "  [dry-run] docker pull --platform $PLATFORM $image"
        return 0
    fi
    if ! docker pull --platform "$PLATFORM" "$image"; then
        err "$tool — pull failed for $image (image may not exist in registry; consider building locally)"
        return 1
    fi
    ok "$tool ready ($image)"
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

    log "pulling ${#tools[@]} image(s) from $REGISTRY"
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
