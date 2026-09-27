# syntax=docker/dockerfile:1.7
# ──────────────────────────────────────────────────────────────────────────────
# psortb — Bacterial subcellular localization prediction (PSORTb v3, GPL)
# Source: brinkmanlab/psortb_commandline:1.0.2 + patched Perl modules
# Bakes in 4 patched Perl modules on top of brinkmanlab/psortb_commandline:1.0.2.
# Perl files from patches/ to fix known runtime bugs in psortb3.pl and the
# Bio::Tools::* modules. linux/amd64 forced (no arm64 image upstream).
# Local pipeline elaboration adds scripts/ + python3 (for post-processor).
# ──────────────────────────────────────────────────────────────────────────────
FROM --platform=linux/amd64 brinkmanlab/psortb_commandline:1.0.2

ARG PERL_BASE=/usr/local/lib/x86_64-linux-gnu/perl/5.22.1

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# ── Bake in patched Perl modules (first-party patches under patches/)
COPY patches/SCLBlast.pm ${PERL_BASE}/Bio/Tools/Run/SCLBlast.pm
COPY patches/SVMLoc.pm   ${PERL_BASE}/Bio/Tools/PSort/Module/SVMLoc.pm
COPY patches/ModuleI.pm  ${PERL_BASE}/Bio/Tools/PSort/ModuleI.pm
COPY patches/psortb3.pl  /usr/local/bin/psortb3_patched.pl

# ── Add modern python3 for local post-processor (xenial base ships 3.5 only)
RUN apt-get update && apt-get install -y --no-install-recommends \
        wget bzip2 ca-certificates bash \
 && wget -qO /tmp/miniforge.sh \
        https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh \
 && bash /tmp/miniforge.sh -b -p /opt/conda \
 && rm /tmp/miniforge.sh \
 && /opt/conda/bin/conda install -y -n base -c conda-forge python=3.11 \
 && /opt/conda/bin/conda clean -afy \
 && ln -sf /opt/conda/bin/python3 /usr/local/bin/python3 \
 && rm -rf /var/lib/apt/lists/*

# Local pipeline-standard layout
COPY entrypoint.sh /opt/psortb/entrypoint.sh
COPY scripts/      /opt/psortb/scripts/
COPY LICENSE.md    /opt/psortb/LICENSE.md
COPY VERSIONS      /opt/psortb/VERSIONS

RUN chmod a+x /usr/local/bin/psortb3_patched.pl \
 && chmod -R a+rX /opt/psortb \
 && find /opt/psortb -type f \( -name '*.sh' -o -name '*.py' \) -exec chmod a+x {} + \
 && ln -sf /opt/psortb/entrypoint.sh /usr/local/bin/run \
 && mkdir -p /input /output

LABEL org.opencontainers.image.title="psortb" \
      org.opencontainers.image.description="PSORTb v3 (brinkmanlab base + first-party Perl patches)" \
      org.opencontainers.image.source="https://github.com/sajalbhattarai/containers" \
      org.opencontainers.image.licenses="GPL-2.0-or-later"

ENTRYPOINT ["/usr/local/bin/run"]
