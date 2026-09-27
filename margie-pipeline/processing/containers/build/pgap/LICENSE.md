# pgap container — licensing

This container bundles HMMER and queries the NCBI PGAP HMM library (NCBIfam + TIGRfam).

## Summary

| Component | License | Bundled? | Redistribution | Commercial | User action? |
|---|---|---|---|---|---|
| HMMER 3.4 | BSD-3-Clause | ✅ yes | ✅ | ✅ | none |
| NCBI PGAP HMM library (`hmm_PGAP.LIB`) | U.S. Government Work (public domain) | ❌ no — downloaded by `download-pgap.sh` | ✅ | ✅ | none |
| Debian 12 slim | various | ✅ yes | ✅ | ✅ | none |

---

## 1. HMMER — BSD-3-Clause
Identical to the pfam and tigrfam containers. Full text quoted in `pfam/LICENSE.md`. Plain language: ship the binary freely; keep the copyright notice; do not use upstream names for endorsement.

---

## 2. NCBI PGAP HMM library — U.S. Government Work (public domain)

**Upstream:** NCBI Prokaryotic Genome Annotation Pipeline (PGAP)
**Source:** https://ftp.ncbi.nlm.nih.gov/hmm/current/
**Citation:** Li, W. *et al.* (2021) *RefSeq: expanding the Prokaryotic Genome Annotation Pipeline reach with protein family model curation.* Nucleic Acids Research 49(D1):D1020–D1028.

### License notice (quoted from NCBI's data terms):

> Works produced by the U.S. Government are not subject to copyright protection
> in the United States. Foreign copyrights may apply.
> NCBI itself places no restrictions on the use or distribution of the data
> contained therein.
> (https://www.ncbi.nlm.nih.gov/home/about/policies/)

### Plain-language interpretation

- The PGAP HMM library is **public domain in the United States** and free of NCBI restrictions worldwide.
- You can use, copy, modify, and redistribute it for any purpose (academic or commercial) without permission or attribution.
- Citation of the 2021 paper is requested as scholarly courtesy.
- The HMM library is **not bundled** in this image — it is downloaded by `download-pgap.sh` and mounted at `/db`.

---

## 3. Base image
Debian 12 slim, same as pfam.

## Obtaining permissions
None required.
