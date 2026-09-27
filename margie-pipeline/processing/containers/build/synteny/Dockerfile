# syntax=docker/dockerfile:1.7
# ──────────────────────────────────────────────────────────────────────────────
# synteny — Annotation transfer via Liftoff (gene rescue from reference genomes).
#
# Workflow:
#   For each reference genome in /input/references/:
#     liftoff -g <ref>.gff3 -o /output/synteny/<ref>/liftoff.gff3 query.fna <ref>.fna
#   Then merge_liftoff.py deduplicates and merges all per-reference GFF3 outputs
#   into a single non-redundant GFF3 file.
#
# Multi-arch: minimap2 compiled from source (amd64 + arm64 via BuildKit);
# Liftoff installed via pip (pure Python).
#
# See LICENSE.md for per-component license terms.
# ──────────────────────────────────────────────────────────────────────────────
ARG LIFTOFF_VERSION=1.6.3.2
ARG MINIMAP2_VERSION=2.28

# ── Stage 1: compile minimap2 from source ─────────────────────────────────────
FROM debian:12-slim AS minimap2_builder
ARG MINIMAP2_VERSION
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential ca-certificates wget \
        zlib1g-dev libbz2-dev liblzma-dev \
 && rm -rf /var/lib/apt/lists/*
RUN cd /tmp \
 && wget -q "https://github.com/lh3/minimap2/archive/refs/tags/v${MINIMAP2_VERSION}.tar.gz" \
 && tar -xzf "v${MINIMAP2_VERSION}.tar.gz" \
 && cd "minimap2-${MINIMAP2_VERSION}" \
 && make -j"$(nproc)" \
 && strip minimap2 \
 && install -m 755 minimap2 /usr/local/bin/minimap2

# ── Final image ────────────────────────────────────────────────────────────────
FROM python:3.11-slim
ARG LIFTOFF_VERSION
ARG MINIMAP2_VERSION
ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 LC_ALL=C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
        tini bash ca-certificates \
        zlib1g libbz2-1.0 liblzma5 \
        libcurl4-openssl-dev libssl-dev \
 && rm -rf /var/lib/apt/lists/*

COPY --from=minimap2_builder /usr/local/bin/minimap2 /usr/local/bin/minimap2

# liftoff==1.6.3.2 pins pysam==0.16.0.1 which uses use_2to3 (removed in
# setuptools>=58) — install deps manually then liftoff with --no-deps.
RUN pip install --no-cache-dir pysam networkx gffutils biopython numpy \
 && pip install --no-cache-dir --no-deps "liftoff==${LIFTOFF_VERSION}"

COPY entrypoint.sh /opt/synteny/entrypoint.sh
COPY scripts/      /opt/synteny/scripts/
COPY LICENSE.md    /opt/synteny/LICENSE.md
COPY VERSIONS      /opt/synteny/VERSIONS

RUN chmod -R a+rX /opt/synteny \
 && find /opt/synteny -type f \( -name '*.sh' -o -name '*.py' \) -exec chmod a+x {} + \
 && ln -sf /opt/synteny/entrypoint.sh /usr/local/bin/run \
 && mkdir -p /input /output

RUN printf '{\n  "tool": "synteny",\n  "liftoff_version": "%s",\n  "minimap2_version": "%s",\n  "base_image": "python:3.11-slim",\n  "build_date": "%s"\n}\n' \
        "${LIFTOFF_VERSION}" "${MINIMAP2_VERSION}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        > /etc/pipeline-build.json

LABEL org.opencontainers.image.title="synteny" \
      org.opencontainers.image.description="Annotation transfer / gene rescue via Liftoff" \
      org.opencontainers.image.source="https://github.com/sajalbhattarai/margie-pipeline" \
      org.opencontainers.image.vendor="margie-annotation" \
      org.opencontainers.image.licenses="GPL-3.0-or-later AND MIT AND BSD-3-Clause" \
      org.opencontainers.image.version="liftoff-1.6.3+minimap2-2.28"

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/run"]
