#!/usr/bin/env bash
# build-all.sh — builds every tool image from its Dockerfile (build_all in lib.sh).
# Usage:
#   ./build-all.sh                  # builds every Dockerfile under $BUILD_DIR, loads locally
#   ./build-all.sh pfam tigrfam     # builds a subset
#   ./build-all.sh --build-and-push # builds multi-arch and pushes to $REGISTRY
#   ./build-all.sh --no-cache       # rebuilds without the Docker layer cache
#   ./build-all.sh --dry-run        # prints what would run
#   ./build-all.sh --accept-all-licenses --redo dbcan
#                                    # accepts licences non-interactively
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/lib.sh"
build_all "$@"
