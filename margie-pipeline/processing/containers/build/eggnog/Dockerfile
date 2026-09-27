# syntax=docker/dockerfile:1.7
# ──────────────────────────────────────────────────────────────────────────────
# eggnog — orthology assignment via eggNOG-mapper.
# Multi-stage build: compile HMMER + DIAMOND from source, install eggnog-mapper
# from PyPI with pinned version.
# See LICENSE.md for license terms (AGPL-3.0 — networked-use clause applies).
# ──────────────────────────────────────────────────────────────────────────────
ARG HMMER_VERSION=3.4
ARG DIAMOND_VERSION=2.1.9
ARG EGGNOG_MAPPER_VERSION=2.1.12

FROM debian:12-slim AS hmmer_builder
ARG HMMER_VERSION
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential ca-certificates wget \
 && rm -rf /var/lib/apt/lists/*
RUN cd /tmp \
 && wget -q "http://eddylab.org/software/hmmer/hmmer-${HMMER_VERSION}.tar.gz" \
 && tar -xzf "hmmer-${HMMER_VERSION}.tar.gz" \
 && cd "hmmer-${HMMER_VERSION}" \
 && ./configure --prefix=/usr/local && make -j"$(nproc)" && make install

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
 && mkdir build && cd build \
 && cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local .. \
 && make -j"$(nproc)" && make install

FROM python:3.11-slim
ARG HMMER_VERSION
ARG DIAMOND_VERSION
ARG EGGNOG_MAPPER_VERSION
ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 LC_ALL=C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
        tini bash ca-certificates zlib1g libgomp1 \
 && rm -rf /var/lib/apt/lists/*

COPY --from=hmmer_builder   /usr/local/bin/hmmscan  /usr/local/bin/hmmscan
COPY --from=hmmer_builder   /usr/local/bin/hmmpress /usr/local/bin/hmmpress
COPY --from=diamond_builder /usr/local/bin/diamond  /usr/local/bin/diamond

# eggnog-mapper 2.1.12 transitively pins biopython==1.76 and psutil==5.7.0.
# Neither has aarch64 wheels and biopython 1.76 sources won't compile against
# modern gcc (Bio/triemodule.c uses pre-C99 lvalue syntax). Install newer
# biopython + psutil first (they have aarch64 wheels), then install
# eggnog-mapper with --no-deps + the few remaining runtime deps explicitly.
RUN pip install --no-cache-dir \
        "biopython>=1.79" "psutil>=5.9" "xlsxwriter" "requests" \
 && pip install --no-cache-dir --no-deps "eggnog-mapper==${EGGNOG_MAPPER_VERSION}"

COPY entrypoint.sh /opt/eggnog/entrypoint.sh
COPY scripts/      /opt/eggnog/scripts/
COPY LICENSE.md    /opt/eggnog/LICENSE.md
COPY VERSIONS      /opt/eggnog/VERSIONS

RUN chmod -R a+rX /opt/eggnog \
 && find /opt/eggnog -type f \( -name '*.sh' -o -name '*.py' \) -exec chmod a+x {} + \
 && ln -sf /opt/eggnog/entrypoint.sh /usr/local/bin/run \
 && mkdir -p /input /output /db

RUN printf '{\n  "tool": "eggnog",\n  "eggnog_mapper_version": "%s",\n  "hmmer_version": "%s",\n  "diamond_version": "%s",\n  "base_image": "python:3.11-slim",\n  "build_date": "%s"\n}\n' \
        "${EGGNOG_MAPPER_VERSION}" "${HMMER_VERSION}" "${DIAMOND_VERSION}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        > /etc/pipeline-build.json

LABEL org.opencontainers.image.title="eggnog" \
      org.opencontainers.image.description="eggNOG-mapper (HMMER + DIAMOND) — from-source binaries, pinned pip version" \
      org.opencontainers.image.source="https://github.com/sajalbhattarai/containers" \
      org.opencontainers.image.vendor="margie-annotation" \
      org.opencontainers.image.licenses="AGPL-3.0-or-later" \
      org.opencontainers.image.version="eggnog-mapper-2.1.12"

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/run"]
