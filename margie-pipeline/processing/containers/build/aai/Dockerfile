# syntax=docker/dockerfile:1.7
# ──────────────────────────────────────────────────────────────────────────────
# aai — Average Amino Acid Identity via EzAAI (all-vs-all prokaryotic genomes).
#
# Takes a directory of protein FASTA (.faa) files, runs EzAAI all-vs-all AAI,
# and outputs a pairwise results file plus a normalised N×N symmetric matrix.
#
# Multi-arch: EzAAI is a platform-independent Java JAR; DIAMOND is compiled
# from source for each target architecture (amd64 / arm64).
#
# See LICENSE.md for per-component license terms.
# ──────────────────────────────────────────────────────────────────────────────
ARG EZAAI_VERSION=1.2.4
ARG DIAMOND_VERSION=2.1.9
ARG JAVA_VERSION=21

# ── Stage 1: compile DIAMOND from source (amd64 + arm64 via BuildKit) ─────────
FROM debian:12-slim AS diamond_builder
ARG DIAMOND_VERSION
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential cmake ca-certificates wget zlib1g-dev \
 && rm -rf /var/lib/apt/lists/*
RUN cd /tmp \
 && wget -q "https://github.com/bbuchfink/diamond/archive/refs/tags/v${DIAMOND_VERSION}.tar.gz" \
 && tar -xzf "v${DIAMOND_VERSION}.tar.gz" \
 && cd "diamond-${DIAMOND_VERSION}" \
 && mkdir -p build && cd build \
 && cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local .. \
 && make -j"$(nproc)" && make install \
 && strip /usr/local/bin/diamond

# ── Final image ────────────────────────────────────────────────────────────────
FROM python:3.11-slim
ARG EZAAI_VERSION
ARG DIAMOND_VERSION
ARG JAVA_VERSION
ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 LC_ALL=C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
        tini bash ca-certificates wget zlib1g \
        "openjdk-${JAVA_VERSION}-jre-headless" \
 && rm -rf /var/lib/apt/lists/*

COPY --from=diamond_builder /usr/local/bin/diamond /usr/local/bin/diamond

# Download the EzAAI JAR (v1.2.3+ ships as ezaai-bin.tar.gz containing EzAAI.jar)
RUN mkdir -p /opt/aai \
 && cd /tmp \
 && wget -q "https://github.com/endixk/ezaai/releases/download/v${EZAAI_VERSION}/ezaai-bin.tar.gz" \
 && tar -xzf ezaai-bin.tar.gz EzAAI.jar \
 && mv EzAAI.jar /opt/aai/EzAAI.jar \
 && rm -f ezaai-bin.tar.gz \
 && chmod a+r /opt/aai/EzAAI.jar

# Thin wrapper so callers write `ezaai` rather than `java -jar ...`
RUN printf '#!/usr/bin/env bash\nexec java -jar /opt/aai/EzAAI.jar "$@"\n' \
        > /usr/local/bin/ezaai \
 && chmod a+x /usr/local/bin/ezaai

COPY entrypoint.sh /opt/aai/entrypoint.sh
COPY scripts/      /opt/aai/scripts/
COPY LICENSE.md    /opt/aai/LICENSE.md
COPY VERSIONS      /opt/aai/VERSIONS

RUN chmod -R a+rX /opt/aai \
 && find /opt/aai -type f \( -name '*.sh' -o -name '*.py' \) -exec chmod a+x {} + \
 && ln -sf /opt/aai/entrypoint.sh /usr/local/bin/run \
 && mkdir -p /input /output

RUN printf '{\n  "tool": "aai",\n  "ezaai_version": "%s",\n  "diamond_version": "%s",\n  "base_image": "python:3.11-slim",\n  "build_date": "%s"\n}\n' \
        "${EZAAI_VERSION}" "${DIAMOND_VERSION}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        > /etc/pipeline-build.json

LABEL org.opencontainers.image.title="aai" \
      org.opencontainers.image.description="Average Amino Acid Identity via EzAAI (all-vs-all)" \
      org.opencontainers.image.source="https://github.com/sajalbhattarai/margie-pipeline" \
      org.opencontainers.image.vendor="margie-annotation" \
      org.opencontainers.image.licenses="MIT AND GPL-3.0-or-later" \
      org.opencontainers.image.version="ezaai-1.2.2+diamond-2.1.9"

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/run"]
