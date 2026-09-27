#!/usr/bin/env bash
# rasttk — RASTtk/BV-BRC genome annotation entrypoint (self-contained)
set -euo pipefail

# =============================================================================
# Usage
# =============================================================================
usage() {
  cat <<EOF
Usage: rasttk_exec -i <input_fasta_or_dir> -o <output_root> [-t <threads>] [-d <database_dir>] [--name <genome_name>] [--scientific <name>] [--domain {Bacteria,Archaea}] [--gram-stain {positive,negative,unknown}] [--only-prodigal] [--only-prodigal-and-glimmer]

Optional biological-context flags (recorded into output filename suffix and pipeline log):
  --domain         Bacteria | Archaea  (default: auto-detected from input folder;
                   Bacteria for gram-positive/-negative/unknown/bacteria, Archaea
                   for archaea). Wired into RASTtk for genetic-code selection.
  --gram-stain     positive | negative | unknown  (default: auto-detected from
                   input folder). Provenance-only; never passed to the RASTtk
                   binary. Ignored when domain resolves to Archaea.

Output filename suffix encodes both:
  Archaea       -> _arch
  Bacteria, +ve -> _bact_gramP
  Bacteria, -ve -> _bact_gramN
  Bacteria, ?   -> _bact_gramU   (or _bact if neither folder nor flag set)
  Unknown, ?    -> _unknown_gramU
  (no match)    -> ""  (original filename preserved)

Bind-mount quick start (Docker):
  docker run --rm \\
    -v /host/path/to/input:/input:ro \\
    -v /host/path/to/output:/output:rw \\
    margie/rasttk:latest \\
    -i /input/genome.fna -o /output

Bind-mount quick start (Apptainer/Singularity on HPC):
  apptainer run \\
    -B /host/input:/input:ro \\
    -B /host/output:/output:rw \\
    rasttk.sif \\
    -i /input/genome.fna -o /output

Notes:
  - -i and -o must use container-side paths (after -v or -B mounts above).
  - For Apptainer, the host bind source paths must exist before run.
    Example: mkdir -p /host/output
  - If -i is a file: process that file only.
  - If -i is a directory: process all FASTA files one by one (.fna/.fasta/.fa).
  - If -i is omitted: auto-process all FASTA files from default input mount.
    Default input mount search order: /input, /work/input, /container/input
  - If -i is a bare filename (for example genome.fna), it is resolved from
    default input mount search order above.
  - Per-genome output directories are auto-created as:
      <output_root>/<organism>/
    (gene calls stay inside gene_calls/ within that directory; no separate
     prodigal/ directory is created)
  - Scientific name is auto-extracted from file name unless --scientific is provided.
  - Use -d to override or supply DB location (exports RASTTK_DB_DIR).
    Example: apptainer run -B /host/db/rasttk:/db:ro rasttk.sif -i ... -d /db
  - Threads are accepted for interface compatibility (RASTtk core pipeline is mostly single-threaded)
  - --only-prodigal skips steps 2-7 and 9 (runs create-genome -> prodigal -> step10+)
  - --only-prodigal-and-glimmer skips steps 2-7 only (runs create-genome -> prodigal -> glimmer -> step10+)
  - --postproc-dir <dir>  override the baked-in SEED enricher (default /opt/rasttk/postproc).
                          Mount a host dir with enrich-rast-tsv.py + helpers to patch without rebuild.
  - --no-postproc         skip in-container SEED variant enrichment entirely
                          (emits the basic rast.tsv only).

OUTPUT STRUCTURE - RASTTK:
  <output_root>/rasttk/<organism>/
    rast.tsv                Comprehensive annotation table (main output)
    rast.gff                Annotated GFF file
    rast.gbk                Annotated GenBank file
    rast.faa                Annotated protein sequences
    rast.fasta              Annotated nucleotide sequence
    fasta.json              Metadata in JSON format
    gene_calls/             Gene calling intermediates
      rna.gff               RNA features (rRNA, tRNA)
      cds.gff               CDS features with functional annotations
    raw/                    Raw pipeline intermediates (RASTtk outputs)
      *.json                Various internal annotation stages
    pipeline-log.txt        Pipeline execution log with RASTtk citations


FILES EXPLAINED:
  rast.tsv:
    - Main consolidated output table with all genes and their annotations
    - Columns: feature_id, genome_id, RNA_type, molecular_weight, and many
      functional annotation fields (product, ec_number, go_terms, etc.)
  
  rast.gff:
    - Standard GFF3 format with all annotated features and attributes
  
  rast.faa:
    - FASTA format protein sequences from all annotated CDS features
  
  gene_calls/rna.gff:
    - Predicted ribosomal RNA (rRNA), transfer RNA (tRNA), and other RNAs
  
  gene_calls/cds.gff:
    - Predicted protein-coding sequences (CDS) with functional annotations
    - Includes product description and other functional information

EOF
}

# =============================================================================
# Defaults
# =============================================================================
INPUT_PATH=""
OUTPUT_ROOT=""
THREADS=8
DB_DIR=""
GENOME_NAME=""
SCIENTIFIC_NAME=""
GENETIC_CODE=11
DOMAIN="Bacteria"
GRAM_STAIN=""
RUN_MODE="full"
POSTPROC_DIR="/opt/rasttk/postproc"
NO_POSTPROC=0

# =============================================================================
# Helpers
# =============================================================================
find_default_input_dir() {
  for d in /input /work/input /container/input; do
    if [[ -d "$d" ]]; then
      printf '%s' "$d"
      return 0
    fi
  done
  return 1
}

resolve_input_path() {
  local raw="$1"

  # If already exists as provided (absolute or relative), keep it.
  if [[ -e "$raw" ]]; then
    printf '%s' "$raw"
    return 0
  fi

  # If bare filename/path does not exist, try resolving from mounted input dir.
  local default_in
  default_in="$(find_default_input_dir || true)"
  if [[ -n "$default_in" && -e "$default_in/$raw" ]]; then
    printf '%s' "$default_in/$raw"
    return 0
  fi

  # Return original so caller can produce a clear error.
  printf '%s' "$raw"
}

# =============================================================================
# Argument parsing
# =============================================================================
while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--input) INPUT_PATH="$2"; shift 2 ;;
    -o|--output) OUTPUT_ROOT="$2"; shift 2 ;;

    -t|--threads) THREADS="$2"; shift 2 ;;
    -d|--database) DB_DIR="$2"; shift 2 ;;
    --name) GENOME_NAME="$2"; shift 2 ;;
    --scientific) SCIENTIFIC_NAME="$2"; shift 2 ;;
    --genetic-code) GENETIC_CODE="$2"; shift 2 ;;
    --domain) DOMAIN="$2"; DOMAIN_USER_SET=1; shift 2 ;;
    --gram-stain) GRAM_STAIN="$2"; GRAM_STAIN_USER_SET=1; shift 2 ;;
    --only-prodigal) RUN_MODE="only-prodigal"; shift ;;
    --only-prodigal-and-glimmer|--only-progigal-and-glimmer) RUN_MODE="only-prodigal-and-glimmer"; shift ;;
    --postproc-dir) POSTPROC_DIR="$2"; shift 2 ;;
    --no-postproc)  NO_POSTPROC=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

[[ -n "$OUTPUT_ROOT" ]] || { echo "ERROR: --output is required"; exit 1; }
mkdir -p "$OUTPUT_ROOT"

if [[ -z "$INPUT_PATH" ]]; then
  INPUT_PATH="$(find_default_input_dir || true)"
  if [[ -z "$INPUT_PATH" ]]; then
    echo "ERROR: --input was omitted and no default input mount was found"
    echo "Hint: bind an input directory to /input (recommended), /work/input, or /container/input"
    exit 1
  fi
  echo "INFO: --input omitted; auto-using input directory: $INPUT_PATH"
else
  INPUT_PATH="$(resolve_input_path "$INPUT_PATH")"
fi

[[ -e "$INPUT_PATH" ]] || { echo "ERROR: input not found: $INPUT_PATH"; exit 1; }

# =============================================================================
# Domain / gram detection helpers
# =============================================================================
sanitize_slug() {
  local s="$1"
  s="${s// /-}"
  s="$(echo "$s" | sed -E 's/[^A-Za-z0-9._-]+/-/g; s/-+/-/g; s/^-+//; s/-+$//')"
  [[ -n "$s" ]] || s="genome"
  printf '%s' "$s"
}

derive_scientific_name() {
  local fasta="$1"
  local base stem no_accession sci
  base="$(basename "$fasta")"
  stem="${base%.*}"
  no_accession="${stem%%__GCF_*}"
  sci="${no_accession//_/ }"
  sci="$(echo "$sci" | sed -E 's/[\[\]]//g; s/[[:space:]]+/ /g; s/^ +//; s/ +$//')"
  [[ -n "$sci" ]] || sci="Unknown organism"
  printf '%s' "$sci"
}

# Detect a domain tag (arch | bact | unknown | "") AND a gram tag
# (gramP | gramN | gramU | "") from any ancestor directory of the input fasta.
# Recognised folder names (case-insensitive, with -/_/space normalised away):
#   archaea / archaeal                                  -> dom=arch     gram=""
#   gram-positive / grampositive / grampos / positive   -> dom=bact     gram=gramP
#   gram-negative / gramnegative / gramneg / negative   -> dom=bact     gram=gramN
#   bacteria                                            -> dom=bact     gram=""
#   unknown / gramu / gramunknown                       -> dom=unknown  gram=gramU
# Returns: prints "<dom_tag>\t<gram_tag>" (tab-separated). Either may be empty.
detect_domain_and_gram_tags() {
  local fasta_abs dir norm
  fasta_abs="$(cd "$(dirname "$1")" 2>/dev/null && pwd)/$(basename "$1")" || fasta_abs="$1"
  dir="$(dirname "$fasta_abs")"
  while [[ -n "$dir" && "$dir" != "/" ]]; do
    norm="$(basename "$dir" | tr '[:upper:]' '[:lower:]' | tr -d ' _-')"
    case "$norm" in
      gramnegative|negative|gramneg|gn) printf 'bact\tgramN'; return 0 ;;
      grampositive|positive|grampos|gp) printf 'bact\tgramP'; return 0 ;;
      archaea|archaeal)                 printf 'arch\t';      return 0 ;;
      bacteria)                         printf 'bact\t';      return 0 ;;
      unknown|gramu|gramunknown)        printf 'unknown\tgramU'; return 0 ;;
    esac
    dir="$(dirname "$dir")"
  done
  printf '\t'
}

# Compose the final output filename suffix from a (domain_tag, gram_tag) pair.
# Format:
#   arch                  -> _arch              (gram is biologically N/A)
#   bact + gramN          -> _bact_gramN
#   bact + gramP          -> _bact_gramP
#   bact + gramU          -> _bact_gramU
#   bact + ""             -> _bact
#   unknown + gramU       -> _unknown_gramU
#   unknown + ""          -> _unknown
#   "" + ""               -> ""  (no suffix; preserves original filename)
compose_full_suffix() {
  local dom_tag="$1" gram_tag="$2"
  if [[ "$dom_tag" == "arch" ]]; then
    printf '_arch'
  elif [[ -n "$dom_tag" ]]; then
    if [[ -n "$gram_tag" ]]; then
      printf '_%s_%s' "$dom_tag" "$gram_tag"
    else
      printf '_%s' "$dom_tag"
    fi
  else
    printf ''
  fi
}

# =============================================================================
# Per-genome annotation
# =============================================================================
run_one() {
  local fasta="$1"
  local user_name="$2"
  local user_sci="$3"
  local base stem sci gname out_slug run_id rast_out_dir
  local detected detected_dom detected_gram dom_tag gram_tag domain_suffix effective_domain

  [[ -f "$fasta" ]] || { echo "ERROR: FASTA not found: $fasta"; return 1; }

  detected="$(detect_domain_and_gram_tags "$fasta")"
  detected_dom="${detected%%$'\t'*}"
  detected_gram="${detected##*$'\t'}"

  if [[ "${DOMAIN_USER_SET:-0}" == "1" ]]; then
    case "$DOMAIN" in
      Archaea|archaea)   dom_tag="arch" ;;
      Bacteria|bacteria) dom_tag="bact" ;;
      Unknown|unknown)   dom_tag="unknown" ;;
      *)                 dom_tag="$detected_dom" ;;
    esac
  else
    dom_tag="$detected_dom"
  fi

  if [[ "$dom_tag" == "arch" ]]; then
    gram_tag=""
  elif [[ "${GRAM_STAIN_USER_SET:-0}" == "1" ]]; then
    case "$GRAM_STAIN" in
      positive|gramP|P) gram_tag="gramP" ;;
      negative|gramN|N) gram_tag="gramN" ;;
      unknown|gramU|U)  gram_tag="gramU" ;;
      *)                gram_tag="$detected_gram" ;;
    esac
  else
    gram_tag="$detected_gram"
  fi

  domain_suffix="$(compose_full_suffix "$dom_tag" "$gram_tag")"

  effective_domain="$DOMAIN"
  if [[ "${DOMAIN_USER_SET:-0}" != "1" ]]; then
    if [[ "$dom_tag" == "arch" ]]; then
      effective_domain="Archaea"
    else
      effective_domain="Bacteria"
    fi
  fi

  base="$(basename "$fasta")"
  stem="${base%.*}"

  if [[ -n "$user_sci" ]]; then
    sci="$user_sci"
  else
    sci="$(derive_scientific_name "$fasta")"
  fi

  if [[ -n "$user_name" ]]; then
    gname="$user_name"
  else
    gname="$(sanitize_slug "$stem")"
  fi

  out_slug="$(sanitize_slug "$sci")"
  run_id="${out_slug}${domain_suffix}"
  rast_out_dir="${OUTPUT_ROOT}/${run_id}"
  mkdir -p "$rast_out_dir"

  {
    echo "=========================================="
    echo "RASTtk Annotation Pipeline"
    echo "=========================================="
    echo ""
    echo "CITATION: This RASTtk pipeline uses BV-BRC servers for annotating genomes."
    echo "  BV-BRC RASTtk documentation: https://www.bv-brc.org/docs/cli_tutorial/rasttk_incremental_commands.html"
    echo ""
    echo "Original paper:"
    echo "  Brettin T, Davis JJ, Disz T, Edwards RA, Gerdes S, Olsen GJ, Olson R,"
    echo "  Overbeek R, Parrello B, Pusch GD, Shukla M, Thomason JA 3rd, Stevens R,"
    echo "  Vonstein V, Wattam AR, Xia F. RASTtk: a modular and extensible"
    echo "  implementation of the RAST algorithm for building custom annotation"
    echo "  pipelines and annotating batches of genomes. Sci Rep. 2015 Feb 10;5:8365."
    echo "  doi: 10.1038/srep08365. PMID: 25666585; PMCID: PMC4322359."
    echo ""
    echo "=========================================="
    echo ""
    echo "Running rasttk_exec"
    echo "  Input:       $fasta"
    echo "  RAST output: $rast_out_dir"
    echo "  Genome:      $gname"
    echo "  Scientific:  $sci"
    echo "  Threads:     $THREADS"
    echo "  Run mode:    $RUN_MODE"
    echo "  Domain:      ${effective_domain}"
    if [[ -n "$domain_suffix" ]]; then
      echo "  Output tag:  ${domain_suffix} (domain=${dom_tag:-?}, gram=${gram_tag:-N/A})"
    fi
    if [[ -n "${RASTTK_DB_DIR:-}" ]]; then
      echo "  DB override: $RASTTK_DB_DIR (SEED enrichment will run)"
    elif [[ -f "/db/seed_database_long.tsv" ]]; then
      echo "  DB:          bundled /db (SEED enrichment will run)"
    else
      echo "  DB:          none provided — SEED enrichment skipped (run externally)"
    fi
  }

  /opt/rasttk/scripts/run_rasttk_incremental.sh \
    "$gname" \
    "$fasta" \
    "$rast_out_dir" \
    "$sci" \
    "$GENETIC_CODE" \
    "$effective_domain" \
    "$RUN_MODE" \
    "$domain_suffix"

  if [[ -n "${RASTTK_DB_DIR:-}" ]] || [[ -f "/db/seed_database_long.tsv" ]]; then
    python3 /opt/rasttk/scripts/generate_rast_tsv.py \
        "$rast_out_dir" "$sci" "${effective_domain}"
    if [[ -f "$rast_out_dir/rast.tsv" ]]; then
      mkdir -p "$rast_out_dir/processed"
      mv "$rast_out_dir/rast.tsv" "$rast_out_dir/processed/rast${domain_suffix}.tsv"
    fi
    postproc_db="${RASTTK_DB_DIR:-/db}"
    enriched_tsv="$rast_out_dir/processed/rast${domain_suffix}.tsv"
    if [[ "$NO_POSTPROC" -eq 1 ]]; then
      echo "Done: $enriched_tsv (--no-postproc set; SEED variant enrichment skipped)"
    elif [[ -f "$postproc_db/seed_database_long.tsv" && -f "$enriched_tsv" ]]; then
      enricher="$POSTPROC_DIR/enrich-rast-tsv.py"
      if [[ ! -f "$enricher" ]]; then
        echo "WARN: postproc enricher not found at $enricher; skipping"
      else
        echo "  Running in-container SEED enrichment (postproc: $POSTPROC_DIR) ..."
        python3 "$enricher" --db "$postproc_db" --rast-tsv "$enriched_tsv" \
          && echo "Done: $enriched_tsv (SEED-enriched + variant-called)" \
          || echo "WARN: SEED enrichment failed; basic rast.tsv preserved"
      fi
    else
      echo "Done: $enriched_tsv (SEED-enriched: subsystem hierarchy only; no variant calls)"
      echo "  (mount db dir with seed_database_long.tsv for full variant enrichment)"
    fi
  else
    echo "Done: $rast_out_dir/processed/rast${domain_suffix}.tsv (no SEED enrichment)"
  fi
}

# =============================================================================
# Main
# =============================================================================
if [[ -n "$DB_DIR" ]]; then
  [[ -d "$DB_DIR" ]] || { echo "ERROR: database dir not found: $DB_DIR"; exit 1; }
  export RASTTK_DB_DIR="$DB_DIR"
fi

if [[ -d "$INPUT_PATH" ]]; then
  if [[ -n "$SCIENTIFIC_NAME" ]]; then
    echo "Note: --scientific is ignored for directory mode; name is derived per file."
  fi
  if [[ -n "$GENOME_NAME" ]]; then
    echo "Note: --name is ignored for directory mode; name is derived per file."
  fi

  mapfile -t FASTAS < <(find "$INPUT_PATH" -maxdepth 1 -type f \( -name '*.fna' -o -name '*.fasta' -o -name '*.fa' \) | sort)
  [[ ${#FASTAS[@]} -gt 0 ]] || { echo "ERROR: no FASTA files found in directory: $INPUT_PATH"; exit 1; }

  total="${#FASTAS[@]}"
  ok=0
  fail=0

  for idx in "${!FASTAS[@]}"; do
    fasta="${FASTAS[$idx]}"
    echo "[$((idx + 1))/$total] Processing $(basename "$fasta")"
    if run_one "$fasta" "" ""; then
      ok=$((ok + 1))
    else
      fail=$((fail + 1))
    fi
  done

  echo "Batch complete: success=$ok failed=$fail"
  [[ "$fail" -eq 0 ]] || exit 2
else
  run_one "$INPUT_PATH" "$GENOME_NAME" "$SCIENTIFIC_NAME"
fi
