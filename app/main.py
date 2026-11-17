"""Tiny demo service: the platform around it is the point, not the app.

GET /health is the load balancer's liveness check. GET / reports where the
process runs, so a browser refresh shows which container answered:

    version   the release (the image tag)
    identity  uid 0 would mean root; ppid 1 means gunicorn is the container's PID 1
    os        the container's own OS (its whole os-release file)
    system    uname: `node` is which container answered, `release` the host's kernel
              (shared by all containers on a host), `machine` the CPU (aarch64 = ARM)
    python    the interpreter version

Environment variables are left out on purpose: they can hold secrets.
"""

import os
import platform

from flask import Flask, jsonify


def os_release() -> dict[str, str]:
    # Only Linux has an os-release file. https://docs.python.org/3/library/platform.html#platform.freedesktop_os_release
    try:
        return platform.freedesktop_os_release()
    except OSError:
        return {}


def create_app() -> Flask:
    flask_app = Flask(__name__)

    @flask_app.get("/health")
    def health():
        return jsonify(status="ok")

    @flask_app.get("/")
    def index():
        # Containers share the host's kernel, which is why `system.release` differs from `os`. https://docs.docker.com/get-started/docker-concepts/the-basics/what-is-a-container/
        return jsonify(
            version=os.environ.get("SERVICE_VERSION", "dev"),
            identity=dict(uid=os.getuid(), gid=os.getgid(), pid=os.getpid(), ppid=os.getppid()),
            os=os_release(),
            system=platform.uname()._asdict(),
            python=platform.python_version(),
        )

    return flask_app


application = create_app()
