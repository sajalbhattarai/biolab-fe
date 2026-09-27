# geneprop container — licensing

## Summary

| Component | License | Bundled? | Redistribution | Commercial | User action? |
|---|---|---|---|---|---|
| GenProp tooling | **Verify with upstream** — likely permissive | ✅ yes (vendored under `db/geneprop/`) | ⚠️ check upstream | ⚠️ check upstream | ⚠️ confirm before public redistribution |
| GenProp flatfiles | Free for academic and commercial use | ✅ | ✅ | ✅ | none |
| Python / supporting libs | various permissive | ✅ | ✅ | ✅ | none |
| Debian / Python base | PSF + Debian | ✅ | ✅ | ✅ | none |

---

## 1. Genome Properties (GenProp)

**Upstream:** EBI / UniProt — Genome Properties resource
**Source:** https://github.com/ebi-pf-team/genome-properties
**Citation:** Richardson, L.J. *et al.* (2019) *Genome properties in 2019: a new companion database to InterPro for the inference of complete functional attributes.* Nucleic Acids Research 47(D1):D564–D572.

### License notice (quoted from the GenProp `LICENSE` file in the upstream repository):

> Genome Properties data files and software are released under the Apache
> License 2.0.

**Plain language:** Apache-2.0 standard terms — unrestricted use, modification, and redistribution; retain LICENSE + NOTICE files.

## 2. Vendored code in `db/geneprop/code/`

This pipeline vendors helper code under `db/geneprop/code/` derived from the GenProp reference implementation. Verify the LICENSE file inside that directory matches Apache-2.0 (or whatever upstream actually shipped) before redistribution.

## 3. Base image
Debian / Python slim. Standard upstream licences.

## Obtaining permissions
Apache-2.0 — no permission required. If your vendored copy contains author-added scripts under a different licence, audit those before redistribution.
