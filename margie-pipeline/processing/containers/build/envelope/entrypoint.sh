#!/usr/bin/env bash
set -euo pipefail
# parses runtime args and passes values to the tool execution path.

usage() {
  cat <<'EOF'
Usage:
  run -i /input -o /output [-t THREADS] [--domain DOMAIN] [--organism-name NAME]

Notes:
  - /input is expected to contain upstream tool outputs, typically:
      /input/tigrfam/processed/*.tsv
      /input/pgap/processed/*.tsv
      /input/pfam/processed/*.tsv
      /input/uniprot/processed/*.tsv
  - Writes:
      /output/raw/envelope_signals.tsv
     /output/raw/{tigrfam,pfam,pgap,uniprot}_marker_hits.tsv
      /output/processed/envelope_summary.tsv
     /output/processed/envelope_results.tsv
      /output/pipeline-log.txt
EOF
}

INPUT=""
OUTPUT=""
THREADS=1
DOMAIN=""
ORGANISM_NAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -i) INPUT="$2"; shift 2 ;;
    -o) OUTPUT="$2"; shift 2 ;;
    -t) THREADS="$2"; shift 2 ;;
    --domain) DOMAIN="$2"; shift 2 ;;
    --organism-name) ORGANISM_NAME="$2"; shift 2 ;;
    -d) shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "[envelope] ERROR: unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

[[ -n "$INPUT" ]] || { echo "[envelope] ERROR: -i is required" >&2; exit 1; }
[[ -n "$OUTPUT" ]] || { echo "[envelope] ERROR: -o is required" >&2; exit 1; }
[[ -d "$INPUT" ]] || { echo "[envelope] ERROR: input dir not found: $INPUT" >&2; exit 1; }

RAW_DIR="$OUTPUT/raw"
PROC_DIR="$OUTPUT/processed"
mkdir -p "$RAW_DIR" "$PROC_DIR"

if [[ -z "$ORGANISM_NAME" ]]; then
  ORGANISM_NAME="$(basename "$INPUT")"
fi

LOG_FILE="$OUTPUT/pipeline-log.txt"
{
  echo "tool=envelope"
  echo "organism=$ORGANISM_NAME"
  echo "domain=${DOMAIN:-unknown}"
  echo "input=$INPUT"
  echo "output=$OUTPUT"
  echo "threads=$THREADS"
} > "$LOG_FILE"

python3 /opt/envelope/scripts/infer_envelope_type.py \
  --input-dir "$INPUT" \
  --raw-output "$RAW_DIR/envelope_signals.tsv" \
  --summary-output "$PROC_DIR/envelope_summary.tsv" \
  --organism-name "$ORGANISM_NAME" \
  --domain "${DOMAIN:-unknown}" \
  >> "$LOG_FILE" 2>&1

echo "status=ok" >> "$LOG_FILE"
