#!/usr/bin/env bash
# Runner for kegg (KofamScan). Consumes .faa files from rasttk output by
# default; override with TOOL_kegg_INPUT.
#
# Usage:
#   ./run-kegg.sh
#   ./run-kegg.sh --list
#   ./run-kegg.sh -- --organism-name MyBug   # extra args forwarded

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/../../../pipeline.conf.sh"
source "$here/lib/pipeline-lib.sh"

TOOL=kegg
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
