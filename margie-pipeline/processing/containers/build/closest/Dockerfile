# syntax=docker/dockerfile:1.7
# ──────────────────────────────────────────────────────────────────────────────
# closest — Rank the top-N closest organisms within the collection for each
# genome, based on pre-computed all-vs-all AAI and/or ANI matrices.
#
# No external database required; all scoring is against the user's own
# annotated collection (outputs of the 'aai' and 'ani' containers).
#
# Input:
#   /input/aai_matrix.tsv   Symmetric AAI matrix from the 'aai' container
#   /input/ani_matrix.tsv   Symmetric ANI matrix from the 'ani' container
#   (at least one of the two inputs is required)
#
# Output:
#   /output/closest/processed/closest_organisms.tsv
#       Per-genome top-N ranking: query_genome, rank, reference_genome,
#       aai, ani, composite_score
#
# Multi-arch: pure Python, no compiled binaries.
# See LICENSE.md for per-component license terms.
# ──────────────────────────────────────────────────────────────────────────────
FROM python:3.11-slim

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
        tini bash ca-certificates \
 && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir pandas

COPY entrypoint.sh /opt/closest/entrypoint.sh
COPY scripts/      /opt/closest/scripts/
COPY LICENSE.md    /opt/closest/LICENSE.md
COPY VERSIONS      /opt/closest/VERSIONS

RUN chmod -R a+rX /opt/closest \
 && find /opt/closest -type f \( -name '*.sh' -o -name '*.py' \) -exec chmod a+x {} + \
 && ln -sf /opt/closest/entrypoint.sh /usr/local/bin/run \
 && mkdir -p /input /output

RUN printf '{\n  "tool": "closest",\n  "base_image": "python:3.11-slim",\n  "build_date": "%s"\n}\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        > /etc/pipeline-build.json

LABEL org.opencontainers.image.title="closest" \
      org.opencontainers.image.description="Rank top-N closest organisms per genome from AAI + ANI matrices" \
      org.opencontainers.image.source="https://github.com/sajalbhattarai/margie-pipeline" \
      org.opencontainers.image.vendor="margie-annotation" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.version="1.0.0"

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/run"]
