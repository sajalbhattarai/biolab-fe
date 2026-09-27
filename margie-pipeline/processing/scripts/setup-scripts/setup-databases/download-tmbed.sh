#!/usr/bin/env bash
# download-tmbed.sh — pre-fetches the ProtT5 encoder used by TMbed
# (Rostlab/prot_t5_xl_half_uniref50-enc, public, ~2.3 GB) into $DB_ROOT/tmbed/.
# Runs inside the tmbed container with $DB_ROOT/tmbed bound to /models (its HF cache),
# so the tmbed image must exist first.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/lib.sh"
tag="download-tmbed"
db_parse_args "$@"

REPO="Rostlab/prot_t5_xl_half_uniref50-enc"
d="$(db tmbed)"

# ---- licence gate ---------------------------------------------------------
# Runs before the skip check so the acceptance record is always written.
# The ProtT5-XL-U50 weights are CC-BY-NC-SA 4.0 (NonCommercial), hence the gate.
licence_gate tmbed TMBED_ACCEPT_LICENCE --accept-tmbed-licence \
    "./setup.sh --databases-only --tool tmbed --accept-tmbed-licence" <<'NOTICE' || exit 0
  ================================================================
  WHY LICENSING MATTERS FOR TMbed / ProtT5
  ================================================================
  TMbed predicts transmembrane topology using a large protein
  language model (ProtT5-XL-U50) developed at TU Munich / Rost Lab.
  While the TMbed software code is Apache-2.0 (commercial-friendly),
  the ProtT5 model WEIGHTS are licensed under CC-BY-NC-SA 4.0, which
  PROHIBITS commercial use without explicit written permission.
  Because TMbed predictions are derived from the ProtT5 embeddings,
  the NonCommercial restriction applies to the outputs as well.
  Please read the exact terms below carefully.

  ── TOOLS ────────────────────────────────────────────────────────

  ┌─ TMbed v1.0.0 (transmembrane segment prediction) ─────────────
  │ Licence: Apache License 2.0 (commercial OK for the code).
  │ Quoted from https://github.com/BernhoferM/TMbed/LICENSE:
  │
  │   "Licensed under the Apache License, Version 2.0 (the
  │    'License'); you may not use this file except in compliance
  │    with the License. You may obtain a copy of the License at
  │    http://www.apache.org/licenses/LICENSE-2.0
  │    Unless required by applicable law or agreed to in writing,
  │    software distributed under the License is distributed on an
  │    'AS IS' BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
  │    either express or implied."
  │
  │ Source: https://github.com/BernhoferM/TMbed (tag v1.0.0)
  │ Citation: Bernhofer M. & Rost B. (2022) BMC Bioinformatics 23:326
  └────────────────────────────────────────────────────────────────

  ── DATABASES / MODEL WEIGHTS ────────────────────────────────────

  ┌─ ProtT5-XL-U50 encoder weights (Rost Lab, TU Munich) ───── ⚠️
  │ Licence: CC-BY-NC-SA 4.0 (NON-COMMERCIAL, attribution, ShareAlike)
  │ Quoted from the model card at:
  │   https://huggingface.co/Rostlab/prot_t5_xl_half_uniref50-enc
  │
  │   "ProtTrans is licensed under the Academic Free License v3.0
  │    for models and the Creative Commons Attribution-NonCommercial-
  │    ShareAlike 4.0 International License (CC-BY-NC-SA-4.0) for
  │    the embeddings and any derived work. Commercial use is not
  │    permitted without explicit written permission from the
  │    Rost Lab."
  │
  │ * NON-COMMERCIAL use: free (with attribution and share-alike
  │                        on any derivative model).
  │ * COMMERCIAL use: PROHIBITED without written permission.
  │   Contact: Burkhard Rost, rostlab@in.tum.de
  │
  │ The model weights (~2.3 GB) are NOT bundled. This script
  │ downloads them from Hugging Face into your local DB directory.
  │
  │ Citation: Elnaggar A. et al. (2022) IEEE TPAMI 44(10):7112-7127
  └────────────────────────────────────────────────────────────────

  By agreeing below, you declare, on your own responsibility, that:
    (a) Your intended use is non-commercial research, OR
    (b) A separate commercial licence has already been obtained
        from the Rost Lab (rostlab@in.tum.de).
  Licence compliance is the sole responsibility of the end user.

  All agreements are recorded and logged with the pipeline version
  (git commit hash). A copy of your acceptance record will be
  saved in: logs/licensing/

  ================================================================
NOTICE

# Ready only when both a weight file and the tokenizer (spiece.model) exist under $d,
# which catches downloads killed before the tokenizer was saved.
if (( DB_REDO == 0 )) \
   && [[ -d "$d" ]] \
   && find "$d" \( -name '*.safetensors' -o -name '*.bin' -o -name '*.pt' \) \
        -print -quit 2>/dev/null | grep -q . \
   && find "$d" -name 'spiece.model' -print -quit 2>/dev/null | grep -q .; then
    ok "tmbed: ProtT5 encoder already cached (use --redo to force)"
    exit 0
fi

run mkdir -p "$d"

log "fetching $REPO via the tmbed container -> $d  (~2.3 GB, public, no token)"

# snapshot_download() writes the files without loading the model into RAM (avoids OOM on CPU nodes).
PY_SNIPPET=$(cat <<'PYEOF'
import os, time
# One file at a time, over plain HTTPS: the parallel and accelerated
# downloaders buffer enough of a 2.3 GB file to be killed for memory inside a
# container, and they die without a traceback.
os.environ.setdefault("HF_HUB_DISABLE_XET", "1")
os.environ.setdefault("HF_HUB_ENABLE_HF_TRANSFER", "0")
from huggingface_hub import snapshot_download

repo = "Rostlab/prot_t5_xl_half_uniref50-enc"
# HF_HOME/hub is huggingface_hub's own layout: what the container finds at
# annotate time, and what check.sh tests for.
cache = os.path.join(os.environ.get("HF_HOME", "/models"), "hub")
print(f"[download-tmbed] downloading {repo} into {cache}", flush=True)
for attempt in range(1, 4):
    try:
        snapshot_download(
            repo_id=repo,
            cache_dir=cache,
            max_workers=1,
            ignore_patterns=["*.msgpack", "flax_model*", "tf_model*"],
        )
        break
    except Exception as exc:                       # resumes from what is on disk
        if attempt == 3:
            raise
        print(f"[download-tmbed] attempt {attempt} stopped ({type(exc).__name__}: {exc}); resuming", flush=True)
        time.sleep(5)
print("[download-tmbed] done.", flush=True)
PYEOF
)

run_in_container tmbed --entrypoint python3 --bind "$d:/models" -- -c "$PY_SNIPPET"

ok "tmbed ready -> $d  (mounted into the container at /models)"
