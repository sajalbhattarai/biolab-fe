# rasttk container — licensing

## Summary

| Component | License | Bundled? | Redistribution | Commercial | User action? |
|---|---|---|---|---|---|
| RASTtk (rast_run_pipeline + SEED toolkit) | BSD-3-Clause-style | ✅ yes (Debian apt or upstream tarball) | ✅ allowed | ✅ allowed | none |
| BV-BRC CLI tools | BSD-style | ✅ | ✅ | ✅ | none |
| BLAST+, HMMER, Prodigal, etc. | various (see below) | ✅ | ✅ | ✅ | none |
| SEED subsystems data | Free for academic and commercial use | ✅ (snapshot) | ✅ with attribution | ✅ | none |
| Debian 12 slim | various | ✅ | ✅ | ✅ | none |

---

## 1. RASTtk (Rapid Annotation using Subsystem Technology) — BSD-3-Clause-style

**Upstream:** Argonne National Laboratory / BV-BRC consortium
**Source:** https://github.com/SEEDtk/SEEDtk and https://github.com/BV-BRC/BV-BRC-CLI
**Citations:**
- **Original RAST:** Aziz, R.K. *et al.* (2008) *The RAST Server: Rapid Annotations using Subsystems Technology.* BMC Genomics 9:75. doi:[10.1186/1471-2164-9-75](https://doi.org/10.1186/1471-2164-9-75)
- **RAST-TK (the algorithm):** Brettin, T. *et al.* (2015) *RASTtk: a modular and extensible implementation of the RAST algorithm for building custom annotation pipelines and annotating batches of genomes.* Scientific Reports 5:8365. doi:[10.1038/srep08365](https://doi.org/10.1038/srep08365)
- **BV-BRC (the platform delivering the CLI used by this image):** Olson, R.D. *et al.* (2023) *Introducing the Bacterial and Viral Bioinformatics Resource Center (BV-BRC): a resource combining PATRIC, IRD and ViPR.* Nucleic Acids Research 51(D1):D678–D689. doi:[10.1093/nar/gkac1003](https://doi.org/10.1093/nar/gkac1003)

### License notice (quoted from the SEEDtk `LICENSE`):

> Copyright (c) Argonne National Laboratory, University of Chicago.
>
> Redistribution and use in source and binary forms, with or without
> modification, are permitted provided that the following conditions are
> met:
>   1. Redistributions of source code must retain the above copyright
>      notice, this list of conditions and the following disclaimer.
>   2. Redistributions in binary form must reproduce the above copyright
>      notice, this list of conditions and the following disclaimer in the
>      documentation and/or other materials provided with the distribution.
>   3. Neither the name of Argonne National Laboratory nor the names of its
>      contributors may be used to endorse or promote products derived from
>      this software without specific prior written permission.
>
> THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
> IS"...

**Plain language:** unrestricted use; retain copyright notice; do not use the Argonne name in promotional materials without permission.

## 2. Bundled bioinformatics tools

RASTtk wraps many tools; each retains its own licence:

| Tool | License |
|---|---|
| BLAST+ | U.S. Public Domain |
| HMMER | BSD-3-Clause |
| Prodigal | GPL-3.0 |
| tRNAscan-SE | GPL |
| Infernal | BSD |
| RAxML | GPL-3.0 |

See individual upstream LICENSE files inside the RASTtk distribution for full text.

## 3. SEED subsystems data

**Upstream:** SEED Project — http://seed-viewer.theseed.org/ (PubSEED + Sapling + ModelSEED)

**Citations:**
- **Original SEED:** Overbeek, R. *et al.* (2005) *The Subsystems Approach to Genome Annotation and its Use in the Project to Annotate 1000 Genomes.* Nucleic Acids Research 33(17):5691–5702. doi:[10.1093/nar/gki866](https://doi.org/10.1093/nar/gki866)
- **SEED + RAST:** Overbeek, R. *et al.* (2014) *The SEED and the Rapid Annotation of microbial genomes using Subsystems Technology (RAST).* Nucleic Acids Research 42(D1):D206–D214. doi:[10.1093/nar/gkt1226](https://doi.org/10.1093/nar/gkt1226)
- **SAS / Sapling SOAP server bundle (`sas.tgz`) used by the build pipeline:** Disz, T. *et al.* (2010) *Accessing the SEED Genome Databases via Web Services API: Tools for Programmers.* BMC Bioinformatics 11:319. doi:[10.1186/1471-2105-11-319](https://doi.org/10.1186/1471-2105-11-319)

### License notice (quoted from SEED Project terms):

> The SEED database and subsystems are made freely available for academic
> and commercial use, subject to citation of the SEED in any resulting
> publications.

**Plain language:** unrestricted use with citation.

### 3a. How the bundled snapshot was produced — first-party build pipeline

The SEED tables mounted into this container (`seed_database_long.tsv`,
`seed_database_wide.tsv`, `seed_database.json`) are **not** a redistributable
upstream release. They are a snapshot assembled by a first-party download
pipeline that talks to the live SEED servers and merges in ModelSEED and KEGG
cross-references.

- **Build pipeline repo:** https://github.com/sajalbhattarai/seed-database-download (MIT — pipeline scripts only)
- **Build image:** `ghcr.io/sajalbhattarai/seed-db:latest` (multi-arch: linux/amd64, linux/arm64)
- **Compiled / adapted by:** Sajal Bhattarai (ORCID [0000-0002-3143-5483](https://orcid.org/0000-0002-3143-5483))
- **License of the build pipeline:** MIT (covers the code only — the *data* the pipeline pulls remains under the SEED Project terms of use above).

The build pipeline scrapes / queries the following live sources at run time:

| Source | Data |
|---|---|
| `pubseed.theseed.org` SOAP API | Subsystem catalog, class hierarchy, role mappings, reaction data |
| `pubseed.theseed.org/subsys.cgi` | Author, last-modified, descriptions, curation notes (ISO-8859-1 decoded → UTF-8) |
| Sapling API | Curator description texts |
| `svr_subsystem_spreadsheet` | Full variant spreadsheets per subsystem |
| [ModelSEED Biochemistry](https://github.com/ModelSEED/ModelSEEDDatabase) GitHub | Compound names, formulas, InChIKey |
| KEGG REST API | Reaction / compound cross-references (see KEGG container LICENSE.md for KEGG's own terms) |

### 3b. ModelSEED biochemistry

**Citation:** Henry, C.S. *et al.* (2010) *High-throughput generation, optimization and analysis of genome-scale metabolic models.* Nature Biotechnology 28:977–982. doi:[10.1038/nbt.1672](https://doi.org/10.1038/nbt.1672)

### 3c. FIGfam protein family annotations (consumed by RAST)

**Citation:** Meyer, F. *et al.* (2009) *FIGfams: yet another set of protein families.* Nucleic Acids Research 37(20):6643–6654. doi:[10.1093/nar/gkp698](https://doi.org/10.1093/nar/gkp698)

## 4. Base image
Debian 12 slim. See https://www.debian.org/legal/licenses/.

## Obtaining permissions
None required.
