# syntax=docker/dockerfile:1.7
# ──────────────────────────────────────────────────────────────────────────────
# merops — DIAMOND blastp against MEROPS peptidase database. Built from source.
# Two-stage: builder compiles DIAMOND, runtime ships only the binary.
# See LICENSE.md for license terms (DIAMOND: GPL-3.0).
# ──────────────────────────────────────────────────────────────────────────────
ARG DIAMOND_VERSION=2.1.9

FROM debian:12-slim AS builder
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
 && make -j"$(nproc)" && make install \
 && cd / && rm -rf "/tmp/diamond-${DIAMOND_VERSION}" "/tmp/v${DIAMOND_VERSION}.tar.gz"

FROM debian:12-slim
ARG DIAMOND_VERSION
ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 LC_ALL=C.UTF-8
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 tini bash ca-certificates zlib1g \
 && rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/local/bin/diamond /usr/local/bin/diamond

COPY entrypoint.sh /opt/merops/entrypoint.sh
COPY scripts/      /opt/merops/scripts/
COPY LICENSE.md    /opt/merops/LICENSE.md
COPY VERSIONS      /opt/merops/VERSIONS

RUN chmod -R a+rX /opt/merops \
 && find /opt/merops -type f \( -name '*.sh' -o -name '*.py' \) -exec chmod a+x {} + \
 && ln -sf /opt/merops/entrypoint.sh /usr/local/bin/run \
 && mkdir -p /input /output /db

RUN printf '{\n  "tool": "merops",\n  "diamond_version": "%s",\n  "base_image": "debian:12-slim",\n  "build_date": "%s"\n}\n' \
        "${DIAMOND_VERSION}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        > /etc/pipeline-build.json

LABEL org.opencontainers.image.title="merops" \
      org.opencontainers.image.description="DIAMOND blastp against MEROPS peptidase database (from-source build)" \
      org.opencontainers.image.source="https://github.com/sajalbhattarai/containers" \
      org.opencontainers.image.vendor="margie-annotation" \
      org.opencontainers.image.licenses="GPL-3.0-or-later AND CC-BY-4.0" \
      org.opencontainers.image.version="diamond-2.1.9"

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/run"]
