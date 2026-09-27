# syntax=docker/dockerfile:1.7
# ──────────────────────────────────────────────────────────────────────────────
# ani — Average Nucleotide Identity via FastANI (all-vs-all prokaryotic genomes).
#
# Takes a directory of nucleotide FASTA (.fna) files, runs FastANI all-vs-all,
# and outputs a pairwise results file plus a normalised N×N symmetric matrix.
#
# Multi-arch: FastANI compiled from source for each target platform
# (amd64 / arm64) using BuildKit's automatic TARGETARCH.
#
# See LICENSE.md for per-component license terms.
# ──────────────────────────────────────────────────────────────────────────────
ARG FASTANI_VERSION=1.34

# ── Stage 1: compile FastANI from source (amd64 + arm64 via BuildKit) ─────────
FROM debian:12-slim AS fastani_builder
ARG FASTANI_VERSION
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential autoconf automake libtool ca-certificates wget \
        zlib1g-dev libboost-all-dev libgsl-dev \
 && rm -rf /var/lib/apt/lists/*
# Bootstrap + configure + compile
RUN cd /tmp \
 && wget -q "https://github.com/ParBLiSS/FastANI/archive/refs/tags/v${FASTANI_VERSION}.tar.gz" \
 && tar -xzf "v${FASTANI_VERSION}.tar.gz" \
 && cd "FastANI-${FASTANI_VERSION}" \
 && ./bootstrap.sh \
 && ./configure --prefix=/usr/local \
 && make -j"$(nproc)" \
 && make install \
 && strip /usr/local/bin/fastANI

# ── Final image ────────────────────────────────────────────────────────────────
FROM python:3.11-slim
ARG FASTANI_VERSION
ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 LC_ALL=C.UTF-8

# Runtime shared libraries required by the fastANI binary on Debian 12
RUN apt-get update && apt-get install -y --no-install-recommends \
        tini bash ca-certificates zlib1g \
        libboost-filesystem1.81.0 libboost-program-options1.81.0 \
        libboost-system1.81.0 \
        libgsl27 libgslcblas0 \
 && rm -rf /var/lib/apt/lists/*

COPY --from=fastani_builder /usr/local/bin/fastANI /usr/local/bin/fastANI

COPY entrypoint.sh /opt/ani/entrypoint.sh
COPY scripts/      /opt/ani/scripts/
COPY LICENSE.md    /opt/ani/LICENSE.md
COPY VERSIONS      /opt/ani/VERSIONS

RUN chmod -R a+rX /opt/ani \
 && find /opt/ani -type f \( -name '*.sh' -o -name '*.py' \) -exec chmod a+x {} + \
 && ln -sf /opt/ani/entrypoint.sh /usr/local/bin/run \
 && mkdir -p /input /output

RUN printf '{\n  "tool": "ani",\n  "fastani_version": "%s",\n  "base_image": "python:3.11-slim",\n  "build_date": "%s"\n}\n' \
        "${FASTANI_VERSION}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        > /etc/pipeline-build.json

LABEL org.opencontainers.image.title="ani" \
      org.opencontainers.image.description="Average Nucleotide Identity via FastANI (all-vs-all)" \
      org.opencontainers.image.source="https://github.com/sajalbhattarai/margie-pipeline" \
      org.opencontainers.image.vendor="margie-annotation" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.version="fastani-1.34"

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/run"]
