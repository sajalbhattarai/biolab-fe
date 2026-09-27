# syntax=docker/dockerfile:1.7
# gtdbtk — GTDB-Tk taxonomy classification (independent container)

FROM mambaorg/micromamba:1.5.8

ARG GTDBTK_VERSION=2.4.0

USER root
SHELL ["/bin/bash", "-lc"]

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    MAMBA_DOCKERFILE_ACTIVATE=1

RUN apt-get update && apt-get install -y --no-install-recommends \
        bash tini ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN micromamba create -y -n gtdbtk \
        -c conda-forge -c bioconda \
        "python=3.11" \
        "gtdbtk=${GTDBTK_VERSION}" \
        "matplotlib" \
        "biopython" \
    && micromamba clean --all --yes

COPY entrypoint.sh       /opt/gtdbtk/entrypoint.sh
COPY scripts/            /opt/gtdbtk/scripts/
COPY patches/markers.py  /opt/gtdbtk/patches/markers.py
COPY LICENSE.md          /opt/gtdbtk/LICENSE.md
COPY VERSIONS            /opt/gtdbtk/VERSIONS

RUN set -eux; \
    GTDBTK_SITE=/opt/conda/envs/gtdbtk/lib/python3.11/site-packages/gtdbtk; \
    # Patch bac_ar_diff unbound-variable bug (v2.7.0, triggered by --place_species + all-ANI collections)
    sed -i 's/^        if not all_classified_ani and not all_failed_prodigal:/        bac_ar_diff = {}\n        if not all_classified_ani and not all_failed_prodigal:/' \
        "$GTDBTK_SITE/classify.py"; \
    # Apply fixed markers.py (genome_domain fails when align_dir is absent)
    cp /opt/gtdbtk/patches/markers.py "$GTDBTK_SITE/markers.py"; \
    chmod -R a+rX /opt/gtdbtk \
    && find /opt/gtdbtk -type f \( -name '*.sh' -o -name '*.py' \) -exec chmod a+x {} + \
    && ln -sf /opt/gtdbtk/entrypoint.sh /usr/local/bin/run \
    && mkdir -p /input /output /db

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/run"]
