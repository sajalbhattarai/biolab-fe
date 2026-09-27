# merops container — licensing

## Summary

| Component | License | Bundled? | Redistribution | Commercial | User action? |
|---|---|---|---|---|---|
| DIAMOND 2.1.9 | GPL-3.0-or-later | ✅ yes | ✅ under GPL | ✅ | none |
| MEROPS pepunit | **Academic use only** | ❌ no — user downloads | ❌ **NO redistribution** of the database | ❌ **requires commercial licence** | ⚠️ **register at https://www.ebi.ac.uk/merops/ before download** |
| Debian 12 slim | various | ✅ | ✅ | ✅ | none |

---

## 1. DIAMOND — GPL-3.0-or-later
Identical terms to the `uniprot` container; see `uniprot/LICENSE.md` for full quoted license text.

**Plain language:** binary may be shipped inside this image; downstream re-distributors must keep the DIAMOND source available (we pin the upstream tarball URL in `VERSIONS`).

---

## 2. MEROPS — Academic use only (registration required)

**Upstream:** MEROPS — the peptidase database, EMBL-EBI
**Source:** https://www.ebi.ac.uk/merops/download_list.shtml
**Citation:** Rawlings, N.D. *et al.* (2018) *The MEROPS database of proteolytic enzymes, their substrates and inhibitors in 2017.* Nucleic Acids Research 46(D1):D624–D632.

### License notice (quoted from the MEROPS download page):

> The MEROPS database is freely accessible for academic use. Commercial
> organisations should contact the MEROPS team to obtain a licence before
> downloading or using the data.

### Plain-language interpretation

- **Academic users:** free to download and use the MEROPS database. No fees, no redistribution of the database, citation required.
- **Commercial users:** must obtain a licence from EMBL-EBI before download or use. Contact: https://www.ebi.ac.uk/about/contact/support/merops
- The MEROPS database is **never bundled** inside this image. The pipeline's `download-merops.sh` prints the licence notice quoted above and asks the user to confirm acceptance (`[y/N]`, 30-second timeout) before downloading anything. Acceptance can also be pre-supplied non-interactively via the `--accept-merops-licence` flag or the `MEROPS_ACCEPT_LICENCE=1` environment variable. If the user declines, times out, or hits Ctrl+C, the database is silently skipped and the rest of the pipeline continues. Distribution of the image alone therefore does not redistribute MEROPS.
- **Re-distribution of the database itself by us or by downstream users is prohibited.** Each end user must download MEROPS themselves under the appropriate licence.

---

## 3. Base image
Debian 12 slim, see https://www.debian.org/legal/licenses/.

## Obtaining a MEROPS commercial licence
Email: merops-helpdesk@ebi.ac.uk · Typical response time: a few business days. EMBL-EBI will issue a licence agreement; pricing is negotiated.
