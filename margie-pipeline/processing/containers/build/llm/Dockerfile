# syntax=docker/dockerfile:1.7
# ──────────────────────────────────────────────────────────────────────────────
# llm — LLM scoring stage for the margie-annotation pipeline (placeholder)
# Accepts labeled.tsv, writes scores.tsv with a PLACEHOLDER_SCORE column.
# Compatible with Docker (linux/amd64, linux/arm64) and Apptainer/Singularity.
# ──────────────────────────────────────────────────────────────────────────────
FROM python:3.11-slim

LABEL org.opencontainers.image.title="margie-scoring" \
      org.opencontainers.image.description="Scoring stage for the margie-annotation pipeline (placeholder)" \
      org.opencontainers.image.source="https://github.com/sajalbhattarai/containers"

RUN pip install --no-cache-dir pandas

COPY entrypoint.py /usr/local/bin/entrypoint.py
RUN chmod +x /usr/local/bin/entrypoint.py

ENTRYPOINT ["python3", "/usr/local/bin/entrypoint.py"]
