#!/usr/bin/env bash
# pull-all.sh — pulls every pipeline image from $REGISTRY into the local Docker daemon (pull_all in lib.sh).
# Usage:
#   ./pull-all.sh                  # pulls all
#   ./pull-all.sh cog pfam         # pulls a subset
#   ./pull-all.sh --redo           # re-pulls existing images
#   ./pull-all.sh --dry-run        # prints the plan only
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/lib.sh"
pull_all "$@"
