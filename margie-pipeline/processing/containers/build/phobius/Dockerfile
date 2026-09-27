# syntax=docker/dockerfile:1.7
# ──────────────────────────────────────────────────────────────────────────────
# phobius — combined signal-peptide / transmembrane-topology prediction
# Source:  http://phobius.sbc.su.se/  (Academic license; NOT redistributable)
# The phobius distribution tarball (phobius101_linux.tgz) is bundled in this
# build context and extracted into vendor/ (perl script + HMM model + x86_64
# decodeanhmm binary). Re-distribution outside this academic pipeline is
# prohibited per the upstream license.
# Local pipeline elaboration adds scripts/process_phobius_raw_results.py.
# ──────────────────────────────────────────────────────────────────────────────
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PYTHONDONTWRITEBYTECODE=1

# Phobius needs only perl at runtime (decodeanhmm.64bit is statically linked).
# tini for clean signal handling; python3 for the local post-processor.
RUN apt-get update && apt-get install -y --no-install-recommends \
        tini ca-certificates bash perl procps python3 \
 && rm -rf /var/lib/apt/lists/*

# Phobius distribution files (from vendor/ — extracted from upstream tarball)
COPY vendor/ /opt/phobius/
# Symlink 64-bit decoder over the legacy 32-bit name (no ia32 libs needed)
RUN ln -sf /opt/phobius/decodeanhmm.64bit /opt/phobius/decodeanhmm \
 && chmod a+x /opt/phobius/decodeanhmm.64bit /opt/phobius/phobius.pl \
 && chmod -R a+rX /opt/phobius \
 && ln -sf /opt/phobius/phobius.pl /usr/local/bin/phobius

# Local pipeline-standard layout
COPY entrypoint.sh /opt/phobius/entrypoint.sh
COPY scripts/      /opt/phobius/scripts/
COPY LICENSE.md    /opt/phobius/LICENSE.md
COPY VERSIONS      /opt/phobius/VERSIONS

RUN chmod -R a+rX /opt/phobius \
 && find /opt/phobius -type f \( -name '*.sh' -o -name '*.py' \) -exec chmod a+x {} + \
 && ln -sf /opt/phobius/entrypoint.sh /usr/local/bin/run \
 && mkdir -p /input /output

LABEL org.opencontainers.image.title="phobius" \
      org.opencontainers.image.description="Phobius signal-peptide+TM topology (academic-license tarball; NOT redistributable)" \
      org.opencontainers.image.source="https://github.com/sajalbhattarai/containers" \
      org.opencontainers.image.licenses="LicenseRef-phobius-academic"

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/run"]
