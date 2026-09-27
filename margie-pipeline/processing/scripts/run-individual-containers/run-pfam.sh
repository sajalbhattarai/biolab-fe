#!/usr/bin/env bash
# Runner for pfam (HMMER hmmscan vs Pfam-A). Consumes .faa files from
# rasttk output by default; override with TOOL_pfam_INPUT.
#
# Usage:
#   ./run-pfam.sh
#   ./run-pfam.sh --list
#   ./run-pfam.sh -- --gram-stain unknown    # extra args forwarded to the container

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/../../../pipeline.conf.sh"
source "$here/lib/pipeline-lib.sh"

TOOL=pfam
EXTRA_ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --list)      print_tool_config "$TOOL"; exit 0 ;;
        --help|-h)   sed -n '2,10p' "$0"; exit 0 ;;
        --runtime)   RUNTIME="$2"; shift 2 ;;
        --)          shift; EXTRA_ARGS+=("$@"); break ;;
        *)           EXTRA_ARGS+=("$1"); shift ;;
    esac
done

run_downstream_tool "$TOOL" ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}
