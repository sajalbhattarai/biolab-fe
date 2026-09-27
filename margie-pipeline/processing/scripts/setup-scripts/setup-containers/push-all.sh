#!/usr/bin/env bash
# push-all.sh — pushes every local $REGISTRY/<tool>:latest image (maintainer use).
# build-all.sh --build-and-push gives a multi-arch manifest; this script pushes single-arch local images.
# Usage:
#   ./push-all.sh                  # pushes every tool that has a local image
#   ./push-all.sh pfam tigrfam     # pushes a subset
#   ./push-all.sh --dry-run        # prints the docker push commands only
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$here/../../../../pipeline.conf.sh"
# shellcheck disable=SC1091
source "$here/../../shared/colors.sh"
tag="push-all"

command -v docker >/dev/null 2>&1 || { err "docker not in PATH"; exit 1; }

dryrun=no
TOOLS=()
for arg in "$@"; do
    case "$arg" in
        --dry-run) dryrun=yes ;;
        --*)       warn "ignoring unknown flag: $arg" ;;
        *)         TOOLS+=("$arg") ;;
    esac
done

# Defaults to every tool that has a local image at $REGISTRY/<t>:latest.
if (( ${#TOOLS[@]} == 0 )); then
    for t in "${all_tools[@]+"${all_tools[@]}"}"; do
        if docker image inspect "$REGISTRY/$t:latest" >/dev/null 2>&1; then
            TOOLS+=("$t")
        fi
    done
fi

if (( ${#TOOLS[@]} == 0 )); then
    warn "no local images found to push (run ./build-all.sh first)"
    exit 0
fi

failed=()
for t in "${TOOLS[@]+"${TOOLS[@]}"}"; do
    # Restricted-licence images (Phobius) are never pushed, whatever the TOOLS list holds.
    case "$t" in
        phobius)
            warn "$t: skipping push -- upstream licence forbids redistribution"
            continue
            ;;
    esac
    image="$REGISTRY/$t:latest"
    log "── pushing $image"
    if [[ "$dryrun" = yes ]]; then
        echo "  [dry-run] docker push $image"
        continue
    fi
    if ! docker push "$image"; then
        failed+=("$t")
    fi
done

if (( ${#failed[@]} )); then
    err "FAILED: ${failed[*]}"
    exit 1
fi
ok "pushed ${#TOOLS[@]} image(s)"
