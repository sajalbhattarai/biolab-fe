# signalP4 container — licensing

⚠️ **USER ACTION REQUIRED**: SignalP 4.x is **NOT** redistributable. Like Phobius, it is licensed by DTU for **academic use** to **individual registered users** with **no redistribution permitted**. This build directory is intentionally **empty** — the SignalP 4.x tarball MUST be downloaded by each user and placed here before building. Do not push an image containing SignalP 4.x to any public registry.

## Summary

| Component | License | Bundled? | Redistribution | Commercial | User action? |
|---|---|---|---|---|---|
| SignalP 4.1 (or 4.0) | **Academic only, NO redistribution** | ❌ NOT bundled here | ❌ forbidden | ❌ commercial licence required | ⚠️ **register and download yourself** |
| Debian base | various | ✅ | ✅ | ✅ | none |

---

## 1. SignalP 4 — DTU academic licence

**Upstream:** Technical University of Denmark — Center for Biological Sequence Analysis
**Distribution:** https://services.healthtech.dtu.dk/services/SignalP-4.1/
**Citation:** Petersen, T.N. *et al.* (2011) *SignalP 4.0: discriminating signal peptides from transmembrane regions.* Nature Methods 8:785–786.

### License notice (quoted from the DTU SignalP 4.1 download page):

> The package is available for academic users free of charge.
>
> Other users are required to obtain a commercial licence.
>
> Redistribution of the software, or any part of it, is not permitted under
> any circumstances. End users must register and download the software from
> this site individually.

### Plain-language interpretation

- **Bundling SignalP 4 in any redistributable image is forbidden.**
- Academic users must individually register at the DTU services portal and download SignalP 4.x for their own use.
- Commercial users must obtain a licence from DTU Health Tech before any use.

## How to obtain SignalP 4

1. Visit https://services.healthtech.dtu.dk/cgi-bin/sw_request?software=signalp&version=4.1
2. Submit the academic-licence form (institutional email required).
3. DTU emails a download link valid for ~24 h.
4. Place `signalp-4.1g.Linux.tar.gz` (or `signalp-4.0`) in this build directory before running the build script.
5. **For commercial use:** licensing inquiries to https://services.healthtech.dtu.dk/help/licensing.php

### Alternative open-source predictors

If a redistributable signal-peptide predictor is needed, consider:
- **DeepSig** (GPL-3.0) — included in this pipeline (`deepsig/`).
- **Phobius** (academic-only, same restrictions as SignalP) — also included (`phobius/`) under the same caveats.
- **SignalP 6.0** — newer, but the same DTU academic-only terms apply.

## 2. Base image
Debian 12 slim. See https://www.debian.org/legal/licenses/.
