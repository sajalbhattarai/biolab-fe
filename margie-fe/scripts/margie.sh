#!/bin/zsh
# Build and run the MARGIE front-end locally.
#
# Prerequisite: the backend API must be reachable at http://localhost:8000.
# Start the backend and open the SSH tunnel to your HPC first -- see the backend repo:
#   https://github.com/sajalbhattarai/bioinformatics-tools
set -e

cd "$(dirname "$0")/.."     # the margie-fe repo root

npm install
npm run build
npm run dev -- --open       # serves http://localhost:5173 and opens your browser
