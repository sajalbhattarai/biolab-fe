#!/usr/bin/env bash
# pull-kegg.sh — pulls the kegg image as an Apptainer .sif (pull_one in lib.sh).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/lib.sh"
pull_one "kegg" "$@"
