#!/usr/bin/env bash
# Runner for classify — domain/gram-stain detector.
#
# Reads nucleotide FASTA files from USER_INPUT_DIR (default: $REPO_ROOT/user-input/),
# runs the classify container to produce a classification_report.tsv, then
# creates relative symlinks in the appropriate input/ subdirectories so the
# rest of the annotation pipeline picks them up automatically:
#
#   Archaea          → input/archaea/
#   Bacteria (gram-) → input/bacteria/gram-negative/
#   Bacteria (gram+) → input/bacteria/gram-positive/
#   Unknown / other  → input/unknown/
#
# Usage:
#   ./run-classify.sh
#   ./run-classify.sh --list
#   ./run-classify.sh --dry-run      # classify only; do not create symlinks
#   ./run-classify.sh --confidence 0.7
#   ./run-classify.sh --no-db        # skip gram-stain DB even if present
#   TOOL_classify_USER_INPUT=/path/to/fastas ./run-classify.sh

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/../../../pipeline.conf.sh"
source "$here/lib/pipeline-lib.sh"

TOOL=classify
DRY_RUN=0
NO_DB=0
CONFIDENCE=0.6
EXTRA_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --list)         echo "Tool=classify  image=$(tool_image classify)  user-input=${TOOL_classify_USER_INPUT:-$USER_INPUT_DIR}"; exit 0 ;;
        --help|-h)      sed -n '2,16p' "$0"; exit 0 ;;
        --runtime)      RUNTIME="$2"; shift 2 ;;
        --dry-run)      DRY_RUN=1; shift ;;
        --no-db)        NO_DB=1; shift ;;
        --confidence)   CONFIDENCE="$2"; shift 2 ;;
        --)             shift; EXTRA_ARGS+=("$@"); break ;;
        *)              EXTRA_ARGS+=("$1"); shift ;;
    esac
done

image="$(tool_image "$TOOL")"

# ── Resolve paths ─────────────────────────────────────────────────────────────
# TOOL_classify_USER_INPUT overrides the source directory.
user_input_dir="${TOOL_classify_USER_INPUT:-$USER_INPUT_DIR}"
db_dir="$DB_ROOT/classify"
input_root="$gene_caller_input"   # $REPO_ROOT/input — where organised FNAs live

if [[ ! -d "$user_input_dir" ]]; then
    printf '[run-classify] ERROR: user-input directory not found: %s\n' \
        "$user_input_dir" >&2
    printf '[run-classify] Create it and place your .fna genome files there.\n' >&2
    exit 1
fi

fna_count=$(find -L "$user_input_dir" -maxdepth 1 \
    \( -name "*.fna" -o -name "*.fa" -o -name "*.fasta" \) | wc -l)

if [[ "$fna_count" -lt 1 ]]; then
    printf '[run-classify] ERROR: no .fna/.fa/.fasta files found in %s\n' \
        "$user_input_dir" >&2
    exit 1
fi

# ── Output staging (temp dir; only the TSV persists) ──────────────────────────
staging_out="${TMPDIR:-/tmp}/margie-classify-out-$$"
mkdir -p "$staging_out"
trap 'rm -rf "$staging_out"' EXIT

printf '[run-classify] image=%s\n' "$image"
printf '[run-classify] user-input: %s (%d genome(s))\n' "$user_input_dir" "$fna_count"
printf '[run-classify] input root: %s\n' "$input_root"

# ── Build mount array ─────────────────────────────────────────────────────────
MOUNTS=(
    "$user_input_dir:/user-input:ro"
    "$staging_out:/output:rw"
)

CONTAINER_ARGS=(
    -i /user-input
    -o /output
    -t "$THREADS"
    --confidence "$CONFIDENCE"
)

# Attaches the DB dir when a DIAMOND marker (.dmnd) or SILVA BLAST index (.nin/.nhr/.nsq)
# is present and --no-db was not given.
_has_classify_db() {
    find "$1" -maxdepth 1 \
        \( -name '*.dmnd' -o -name '*.nin' -o -name '*.nhr' -o -name '*.nsq' \) \
        -print -quit 2>/dev/null | grep -q .
}
if [[ "$NO_DB" -eq 0 && -d "$db_dir" ]] && _has_classify_db "$db_dir"; then
    MOUNTS+=("$db_dir:/db/classify:ro")
    CONTAINER_ARGS+=(-d /db/classify)
    printf '[run-classify] DB:         %s\n' "$db_dir"
else
    printf '[run-classify] DB:         (not present — gram stain will be "unknown")\n'
fi

[[ "$DRY_RUN" -eq 1 ]] && CONTAINER_ARGS+=(--dry-run)

# ── Run the classify container ────────────────────────────────────────────────
run_container "$image" "${CONTAINER_ARGS[@]}" ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}

# ── Read the report and copy each genome into input/ ──────────────────────────
report_tsv="$staging_out/classification_report.tsv"
if [[ ! -s "$report_tsv" ]]; then
    printf '[run-classify] ERROR: classification_report.tsv not found or empty\n' >&2
    exit 1
fi

# Creates every target directory, archaea included.
mkdir -p \
    "$input_root/archaea" \
    "$input_root/bacteria/gram-negative" \
    "$input_root/bacteria/gram-positive" \
    "$input_root/unknown"

placed=0
skipped=0
unknown_count=0

while IFS=$'\t' read -r genome domain gram_stain confidence \
                          rrna_bac rrna_arc gram_neg_h gram_pos_h method; do
    [[ "$genome" == "genome" ]] && continue
    [[ -z "$genome" ]] && continue

    # Destination from domain and gram stain.
    case "${domain}/${gram_stain}" in
        Archaea/*)          dest="$input_root/archaea" ;;
        Bacteria/negative)  dest="$input_root/bacteria/gram-negative" ;;
        Bacteria/positive)  dest="$input_root/bacteria/gram-positive" ;;
        *)
            dest="$input_root/unknown"
            (( unknown_count++ )) || true
            ;;
    esac

    src="$user_input_dir/$genome"
    if [[ ! -f "$src" ]]; then
        printf '[run-classify] WARNING: source file not found, skipping: %s\n' "$src" >&2
        (( skipped++ )) || true
        continue
    fi

    target_link="$dest/$genome"
    if [[ -f "$target_link" ]]; then
        printf '[run-classify]   already copied: %s → %s/\n' \
            "$genome" "${dest#$REPO_ROOT/}"
        (( skipped++ )) || true
        continue
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
        printf '[run-classify]   [dry-run] %s → %s/\n' \
            "$genome" "${dest#$REPO_ROOT/}"
    else
        cp -p "$src" "$target_link"
        printf '[run-classify]   placed: %s → %s/\n' \
            "$genome" "${dest#$REPO_ROOT/}"
    fi
    (( placed++ )) || true

done < "$report_tsv"

# Keeps a copy of the report under input/ for provenance.
final_report="$input_root/classification_report.tsv"
if [[ "$DRY_RUN" -eq 0 ]]; then
    cp "$report_tsv" "$final_report"
fi

printf '[run-classify] ── Summary ──────────────────────────────────\n'
printf '[run-classify]   Placed:   %d\n' "$placed"
printf '[run-classify]   Skipped (already copied): %d\n' "$skipped"
printf '[run-classify]   Unknown (→ input/unknown/): %d\n' "$unknown_count"
printf '[run-classify]   Report: %s\n' "$final_report"
printf '[run-classify] Done.\n'
