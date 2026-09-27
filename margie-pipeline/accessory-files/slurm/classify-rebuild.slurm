#!/bin/bash
#SBATCH --job-name=classify-build
#SBATCH --account=YOUR_ACCOUNT   # set to your HPC allocation
#SBATCH --partition=cpu
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=64G
#SBATCH --time=00:30:00
#SBATCH --output=logs/annotation/classify-build-%j.out
#SBATCH --error=logs/annotation/classify-build-%j.err

set -euo pipefail
cd "$SLURM_SUBMIT_DIR"
mkdir -p logs/annotation

module load apptainer 2>/dev/null || module load singularity 2>/dev/null || true

BUILD_DIR="processing/containers/build/classify"
SIF="$SLURM_SUBMIT_DIR/processing/containers/sifs/classify.sif"

echo "[$(date)] Building classify SIF from $BUILD_DIR"
cd "$BUILD_DIR"
apptainer build --fakeroot --force "$SIF" apptainer.def
echo "[$(date)] BUILD OK — $SIF"
