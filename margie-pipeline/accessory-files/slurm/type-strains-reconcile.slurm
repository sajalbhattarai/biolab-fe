#!/bin/bash
# type-strains-reconcile.slurm — update the type_strain_genomes.tsv manifest
# after a shard-array download by scanning the genome directory on disk.
# Typically run as a SLURM dependency after type-strains-array.slurm:
#
#   ARRAY_JOB=$(sbatch --parsable type-strains-array.slurm)
#   sbatch --dependency=afterok:${ARRAY_JOB} type-strains-reconcile.slurm
#
#SBATCH --job-name=margie-type-strains-reconcile
#SBATCH --account=YOUR_ACCOUNT   # set to your HPC allocation
#SBATCH --partition=cpu
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=8G
#SBATCH --time=02:00:00
#SBATCH --output=logs/databases/type-strains-reconcile-%j.out
#SBATCH --error=logs/databases/type-strains-reconcile-%j.err

set -euo pipefail
cd "$SLURM_SUBMIT_DIR"
mkdir -p logs/databases

module load apptainer 2>/dev/null || module load singularity 2>/dev/null || true

export MARGIE_ACCEPT_TERMS=1

echo "[reconcile] syncing manifest with filesystem..."

./processing/scripts/setup-scripts/setup-databases/reconcile-type_strains.sh

echo "[reconcile] done"
