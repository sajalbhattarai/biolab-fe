# syntax=docker/dockerfile:1.7
# ──────────────────────────────────────────────────────────────────────────────
# operon — UniOP intergenic-distance operon prediction.
# UniOP source vendored under ./UniOP (snapshot of https://github.com/hongsua/UniOP
# main branch as of 2025-05-30). Snapshot URL + commit are recorded in VERSIONS.
# Prodigal from Debian apt; pure-Python deps from PyPI with pinned versions.
# See LICENSE.md for license terms.
# ──────────────────────────────────────────────────────────────────────────────
FROM python:3.11-slim
ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 LC_ALL=C.UTF-8 \
    UNIOP_HOME=/opt/UniOP

RUN apt-get update && apt-get install -y --no-install-recommends \
        tini bash ca-certificates prodigal \
 && rm -rf /var/lib/apt/lists/*

# Pinned Python deps for UniOP (pure Python + manylinux wheels — multi-arch safe)
RUN pip install --no-cache-dir \
        "numpy==1.26.4" \
        "pandas==2.2.2" \
        "scikit-learn==1.4.2" \
        "scipy==1.13.1" \
        "joblib==1.4.2"

# Vendored UniOP source
COPY UniOP /opt/UniOP
RUN chmod +x /opt/UniOP/src/UniOP \
 && ln -sf /opt/UniOP/src/UniOP /usr/local/bin/UniOP

COPY entrypoint.sh /opt/operon/entrypoint.sh
COPY scripts/      /opt/operon/scripts/
COPY LICENSE.md    /opt/operon/LICENSE.md
COPY VERSIONS      /opt/operon/VERSIONS

RUN chmod -R a+rX /opt/operon \
 && find /opt/operon -type f \( -name '*.sh' -o -name '*.py' \) -exec chmod a+x {} + \
 && ln -sf /opt/operon/entrypoint.sh /usr/local/bin/run \
 && mkdir -p /input /output /db

RUN printf '{\n  "tool": "operon",\n  "uniop_snapshot": "2025-05-30",\n  "uniop_upstream": "https://github.com/hongsua/UniOP",\n  "base_image": "python:3.11-slim",\n  "build_date": "%s"\n}\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        > /etc/pipeline-build.json

LABEL org.opencontainers.image.title="operon" \
      org.opencontainers.image.description="UniOP intergenic-distance operon prediction (vendored snapshot)" \
      org.opencontainers.image.source="https://github.com/sajalbhattarai/containers" \
      org.opencontainers.image.vendor="margie-annotation" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.version="uniop-snapshot-2025-05-30"

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/run"]
