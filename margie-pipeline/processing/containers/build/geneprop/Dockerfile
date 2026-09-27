# syntax=docker/dockerfile:1.7
# ──────────────────────────────────────────────────────────────────────────────
# geneprop — EBI Genome Properties evaluator (pure-python over flatfiles)
# Source:  https://github.com/ebi-pf-team/genome-properties  (mounted at /db)
# Build recipe: condaforge/miniforge3
# base + conda install pandas. Local pipeline elaboration adds scripts/.
# ──────────────────────────────────────────────────────────────────────────────
FROM condaforge/miniforge3:latest

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PYTHONDONTWRITEBYTECODE=1

RUN conda install -y -c conda-forge -c bioconda python=3.11 pandas \
 && conda clean -afy

COPY entrypoint.sh /opt/geneprop/entrypoint.sh
COPY scripts/      /opt/geneprop/scripts/
COPY LICENSE.md    /opt/geneprop/LICENSE.md
COPY VERSIONS      /opt/geneprop/VERSIONS

RUN chmod -R a+rX /opt/geneprop \
 && find /opt/geneprop -type f \( -name '*.sh' -o -name '*.py' \) -exec chmod a+x {} + \
 && ln -sf /opt/geneprop/entrypoint.sh /usr/local/bin/run \
 && mkdir -p /input /output /db

LABEL org.opencontainers.image.title="geneprop" \
      org.opencontainers.image.description="EBI Genome Properties evaluator (upstream miniforge3 base)" \
      org.opencontainers.image.source="https://github.com/sajalbhattarai/containers" \
      org.opencontainers.image.licenses="Apache-2.0"

ENTRYPOINT ["/usr/local/bin/run"]
