# syntax=docker/dockerfile:1

# Debian slim, not Alpine: most Python wheels target glibc, and musl forces slow source builds. https://pythonspeed.com/articles/alpine-docker-python/
FROM python:3.14-slim AS builder

COPY --from=ghcr.io/astral-sh/uv:0.13.7 /uv /usr/local/bin/uv

ENV UV_PROJECT_ENVIRONMENT=/opt/venv \
    UV_PYTHON_DOWNLOADS=never

WORKDIR /build

# Manifests first, so this layer is reused until the dependencies change. https://docs.docker.com/build/cache/
COPY pyproject.toml uv.lock ./

# --locked fails the build if uv.lock is stale, so every build installs the same versions. https://docs.astral.sh/uv/concepts/projects/sync/
RUN uv sync --locked --no-dev

ENV PATH="/opt/venv/bin:$PATH"

# A separate stage runs the tests, so `docker build --target test .` fails when they fail. https://docs.docker.com/build/building/multi-stage/
FROM builder AS test

RUN uv sync --locked
COPY app ./app
COPY tests ./tests
RUN python -m pytest -q

FROM python:3.14-slim AS runtime

ENV PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH"

# Patch lagging OS packages and drop pip, whose bundled libraries trip vulnerability scanners. https://docs.docker.com/build/building/best-practices/
RUN apt-get update \
 && apt-get upgrade -y --no-install-recommends \
 && rm -rf /var/lib/apt/lists/* \
 && python -m pip uninstall -y pip

# Fixed numeric ids let ECS and scanners verify "non-root" without resolving names. https://docs.docker.com/build/building/best-practices/
RUN groupadd --system --gid 10001 app \
 && useradd --system --uid 10001 --gid app --no-create-home \
            --shell /usr/sbin/nologin app

COPY --from=builder /opt/venv /opt/venv

WORKDIR /srv
COPY --chown=app:app app ./app
COPY --chown=app:app gunicorn.conf.py .

USER 10001:10001

# Declared last so a new version doesn't invalidate the layers above. https://docs.docker.com/build/cache/
ARG SERVICE_VERSION=dev
ENV SERVICE_VERSION=${SERVICE_VERSION}

# Exec form makes gunicorn PID 1, so it receives SIGTERM; shell form would swallow it. https://docs.docker.com/reference/dockerfile/
CMD ["gunicorn", "--config", "gunicorn.conf.py", "app.main:application"]
