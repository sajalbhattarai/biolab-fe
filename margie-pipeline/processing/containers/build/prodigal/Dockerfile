# syntax=docker/dockerfile:1.7
# ──────────────────────────────────────────────────────────────────────────────
# prodigal — gene calling without RASTtk. Built from source for reproducibility.
# Used for genomes whose genetic code is not known (RASTtk needs one). Writes
# the same gene_calls/ layout RASTtk does, so every downstream tool works as is.
# Two-stage build: builder compiles Prodigal, runtime ships only the binary.
# See LICENSE.md for license terms (Prodigal: GPL-3.0).
# ──────────────────────────────────────────────────────────────────────────────
ARG PRODIGAL_VERSION=2.6.3

# ── stage 1: builder — compile Prodigal from the upstream release tarball ────
FROM debian:12-slim AS builder
ARG PRODIGAL_VERSION
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential ca-certificates wget \
 && rm -rf /var/lib/apt/lists/*

RUN cd /tmp \
 && wget -q "https://github.com/hyattpd/Prodigal/archive/refs/tags/v${PRODIGAL_VERSION}.tar.gz" -O prodigal.tar.gz \
 && tar -xzf prodigal.tar.gz \
 && cd "Prodigal-${PRODIGAL_VERSION}" \
 && make \
 && install -m 0755 prodigal /usr/local/bin/prodigal \
 && cd / && rm -rf /tmp/prodigal.tar.gz "/tmp/Prodigal-${PRODIGAL_VERSION}"

# ── stage 2: runtime — slim image with the binary + python ───────────────────
FROM debian:12-slim
ARG PRODIGAL_VERSION
ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 tini bash ca-certificates \
 && rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/local/bin/prodigal /usr/local/bin/prodigal

# Pipeline entrypoint + formatter
COPY entrypoint.sh /opt/prodigal/entrypoint.sh
COPY scripts/      /opt/prodigal/scripts/
COPY LICENSE.md    /opt/prodigal/LICENSE.md
COPY VERSIONS      /opt/prodigal/VERSIONS

RUN chmod -R a+rX /opt/prodigal \
 && find /opt/prodigal -type f \( -name '*.sh' -o -name '*.py' \) -exec chmod a+x {} + \
 && ln -sf /opt/prodigal/entrypoint.sh /usr/local/bin/run \
 && mkdir -p /input /output

# Build-time provenance — readable inside the image
RUN printf '{\n  "tool": "prodigal",\n  "prodigal_version": "%s",\n  "base_image": "debian:12-slim",\n  "build_date": "%s"\n}\n' \
        "${PRODIGAL_VERSION}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        > /etc/pipeline-build.json

LABEL org.opencontainers.image.title="prodigal" \
      org.opencontainers.image.description="Prodigal gene calling in the RASTtk gene_calls layout (from-source build)" \
      org.opencontainers.image.source="https://github.com/sajalbhattarai/margie-pipeline" \
      org.opencontainers.image.vendor="margie-annotation" \
      org.opencontainers.image.licenses="GPL-3.0-only" \
      org.opencontainers.image.version="prodigal-2.6.3"

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/run"]
