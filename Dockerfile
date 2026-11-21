# Official Python image (slim variant keeps the image small)
FROM python:3.12-slim

LABEL org.opencontainers.image.title="dice-devops-finalproject-server" \
      org.opencontainers.image.description="Generates a 1KB random file and sends it with its SHA-256 checksum"

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    SERVER_PORT=5000 \
    DATA_DIR=/serverdata

# Packages needed by the app: the app itself only uses the Python standard library,
# tini is installed as a minimal init so signals (docker stop) are handled cleanly.
RUN apt-get update \
    && apt-get install -y --no-install-recommends tini \
    && rm -rf /var/lib/apt/lists/*

# Run as a non-root user; pre-create the data dir so the named volume
# inherits the correct ownership on first mount.
RUN useradd --create-home --uid 10001 appuser \
    && mkdir -p /serverdata \
    && chown appuser:appuser /serverdata

WORKDIR /app
COPY app/ /app/

USER appuser

VOLUME ["/serverdata"]
EXPOSE 5000

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD ["python", "/app/healthcheck.py"]

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["python", "/app/server.py"]
