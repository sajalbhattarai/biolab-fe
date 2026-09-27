# syntax=docker/dockerfile:1.7
# ──────────────────────────────────────────────────────────────────────────────
# dbcan — Carbohydrate-active enzyme annotation (HMMER + DIAMOND + dbCAN-sub).
# Multi-stage build: compile HMMER and DIAMOND from upstream source, then
# install run_dbcan from PyPI with pinned versions on python:3.11-slim.
# See LICENSE.md for license terms.
# ──────────────────────────────────────────────────────────────────────────────
ARG HMMER_VERSION=3.4
ARG DIAMOND_VERSION=2.1.9
ARG DBCAN_VERSION=5.1.2
# dbcan 5.1.2 pins pyrodigal==3.6.3 (upstream constraint); keep aligned.
ARG PYRODIGAL_VERSION=3.6.3

# ── stage 1: HMMER builder ──────────────────────────────────────────────────
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

# ── stage 2: DIAMOND builder ────────────────────────────────────────────────
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

# ── stage 3: runtime ────────────────────────────────────────────────────────
FROM python:3.11-slim
ARG HMMER_VERSION
ARG DIAMOND_VERSION
ARG DBCAN_VERSION
ARG PYRODIGAL_VERSION
ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 LC_ALL=C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
        tini bash ca-certificates zlib1g libgomp1 \
 && rm -rf /var/lib/apt/lists/*

# Bring in compiled binaries
COPY --from=hmmer_builder   /usr/local/bin/hmmscan  /usr/local/bin/hmmscan
COPY --from=hmmer_builder   /usr/local/bin/hmmpress /usr/local/bin/hmmpress
COPY --from=hmmer_builder   /usr/local/bin/hmmstat  /usr/local/bin/hmmstat
COPY --from=diamond_builder /usr/local/bin/diamond  /usr/local/bin/diamond

# run_dbcan from PyPI with pinned versions
RUN pip install --no-cache-dir \
        "dbcan==${DBCAN_VERSION}" \
        "pyrodigal==${PYRODIGAL_VERSION}"

COPY entrypoint.sh /opt/dbcan/entrypoint.sh
COPY scripts/      /opt/dbcan/scripts/
COPY LICENSE.md    /opt/dbcan/LICENSE.md
COPY VERSIONS      /opt/dbcan/VERSIONS

RUN chmod -R a+rX /opt/dbcan \
 && find /opt/dbcan -type f \( -name '*.sh' -o -name '*.py' \) -exec chmod a+x {} + \
 && ln -sf /opt/dbcan/entrypoint.sh /usr/local/bin/run \
 && mkdir -p /input /output /db

RUN printf '{\n  "tool": "dbcan",\n  "hmmer_version": "%s",\n  "diamond_version": "%s",\n  "dbcan_version": "%s",\n  "pyrodigal_version": "%s",\n  "base_image": "python:3.11-slim",\n  "build_date": "%s"\n}\n' \
        "${HMMER_VERSION}" "${DIAMOND_VERSION}" "${DBCAN_VERSION}" "${PYRODIGAL_VERSION}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        > /etc/pipeline-build.json

LABEL org.opencontainers.image.title="dbcan" \
      org.opencontainers.image.description="run_dbcan v5 (HMMER + DIAMOND + dbCAN-sub) — from-source binaries, pinned pip versions" \
      org.opencontainers.image.source="https://github.com/sajalbhattarai/containers" \
      org.opencontainers.image.vendor="margie-annotation" \
      org.opencontainers.image.licenses="GPL-3.0-or-later" \
      org.opencontainers.image.version="dbcan-5.1.2"

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/run"]
