# deepsig container — licensing

## Summary

| Component | License | Bundled? | Redistribution | Commercial | User action? |
|---|---|---|---|---|---|
| DeepSig 1.2.x | GPL-3.0-or-later | ✅ yes (pip / git) | ✅ under GPL | ✅ allowed | none |
| TensorFlow / Keras runtime | Apache-2.0 | ✅ | ✅ | ✅ | none |
| DeepSig model weights | GPL-3.0-or-later (released with code) | ✅ | ✅ | ✅ | none |
| Python 3 base | PSF + Debian | ✅ | ✅ | ✅ | none |

---

## 1. DeepSig — GNU GPL-3.0-or-later

**Upstream:** Biocomputing Group, University of Bologna
**Source:** https://github.com/BolognaBiocomp/deepsig
**Citation:** Savojardo, C. *et al.* (2018) *DeepSig: deep learning improves signal peptide detection in proteins.* Bioinformatics 34(10):1690–1696.

### License notice (quoted from DeepSig `LICENSE`, GPL-3.0):

> This program is free software: you can redistribute it and/or modify it
> under the terms of the GNU General Public License as published by the
> Free Software Foundation, either version 3 of the License, or (at your
> option) any later version.
>
> This program is distributed in the hope that it will be useful, but
> WITHOUT ANY WARRANTY; without even the implied warranty of
> MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General
> Public License for more details.

**Plain language:** unrestricted use, ship freely, retain GPL chain. The DeepSig model weights are released under the same GPL-3.0 licence as the code.

## 2. TensorFlow — Apache-2.0
**Source:** https://github.com/tensorflow/tensorflow/blob/master/LICENSE — unrestricted, retain notices.

## 3. Base image
Debian / Python slim. Standard upstream licences.

## Obtaining permissions
None required.
