#!/usr/bin/env bash
# pull-tigrfam.sh — pulls the tigrfam image as an Apptainer .sif (pull_one in lib.sh).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/lib.sh"
pull_one "tigrfam" "$@"
