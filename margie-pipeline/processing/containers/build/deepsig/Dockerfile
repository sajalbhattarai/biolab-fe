# syntax=docker/dockerfile:1.7
# ──────────────────────────────────────────────────────────────────────────────
# deepsig — neural signal-peptide prediction (BolognaBiocomp DeepSig)
# Source:  https://github.com/BolognaBiocomp/deepsig (GPL-3, redistributable)
# Build recipe: uses the official
# bolognabiocomp/deepsig base image, which bundles python + tensorflow +
# biopython + deepsig source at /usr/src/deepsig.
# Local pipeline elaboration: adds scripts/process_deepsig_raw_results.py and
# the shared scripts/pipeline_log.sh helper that entrypoint.sh sources.
# Base image pinned by digest (resolved 2026-05-30 from bolognabiocomp/deepsig:latest)
# for reproducible from-source builds.
# ──────────────────────────────────────────────────────────────────────────────
FROM bolognabiocomp/deepsig@sha256:2d8ccba3406ec3814de3cc84b13047b70f26d5546acefb63a573fc20c009e9a9

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PYTHONDONTWRITEBYTECODE=1 \
    TF_CPP_MIN_LOG_LEVEL=3 \
    DEEPSIG_ROOT=/usr/src/deepsig

# `deepsig` shim on PATH so entrypoint can call it directly
RUN chmod a+x /usr/src/deepsig/deepsig.py \
 && ln -sf /usr/src/deepsig/deepsig.py /usr/local/bin/deepsig

# Local pipeline-standard layout (matches pfam et al.)
COPY entrypoint.sh /opt/deepsig/entrypoint.sh
COPY scripts/      /opt/deepsig/scripts/
COPY LICENSE.md    /opt/deepsig/LICENSE.md
COPY VERSIONS      /opt/deepsig/VERSIONS

RUN chmod -R a+rX /opt/deepsig \
 && find /opt/deepsig -type f \( -name '*.sh' -o -name '*.py' \) -exec chmod a+x {} + \
 && ln -sf /opt/deepsig/entrypoint.sh /usr/local/bin/run \
 && mkdir -p /input /output

LABEL org.opencontainers.image.title="deepsig" \
      org.opencontainers.image.description="DeepSig signal-peptide predictor (upstream base image)" \
      org.opencontainers.image.source="https://github.com/sajalbhattarai/containers" \
      org.opencontainers.image.licenses="GPL-3.0-only"

ENTRYPOINT ["/usr/local/bin/run"]
