# uniprot container — licensing

## Summary

| Component | License | Bundled? | Redistribution | Commercial | User action? |
|---|---|---|---|---|---|
| DIAMOND 2.1.9 | GPL-3.0-or-later | ✅ yes (binary + must offer source on request) | ✅ allowed under GPL terms | ✅ allowed | none, but downstream distributors must keep GPL chain |
| UniProt Swiss-Prot | CC-BY 4.0 | ❌ no — downloaded by `download-uniprot.sh` | ✅ allowed with attribution | ✅ allowed | none, attribution required if republished |
| Debian 12 slim | various | ✅ | ✅ | ✅ | none |

---

## 1. DIAMOND — GNU General Public License v3.0 or later

**Upstream:** https://github.com/bbuchfink/diamond
**Source archive:** https://github.com/bbuchfink/diamond/archive/refs/tags/v2.1.9.tar.gz
**Author:** Benjamin Buchfink and contributors
**Citations:**
- **Original DIAMOND:** Buchfink, B., Xie, C., Huson, D.H. (2015) *Fast and sensitive protein alignment using DIAMOND.* Nature Methods 12:59–60. doi:[10.1038/nmeth.3176](https://doi.org/10.1038/nmeth.3176)
- **Latest (DIAMOND2 — this image's algorithm):** Buchfink, B., Reuter, K., Drost, H.-G. (2021) *Sensitive protein alignments at tree-of-life scale using DIAMOND.* Nature Methods 18:366–368. doi:[10.1038/s41592-021-01101-x](https://doi.org/10.1038/s41592-021-01101-x)

### License notice (quoted from `diamond-2.1.9/LICENSE`, the full GPL-3.0 text):

> This program is free software: you can redistribute it and/or modify it under
> the terms of the GNU General Public License as published by the Free Software
> Foundation, either version 3 of the License, or (at your option) any later
> version.
>
> This program is distributed in the hope that it will be useful, but WITHOUT
> ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
> FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
> more details.
>
> You should have received a copy of the GNU General Public License along with
> this program. If not, see <https://www.gnu.org/licenses/>.

### Plain-language interpretation (GPL §3 — "Conveying Non-Source Forms")

- **You can redistribute** the DIAMOND binary inside this image — academically and commercially.
- **You must** make the *corresponding source code* of the bundled DIAMOND version available to any recipient on request (GPL §6). We satisfy this by pinning the source URL in `VERSIONS` and quoting it here; downstream re-distributors should keep that link reachable or mirror the tarball.
- **You must not** add restrictions that prevent recipients from exercising their GPL rights (e.g. no DRM, no NDAs on the binary).
- Tools that *link against* DIAMOND code (none in this image — we only invoke the binary) would themselves need to be GPL-compatible.
- **No warranty** is offered.

---

## 2. UniProt Swiss-Prot — Creative Commons Attribution 4.0 International

**Upstream:** UniProt Consortium
**Source:** https://ftp.uniprot.org/pub/databases/uniprot/current_release/knowledgebase/complete/uniprot_sprot.fasta.gz
**Citations:**
- **Latest (2025 update):** UniProt Consortium (2025) *UniProt: the Universal Protein Knowledgebase in 2025.* Nucleic Acids Research 53(D1):D609–D617. doi:[10.1093/nar/gkae1010](https://doi.org/10.1093/nar/gkae1010)
- **Prior update (2023):** UniProt Consortium (2023) *UniProt: the Universal Protein Knowledgebase in 2023.* Nucleic Acids Research 51(D1):D523–D531. doi:[10.1093/nar/gkac1052](https://doi.org/10.1093/nar/gkac1052)

### License notice (quoted from https://www.uniprot.org/help/license):

> We have chosen to apply the Creative Commons Attribution 4.0 International
> (CC BY 4.0) License to all copyrightable parts of our databases.

### Plain-language interpretation

- **You can** use, copy, modify, and redistribute UniProt for any purpose, including commercial.
- **You must** give credit to UniProt (cite the 2023 paper above) and indicate any changes.
- The Swiss-Prot FASTA is **not bundled** — downloaded by `download-uniprot.sh` and mounted at `/db`.

---

## 3. Base image
Debian 12 slim. Standard apt packages governed by their individual licenses (mostly GPL/BSD/MIT). See https://www.debian.org/legal/licenses/.

## Obtaining permissions
None required for either DIAMOND or UniProt. For DIAMOND source mirror requests: https://github.com/bbuchfink/diamond/issues. For UniProt: https://www.uniprot.org/contact.
