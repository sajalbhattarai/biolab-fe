# cog container — licensing

## Summary

| Component | License | Bundled? | Redistribution | Commercial | User action? |
|---|---|---|---|---|---|
| NCBI BLAST+ 2.16.0 | U.S. Government Work (public domain) | ✅ yes (official NCBI binary) | ✅ allowed | ✅ allowed | none |
| cogclassifier 2.0.0 | MIT | ✅ yes (pip) | ✅ allowed | ✅ allowed | none |
| COG database (NCBI CDD COG_LE) | U.S. Government Work (public domain) | ❌ no — downloaded by `download-cog.sh` | ✅ allowed | ✅ allowed | none |
| Python 3.11-slim base | PSF + Debian | ✅ | ✅ | ✅ | none |

---

## 1. NCBI BLAST+ — U.S. Government Work (public domain)

**Upstream:** NCBI BLAST+ command-line tools
**Source:** https://ftp.ncbi.nlm.nih.gov/blast/executables/blast+/2.16.0/
**Citations:**
- **Original BLAST:** Altschul, S.F., Gish, W., Miller, W., Myers, E.W., Lipman, D.J. (1990) *Basic local alignment search tool.* J. Mol. Biol. 215(3):403–410. doi:[10.1016/S0022-2836(05)80360-2](https://doi.org/10.1016/S0022-2836(05)80360-2)
- **BLAST+ (this implementation):** Camacho, C. *et al.* (2009) *BLAST+: architecture and applications.* BMC Bioinformatics 10:421. doi:[10.1186/1471-2105-10-421](https://doi.org/10.1186/1471-2105-10-421)

### License notice (quoted from `ncbi-blast-2.16.0+/LICENSE`):

> PUBLIC DOMAIN NOTICE
> National Center for Biotechnology Information
>
> This software/database is a "United States Government Work" under the terms
> of the United States Copyright Act. It was written as part of the author's
> official duties as a United States Government employee and thus cannot be
> copyrighted. This software/database is freely available to the public for
> use. The National Library of Medicine and the U.S. Government have not
> placed any restriction on its use or reproduction.

### Plain-language interpretation

- BLAST+ is **public domain in the United States** and free of NCBI restrictions worldwide.
- You can ship the binaries inside this image, in any context, for any purpose.
- This image bundles the **official NCBI linux-x64 binary tarball** — the same artefact the NCBI distributes. This is the canonical reference build. (We choose this over compiling from source because the NCBI binary IS the reference.)
- **AMD64 only:** NCBI does not publish official ARM64 binaries. The image is built for `linux/amd64`; users on ARM hosts (Apple Silicon, etc.) run it under emulation, which is supported by Docker but slower.

---

## 2. cogclassifier — MIT License

**Upstream:** https://github.com/moshi4/COGclassifier
**Source:** https://pypi.org/project/cogclassifier/2.0.0/
**Author:** Yuki Moshi (moshi4)
**Citation:** No formal publication; cite the GitHub repository.

### License notice (quoted from the cogclassifier `LICENSE` file):

> MIT License
>
> Copyright (c) 2022 moshi4
>
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
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
> IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
> FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
> AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
> LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
> FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
> DEALINGS IN THE SOFTWARE.

### Plain-language interpretation

- Use, ship, and modify freely (academically and commercially) provided the copyright notice is retained.
- This LICENSE.md satisfies the notice requirement when the image is redistributed.

---

## 3. COG database (NCBI CDD COG_LE collection)

**Upstream:** NCBI Conserved Domains Database — COG collection
**Source:** https://ftp.ncbi.nlm.nih.gov/pub/COG/COG2024/data/
**Citations:**
- **Original:** Tatusov, R.L., Koonin, E.V., Lipman, D.J. (1997) *A genomic perspective on protein families.* Science 278(5338):631–637. doi:[10.1126/science.278.5338.631](https://doi.org/10.1126/science.278.5338.631)
- **Latest dedicated update:** Galperin, M.Y. *et al.* (2021) *COG database update: focus on microbial diversity, model organisms, and widely used research tools.* Nucleic Acids Research 49(D1):D274–D281. doi:[10.1093/nar/gkaa1018](https://doi.org/10.1093/nar/gkaa1018)

### License notice (quoted from NCBI's data terms):

> Works produced by the U.S. Government are not subject to copyright protection
> in the United States.

### Plain-language interpretation

- Public domain, no restrictions. Citation requested as scholarly courtesy.
- The COG profiles are **not bundled** in this image — downloaded by `download-cog.sh`.

---

## 4. Base image (python:3.11-slim)
The official Python Docker image, built on Debian slim. Python is PSF-2.0-licensed; Debian packages governed by their individual licenses.

## Obtaining permissions
None required for any component.
