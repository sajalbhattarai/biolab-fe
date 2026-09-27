# synteny container — licensing

## Compliance summary

| Component | License | Bundled? | Redistribution | Commercial | Action required |
|---|---|---|---|---|---|
| Liftoff 1.6.3 | GPL-3.0-or-later | ✅ via pip | ✅ allowed (GPL-compliant) | ✅ allowed | cite Shumate & Salzberg 2021 |
| minimap2 2.28 | MIT | ✅ compiled from source | ✅ allowed | ✅ allowed | cite Li 2021 |
| Python 3.11 slim base | PSF-2.0 + Debian DFSG | ✅ | ✅ | ✅ | none |
| merge_liftoff.py | BSD-3-Clause | ✅ first-party | ✅ | ✅ | none |

---

## 1. Liftoff 1.6.3 — GPL-3.0-or-later

**Upstream:** Alaina Shumate and Steven Salzberg, Johns Hopkins University  
**Source:** <https://github.com/agshumate/Liftoff>

This software is distributed under the GNU General Public License v3.0 or
later.  The full license text is available at
<https://www.gnu.org/licenses/gpl-3.0.en.html>.

**Citation:**
Shumate A, Salzberg SL (2021) *Liftoff: accurate mapping of gene annotations.*
Bioinformatics 37(12):1639–1643.
doi:[10.1093/bioinformatics/btaa1016](https://doi.org/10.1093/bioinformatics/btaa1016)

---

## 2. minimap2 2.28 — MIT License

**Upstream:** Heng Li (Wellcome Sanger Institute / Dana-Farber Cancer Institute)  
**Source:** <https://github.com/lh3/minimap2/archive/refs/tags/v2.28.tar.gz>

> Copyright (c) 2018-present Dana-Farber Cancer Institute  
> Copyright (c) 2017-2018 Broad Institute  
> MIT License — permission granted to use, copy, modify, merge, publish,
> distribute, sublicense, and/or sell copies.

**Citation:**
Li H (2021) *New strategies to improve minimap2 alignment accuracy.*
Bioinformatics 37(23):4572–4574.
doi:[10.1093/bioinformatics/btab705](https://doi.org/10.1093/bioinformatics/btab705)

---

## 3. merge_liftoff.py — BSD-3-Clause

First-party pipeline script that merges per-reference Liftoff GFF3 outputs
into a single non-redundant annotation file.
Copyright © margie-annotation contributors.  Released under BSD-3-Clause.
