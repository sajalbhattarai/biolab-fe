# dbcan container — licensing

## Summary

| Component | License | Bundled? | Redistribution | Commercial | User action? |
|---|---|---|---|---|---|
| dbCAN 5.1.2 (`run_dbcan`) | GPL-3.0-or-later | ✅ yes (pip) | ✅ under GPL | ✅ | none, keep GPL chain |
| HMMER 3.4 | BSD-3-Clause | ✅ yes (from-source) | ✅ | ✅ | none |
| DIAMOND 2.1.9 | GPL-3.0-or-later | ✅ yes (from-source) | ✅ under GPL | ✅ | none, keep GPL chain |
| pyrodigal 3.5.2 | GPL-3.0-or-later | ✅ yes (pip) | ✅ under GPL | ✅ | none |
| dbCAN HMM database | CC-BY-SA 4.0 | ❌ no — downloaded by `download-dbcan.sh` | ✅ with attribution + share-alike | ✅ | none |
| Python 3.11-slim base | PSF + Debian | ✅ | ✅ | ✅ | none |

---

## 1. run_dbcan (dbCAN Python tool) — GPL-3.0-or-later

**Upstream:** https://github.com/linnabrown/run_dbcan
**Source:** https://pypi.org/project/dbcan/5.1.2/
**Citations:**
- **Original:** Yin, Y., Mao, X., Yang, J., Chen, X., Mao, F., Xu, Y. (2012) *dbCAN: a web resource for automated carbohydrate-active enzyme annotation.* Nucleic Acids Research 40(W1):W445–W451. doi:[10.1093/nar/gks479](https://doi.org/10.1093/nar/gks479)
- **dbCAN2:** Zhang, H. *et al.* (2018) *dbCAN2: a meta server for automated carbohydrate-active enzyme annotation.* Nucleic Acids Research 46(W1):W95–W101. doi:[10.1093/nar/gky418](https://doi.org/10.1093/nar/gky418)
- **Latest (dbCAN3 — this image's algorithm):** Zheng, J. *et al.* (2023) *dbCAN3: automated carbohydrate-active enzyme and substrate annotation.* Nucleic Acids Research 51(W1):W115–W121. doi:[10.1093/nar/gkad328](https://doi.org/10.1093/nar/gkad328)

### License notice (quoted from the run_dbcan `LICENSE`, GPL-3.0):

> This program is free software: you can redistribute it and/or modify it
> under the terms of the GNU General Public License as published by the Free
> Software Foundation, either version 3 of the License, or (at your option)
> any later version.
>
> This program is distributed in the hope that it will be useful, but WITHOUT
> ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
> FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
> more details.

### Plain-language interpretation

- Use, ship, and modify freely under GPL terms.
- Downstream distributors must keep source available (we satisfy this by pinning the PyPI URL in `VERSIONS`).

---

## 2. HMMER — BSD-3-Clause
Same as the `pfam` container. See `pfam/LICENSE.md` for full quoted text.

## 3. DIAMOND — GPL-3.0-or-later
Same as the `uniprot` container. See `uniprot/LICENSE.md` for full quoted text.

## 4. pyrodigal — GPL-3.0-or-later

**Upstream:** https://github.com/althonos/pyrodigal
**Source:** https://pypi.org/project/pyrodigal/3.5.2/
**Citation:** Larralde, M. (2022) *Pyrodigal: Python bindings and interface to Prodigal.* JOSS 7(72):4296.

GPL-3.0 same terms as DIAMOND. Plain language: ship freely, keep source link.

---

## 5. dbCAN HMM database — Creative Commons Attribution-ShareAlike 4.0

**Upstream:** Yin Lab, University of Nebraska–Lincoln
**Source:** https://bcb.unl.edu/dbCAN2/download/Databases/
**Citation:** Same as run_dbcan (Zheng et al. 2023).

### License notice (quoted from dbCAN database README):

> The dbCAN HMM database is released under the Creative Commons
> Attribution-ShareAlike 4.0 International License.

### Plain-language interpretation

- Use and redistribute freely with attribution; share derivatives under the same license.
- The dbCAN HMM files are **not bundled** in this image — downloaded by `download-dbcan.sh` and mounted at `/db`.

---

## 6. Base image
`python:3.11-slim` — Python is PSF-2.0; Debian base packages governed by their individual licenses.

## Obtaining permissions
None required.
