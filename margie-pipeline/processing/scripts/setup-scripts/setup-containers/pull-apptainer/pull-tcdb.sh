#!/usr/bin/env bash
# pull-tcdb.sh — pulls the tcdb image as an Apptainer .sif (pull_one in lib.sh).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/lib.sh"
pull_one "tcdb" "$@"
