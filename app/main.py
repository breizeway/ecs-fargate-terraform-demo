"""Tiny demo service: the platform around it is the point, not the app.

GET /healthz is the load balancer's liveness check. GET / reports facts about
where the process is running, so a browser refresh shows which container answered.
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
    @flask_app.get("/healthz")
    def healthz():
        return jsonify(status="ok")

    @flask_app.get("/")
    def index():
        return jsonify(
            hostname=socket.gethostname(),  # which container answered
            uid=os.getuid(),  # not 0, so not root
            machine=platform.machine(),  # CPU architecture (aarch64 = ARM)
            distro=distro(),  # the container's OS
            kernel=platform.release(),  # the host's kernel: containers share it
            version=os.environ.get("SERVICE_VERSION", "dev"),
        )

    return flask_app


application = create_app()
