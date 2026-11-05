#!/bin/sh
# Container entrypoint: apply migrations, then replace this shell with the API server.
#   RUN_MIGRATIONS=false   skip the migration step (e.g. when a separate release job runs it)
#   PORT                   listen port (default 8000)
#   WEB_CONCURRENCY        number of worker processes (read by uvicorn; default 1)
set -eu

if [ "${RUN_MIGRATIONS:-true}" = "true" ]; then
    echo "Applying database migrations..."
    alembic upgrade head
fi

echo "Starting API on port ${PORT:-8000}"
exec uvicorn app.main:create_app --factory \
    --host 0.0.0.0 --port "${PORT:-8000}" \
    --no-access-log --proxy-headers
