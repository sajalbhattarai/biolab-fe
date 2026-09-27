# pfam container — licensing

This container bundles two distinct components, each with its own license:

1. **HMMER 3.4** (the `hmmscan` / `hmmpress` binaries) — BSD-3-Clause
2. **Pfam-A database** (downloaded separately at runtime, not bundled) — CC0 1.0

## Summary table

| Component | License | Bundled in image? | Redistribution | Commercial use | User action required? |
|---|---|---|---|---|---|
| HMMER 3.4 | BSD-3-Clause | ✅ yes (binaries) | ✅ allowed (must retain notice) | ✅ allowed | none |
| Pfam-A 37.0 | CC0 1.0 (public domain) | ❌ no — downloaded by `download-pfam.sh` | ✅ allowed | ✅ allowed | none |
| Debian 12 slim (base) | various (mostly GPL/BSD) | ✅ yes | ✅ allowed under each component's terms | ✅ allowed | none |

---

## 1. HMMER — BSD-3-Clause

**Upstream:** http://hmmer.org · http://eddylab.org/software/hmmer/
**Source archive:** http://eddylab.org/software/hmmer/hmmer-3.4.tar.gz
**Author:** Sean R. Eddy and the HMMER development team
**Citation:** Eddy, S.R. (2011) *Accelerated Profile HMM Searches.* PLoS Comput Biol 7(10):e1002195.

### Exact license text (quoted verbatim from `hmmer-3.4/LICENSE`):

> HMMER 3.4 is freely distributed under the BSD open source license.
>
> Copyright (C) 1992-2023 Sean R. Eddy
> Copyright (C) 1992-2023 The President and Fellows of Harvard College
> Copyright (C) 1992-2023 Howard Hughes Medical Institute
> Copyright (C) 1992-2023 Washington University School of Medicine
>
> Redistribution and use in source and binary forms, with or without
> modification, are permitted provided that the following conditions are met:
>
>   1. Redistributions of source code must retain the above copyright
>      notice, this list of conditions and the following disclaimer.
>   2. Redistributions in binary form must reproduce the above copyright
>      notice, this list of conditions and the following disclaimer in
>      the documentation and/or other materials provided with the
>      distribution.
>   3. Neither the name of any copyright holder nor the names of its
>      contributors may be used to endorse or promote products derived
>      from this software without specific prior written permission.
>
> THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
> "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
> LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
> A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
> HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
> SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES …

### Plain-language interpretation

- **You can redistribute** the HMMER binaries inside this Docker image — academically and commercially — provided this LICENSE.md travels with the image (it's baked in at `/opt/pfam/LICENSE.md` and reproduced here at the source).
- **You cannot** use the names "HMMER", "Sean Eddy", "Harvard", "HHMI", or "WashU" to endorse derivative products without their written permission (clause 3).
- **No warranty** is offered. We pass that disclaimer through to downstream users.

---

## 2. Pfam-A database — CC0 1.0 (Creative Commons Public Domain Dedication)

**Upstream:** https://www.ebi.ac.uk/interpro/ (Pfam was migrated from Xfam to EBI/InterPro)
**Source:** https://ftp.ebi.ac.uk/pub/databases/Pfam/releases/Pfam37.0/
**Maintainer:** EMBL-EBI · InterPro team
**Citations:**
- **Original:** Sonnhammer, E.L.L., Eddy, S.R., Durbin, R. (1997) *Pfam: a comprehensive database of protein domain families based on seed alignments.* Proteins 28(3):405–420. doi:[10.1002/(SICI)1097-0134(199707)28:3<405::AID-PROT10>3.0.CO;2-L](https://doi.org/10.1002/(SICI)1097-0134(199707)28:3<405::AID-PROT10>3.0.CO;2-L)
- **Latest dedicated update:** Mistry, J. *et al.* (2021) *Pfam: The protein families database in 2021.* Nucleic Acids Research 49(D1):D412–D419. doi:[10.1093/nar/gkaa913](https://doi.org/10.1093/nar/gkaa913)
- **Pfam-in-InterPro (Pfam now lives inside InterPro since 2022):** Paysan-Lafosse, T. *et al.* (2023) *InterPro in 2022.* Nucleic Acids Research 51(D1):D418–D427. doi:[10.1093/nar/gkac993](https://doi.org/10.1093/nar/gkac993)

### License notice (quoted from EBI Pfam README, current release):

> Pfam is freely available under the Creative Commons Zero ("CC0") licence.

### Plain-language interpretation

- Pfam-A is **public domain**. You can use, copy, modify, and redistribute it for any purpose, academic or commercial, with no attribution required (citation is requested as scholarly courtesy, not as a legal obligation).
- The Pfam-A `.hmm` files are **not bundled** inside this image — they are downloaded at install time by `processing/scripts/setup-scripts/setup-databases/download-pfam.sh` from the EBI FTP server, into the host's `db/pfam/` directory, and mounted at `/db` when the container runs. Distribution of the image alone therefore does not redistribute Pfam-A.

---

## 3. Base image (Debian 12 slim) and runtime packages

The runtime stage installs `python3`, `tini`, `bash`, `ca-certificates` from Debian. These are governed by their individual package licenses (mostly GPL-2/GPL-3/BSD/MIT). Debian's full license catalogue: https://www.debian.org/legal/licenses/.

The build itself complies with each upstream package's redistribution terms because:
- Source packages are pulled at build time from Debian's official apt repositories.
- We do not modify any Debian-provided binary.
- Binary GPL components (e.g. `bash`) are accompanied by Debian's standard mechanism for obtaining source (`apt-get source <pkg>`), which satisfies GPL §3.

---

## How to obtain new licenses or permissions

None required. Both HMMER and Pfam-A are freely usable. If you redistribute this image, ensure:
- This `LICENSE.md` remains accessible at `/opt/pfam/LICENSE.md` inside the image.
- The HMMER copyright notice is preserved (already satisfied by shipping this file).

If you have questions about HMMER licensing, contact the Eddy Lab: http://eddylab.org/contact.html
For Pfam licensing questions, contact EMBL-EBI: https://www.ebi.ac.uk/about/contact/support/pfam
