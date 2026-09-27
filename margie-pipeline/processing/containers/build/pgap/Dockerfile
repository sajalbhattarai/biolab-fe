# syntax=docker/dockerfile:1.7
# ──────────────────────────────────────────────────────────────────────────────
# pgap — HMMER hmmscan against the NCBI PGAP HMM library (NCBIfam + TIGRfam).
# Built from source for reproducibility. Identical HMMER stage as pfam/tigrfam.
# See LICENSE.md for license terms.
# ──────────────────────────────────────────────────────────────────────────────
ARG HMMER_VERSION=3.4

FROM debian:12-slim AS builder
ARG HMMER_VERSION
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential ca-certificates wget \
 && rm -rf /var/lib/apt/lists/*
RUN cd /tmp \
 && wget -q "http://eddylab.org/software/hmmer/hmmer-${HMMER_VERSION}.tar.gz" \
 && tar -xzf "hmmer-${HMMER_VERSION}.tar.gz" \
 && cd "hmmer-${HMMER_VERSION}" \
 && ./configure --prefix=/usr/local && make -j"$(nproc)" && make install \
 && cd / && rm -rf /tmp/hmmer-*

FROM debian:12-slim
ARG HMMER_VERSION
ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 LC_ALL=C.UTF-8
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 tini bash ca-certificates \
 && rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/local/bin/hmmscan  /usr/local/bin/hmmscan
COPY --from=builder /usr/local/bin/hmmpress /usr/local/bin/hmmpress
COPY --from=builder /usr/local/bin/hmmstat  /usr/local/bin/hmmstat

COPY entrypoint.sh /opt/pgap/entrypoint.sh
COPY scripts/      /opt/pgap/scripts/
COPY LICENSE.md    /opt/pgap/LICENSE.md
COPY VERSIONS      /opt/pgap/VERSIONS

RUN chmod -R a+rX /opt/pgap \
 && find /opt/pgap -type f \( -name '*.sh' -o -name '*.py' \) -exec chmod a+x {} + \
 && ln -sf /opt/pgap/entrypoint.sh /usr/local/bin/run \
 && mkdir -p /input /output /db

RUN printf '{\n  "tool": "pgap",\n  "hmmer_version": "%s",\n  "base_image": "debian:12-slim",\n  "build_date": "%s"\n}\n' \
        "${HMMER_VERSION}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        > /etc/pipeline-build.json

LABEL org.opencontainers.image.title="pgap" \
      org.opencontainers.image.description="HMMER hmmscan against NCBI PGAP HMM library (from-source build)" \
      org.opencontainers.image.source="https://github.com/sajalbhattarai/containers" \
      org.opencontainers.image.vendor="margie-annotation" \
      org.opencontainers.image.licenses="BSD-3-Clause AND PublicDomain" \
      org.opencontainers.image.version="hmmer-3.4"

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/run"]
