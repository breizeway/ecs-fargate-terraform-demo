"""gunicorn settings.

Every value can be overridden with an environment variable, so the same
configuration works locally and in a container with a different size.
"""

import os

bind = f"0.0.0.0:{os.environ.get('PORT', '8000')}"

# Set explicitly: the common "2 * cpu_count() + 1" formula reads the host's CPU
# count rather than the container's CPU limit, which over-provisions small tasks.
workers = int(os.environ.get("WEB_CONCURRENCY", "2"))
threads = int(os.environ.get("GUNICORN_THREADS", "4"))

# Keep worker heartbeat files in memory where possible (Linux). macOS has no
# /dev/shm, so fall back to gunicorn's default temporary directory there.
worker_tmp_dir = "/dev/shm" if os.path.isdir("/dev/shm") else None

# Finish in-flight requests on SIGTERM, but stay below the platform's stop
# timeout (ECS default: 30s) so the process exits before it is killed.
graceful_timeout = 20
timeout = 30

# Log to stdout/stderr and let the platform collect the output.
accesslog = "-"
errorlog = "-"
