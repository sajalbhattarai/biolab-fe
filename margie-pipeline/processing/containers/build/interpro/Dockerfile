# syntax=docker/dockerfile:1.7
# ──────────────────────────────────────────────────────────────────────────────
# interpro — InterProScan launcher (Java 11 + Perl + Python 3 runtime)
# Source:  https://github.com/ebi-pf-team/interproscan  (binaries mounted at /db)
# Build recipe: eclipse-temurin Java
# 11 base; forces linux/amd64 because InterProScan ships x86_64 binaries only.
# Local pipeline elaboration adds scripts/process_interpro_raw_results.py.
# ──────────────────────────────────────────────────────────────────────────────
FROM --platform=linux/amd64 eclipse-temurin:11-jre-jammy

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PYTHONDONTWRITEBYTECODE=1

# InterProScan ships its own binaries (hmmer, coils, etc.) inside data/.
# We only provide Java 11 (base image) + Python 3 + Perl for helper scripts.
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 python3-pip perl libgomp1 libgcc-s1 tini bash ca-certificates \
 && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /opt/interpro/entrypoint.sh
COPY scripts/      /opt/interpro/scripts/
COPY LICENSE.md    /opt/interpro/LICENSE.md
COPY VERSIONS      /opt/interpro/VERSIONS

RUN chmod -R a+rX /opt/interpro \
 && find /opt/interpro -type f \( -name '*.sh' -o -name '*.py' \) -exec chmod a+x {} + \
 && ln -sf /opt/interpro/entrypoint.sh /usr/local/bin/run \
 && mkdir -p /input /output /db

LABEL org.opencontainers.image.title="interpro" \
      org.opencontainers.image.description="InterProScan launcher (upstream eclipse-temurin base)" \
      org.opencontainers.image.source="https://github.com/sajalbhattarai/containers" \
      org.opencontainers.image.licenses="Apache-2.0"

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/run"]
