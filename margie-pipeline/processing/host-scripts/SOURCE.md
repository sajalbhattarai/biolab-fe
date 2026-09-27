# Host scripts from margie-backend

These are margie-backend's post-annotation scripts, copied unchanged from
`bioinformatics_tools/workflow_tools/` at margie-backend commit `6075d32`.
They run on the host, not in a container, as they do in margie-backend's
`margie_sb.smk`; `processing/scripts/run-individual-containers/run-meta.sh`
calls them with the same arguments and in the same order.

| Folder / file | margie_sb step |
|---|---|
| `consolidation/` | phase 9: merge every tool's results into one table per genome |
| `labeling/` | phase 10: canonical label, EC consensus, operon info, cluster agreement |
| `scoring/` | phase 11: OCC reference update, C1-C4 and the final confidence score |
| `fingerprint/` | phase 12: gene and operon fingerprints, FINAL tables, Excel export |
| `evidence/` | phase 14: per-gene evidence report |
| `viz/` | interactive genome viewer and circular map |
| `scoring/analysis/report_figures/` | per-organism and pangenome report figures |
| `enrich_with_envelope.py` | adds the envelope call to deepsig / psortb / signalp4 results |
| `reorganize_outputs.py` | final per-genome folder layout |

Not copied: `scoring/analysis/c3_figures/` (research figures, not part of a
run), the database loaders and the LLM step.

They need Python 3.11+ with the packages in `requirements.txt`;
`processing/scripts/shared/host-python.sh` creates that environment on first
use (or set `MARGIE_PYTHON` to an interpreter that already has them).

## Updating

Copy the folders again from a margie-backend checkout, then update the commit
above:

```bash
SRC=../margie-backend/bioinformatics_tools/workflow_tools
DST=processing/host-scripts
for d in consolidation labeling fingerprint evidence viz; do
    rsync -a --delete --exclude __pycache__ "$SRC/$d/" "$DST/$d/"
done
rsync -a --exclude __pycache__ --exclude analysis "$SRC/scoring/" "$DST/scoring/"
rsync -a --delete --exclude __pycache__ "$SRC/scoring/analysis/report_figures/" "$DST/scoring/analysis/report_figures/"
cp "$SRC/enrich_with_envelope.py" "$SRC/reorganize_outputs.py" "$DST/"
```
