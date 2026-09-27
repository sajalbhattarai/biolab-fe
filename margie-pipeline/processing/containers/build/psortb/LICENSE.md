# psortb container — licensing

## Summary

| Component | License | Bundled? | Redistribution | Commercial | User action? |
|---|---|---|---|---|---|
| PSORTb 3.0 | GPL-2.0-or-later | ✅ yes | ✅ under GPL | ✅ allowed | none |
| BLAST+ (NCBI) | U.S. Government Work (public domain) | ✅ | ✅ | ✅ | none |
| Pftools (Pfsearch / Pfscan) | GPL-2.0-or-later | ✅ | ✅ under GPL | ✅ | none |
| BioPerl runtime | Artistic License 2.0 / GPL | ✅ | ✅ | ✅ | none |
| Debian 12 slim | various | ✅ | ✅ | ✅ | none |

---

## 1. PSORTb — GNU GPL-2.0-or-later

**Upstream:** Brinkman Laboratory, Simon Fraser University
**Source:** https://github.com/brinkmanlab/psortb_commandline_docker
**Citation:** Yu, N.Y. *et al.* (2010) *PSORTb 3.0: improved protein subcellular localization prediction with refined localization subcategories and predictive capabilities for all prokaryotes.* Bioinformatics 26(13):1608–1615.

### License notice (quoted from PSORTb `COPYING`):

> PSORTb is free software; you can redistribute it and/or modify it under
> the terms of the GNU General Public License as published by the Free
> Software Foundation; either version 2 of the License, or (at your option)
> any later version.
>
> This program is distributed in the hope that it will be useful, but
> WITHOUT ANY WARRANTY; without even the implied warranty of
> MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General
> Public License for more details.

**Plain language:** ship freely under GPL terms; downstream re-distributors must keep the PSORTb source available.

## 2. NCBI BLAST+ — U.S. Public Domain
Same as `cog`. See `cog/LICENSE.md` for full quoted text.

## 3. Pftools — GPL-2.0-or-later
**Upstream:** https://github.com/sib-swiss/pftools3 — SIB Swiss Institute of Bioinformatics. GPL-2.0 same terms as PSORTb.

## 4. BioPerl — Artistic License 2.0 / GPL
Dual-licensed; either licence applies. Free for any use.

## 5. Base image
Debian 12 slim. See https://www.debian.org/legal/licenses/.

## Obtaining permissions
None required.
