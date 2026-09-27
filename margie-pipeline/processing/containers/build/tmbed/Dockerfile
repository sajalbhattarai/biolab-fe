# syntax=docker/dockerfile:1.7
# ──────────────────────────────────────────────────────────────────────────────
# tmbed — deep-learning transmembrane segment + signal peptide predictor.
# PyTorch CPU wheels + tmbed installed from upstream GitHub at pinned tag.
# Model weights (ProtT5-XL-U50, ~2.25 GB) are downloaded on first run into /models.
# See LICENSE.md for license terms.
# ──────────────────────────────────────────────────────────────────────────────
ARG TMBED_REF=v1.0.0
ARG TORCH_VERSION=2.2.2

FROM python:3.11-slim
ARG TMBED_REF
ARG TORCH_VERSION
ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 LC_ALL=C.UTF-8 \
    TRANSFORMERS_CACHE=/models HF_HOME=/models TORCH_HOME=/models

RUN apt-get update && apt-get install -y --no-install-recommends \
        tini bash ca-certificates git wget \
 && rm -rf /var/lib/apt/lists/*

# CPU-only PyTorch (smaller, no CUDA; pinned version)
RUN pip install --no-cache-dir \
        --index-url https://download.pytorch.org/whl/cpu \
        "torch==${TORCH_VERSION}"

# TMbed at pinned upstream tag. Upstream v1.0.0 pins torch<2.0.0 (stale upper
# bound — tmbed runs fine on torch 2.x), so install with --no-deps and pull in
# its actual runtime deps explicitly.
RUN pip install --no-cache-dir \
        "transformers==4.36.2" \
        "h5py==3.10.0" \
        "numpy<2" \
        "sentencepiece" \
        "tqdm" \
         "einops" \
         "typer" \
 && pip install --no-cache-dir --no-deps \
        "git+https://github.com/BernhoferM/TMbed.git@${TMBED_REF}"

COPY entrypoint.sh /opt/tmbed/entrypoint.sh
COPY scripts/      /opt/tmbed/scripts/
COPY LICENSE.md    /opt/tmbed/LICENSE.md
COPY VERSIONS      /opt/tmbed/VERSIONS

RUN chmod -R a+rX /opt/tmbed \
 && find /opt/tmbed -type f \( -name '*.sh' -o -name '*.py' \) -exec chmod a+x {} + \
 && ln -sf /opt/tmbed/entrypoint.sh /usr/local/bin/run \
 && mkdir -p /input /output /db /models

RUN printf '{\n  "tool": "tmbed",\n  "tmbed_ref": "%s",\n  "torch_version": "%s",\n  "base_image": "python:3.11-slim",\n  "build_date": "%s"\n}\n' \
        "${TMBED_REF}" "${TORCH_VERSION}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        > /etc/pipeline-build.json

LABEL org.opencontainers.image.title="tmbed" \
      org.opencontainers.image.description="TMbed transmembrane predictor — PyTorch CPU, pinned upstream tag" \
      org.opencontainers.image.source="https://github.com/sajalbhattarai/containers" \
      org.opencontainers.image.vendor="margie-annotation" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.version="tmbed-1.0.0"

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/run"]
