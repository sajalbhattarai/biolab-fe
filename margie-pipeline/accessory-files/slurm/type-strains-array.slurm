#!/bin/bash
# type-strains-array.slurm — download all type-strain genomes using a
# 16-task SLURM array.  Each task handles 1/16 of the manifest independently
# (by row-index modulo shard_total), skipping already-downloaded files.
#
# Usage:
#   sbatch type-strains-array.slurm                     # 16 shards, scope=all
#   sbatch type-strains-array.slurm --scope report      # only report accessions
#
# After all tasks complete, run the reconcile step to sync the manifest TSV:
#   sbatch --dependency=afterok:<JOBID> type-strains-reconcile.slurm
#
#SBATCH --job-name=margie-type-strains
#SBATCH --account=YOUR_ACCOUNT   # set to your HPC allocation
#SBATCH --partition=cpu
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=4G
#SBATCH --time=23:00:00
#SBATCH --array=0-15
#SBATCH --output=logs/databases/type-strains-%A_%a.out
#SBATCH --error=logs/databases/type-strains-%A_%a.err

set -euo pipefail
cd "$SLURM_SUBMIT_DIR"
mkdir -p logs/databases

module load apptainer 2>/dev/null || module load singularity 2>/dev/null || true

export MARGIE_ACCEPT_TERMS=1
export TYPE_STRAINS_SCOPE="${TYPE_STRAINS_SCOPE:-all}"
export TYPE_STRAINS_SHARD_INDEX="$SLURM_ARRAY_TASK_ID"
export TYPE_STRAINS_SHARD_TOTAL=16

echo "[shard ${SLURM_ARRAY_TASK_ID}/16] starting — scope=${TYPE_STRAINS_SCOPE}"

./setup.sh --databases-only --tool type_strains --accept-all-licenses "$@"

echo "[shard ${SLURM_ARRAY_TASK_ID}/16] done"
