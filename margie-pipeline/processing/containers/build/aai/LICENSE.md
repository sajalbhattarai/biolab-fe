# aai container — licensing

## Compliance summary

| Component | License | Bundled? | Redistribution | Commercial | Action required |
|---|---|---|---|---|---|
| EzAAI 1.2.2 | MIT | ✅ JAR from GitHub releases | ✅ allowed | ✅ allowed | cite Kim et al. 2021 |
| DIAMOND 2.1.9 | GPL-3.0-or-later | ✅ compiled from source | ✅ allowed (GPL-compliant) | ✅ allowed | source tarball URL below |
| OpenJDK 17 JRE | GPL-2.0 w/ Classpath Exception | ✅ apt | ✅ allowed | ✅ allowed | none |
| Python 3.11 slim base | PSF-2.0 + Debian DFSG | ✅ | ✅ | ✅ | none |

---

## 1. EzAAI 1.2.2 — MIT License

**Upstream:** Donghyun Kim (endixk), Korea Advanced Institute of Science and Technology (KAIST)  
**Source:** <https://github.com/endixk/ezaai>

> Permission is hereby granted, free of charge, to any person obtaining a copy
> of this software and associated documentation files (the "Software"), to deal
> in the Software without restriction, including without limitation the rights
> to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
> copies of the Software, and to permit persons to whom the Software is
> furnished to do so, subject to the following conditions: The above copyright
> notice and this permission notice shall be included in all copies or
> substantial portions of the Software.

**Citation:**
Kim D, Park S, Chun J (2021) *Introducing EzAAI: a pipeline for high throughput
calculations of prokaryotic average amino acid identity.* J Microbiol
59(5):476–480. doi:[10.1007/s12275-021-1154-0](https://doi.org/10.1007/s12275-021-1154-0)

---

## 2. DIAMOND 2.1.9 — GPL-3.0-or-later

Used internally by EzAAI for protein–protein alignments.

**Source (GPL §6):** <https://github.com/bbuchfink/diamond/archive/refs/tags/v2.1.9.tar.gz>

**Citations:**
- Buchfink B, Xie C, Huson DH (2015) *Fast and sensitive protein alignment using DIAMOND.* Nat Methods 12:59–60. doi:[10.1038/nmeth.3176](https://doi.org/10.1038/nmeth.3176)
- Buchfink B, Reuter K, Drost H-G (2021) *Sensitive protein alignments at tree-of-life scale using DIAMOND.* Nat Methods 18:366–368. doi:[10.1038/s41592-021-01101-x](https://doi.org/10.1038/s41592-021-01101-x)
