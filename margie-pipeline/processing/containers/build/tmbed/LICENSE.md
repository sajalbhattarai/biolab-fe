# tmbed container — licensing

## Summary

| Component | License | Bundled? | Redistribution | Commercial | User action? |
|---|---|---|---|---|---|
| TMbed 1.0.0 | Apache-2.0 | ✅ yes (pip from GitHub tag) | ✅ allowed | ✅ allowed | none |
| PyTorch 2.2.2 (CPU) | BSD-3-Clause-style | ✅ yes (pip) | ✅ | ✅ | none |
| transformers 4.36.2 | Apache-2.0 | ✅ yes (pip) | ✅ | ✅ | none |
| sentencepiece 0.2.0 | Apache-2.0 | ✅ yes (pip) | ✅ | ✅ | none |
| ProtT5-XL-U50 model weights | **CC-BY-NC-SA 4.0 (NonCommercial)** | ❌ no — downloaded on first run | ✅ with NC + SA | ❌ **NonCommercial only** | ⚠️ commercial use prohibited; contact Rostlab |
| Python 3.11-slim base | PSF + Debian | ✅ | ✅ | ✅ | none |

---

## 1. TMbed — Apache License 2.0

**Upstream:** https://github.com/BernhoferM/TMbed
**Source:** https://github.com/BernhoferM/TMbed/releases/tag/v1.0.0
**Author:** Michael Bernhofer, Rost Lab, TU Munich
**Citation:** Bernhofer, M. & Rost, B. (2022) *TMbed — Transmembrane proteins predicted through language model embeddings.* BMC Bioinformatics 23:326.

### License notice (quoted from TMbed `LICENSE`):

> Licensed under the Apache License, Version 2.0 (the "License"); you may not
> use this file except in compliance with the License. You may obtain a copy
> of the License at
>
>     http://www.apache.org/licenses/LICENSE-2.0
>
> Unless required by applicable law or agreed to in writing, software
> distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
> WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.

**Plain language:** unrestricted use, modification, and redistribution; retain the LICENSE and NOTICE files. Patent grant included.

---

## 2. PyTorch — BSD-3-Clause-style license

**Source:** https://github.com/pytorch/pytorch/blob/main/LICENSE
PyTorch is BSD-3-Clause-style. Free for any use; retain copyright notices.

## 3. transformers (Hugging Face) — Apache-2.0
**Source:** https://github.com/huggingface/transformers — Apache-2.0 same terms as TMbed.

## 4. sentencepiece — Apache-2.0
**Source:** https://github.com/google/sentencepiece — Apache-2.0.

---

## 5. ⚠️ ProtT5-XL-U50 encoder model weights — CC-BY-NC-SA 4.0 (NonCommercial)

**Upstream:** Rost Lab, TU Munich
**Source:** https://huggingface.co/Rostlab/prot_t5_xl_half_uniref50-enc
**Citation:** Elnaggar, A. *et al.* (2022) *ProtTrans: Toward Understanding the Language of Life Through Self-Supervised Learning.* IEEE TPAMI 44(10):7112–7127.

### License notice (quoted from the model card on Hugging Face):

> ProtTrans is licensed under the **Academic Free License v3.0** for models
> and the **Creative Commons Attribution-NonCommercial-ShareAlike 4.0
> International License (CC-BY-NC-SA-4.0)** for the embeddings and any
> derived work. Commercial use is not permitted without explicit written
> permission from the Rost Lab.

### Plain-language interpretation

- **Academic / non-commercial use:** free, with attribution and share-alike on any derivative model.
- **Commercial use is prohibited** without written permission from the Rost Lab.
- The model is **never bundled** in this image — TMbed downloads it from Hugging Face on first run into `/models` (mount a persistent host directory to cache).
- TMbed itself is Apache-2.0 (commercial-friendly), but **using TMbed produces outputs derived from the ProtT5 model**, so the NonCommercial restriction propagates to your predictions.

---

## 6. Base image
`python:3.11-slim`. Python is PSF-2.0; Debian packages governed by their individual licenses.

## Obtaining permissions
- TMbed software: none required.
- ProtT5 commercial licence: Burkhard Rost, rostlab@in.tum.de — describe intended commercial use.
