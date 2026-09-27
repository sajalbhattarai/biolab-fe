#!/usr/bin/env bash
# Runner for deepsig (signal-peptide prediction). See pipeline.conf.sh for config.
#
# Usage:
#   ./run-deepsig.sh
#   ./run-deepsig.sh --list
#   ./run-deepsig.sh -- --gram-stain negative

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/../../../pipeline.conf.sh"
source "$here/lib/pipeline-lib.sh"

TOOL=deepsig
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

# The deepsig models ship inside the container; the empty DB dir satisfies the pipeline-lib check.
mkdir -p "$DB_ROOT/deepsig"

run_downstream_tool "$TOOL" ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}
