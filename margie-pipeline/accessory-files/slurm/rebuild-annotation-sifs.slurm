#!/bin/bash
# rebuild-annotation-sifs.slurm — rebuild all 20 updated annotation container SIFs.
# Run after entrypoint changes (directory-mode refactor + operon enable + postproc move).
#
# Submit:
#   sbatch accessory-files/slurm/rebuild-annotation-sifs.slurm
#
# To rebuild a subset, pass tool names:
#   sbatch accessory-files/slurm/rebuild-annotation-sifs.slurm consolidation
#   sbatch accessory-files/slurm/rebuild-annotation-sifs.slurm kegg eggnog
#SBATCH --job-name=margie-rebuild-sifs
#SBATCH --account=YOUR_ACCOUNT   # set to your HPC allocation
#SBATCH --partition=cpu
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=64G
#SBATCH --time=06:00:00
#SBATCH --output=logs/annotation/rebuild-sifs-%j.out
#SBATCH --error=logs/annotation/rebuild-sifs-%j.err

set -euo pipefail
cd "$SLURM_SUBMIT_DIR"
mkdir -p logs/annotation

module load apptainer 2>/dev/null || module load singularity 2>/dev/null || true

BUILD_ROOT="$SLURM_SUBMIT_DIR/processing/containers/build"
SIF_DIR="$SLURM_SUBMIT_DIR/processing/containers/sifs"
mkdir -p "$SIF_DIR"

# All 20 containers updated in this session (directory-mode + gram-detection refactor).
ALL_TOOLS=(
    kegg cog pfam pgap tigrfam dbcan eggnog merops tcdb uniprot interpro geneprop
    tmhmm tmbed phobius tatfinder psortb deepsig
    operon
    consolidation
)

# Allow caller to pass a subset: sbatch ... kegg consolidation
if [[ $# -gt 0 ]]; then
    TOOLS=("$@")
else
    TOOLS=("${ALL_TOOLS[@]}")
fi

total=${#TOOLS[@]}
ok_count=0
fail_count=0
failed_tools=()

echo "[$(date)] Rebuilding $total SIF(s): ${TOOLS[*]}"
echo "================================================================"

for tool in "${TOOLS[@]}"; do
    BUILD_DIR="$BUILD_ROOT/$tool"
    SIF="$SIF_DIR/${tool}.sif"

    if [[ ! -d "$BUILD_DIR" ]]; then
        echo "[$(date)] SKIP $tool — no build dir at $BUILD_DIR" >&2
        continue
    fi
    if [[ ! -f "$BUILD_DIR/apptainer.def" ]]; then
        echo "[$(date)] SKIP $tool — no apptainer.def in $BUILD_DIR" >&2
        continue
    fi

    echo "================================================================"
    echo "[$(date)] [$((ok_count + fail_count + 1))/$total] Building: $tool"
    echo "  BUILD_DIR : $BUILD_DIR"
    echo "  SIF       : $SIF"
    echo "================================================================"

    if (cd "$BUILD_DIR" && apptainer build --fakeroot --force "$SIF" apptainer.def); then
        echo "[$(date)] OK: $tool → $SIF"
        ok_count=$(( ok_count + 1 ))
    else
        echo "[$(date)] FAILED: $tool" >&2
        fail_count=$(( fail_count + 1 ))
        failed_tools+=("$tool")
    fi
done

echo "================================================================"
echo "[$(date)] Build summary: success=$ok_count  failed=$fail_count  total=$total"
if (( ${#failed_tools[@]} )); then
    echo "[$(date)] FAILED tools: ${failed_tools[*]}" >&2
    exit 1
fi
echo "[$(date)] All SIFs rebuilt successfully."
