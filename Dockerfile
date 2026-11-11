# syntax=docker/dockerfile:1

ARG PYTHON_VERSION=3.14

# ---- builder: install dependencies into a virtualenv ------------------------
# Debian-based "slim" image rather than Alpine: most Python binary wheels target
# glibc, and musl (Alpine) often forces slow source builds.
FROM python:${PYTHON_VERSION}-slim AS builder

COPY --from=ghcr.io/astral-sh/uv:0.13.7 /uv /usr/local/bin/uv

ENV UV_PROJECT_ENVIRONMENT=/opt/venv \
    UV_PYTHON_DOWNLOADS=never \
    UV_LINK_MODE=copy \
    UV_NO_CACHE=1

WORKDIR /build

# Copy only the dependency manifests first so this layer stays cached until
# they change, not on every source edit.
COPY pyproject.toml uv.lock ./

# --locked fails the build if uv.lock is out of date with pyproject.toml.
RUN uv sync --locked --no-dev

ENV PATH="/opt/venv/bin:$PATH"

# ---- test: `docker build --target test .` fails if the tests fail -----------
FROM builder AS test

RUN uv sync --locked
COPY app ./app
COPY tests ./tests
RUN python -m pytest -q

# ---- runtime: the image that ships ------------------------------------------
FROM python:${PYTHON_VERSION}-slim AS runtime

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PATH="/opt/venv/bin:$PATH"

# Apply pending Debian security fixes (the base image can lag behind), then
# remove pip: nothing needs it at runtime, and it bundles libraries (urllib3,
# msgpack, ...) that vulnerability scanners report. Trade-off: `apt-get upgrade`
# makes builds less reproducible over time; pinning the base image by digest and
# rebuilding on a schedule is the stricter alternative.
RUN apt-get update \
 && apt-get upgrade -y --no-install-recommends \
 && rm -rf /var/lib/apt/lists/* \
 && python -m pip uninstall -y pip

# Run as an unprivileged user. Fixed numeric ids keep file ownership predictable
# and let orchestrators verify "non-root" without resolving names.
RUN groupadd --system --gid 10001 app \
 && useradd --system --uid 10001 --gid app --no-create-home \
            --shell /usr/sbin/nologin app

# Only the built virtualenv comes across: no uv, pip cache or build files.
COPY --from=builder /opt/venv /opt/venv

WORKDIR /srv
COPY --chown=app:app app ./app
COPY --chown=app:app gunicorn.conf.py .

USER 10001:10001
EXPOSE 8000

# Declared late so changing the version doesn't invalidate earlier layers.
ARG SERVICE_VERSION=dev
ENV SERVICE_VERSION=${SERVICE_VERSION}

# Used by `docker run`. Amazon ECS ignores this instruction: ECS health checks
# come from the task definition and the load balancer's target group.
# Python's standard library is used so the image doesn't need curl.
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/healthz', timeout=2)"]

# Exec form: gunicorn is PID 1 and receives SIGTERM directly. Shell form would
# run it under `/bin/sh -c`, which does not forward signals, so `docker stop`
# would wait out its timeout and then SIGKILL the process.
CMD ["gunicorn", "--config", "gunicorn.conf.py", "app.main:application"]
