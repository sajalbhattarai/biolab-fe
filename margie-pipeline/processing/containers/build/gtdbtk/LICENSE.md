# Licences — gtdbtk container

This document covers licenses, attribution, and provenance expectations for the
`gtdbtk` container in the MARGIE pipeline.

---

## GTDB-Tk 2.7.0

Licence: GNU General Public License v3.0 or later (GPL-3.0-or-later)
Upstream: https://github.com/Ecogenomics/GTDBTk
Source package: Bioconda (`gtdbtk=2.7.0`)

GTDB-Tk is the primary taxonomy assignment software used in this container.
Any redistribution of derivative binaries must comply with GPL terms.

Citation:
	Chaumeil PA, Mussig AJ, Hugenholtz P, Parks DH (2022)
	*GTDB-Tk v2: memory friendly classification with the Genome Taxonomy
	Database.* Bioinformatics 38(23):5315-5316.
	doi:10.1093/bioinformatics/btac672

---

## GTDB Reference Data Package

The GTDB reference package is NOT bundled in this image. It is mounted at
runtime from `db/gtdbtk/` and configured through `GTDBTK_DATA_PATH`.

Users are responsible for obtaining and using GTDB reference data according to
GTDB distribution terms.

Reference download portal:
	https://gtdb.ecogenomic.org/downloads

Citation:
	Parks DH et al. (2022) *GTDB: an ongoing census of bacterial and archaeal
	diversity through a phylogenetically consistent, rank normalized and
	complete genome-based taxonomy.* Nucleic Acids Research 50(D1):D785-D794.
	doi:10.1093/nar/gkab776

---

## Runtime Dependencies Installed with GTDB-Tk (Bioconda Stack)

Installed as dependencies of GTDB-Tk (via conda/bioconda) and executed by
`gtdbtk classify_wf`:

- FastANI 1.34
- skani 0.3.2
- HMMER 3.4
- Prodigal 2.6.3
- pplacer 1.1.alpha19

These components keep their own upstream licenses. This container does not
override upstream licensing obligations; users should cite tool-specific
methods where required by their publication standards.

---

## Container Base and First-Party Wrapper

- Base image: `mambaorg/micromamba:1.5.8`
- Wrapper/entrypoint code: first-party pipeline glue (MARGIE project)

The wrapper orchestrates GTDB-Tk execution and writes pipeline provenance
artifacts but does not change GTDB-Tk algorithmic behavior.

---

## Provenance Outputs (for Reproducibility)

The GTDB container writes the following run artifacts:

- `output/gtdbtk/gtdbtk/raw/pipeline-log.txt`
	Detailed step-by-step provenance log (inputs, parameters, command lines,
	timing, and completion status).

- `output/gtdbtk/gtdbtk/raw/trees/tree_manifest.tsv`
	Mapping from raw tree/placement source files to exported tree artifacts.

- `output/gtdbtk/gtdbtk/raw/trees/*`
	Exported tree-related files discovered from GTDB raw outputs (`*.tree`,
	`*.tre`, `*.nwk`, `*.newick`, and placement JSON where produced).

These files are intended for publication audit trails and do not supersede
upstream GTDB-Tk or GTDB license requirements.
