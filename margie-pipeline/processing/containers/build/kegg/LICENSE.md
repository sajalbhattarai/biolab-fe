# kegg container — licensing

## Summary

| Component | License | Bundled? | Redistribution | Commercial | User action? |
|---|---|---|---|---|---|
| KofamScan 1.3.0 | MIT | ✅ yes (tarball) | ✅ allowed | ✅ allowed | none |
| HMMER 3.4 | BSD-3-Clause | ✅ yes (from-source) | ✅ | ✅ | none |
| GNU parallel | GPL-3.0-or-later | ✅ (Debian apt) | ✅ under GPL | ✅ | none, optional CITATION |
| Ruby | BSD/Ruby License | ✅ (Debian apt) | ✅ | ✅ | none |
| KOfam HMM profiles + ko_list | **Public, free for academic and commercial use** | ❌ no — downloaded by `download-kegg.sh` | ✅ allowed (the public KOfam subset) | ⚠️ full KEGG database commercial use requires licence | ⚠️ if using non-KOfam KEGG data, see https://www.kegg.jp/kegg/legal.html |
| Debian 12 slim | various | ✅ | ✅ | ✅ | none |

---

## 1. KofamScan — MIT License

**Upstream:** https://github.com/takaram/kofam_scan
**Source:** https://www.genome.jp/ftp/tools/kofam_scan/kofam_scan-1.3.0.tar.gz
**Author:** Takuya Aramaki, Kanehisa Laboratories
**Citation:** Aramaki, T. *et al.* (2020) *KofamKOALA: KEGG Ortholog assignment based on profile HMM and adaptive score threshold.* Bioinformatics 36(7):2251–2252.

### License notice (quoted from KofamScan `LICENSE.txt`):

> MIT License
>
> Copyright (c) 2019 Takuya Aramaki
>
> Permission is hereby granted, free of charge, to any person obtaining a
> copy of this software and associated documentation files (the "Software"),
> to deal in the Software without restriction, including without limitation
> the rights to use, copy, modify, merge, publish, distribute, sublicense,
> and/or sell copies of the Software, and to permit persons to whom the
> Software is furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in
> all copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
> IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
> FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.

**Plain language:** unrestricted use, ship the binary freely, retain notice.

---

## 2. HMMER — BSD-3-Clause
Same as `pfam`. See `pfam/LICENSE.md`.

## 3. GNU parallel — GPL-3.0
Standard Debian package. Authors request (but do not require) citation: Tange, O. (2011) *GNU Parallel — The Command-Line Power Tool.*

---

## 4. KOfam profile HMMs + ko_list — Free public release

**Upstream:** Kanehisa Laboratories
**Source:** https://www.genome.jp/ftp/db/kofam/
**Citation:** Same as KofamScan (Aramaki et al. 2020).

### License notice (quoted from https://www.genome.jp/tools/kofamkoala/):

> The KOfam database (a customized profile HMM database of KEGG Orthologs)
> is freely available without restriction from the KEGG FTP site.

### Plain-language interpretation

- The **KOfam subset** (profile HMMs + ko_list thresholds) used by KofamScan is freely redistributable and usable commercially.
- The **full KEGG database** (pathways, modules, BRITE, etc.) has stricter terms: free for academic use, commercial use requires a licence from Kanehisa Laboratories (https://www.kegg.jp/kegg/legal.html). This pipeline only uses KOfam, not the full KEGG database.
- Not bundled — downloaded by `download-kegg.sh` and mounted at `/db`.

---

## 5. Base image
Debian 12 slim. See https://www.debian.org/legal/licenses/.

## Obtaining permissions
- KOfam: none.
- Full KEGG commercial licence (not needed for this pipeline): kegg@kanehisa.jp
