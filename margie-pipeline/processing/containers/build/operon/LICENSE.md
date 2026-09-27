# operon container — licensing

## Summary

| Component | License | Bundled? | Redistribution | Commercial | User action? |
|---|---|---|---|---|---|
| UniOP (vendored snapshot) | MIT | ✅ yes (vendored) | ✅ allowed | ✅ allowed | none |
| Prodigal 2.6.3 | GPL-3.0-or-later | ✅ (Debian apt) | ✅ under GPL | ✅ | none |
| numpy 1.26.4 | BSD-3-Clause | ✅ | ✅ | ✅ | none |
| pandas 2.2.2 | BSD-3-Clause | ✅ | ✅ | ✅ | none |
| scikit-learn 1.4.2 | BSD-3-Clause | ✅ | ✅ | ✅ | none |
| scipy 1.13.1 | BSD-3-Clause | ✅ | ✅ | ✅ | none |
| joblib 1.4.2 | BSD-3-Clause | ✅ | ✅ | ✅ | none |
| Python 3.11-slim base | PSF + Debian | ✅ | ✅ | ✅ | none |

---

## 1. UniOP — MIT License

**Upstream:** https://github.com/hongsua/UniOP
**Vendored as a snapshot:** `./UniOP/` in this build directory, copied verbatim into the image at `/opt/UniOP`. Snapshot date is recorded in `VERSIONS`. Because UniOP's main branch had not been formally tagged when this image was built, we vendor a known-good snapshot rather than a moving reference; downstream re-builders can diff against `upstream/main` to verify.
**Author:** Hong Sua (hongsua)
**Citation:** Hong, S. (2023) *UniOP: Predicting operons using intergenic distance.* GitHub repository.

### License notice (quoted from the UniOP `README.md`):

> UniOP is released under the MIT License.

The MIT License grants:

> Permission is hereby granted, free of charge, to any person obtaining a copy
> of this software and associated documentation files (the "Software"), to
> deal in the Software without restriction, including without limitation the
> rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
> sell copies of the Software, and to permit persons to whom the Software is
> furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in
> all copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.

**Plain language:** unrestricted use, modification, and redistribution; retain the notice.

---

## 2. Prodigal — GPL-3.0-or-later

**Upstream:** https://github.com/hyattpd/Prodigal
**Source:** Debian 12 apt package `prodigal` (version 2.6.3).
**Citation:** Hyatt, D. *et al.* (2010) *Prodigal: prokaryotic gene recognition and translation initiation site identification.* BMC Bioinformatics 11:119.

GPL-3.0 standard terms — ship freely, downstream rebuilders keep source link available (Debian's source package satisfies this).

---

## 3. Scientific Python stack
numpy, pandas, scikit-learn, scipy, joblib — all BSD-3-Clause. Free for any use; retain copyright notices in derivative source distributions.

## 4. Base image
`python:3.11-slim`. Python is PSF-2.0; Debian packages governed by their individual licenses.

## Obtaining permissions
None required.
