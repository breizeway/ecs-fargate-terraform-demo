"""Tiny demo service.

The point of this project is the platform around the app (image build, IaC,
deployment), not the app itself. The index route reports facts about the
environment the process is running in, so the container/Linux behaviour
is visible from a browser or curl.
"""

import os
import platform
import socket
from pathlib import Path

from flask import Flask, jsonify

CGROUP_ROOT = Path("/sys/fs/cgroup")
OS_RELEASE = Path("/etc/os-release")


def _read(path: Path) -> str | None:
    try:
        return path.read_text().strip()
    except OSError:
        return None


def distro() -> str | None:
    """PRETTY_NAME from /etc/os-release, e.g. 'Debian GNU/Linux 13 (trixie)'."""
    for line in (_read(OS_RELEASE) or "").splitlines():
        if line.startswith("PRETTY_NAME="):
            return line.split("=", 1)[1].strip('"')
    return None


def cgroup_limits() -> dict[str, str | None]:
    """Resource limits enforced by the kernel (cgroup v2).

    These can differ from what os.cpu_count() or /proc/meminfo report, because
    those show the host, not the container's limits.
    """
    return {
        "memory_max": _read(CGROUP_ROOT / "memory.max"),
        "cpu_max": _read(CGROUP_ROOT / "cpu.max"),
    }


def create_app() -> Flask:
    flask_app = Flask(__name__)

    @flask_app.get("/healthz")
    def healthz():
        return jsonify(status="ok")

    @flask_app.get("/")
    def index():
        return jsonify(
            hostname=socket.gethostname(),
            pid=os.getpid(),
            uid=os.getuid(),
            gid=os.getgid(),
            kernel=platform.release(),
            machine=platform.machine(),
            distro=distro(),
            python=platform.python_version(),
            version=os.environ.get("SERVICE_VERSION", "dev"),
            cpu_count=os.cpu_count(),
            cgroup=cgroup_limits(),
        )

    return flask_app


application = create_app()
