# Licensing summary — all containers

This file is the **master licensing reference** for the annotation-pipeline containers. Every per-tool container has its own `LICENSE.md` with verbatim-quoted licence text and plain-language interpretation; this file aggregates them into a single peer-review-ready table.

**For publication and redistribution decisions, always cross-check the per-tool `LICENSE.md`.**

## Quick legend

| Symbol | Meaning |
|---|---|
| ✅ | Permitted without further action |
| ⚠️ | Permitted but with conditions (read the per-tool LICENSE.md) |
| ❌ | Not permitted |
| 🔑 | User must obtain a licence or register before downloading the data/binary |

## Master table — A1 + A2 sequence-similarity / HMM tools (built from source)

| Tool | Engine | Engine licence | Database | DB licence | Bundle DB in image? | Commercial OK? | User action |
|---|---|---|---|---|---|---|---|
| `pfam` | HMMER 3.4 | BSD-3-Clause | Pfam-A | CC0 (public domain) | ❌ user downloads | ✅ | none |
| `tigrfam` | HMMER 3.4 | BSD-3-Clause | TIGRFAMs 15.0 | CC-BY-SA 4.0 | ❌ user downloads | ✅ | attribute |
| `pgap` | HMMER 3.4 | BSD-3-Clause | NCBI PGAP HMMs | U.S. Public Domain | ❌ user downloads | ✅ | none |
| `uniprot` | DIAMOND 2.1.9 | GPL-3.0+ | UniProt Swiss-Prot | CC-BY 4.0 | ❌ user downloads | ✅ | attribute |
| `merops` | DIAMOND 2.1.9 | GPL-3.0+ | MEROPS 12.5 | **Academic only** | ❌ user downloads | ❌ commercial requires licence | 🔑 register at EBI |
| `tcdb` | DIAMOND 2.1.9 | GPL-3.0+ | TCDB 2024 | Free academic; commercial needs permission | ❌ user downloads | ⚠️ Saier Lab permission | 🔑 if commercial |
| `cog` | NCBI BLAST+ 2.16.0 + cogclassifier 2.0.0 | Public Domain + MIT | NCBI CDD COG | U.S. Public Domain | ❌ user downloads | ✅ | none |
| `dbcan` | run_dbcan 5.1.2 (HMMER + DIAMOND + pyrodigal) | GPL-3.0+ | dbCAN HMMs | CC-BY-SA 4.0 | ❌ user downloads | ✅ | attribute + GPL chain |
| `eggnog` | eggNOG-mapper 2.1.12 (HMMER + DIAMOND) | **AGPL-3.0+** | eggNOG 5.0.2 | CC-BY 4.0 | ❌ user downloads | ✅ | ⚠️ network-deploy must expose source |
| `kegg` | KofamScan 1.3.0 + HMMER 3.4 | MIT + BSD-3 | KOfam HMMs | Free | ❌ user downloads | ✅ | none for KOfam; full KEGG = commercial licence |

## Master table — A1 + A2 ML / topology tools

| Tool | Engine | Engine licence | Model weights | Weights licence | Commercial OK? | User action |
|---|---|---|---|---|---|---|
| `tmbed` | TMbed 1.0.0 (PyTorch CPU) | Apache-2.0 | ProtT5-XL-U50 | **CC-BY-NC-SA 4.0** | ❌ NonCommercial | 🔑 contact Rostlab for commercial |
| `tmhmm` | tmhmm.py 1.3.2 (MIT reimplementation) | MIT | n/a | n/a | ✅ | none (NOT the proprietary DTU TMHMM2) |
| `operon` | UniOP (vendored snapshot 2025-05-30) + Prodigal | MIT + GPL-3 | n/a | n/a | ✅ | none |

## Master table — classify (pre-pipeline domain / gram-stain detector)

| Component | Version | Licence | Commercial OK? | User action |
|---|---|---|---|---|
| Prodigal (gene caller) | 2.6.3 | GPL-3.0+ | ✅ | cite Hyatt et al. 2010, BMC Bioinformatics 11:119 |
| HMMER / nhmmer (rRNA search) | 3.x | BSD-3-Clause | ✅ | none |
| Barrnap HMMs (rRNA database) | 0.9 | GPL-3.0 | ✅ | cite Seemann T. github.com/tseemann/barrnap |
| DIAMOND (gram-stain markers, fallback Tier 3) | 2.1.9 | GPL-3.0+ | ✅ | none |
| NCBI BLAST+ / blastn (SILVA search, Tier 2) | 2.14 | Public Domain | ✅ | none |
| SILVA SSU NR99 (16S gram-stain DB, Tier 2) | 138.2 | **CC BY 4.0** | ✅ | ⚠️ cite Quast C et al. (2013) Nucleic Acids Res 41(D1):D590-D596 |
| UniProt Swiss-Prot seeds (BamA/LtaS markers) | — | CC BY 4.0 | ✅ | ⚠️ attribute UniProt Consortium |
| classify_genome.py (first-party) | 1.1.0 | MIT | ✅ | none |

## Master table — A3 downstream / wrapper tools

| Tool | License | Bundle in public registry? | Commercial OK? | User action |
|---|---|---|---|---|
| `interpro` | Apache-2.0 (core) + mixed member-DB licences | ✅ core; ⚠️ ProSite/SMART commercial restricted | ⚠️ mixed | 🔑 if using ProSite/SMART commercially |
| `psortb` | GPL-2.0+ | ✅ | ✅ | keep GPL chain; gated by this pipeline (off until accepted) |
| `deepsig` | GPL-3.0+ | ✅ | ✅ | keep GPL chain |
| `phobius` | **Academic only, NO redistribution** | ❌ **MUST strip tarball before push** | ❌ commercial requires DTU licence | 🔑 each user registers at SBC |
| `signalP4` | **Academic only, NO redistribution** | ❌ NOT bundled (intentionally empty) | ❌ commercial requires DTU licence | 🔑 each user registers at DTU |
| `rasttk` | BSD-3-Clause-style (Argonne) | ✅ | ✅ | none |
| `geneprop` | Apache-2.0 (GenProp) | ✅ | ✅ | none |
| `prodigal` | GPL-3.0 | ✅ | ✅ | keep GPL chain |
| `envelope` | BSD-3-Clause (first-party) | ✅ | ✅ | none |

## Compliance checklist before publishing this image set to a public registry

1. **Strip Phobius** — delete `processing/containers/build/phobius/phobius101_linux.tgz` before any `docker push` to a public registry.
2. **Ensure SignalP4 is empty** — `processing/containers/build/signalP4/` must contain no DTU-licensed tarball.
3. **Document AGPL exposure** — if you deploy `eggnog` as a network service, expose a "Source" link pointing to https://github.com/eggnogdb/eggnog-mapper.
4. **Document NonCommercial constraints** — `tmbed` produces outputs that inherit the CC-BY-NC-SA-4.0 restriction of ProtT5. Make this visible to downstream pipeline users.
5. **Cite upstream tools** in any publication using this pipeline. Per-tool `LICENSE.md` files include the recommended citation.
6. **Check commercial-use posture** — if any downstream user of your image will use it commercially, audit MEROPS, TCDB, ProSite, SMART, SignalP, Phobius, TMHMM2, and ProtT5; each requires a separate commercial licence.

## How to obtain commercial / academic permissions — quick reference

| Tool | Contact | URL |
|---|---|---|
| MEROPS commercial | merops-helpdesk@ebi.ac.uk | https://www.ebi.ac.uk/about/contact/support/merops |
| TCDB commercial | Milton Saier — msaier@ucsd.edu | https://www.tcdb.org |
| ProtT5 commercial (for TMbed) | Rostlab — rostlab@in.tum.de | https://www.rostlab.org/ |
| Phobius academic | Lukas Käll | https://phobius.sbc.su.se/data.html |
| SignalP / TMHMM 2 academic | DTU Health Tech | https://services.healthtech.dtu.dk/ |
| ProSite commercial | licensing@sib.swiss | https://prosite.expasy.org/prosite_license.html |
| SMART commercial | smart@embl.de | http://smart.embl.de/ |
| Full KEGG commercial | kegg@kanehisa.jp | https://www.kegg.jp/kegg/legal.html |

---

*Generated as part of the from-source migration. For peer-review reproducibility, see `processing/containers/build/<tool>/VERSIONS` for upstream URLs + pinned versions, and `processing/scripts/setup-scripts/setup-containers/build-<tool>.sh` for the build invocation.*
