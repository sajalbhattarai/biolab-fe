#!/usr/bin/env bash
# run-signalp4.sh — SignalP 4.1 signal peptide prediction.
#
# HPC-ONLY: requires apptainer/singularity runtime and the Purdue biocontainer
# module:   module load biocontainers/default signalp4/4.1
# The script silently exits (exit 0) when running in docker mode or when no
# apptainer/singularity is available on the host.
#
# SignalP 4.1 is NOT redistributable (DTU academic licence).  It is pre-installed
# in the HPC biocontainers stack as a Singularity image; each user has already
# agreed to the DTU academic licence by using the HPC system.
#
# The organism type (-t gram+/gram-) comes from the envelope stage
# (run-envelope.sh); a genome without an envelope result is skipped.
#
# Input:  $annotation_input/<genome>/gene_calls/genome.faa  (from the gene caller)
# Output: $annotation_output_root/signalp4/<genome>/
#           raw/       <genome>_signalp4.txt     raw SignalP 4.1 short-format output
#           processed/ signalp4_results.tsv      normalized TSV with SIGNALP4_ columns
#
# Usage:
#   ./run-signalp4.sh
#   ./run-signalp4.sh --list

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=pipeline.conf.sh
source "$here/../../../pipeline.conf.sh"
# shellcheck source=lib/pipeline-lib.sh
source "$here/lib/pipeline-lib.sh"

TOOL=signalp4

while [[ $# -gt 0 ]]; do
    case "$1" in
        --list)    print_tool_config "$TOOL"; exit 0 ;;
        --help|-h) sed -n '2,20p' "$0"; exit 0 ;;
        --runtime) RUNTIME="$2"; shift 2 ;;
        *)         echo "[signalp4] WARNING: unknown option '$1' — ignored" >&2; shift ;;
    esac
done

# ── HPC / runtime guard ────────────────────────────────────────────────────────
rt="$(detect_runtime)"
if [[ "$rt" != "apptainer" ]]; then
    echo "[signalp4] INFO: runtime is '$rt' (not apptainer/HPC) — skipping." >&2
    echo "[signalp4]   SignalP 4.1 is only available via the HPC biocontainer module." >&2
    exit 0
fi

# ── Load HPC biocontainer module ───────────────────────────────────────────────
# shellcheck disable=SC1090
if ! module load biocontainers/default signalp4/4.1 2>/dev/null; then
    echo "[signalp4] ERROR: 'module load biocontainers/default signalp4/4.1' failed." >&2
    echo "[signalp4]   Ensure you are on a system where the biocontainers module is available." >&2
    exit 1
fi

# The module may provide signalp as a shell function or as a binary.
if ! declare -f signalp >/dev/null 2>&1 && ! command -v signalp >/dev/null 2>&1; then
    echo "[signalp4] ERROR: signalp not callable after module load." >&2
    exit 1
fi

# ── Discover .faa inputs (same pattern as run_downstream_tool) ────────────────
out="$(tool_output "$TOOL")"
mkdir -p "$out"

faa_files=()
while IFS= read -r -d '' f; do
    faa_files+=("$f")
done < <(gene_call_roots | while IFS= read -r _root; do
    find -L "$_root" -type f -path '*/gene_calls/genome.faa' -not -path '*/.staging-*' -print0 2>/dev/null
done)

if [[ ${#faa_files[@]} -eq 0 ]]; then
    echo "[signalp4] WARN: no gene_calls/genome.faa files found — did the gene caller run?" >&2
    exit 0
fi

echo "[signalp4] discovered ${#faa_files[@]} .faa file(s)"

# ── Process each organism ──────────────────────────────────────────────────────
for f in "${faa_files[@]+"${faa_files[@]}"}"; do
    organism_name="$(basename "$(dirname "$(dirname "$f")")")"

    # Honours PIPELINE_ORGANISM_FILTER, which keeps parallel HPC subshells off each other's outputs.
    [[ -n "${PIPELINE_ORGANISM_FILTER:-}" && "$organism_name" != "$PIPELINE_ORGANISM_FILTER" ]] && continue

    sp_t="$(envelope_flag "$organism_name" signalp4)"
    gs="$(envelope_gram "$organism_name")"
    if [[ -z "$sp_t" ]]; then
        echo "[signalp4] WARN: $organism_name has no envelope result yet (run-envelope.sh); skipping" >&2
        continue
    fi

    dst="$out/$organism_name"
    label="$organism_name"
    mkdir -p "$dst/raw" "$dst/processed"

    raw_out="$dst/raw/${organism_name}_signalp4.txt"
    processed_out="$dst/processed/signalp4_results.tsv"
    cmd_used="signalp -t $sp_t -f short $(basename "$f")"

    echo "[signalp4] $label  ($sp_t)"

    # SignalP 4.1 short-format output.
    signalp -t "$sp_t" -f short "$f" > "$raw_out" 2>/dev/null

    # ── Convert the short output to a normalised TSV ──────────────────────────
    # Columns: name Cmax pos Ymax pos Smax pos Smean D ? Dmaxcut Networks-used ('?' is Y/N for a signal peptide).
    python3 - "$raw_out" "$processed_out" \
              "$organism_name" "$gs" "$sp_t" "$cmd_used" <<'PYEOF'
import sys
import csv
import re

raw_file, out_file, organism_name, gram_stain, sp_t, cmd_used = sys.argv[1:]

HEADER = [
    "feature_id", "organism_name", "gram_stain",
    "SIGNALP4_has_signal_peptide",
    "SIGNALP4_D_score", "SIGNALP4_D_threshold",
    "SIGNALP4_Cmax", "SIGNALP4_Cmax_pos",
    "SIGNALP4_Ymax", "SIGNALP4_Ymax_pos",
    "SIGNALP4_Smax", "SIGNALP4_Smax_pos",
    "SIGNALP4_Smean",
    "SIGNALP4_networks", "SIGNALP4_organism_type",
    "SIGNALP4_command_used",
]

rows = []
with open(raw_file) as fh:
    for line in fh:
        line = line.rstrip("\n")
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) < 12:
            continue
        name     = parts[0]
        cmax     = parts[1];  cmax_pos = parts[2]
        ymax     = parts[3];  ymax_pos = parts[4]
        smax     = parts[5];  smax_pos = parts[6]
        smean    = parts[7]
        d_score  = parts[8]
        has_sp   = parts[9]    # Y or N
        d_thresh = parts[10]
        networks = parts[11]
        rows.append([
            name, organism_name, gram_stain,
            has_sp,
            d_score, d_thresh,
            cmax, cmax_pos,
            ymax, ymax_pos,
            smax, smax_pos,
            smean,
            networks, sp_t,
            cmd_used,
        ])

with open(out_file, "w", newline="") as fh:
    w = csv.writer(fh, delimiter="\t")
    w.writerow(HEADER)
    w.writerows(rows)

sp_count = sum(1 for r in rows if r[3] == "Y")
print(f"[signalp4]   {len(rows)} proteins  |  {sp_count} with signal peptide  →  {out_file}",
      file=__import__("sys").stderr)
PYEOF
done

echo "[signalp4] complete — results in $out"
