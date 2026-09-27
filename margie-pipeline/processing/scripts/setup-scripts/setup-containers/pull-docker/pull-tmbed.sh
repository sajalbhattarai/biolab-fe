#!/usr/bin/env bash
# pull-tmbed.sh — pulls the tmbed image into the local Docker daemon (pull_one in lib.sh).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/lib.sh"
pull_one "tmbed" "$@"
