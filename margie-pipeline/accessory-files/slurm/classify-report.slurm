#!/bin/bash
#SBATCH --job-name=classify-report
#SBATCH --account=YOUR_ACCOUNT   # set to your HPC allocation
#SBATCH --partition=cpu
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=02:00:00
#SBATCH --output=logs/annotation/classify-report-%j.out
#SBATCH --error=logs/annotation/classify-report-%j.err

set -euo pipefail

REPO_ROOT="${SLURM_SUBMIT_DIR:-}"
if [[ -z "$REPO_ROOT" || ! -f "$REPO_ROOT/processing/scripts/run-individual-containers/run-classify.sh" ]]; then
    REPO_ROOT="$HOME/margie-pipeline"
fi
cd "$REPO_ROOT"

mkdir -p logs/annotation

processing/scripts/run-individual-containers/run-classify.sh
