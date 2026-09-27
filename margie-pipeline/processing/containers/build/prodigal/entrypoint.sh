#!/usr/bin/env bash
# prodigal — gene calling for genomes whose genetic code is not known, in the
# same gene_calls/ layout RASTtk writes, so downstream tools need no changes.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: run -i <genome.fna> -o <output_dir> [-g <genetic code>] [-p single|meta|auto]
           [-t <threads>] [--domain <Bacteria|Archaea|Unknown>] [--organism-name <name>] [--force]

  -g   NCBI translation table (default 11). Used in single mode only.
  -p   auto (default): single when the genome is at least 20 kb, which
       Prodigal needs to train on it; meta (pre-trained models) otherwise.
  -t   accepted for interface compatibility; Prodigal is single-threaded.
  --domain, --organism-name   written to the table's organism / domain columns.
  --force  re-run even if gene_calls/genome.faa already exists.

Writes (under <output_dir>):
  gene_calls/genome.faa   proteins    >contig_N # start # end # strand # ID=contig_N;...
  gene_calls/genome.ffn   CDS nucleotide sequences
  gene_calls/genome.gff   GFF3, ID=contig_N (the same IDs as genome.faa)
  gene_calls/genome.fna   the input genome
  processed/prodigal_gene_calls.tsv   one row per gene (coordinates, strand, length)
  raw/                    Prodigal's own output and log
  pipeline-log.txt
EOF
}

INPUT="" OUTPUT="" CODE=11 MODE=auto DOMAIN="" NAME="" FORCE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -i) INPUT="$2"; shift 2 ;;
    -o) OUTPUT="$2"; shift 2 ;;
    -g) CODE="$2"; shift 2 ;;
    -p) MODE="$2"; shift 2 ;;
    -t) shift 2 ;;
    --domain) DOMAIN="$2"; shift 2 ;;
    --organism-name) NAME="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[prodigal] ERROR: unknown option: $1" >&2; usage; exit 2 ;;
  esac
done

[[ -f "$INPUT" ]]  || { echo "[prodigal] ERROR: input genome not found: $INPUT" >&2; exit 1; }
[[ -n "$OUTPUT" ]] || { echo "[prodigal] ERROR: -o is required" >&2; exit 1; }
[[ "$CODE" =~ ^[0-9]+$ ]] || { echo "[prodigal] ERROR: -g must be a number: $CODE" >&2; exit 1; }
: "${NAME:=$(basename "${INPUT%.*}")}"

GC="$OUTPUT/gene_calls" RAW="$OUTPUT/raw" PROC="$OUTPUT/processed"
if [[ "$FORCE" != 1 && -s "$GC/genome.faa" ]]; then
  echo "[prodigal] $NAME: gene calls already present, skipping (use --force to redo)"
  exit 0
fi
mkdir -p "$GC" "$RAW" "$PROC"

# Prodigal can only train on a genome of at least 20,000 bp.
length="$(grep -v '^>' "$INPUT" | tr -d ' \n\r' | wc -c | tr -d ' ')"
if [[ "$MODE" == auto ]]; then
  if (( length >= 20000 )); then MODE=single; else MODE=meta; fi
fi
case "$MODE" in
  single) args=(-p single -g "$CODE") ;;
  meta)   args=(-p meta) ;;   # -g does not apply to the pre-trained models
  *) echo "[prodigal] ERROR: -p must be single, meta or auto" >&2; exit 2 ;;
esac

cmd=(prodigal -i "$INPUT" -f gff -o "$RAW/prodigal.gff" -a "$RAW/prodigal.faa" -d "$RAW/prodigal.ffn" "${args[@]}")
code_used="n/a (meta mode)"; [[ "$MODE" == single ]] && code_used="$CODE"
echo "[prodigal] $NAME: ${length} bp, mode=$MODE, genetic code $code_used"
"${cmd[@]}" > "$RAW/prodigal.log" 2>&1 || { cat "$RAW/prodigal.log" >&2; exit 1; }

python3 /opt/prodigal/scripts/format_gene_calls.py \
  --gff "$RAW/prodigal.gff" --faa "$RAW/prodigal.faa" --ffn "$RAW/prodigal.ffn" \
  --out-dir "$GC" --table "$PROC/prodigal_gene_calls.tsv" \
  --genetic-code "$( [[ "$MODE" == single ]] && echo "$CODE" )" --mode "$MODE" \
  --organism "$NAME" --domain "${DOMAIN:-Unknown}"
cp "$INPUT" "$GC/genome.fna"

genes="$(grep -c '^>' "$GC/genome.faa" || true)"
{
  echo "tool=prodigal"
  echo "version=$(prodigal -v 2>&1 | grep -o 'V[0-9.]*' | head -1)"
  echo "organism=$NAME"
  echo "domain=${DOMAIN:-unknown}"
  echo "genome_length_bp=$length"
  echo "mode=$MODE"
  echo "genetic_code=$code_used"
  echo "command=${cmd[*]}"
  echo "genes=$genes"
  echo "finished=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$OUTPUT/pipeline-log.txt"
echo "[prodigal] $NAME: $genes genes -> $GC"
