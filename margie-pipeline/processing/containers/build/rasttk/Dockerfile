# syntax=docker/dockerfile:1.7
# ──────────────────────────────────────────────────────────────────────────────
# rasttk — RAST-TK / BV-BRC subsystem-based prokaryote annotation
# Source: https://github.com/BV-BRC/BV-BRC-CLI/releases (rast-* commands)
# Build recipe: ubuntu:22.04 + bvbrc-cli-ubuntu-22-1.048.deb installed via apt. The
# upstream single-shot entrypoint into a multi-script batch/incremental
# runner (scripts/ — 10 scripts driving batches, TSV generation, etc.)
# ──────────────────────────────────────────────────────────────────────────────
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PATH=/opt/rasttk/scripts:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    RASTTK_NO_BUNDLED_DB=true \
    PYTHONDONTWRITEBYTECODE=1

# ── System deps (minimal — bvbrc deb pulls Perl/HMMER/etc. transitively)
# libsoap-lite-perl and libplack-perl are required for the local GenomeAnnotation
# PSGI service (plackup + SOAP::Lite) used to run rast-* commands offline on HPC.
RUN apt-get update && apt-get install -y --no-install-recommends \
        wget ca-certificates libssl-dev libdb5.3 python3 tini bash \
        libsoap-lite-perl libplack-perl \
 && rm -rf /var/lib/apt/lists/*

# ── BV-BRC CLI (rast-create-genome, rast-call-features-*, rast-export-genome)
RUN wget -q https://github.com/BV-BRC/BV-BRC-CLI/releases/download/1.048/bvbrc-cli-ubuntu-22-1.048.deb \
        -O /tmp/bvbrc.deb \
 && apt-get update \
 && apt-get install -y --no-install-recommends /tmp/bvbrc.deb \
 && rm /tmp/bvbrc.deb \
 && rm -rf /var/lib/apt/lists/* \
 && find /usr/share/bv-brc/deployment/lib -name "*.pm" -o -name "*.py" -o -name "*.js" | \
    xargs grep -rl 'tutorial\.theseed\.org/services/genome_annotation' | \
    xargs sed -i 's|tutorial\.theseed\.org/services/genome_annotation|p3.theseed.org/services/genome_annotation|g'

# ── Local pipeline-standard layout (entrypoint = rasttk_exec.sh elaborated runner)
COPY entrypoint.sh /opt/rasttk/entrypoint.sh
COPY scripts/      /opt/rasttk/scripts/
COPY postproc/     /opt/rasttk/postproc/
COPY LICENSE.md    /opt/rasttk/LICENSE.md
COPY VERSIONS      /opt/rasttk/VERSIONS

RUN chmod -R a+rX /opt/rasttk \
 && find /opt/rasttk -type f \( -name '*.sh' -o -name '*.py' \) -exec chmod a+x {} + \
 && ln -sf /opt/rasttk/entrypoint.sh /usr/local/bin/run \
 && mkdir -p /input /output /db

LABEL org.opencontainers.image.title="rasttk" \
      org.opencontainers.image.description="RAST-TK / BV-BRC annotation (upstream BV-BRC CLI .deb)" \
      org.opencontainers.image.source="https://github.com/margie-annotation/margie-pipeline" \
      org.opencontainers.image.licenses="GPL-3.0-or-later"

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/run"]
