"""gunicorn settings. Environment variables override the defaults."""

import os

bind = f"0.0.0.0:{os.environ.get('PORT', '8000')}"

# Fixed count: cpu_count() reports the host's CPUs, not the container's limit. https://gunicorn.org/design/
workers = int(os.environ.get("WEB_CONCURRENCY", "2"))
threads = int(os.environ.get("GUNICORN_THREADS", "4"))

# Heartbeat files need a writable in-memory dir (ECS root filesystem is read-only; macOS has no /dev/shm). https://gunicorn.org/faq/
worker_tmp_dir = "/dev/shm" if os.path.isdir("/dev/shm") else None

# Finish in-flight requests on SIGTERM and exit before ECS's default 30 s stop timeout sends SIGKILL. https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definition_parameters.html
graceful_timeout = 20
timeout = 30

# '-' logs to stdout/stderr instead of files, so the platform can collect the output. https://gunicorn.org/reference/settings/#accesslog
accesslog = "-"
errorlog = "-"
