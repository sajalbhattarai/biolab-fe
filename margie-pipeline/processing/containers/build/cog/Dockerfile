# syntax=docker/dockerfile:1.7
# ──────────────────────────────────────────────────────────────────────────────
# cog — NCBI BLAST+ rpsblast against COG profiles + cogclassifier post-process.
# Uses the official NCBI BLAST+ release tarball (canonical reference build).
# cogclassifier installed from pip with pinned version.
# AMD64-only: NCBI ships official binaries for linux/amd64 only.
# See LICENSE.md for license terms.
# ──────────────────────────────────────────────────────────────────────────────
ARG BLAST_VERSION=2.16.0
ARG COGCLASSIFIER_VERSION=2.0.0

FROM --platform=linux/amd64 python:3.11-slim
ARG BLAST_VERSION
ARG COGCLASSIFIER_VERSION
ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 LC_ALL=C.UTF-8

# Runtime deps (tini for PID 1; libgomp/zlib for BLAST+; wget/ca-certs for fetch)
RUN apt-get update && apt-get install -y --no-install-recommends \
        tini bash ca-certificates wget libgomp1 zlib1g \
 && rm -rf /var/lib/apt/lists/*

# Install BLAST+ from the official NCBI release tarball
RUN cd /tmp \
 && wget -q "https://ftp.ncbi.nlm.nih.gov/blast/executables/blast+/${BLAST_VERSION}/ncbi-blast-${BLAST_VERSION}+-x64-linux.tar.gz" \
 && tar -xzf "ncbi-blast-${BLAST_VERSION}+-x64-linux.tar.gz" \
 && cp "ncbi-blast-${BLAST_VERSION}+/bin/rpsblast" /usr/local/bin/rpsblast \
 && cp "ncbi-blast-${BLAST_VERSION}+/bin/blastdbcmd" /usr/local/bin/blastdbcmd \
 && chmod a+x /usr/local/bin/rpsblast /usr/local/bin/blastdbcmd \
 && cd / && rm -rf /tmp/ncbi-blast-*

# Install cogclassifier — pinned upstream version
RUN pip install --no-cache-dir "cogclassifier==${COGCLASSIFIER_VERSION}"

COPY entrypoint.sh /opt/cog/entrypoint.sh
COPY scripts/      /opt/cog/scripts/
COPY LICENSE.md    /opt/cog/LICENSE.md
COPY VERSIONS      /opt/cog/VERSIONS

RUN chmod -R a+rX /opt/cog \
 && find /opt/cog -type f \( -name '*.sh' -o -name '*.py' \) -exec chmod a+x {} + \
 && ln -sf /opt/cog/entrypoint.sh /usr/local/bin/run \
 && mkdir -p /input /output /db \
 && /usr/local/bin/run --help >/dev/null

RUN printf '{\n  "tool": "cog",\n  "blast_version": "%s",\n  "cogclassifier_version": "%s",\n  "base_image": "python:3.11-slim",\n  "build_date": "%s"\n}\n' \
        "${BLAST_VERSION}" "${COGCLASSIFIER_VERSION}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        > /etc/pipeline-build.json

LABEL org.opencontainers.image.title="cog" \
      org.opencontainers.image.description="NCBI BLAST+ rpsblast against COG + cogclassifier post-processing" \
        org.opencontainers.image.source="https://github.com/sajalbhattarai/margie-pipeline" \
      org.opencontainers.image.vendor="margie-annotation" \
      org.opencontainers.image.licenses="PublicDomain AND MIT" \
      org.opencontainers.image.version="blast-2.16.0+cogclassifier-2.0.0"

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/run"]
