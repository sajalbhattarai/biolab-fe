# tigrfam container — licensing

This container bundles two distinct components:

1. **HMMER 3.4** — BSD-3-Clause (binaries bundled)
2. **TIGRFAMs 15.0** — CC-BY-SA 4.0 (downloaded separately at runtime, not bundled)

## Summary

| Component | License | Bundled? | Redistribution | Commercial use | User action? |
|---|---|---|---|---|---|
| HMMER 3.4 | BSD-3-Clause | ✅ yes | ✅ allowed (must retain notice) | ✅ allowed | none |
| TIGRFAMs 15.0 | CC-BY-SA 4.0 | ❌ no — downloaded by `download-tigrfam.sh` | ✅ allowed with attribution + same-license sharing | ✅ allowed | none, but attribution required if you republish |
| Debian 12 slim | various | ✅ yes | ✅ | ✅ | none |

---

## 1. HMMER — BSD-3-Clause
Same terms as the pfam image. Full quoted text:

> HMMER 3.4 is freely distributed under the BSD open source license.
>
> Copyright (C) 1992-2023 Sean R. Eddy
> Copyright (C) 1992-2023 The President and Fellows of Harvard College
> Copyright (C) 1992-2023 Howard Hughes Medical Institute
> Copyright (C) 1992-2023 Washington University School of Medicine
>
> Redistribution and use in source and binary forms, with or without
> modification, are permitted provided that the following conditions are met:
>   1. Redistributions of source code must retain the above copyright notice…
>   2. Redistributions in binary form must reproduce the above copyright notice…
>   3. Neither the name of any copyright holder nor the names of its contributors
>      may be used to endorse or promote products derived from this software
>      without specific prior written permission.
> THIS SOFTWARE IS PROVIDED "AS IS" … NO WARRANTY.

**Plain language:** ship the binary freely; keep the notice; don't claim Eddy Lab/Harvard/HHMI/WashU endorsement. (Source: `hmmer-3.4/LICENSE`.)

---

## 2. TIGRFAMs 15.0 — Creative Commons Attribution-ShareAlike 4.0

**Upstream:** Originally J. Craig Venter Institute (JCVI); now hosted by NCBI as part of NCBIfam.
**Source:** https://ftp.ncbi.nlm.nih.gov/hmm/TIGRFAMs/release_15.0/
**Citation:** Haft, D.H. *et al.* (2013) *TIGRFAMs and Genome Properties in 2013.* Nucleic Acids Research 41(D1):D387–D395. doi:[10.1093/nar/gks1195](https://doi.org/10.1093/nar/gks1195)

**Note (current maintenance):** Since ~2018, TIGRFAMs has been transferred to NCBI and is now maintained as part of the **NCBIfam** collection at https://ftp.ncbi.nlm.nih.gov/hmm/current/ (alongside the PGAP HMM library). The 15.0 release pinned here is the canonical TIGRFAMs distribution; subsequent updates ship via NCBIfam.

### License notice (quoted from the TIGRFAMs README, release 15.0):

> TIGRFAMs is provided under the Creative Commons Attribution-ShareAlike 4.0
> International License (CC BY-SA 4.0).
> https://creativecommons.org/licenses/by-sa/4.0/

### Plain-language interpretation

- **You can** use, copy, modify, and redistribute TIGRFAMs for any purpose, including commercial.
- **You must** give credit (cite the 2013 paper above and link to the license).
- **You must** share any derivative HMM library under the same CC-BY-SA 4.0 license.
- The TIGRFAMs `.LIB` file is **not bundled** inside this image — it is downloaded at install time by `download-tigrfam.sh` from NCBI's FTP server and mounted at `/db`. Distribution of the image alone therefore does not redistribute TIGRFAMs.

---

## 3. Base image (Debian 12 slim) and runtime packages
Same as pfam. See https://www.debian.org/legal/licenses/.

## Obtaining permissions
None required. Both licenses are public. Questions: NCBI helpdesk for TIGRFAMs, Eddy Lab for HMMER.
