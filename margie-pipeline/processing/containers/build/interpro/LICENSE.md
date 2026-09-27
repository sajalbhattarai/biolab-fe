# interpro container — licensing

## Summary

| Component | License | Bundled? | Redistribution | Commercial | User action? |
|---|---|---|---|---|---|
| InterProScan 5.x (core) | Apache-2.0 | ✅ yes (bundled installer) | ✅ allowed | ✅ allowed | none |
| InterPro member databases | mixed — see breakdown below | partly bundled, partly downloaded | ⚠️ varies per member db | ⚠️ varies | ⚠️ check each member database |
| OpenJDK 11 | GPL-2.0 with Classpath Exception | ✅ yes | ✅ allowed | ✅ allowed | none |
| Debian 12 slim | various | ✅ | ✅ | ✅ | none |

⚠️ **AMD64 only.** InterProScan ships with bundled JVM + binary dependencies for `linux/amd64` only. ARM users run under emulation.

---

## 1. InterProScan core — Apache-2.0

**Upstream:** EMBL-EBI InterPro team
**Source:** https://github.com/ebi-pf-team/interproscan
**Citations:**
- **InterProScan engine (original):** Jones, P. *et al.* (2014) *InterProScan 5: genome-scale protein function classification.* Bioinformatics 30(9):1236–1240. doi:[10.1093/bioinformatics/btu031](https://doi.org/10.1093/bioinformatics/btu031)
- **InterPro consortium (latest dedicated update):** Paysan-Lafosse, T. *et al.* (2023) *InterPro in 2022.* Nucleic Acids Research 51(D1):D418–D427. doi:[10.1093/nar/gkac993](https://doi.org/10.1093/nar/gkac993)
- **Original InterPro:** Apweiler, R. *et al.* (2001) *The InterPro database, an integrated documentation resource for protein families, domains and functional sites.* Nucleic Acids Research 29(1):37–40. doi:[10.1093/nar/29.1.37](https://doi.org/10.1093/nar/29.1.37)

**Latest release tarballs:** https://ftp.ebi.ac.uk/pub/software/unix/iprscan/5/

### License notice (quoted from InterProScan `LICENSE`):

> Licensed under the Apache License, Version 2.0 (the "License"); you may not
> use this file except in compliance with the License. You may obtain a copy
> of the License at
>
>     http://www.apache.org/licenses/LICENSE-2.0
>
> Unless required by applicable law or agreed to in writing, software
> distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
> WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.

**Plain language:** the InterProScan engine itself is freely redistributable for any use, academic or commercial.

---

## 2. InterPro member databases — varied terms

InterProScan integrates many member databases, each with its own licence. Some are bundled in the InterProScan release tarball; others must be downloaded separately by the end user.

### Bundled and unrestricted (academic + commercial)

| Database | License | Notes |
|---|---|---|
| Pfam | CC0 (public domain) | bundled |
| TIGRFAM | CC-BY-SA 4.0 | bundled, attribution required |
| HAMAP | CC-BY 4.0 | bundled |
| PIRSF | Free, attribution | bundled |
| PRINTS | Free, attribution | bundled |
| SUPERFAMILY | Free for academic and commercial use | bundled |
| Gene3D | Free | bundled |

### Bundled but with restrictions

| Database | License | Notes |
|---|---|---|
| ProSite | **Free academic; commercial use requires SIB licence** | bundled; commercial users contact licensing@sib.swiss |
| SMART | **Academic only — commercial use requires EMBL licence** | bundled; commercial users contact smart@embl.de |
| CATH-Gene3D | Free for academic and commercial use | bundled |

### Optional / user-downloaded

| Database | License | Notes |
|---|---|---|
| SignalP / TMHMM / Phobius | **Academic only, NO redistribution** | NOT bundled; user must register and add separately |
| PANTHER | Free with registration | NOT bundled by default |

### License notices (quoted)

**ProSite** (from https://prosite.expasy.org/prosite_license.html):
> The use of the PROSITE database is **free of charge for academic and
> non-commercial use**. Commercial users must obtain a licence from the SIB.

**SMART** (from http://smart.embl.de/):
> SMART is freely accessible to academic users; commercial users require a
> separate licence from EMBL.

---

## 3. OpenJDK 11 — GPL-2.0 with Classpath Exception
Bundled via the InterProScan release tarball or Debian apt. The Classpath Exception allows linking with non-GPL code, so user pipelines that invoke InterProScan are not infected by GPL.

## 4. Base image
Debian 12 slim. See https://www.debian.org/legal/licenses/.

## Obtaining commercial permissions

- **ProSite:** licensing@sib.swiss
- **SMART:** smart@embl.de
- **SignalP / TMHMM / Phobius:** see their individual LICENSE.md in this repository.
- **InterPro itself (core):** Apache-2.0 — no permission needed.
