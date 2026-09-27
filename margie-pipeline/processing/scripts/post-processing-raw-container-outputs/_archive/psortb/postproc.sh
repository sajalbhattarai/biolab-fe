#!/usr/bin/env bash
# postproc.sh — PSORTb host-side post-processing (archived).
# Called by pipeline-lib.sh::run_postproc with the psortb group output dir; converts each
# raw/psortb.txt into processed/psortb_results.tsv, since the container has no postprocess step.
set -euo pipefail

OUT_DIR="${1:?usage: postproc.sh <psortb-group-output-dir>}"

PY="${PYTHON:-python3}"
if ! command -v "$PY" >/dev/null 2>&1; then
    echo "[postproc/psortb] WARN: python3 not found — skipping TSV generation" >&2
    exit 0
fi

found=0
while IFS= read -r raw_file; do
    org_dir="$(dirname "$(dirname "$raw_file")")"   # .../psortb/<rel>/  ← organism dir
    processed_dir="$org_dir/processed"
    out_tsv="$processed_dir/psortb_results.tsv"

    [[ -f "$out_tsv" ]] && { echo "[postproc/psortb] skipping (already exists): $out_tsv" >&2; continue; }

    mkdir -p "$processed_dir"

    # Gram stain and PSORTb class from the directory path.
    org_lower="$(printf '%s' "$org_dir" | tr '[:upper:]' '[:lower:]')"
    if   [[ "$org_lower" == *gram-positive* ]]; then gram_stain="positive"; gram_class="p"
    elif [[ "$org_lower" == *gram-negative* ]]; then gram_stain="negative"; gram_class="n"
    elif [[ "$org_lower" == *archaea*       ]]; then gram_stain="unknown";  gram_class="a"
    else                                             gram_stain="unknown";  gram_class="n"
    fi

    organism_name="$(basename "$org_dir")"

    # Command line from the pipeline log, if present.
    log_file="$org_dir/psortb-pipeline-log.txt"
    cmd_used=""
    if [[ -f "$log_file" ]]; then
        cmd_used="$(grep -m1 "^Command" "$log_file" | sed 's/^Command[[:space:]]*:[[:space:]]*//' || true)"
    fi
    [[ -z "$cmd_used" ]] && cmd_used="psortb -o terse -$gram_class"

    "$PY" - "$raw_file" "$out_tsv" "$organism_name" "$gram_stain" "$gram_class" "$cmd_used" <<'PYEOF'
import sys
import csv

raw_file, out_file, organism_name, gram_stain, gram_class, cmd_used = sys.argv[1:]

HEADER = [
    "feature_id", "organism_name", "gram_stain",
    "psortb_localization", "psortb_score", "psortb_gram_class",
    "psortb_tool_used", "psortb_command_used",
    "psortb_input_path", "psortb_output_path",
]

rows = []
with open(raw_file) as fh:
    reader = csv.reader(fh, delimiter="\t")
    for line_parts in reader:
        if len(line_parts) < 3:
            continue
        seq_id_full = line_parts[0]
        if seq_id_full.startswith("SeqID"):
            continue
        localization = line_parts[1].strip()
        score = line_parts[2].strip()
        # feature_id is the first space-delimited token (fig|...|peg.N)
        feature_id = seq_id_full.split(" ", 1)[0]
        rows.append([
            feature_id, organism_name, gram_stain,
            localization, score, gram_class,
            "PSORTb 3.0", cmd_used,
            raw_file, out_file,
        ])

with open(out_file, "w", newline="") as fh:
    w = csv.writer(fh, delimiter="\t")
    w.writerow(HEADER)
    w.writerows(rows)

print(f"[postproc/psortb]   {len(rows)} proteins → {out_file}", file=__import__("sys").stderr)
PYEOF
    found=$(( found + 1 ))
done < <(find -L "$OUT_DIR" -type f -name "psortb.txt" -path "*/raw/psortb.txt" 2>/dev/null)

if (( found == 0 )); then
    echo "[postproc/psortb] no raw/psortb.txt found under $OUT_DIR — nothing to post-process" >&2
fi
