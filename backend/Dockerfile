# syntax=docker/dockerfile:1.7
# Production image for the Gully Umpire API.
#   docker build -t gully-umpire-api ./backend
#   docker run --env-file backend/.env -p 8000:8000 gully-umpire-api
# Secrets are NEVER baked in: configuration comes from environment variables at run time.

# ---- build stage: resolve dependencies into a virtualenv ---------------------------------------
FROM python:3.13-slim AS builder

ENV PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

WORKDIR /build
COPY requirements.txt ./
RUN pip install -r requirements.txt

# ---- runtime stage ------------------------------------------------------------------------------
FROM python:3.13-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH" \
    PORT=8000

# Unprivileged user; the image has no shell login and no write access to the code.
RUN groupadd --system --gid 10001 app \
 && useradd --system --uid 10001 --gid app --home-dir /app --shell /usr/sbin/nologin app

WORKDIR /app
COPY --from=builder /opt/venv /opt/venv
COPY alembic.ini ./
COPY alembic ./alembic
COPY app ./app
COPY scripts/entrypoint.sh ./scripts/entrypoint.sh
RUN chmod 0555 scripts/entrypoint.sh

USER app
EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD python -c "import os, urllib.request as u; u.urlopen('http://127.0.0.1:%s/health' % os.environ.get('PORT', '8000'), timeout=3)" || exit 1

ENTRYPOINT ["./scripts/entrypoint.sh"]
