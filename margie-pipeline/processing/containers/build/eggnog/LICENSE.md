# eggnog container — licensing

⚠️ **This container is licensed under AGPL-3.0. If you offer this pipeline as a network service (e.g. a web API), you must offer the corresponding source code to users.** See section 1 below.

## Summary

| Component | License | Bundled? | Redistribution | Commercial | User action? |
|---|---|---|---|---|---|
| eggNOG-mapper 2.1.12 | **AGPL-3.0-or-later** | ✅ yes (pip) | ✅ under AGPL | ✅ allowed | ⚠️ network deployment must expose source |
| HMMER 3.4 | BSD-3-Clause | ✅ yes (from-source) | ✅ | ✅ | none |
| DIAMOND 2.1.9 | GPL-3.0-or-later | ✅ yes (from-source) | ✅ under GPL | ✅ | none |
| eggNOG 5.0.2 database | CC-BY 4.0 | ❌ no — downloaded by `download-eggnog.sh` | ✅ with attribution | ✅ | none |
| Python 3.11-slim base | PSF + Debian | ✅ | ✅ | ✅ | none |

---

## 1. eggNOG-mapper — GNU Affero General Public License v3 (AGPL-3.0-or-later)

**Upstream:** https://github.com/eggnogdb/eggnog-mapper
**Source:** https://pypi.org/project/eggnog-mapper/2.1.12/
**Author:** Jaime Huerta-Cepas and contributors
**Citations:**
- **Original eggNOG-mapper:** Huerta-Cepas, J. *et al.* (2017) *Fast genome-wide functional annotation through orthology assignment by eggNOG-mapper.* Molecular Biology and Evolution 34(8):2115–2122. doi:[10.1093/molbev/msx148](https://doi.org/10.1093/molbev/msx148)
- **Latest (v2 — this image):** Cantalapiedra, C.P. *et al.* (2021) *eggNOG-mapper v2: Functional Annotation, Orthology Assignments, and Domain Prediction at the Metagenomic Scale.* Molecular Biology and Evolution 38(12):5825–5829. doi:[10.1093/molbev/msab293](https://doi.org/10.1093/molbev/msab293)

### License notice (quoted from eggnog-mapper `LICENSE`, AGPL-3.0 §13):

> If you modify the Program, your modified version must prominently offer all
> users interacting with it remotely through a computer network (if your
> version supports such interaction) an opportunity to receive the
> Corresponding Source of your version by providing access to the
> Corresponding Source from a network server at no charge, through some
> standard or customary means of facilitating copying of software. This
> Corresponding Source shall include the Corresponding Source for any work
> covered by version 3 of the GNU General Public License that is
> incorporated pursuant to the following paragraph.

### Plain-language interpretation

- **Local use is unrestricted.** Use the container freely on your laptop, on HPC, or in a private workflow.
- **Network deployment (e.g. SaaS, public web API):** if you expose eggNOG-mapper to remote users over a network, you must offer those users a way to download the corresponding source code (the eggnog-mapper source plus any of your modifications). We do not modify eggnog-mapper; downstream distributors who do must add a "Source" link visible to end users.
- **Combining with proprietary code:** AGPL prohibits linking eggnog-mapper into a proprietary binary. Our pipeline only invokes it via the CLI, so the rest of the pipeline remains independent.
- **No warranty** is offered.

---

## 2. HMMER — BSD-3-Clause
Same as `pfam`. See `pfam/LICENSE.md` for full text.

## 3. DIAMOND — GPL-3.0-or-later
Same as `uniprot`. See `uniprot/LICENSE.md` for full text.

## 4. eggNOG database — CC-BY 4.0

**Upstream:** EMBL eggNOG team
**Source:** http://eggnogdb.embl.de/download/emapperdb-5.0.2/
**Citations:**
- **Database release this image uses (5.0.2):** Huerta-Cepas, J. *et al.* (2019) *eggNOG 5.0: a hierarchical, functionally and phylogenetically annotated orthology resource based on 5090 organisms and 2502 viruses.* Nucleic Acids Research 47(D1):D309–D314. doi:[10.1093/nar/gky1085](https://doi.org/10.1093/nar/gky1085)
- **Latest database (6.0 — not used here, kept for reference):** Hernández-Plaza, A. *et al.* (2023) *eggNOG 6.0: enabling comparative genomics across 12,535 organisms.* Nucleic Acids Research 51(D1):D389–D394. doi:[10.1093/nar/gkac1022](https://doi.org/10.1093/nar/gkac1022)

### License notice (quoted from eggNOG download page):

> The eggNOG data is released under the Creative Commons Attribution 4.0
> International License.

**Plain language:** use, redistribute, modify freely; attribute eggNOG (cite the 2019 paper). Not bundled in this image.

---

## 5. Base image
`python:3.11-slim`. Python is PSF-2.0; Debian packages governed by their individual licenses.

## Obtaining permissions
None required. AGPL compliance is the only operational concern: if you network-deploy this image, expose a link to https://github.com/eggnogdb/eggnog-mapper somewhere user-visible.
