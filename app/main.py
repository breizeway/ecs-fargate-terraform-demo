"""Tiny demo service: the platform around it is the point, not the app.

GET /health is the load balancer's liveness check. GET / reports where the
process runs, so a browser refresh shows which container answered:

    hostname  which container answered
    uid       0 would mean root; anything else is an unprivileged user
    machine   CPU architecture (aarch64 = ARM)
    distro    the container's own OS
    kernel    the host's kernel, which all containers on a host share
    version   the release (the image tag)
"""

import os
import platform
import socket

from flask import Flask, jsonify


def distro() -> str | None:
    # Only Linux has os-release (a Mac running outside Docker does not). https://docs.python.org/3/library/platform.html#platform.freedesktop_os_release
    try:
        return platform.freedesktop_os_release()["PRETTY_NAME"]
    except OSError:
        return None


def create_app() -> Flask:
    flask_app = Flask(__name__)

    # Cheap and dependency-free, so a database blip can't mark every container unhealthy. https://docs.aws.amazon.com/elasticloadbalancing/latest/application/target-group-health-checks.html
    @flask_app.get("/health")
    def health():
        return jsonify(status="ok")

    @flask_app.get("/")
    def index():
        # Containers share the host's kernel, which is why `kernel` differs from `distro`. https://docs.docker.com/get-started/docker-concepts/the-basics/what-is-a-container/
        return jsonify(
            hostname=socket.gethostname(),
            uid=os.getuid(),
            machine=platform.machine(),
            distro=distro(),
            kernel=platform.release(),
            version=os.environ.get("SERVICE_VERSION", "dev"),
        )

    return flask_app


application = create_app()
