#!/bin/bash
#SBATCH --job-name=gtdb-neighborhoods
#SBATCH --account=YOUR_ACCOUNT   # set to your HPC allocation
#SBATCH --partition=cpu
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=24:00:00
#SBATCH --output=logs/annotation/gtdb-neighborhoods-%j.out
#SBATCH --error=logs/annotation/gtdb-neighborhoods-%j.err

set -euo pipefail

REPO_ROOT="${SLURM_SUBMIT_DIR:-}"
if [[ -z "$REPO_ROOT" || ! -f "$REPO_ROOT/processing/scripts/generate-gtdb-neighborhoods.py" ]]; then
    REPO_ROOT="$HOME/margie-pipeline"
fi
cd "$REPO_ROOT"

mkdir -p logs/annotation output/gtdbtk/gtdbtk/processed/neighborhoods

export MPLBACKEND=Agg

python3 processing/scripts/generate-gtdb-neighborhoods.py
