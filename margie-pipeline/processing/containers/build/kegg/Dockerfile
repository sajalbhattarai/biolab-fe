# syntax=docker/dockerfile:1.7
# ──────────────────────────────────────────────────────────────────────────────
# kegg — KEGG Ortholog assignment via KofamScan.
# KofamScan from ftp.genome.jp official tarball, HMMER compiled from source,
# GNU parallel from Debian (BSD-licensed redistributable).
# See LICENSE.md for license terms.
# ──────────────────────────────────────────────────────────────────────────────
ARG HMMER_VERSION=3.4
ARG KOFAMSCAN_VERSION=1.3.0

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

FROM debian:12-slim
ARG HMMER_VERSION
ARG KOFAMSCAN_VERSION
ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 LC_ALL=C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
        tini bash ca-certificates wget ruby parallel python3 \
 && rm -rf /var/lib/apt/lists/*

COPY --from=hmmer_builder /usr/local/bin/hmmscan  /usr/local/bin/hmmscan
COPY --from=hmmer_builder /usr/local/bin/hmmsearch /usr/local/bin/hmmsearch
COPY --from=hmmer_builder /usr/local/bin/hmmpress /usr/local/bin/hmmpress

# Install KofamScan from upstream genome.jp tarball
RUN cd /opt \
 && wget -q "https://www.genome.jp/ftp/tools/kofam_scan/kofam_scan-${KOFAMSCAN_VERSION}.tar.gz" \
 && tar -xzf "kofam_scan-${KOFAMSCAN_VERSION}.tar.gz" \
 && rm "kofam_scan-${KOFAMSCAN_VERSION}.tar.gz" \
 && mv "kofam_scan-${KOFAMSCAN_VERSION}" kofamscan \
 && ln -sf /opt/kofamscan/exec_annotation /usr/local/bin/exec_annotation

COPY entrypoint.sh /opt/kegg/entrypoint.sh
COPY scripts/      /opt/kegg/scripts/
COPY LICENSE.md    /opt/kegg/LICENSE.md
COPY VERSIONS      /opt/kegg/VERSIONS

RUN chmod -R a+rX /opt/kegg /opt/kofamscan \
 && find /opt/kegg -type f \( -name '*.sh' -o -name '*.py' \) -exec chmod a+x {} + \
 && ln -sf /opt/kegg/entrypoint.sh /usr/local/bin/run \
 && mkdir -p /input /output /db

RUN printf '{\n  "tool": "kegg",\n  "kofamscan_version": "%s",\n  "hmmer_version": "%s",\n  "base_image": "debian:12-slim",\n  "build_date": "%s"\n}\n' \
        "${KOFAMSCAN_VERSION}" "${HMMER_VERSION}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        > /etc/pipeline-build.json

LABEL org.opencontainers.image.title="kegg" \
      org.opencontainers.image.description="KofamScan against KEGG Orthology HMM profiles (HMMER from source)" \
      org.opencontainers.image.source="https://github.com/sajalbhattarai/containers" \
      org.opencontainers.image.vendor="margie-annotation" \
      org.opencontainers.image.licenses="MIT AND BSD-3-Clause" \
      org.opencontainers.image.version="kofamscan-1.3.0+hmmer-3.4"

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/run"]
