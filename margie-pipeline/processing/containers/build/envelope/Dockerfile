# syntax=docker/dockerfile:1.7
# ──────────────────────────────────────────────────────────────────────────────
# envelope — envelope-type inference from upstream annotation descriptors.
# Pure-Python (stdlib only); no compiled dependencies, so this builds natively
# on both linux/amd64 and linux/arm64.
#
# Kept in step with apptainer.def in this directory — the two recipes must
# produce equivalent images. See LICENSE.md for license terms.
# ──────────────────────────────────────────────────────────────────────────────
FROM python:3.11-slim
ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 LC_ALL=C.UTF-8 \
    PYTHONDONTWRITEBYTECODE=1

RUN apt-get update && apt-get install -y --no-install-recommends \
        bash ca-certificates \
 && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /opt/envelope/entrypoint.sh
COPY scripts/      /opt/envelope/scripts/

RUN chmod -R a+rX /opt/envelope \
 && find /opt/envelope -type f \( -name '*.sh' -o -name '*.py' \) -exec chmod a+x {} + \
 && printf '#!/usr/bin/env bash\nexec /opt/envelope/entrypoint.sh "$@"\n' > /usr/local/bin/run \
 && printf '#!/usr/bin/env bash\nexec /usr/local/bin/run "$@"\n' > /usr/local/bin/margie_run \
 && chmod +x /usr/local/bin/run /usr/local/bin/margie_run \
 && mkdir -p /input /output

LABEL org.opencontainers.image.title="envelope" \
      org.opencontainers.image.description="Envelope-type inference from upstream annotation descriptors" \
      org.opencontainers.image.source="https://github.com/sajalbhattarai/containers" \
      org.opencontainers.image.licenses="BSD-3-Clause"

ENTRYPOINT ["/usr/local/bin/run"]
