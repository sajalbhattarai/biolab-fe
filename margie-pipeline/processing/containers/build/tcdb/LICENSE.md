# tcdb container — licensing

## Summary

| Component | License | Bundled? | Redistribution | Commercial | User action? |
|---|---|---|---|---|---|
| DIAMOND 2.1.9 | GPL-3.0-or-later | ✅ yes | ✅ under GPL | ✅ | none |
| TCDB | Free for academic and non-profit; **commercial use requires permission** | ❌ no — downloaded by `download-tcdb.sh` | ⚠️ permitted with citation; commercial redistribution restricted | ⚠️ requires permission | ⚠️ acceptable use policy at https://www.tcdb.org |
| Debian 12 slim | various | ✅ | ✅ | ✅ | none |

---

## 1. DIAMOND — GPL-3.0-or-later
Identical terms to the `uniprot` container; see `uniprot/LICENSE.md` for full quoted license text.

---

## 2. TCDB — Transporter Classification Database

**Upstream:** Saier Lab, University of California San Diego
**Source:** https://www.tcdb.org/download.php
**Citation:** Saier, M.H., Jr. *et al.* (2021) *The Transporter Classification Database (TCDB): 2021 update.* Nucleic Acids Research 49(D1):D461–D467.

### License notice (quoted from the TCDB acceptable-use page, https://www.tcdb.org):

> TCDB is provided free of charge for academic and non-profit use, subject to
> proper citation of the database in any resulting publication.
> Commercial use of the data requires prior written permission from the
> Saier Lab.

### Plain-language interpretation

- **Academic / non-profit users:** free to use the TCDB database for research; citation required in publications.
- **Commercial users:** must obtain written permission from the Saier Lab before use.
- The TCDB FASTA is **not bundled** inside this image — downloaded by `download-tcdb.sh` and mounted at `/db`.
- This pipeline does not redistribute TCDB.

---

## 3. Base image
Debian 12 slim, see https://www.debian.org/legal/licenses/.

## Obtaining a TCDB commercial licence
Contact: Milton Saier, msaier@ucsd.edu · UC San Diego. Provide a description of intended commercial use.
