import pytest

from app import main


@pytest.fixture
def client():
    flask_app = main.create_app()
    flask_app.config.update(TESTING=True)
    return flask_app.test_client()


def test_healthz_ok(client):
    resp = client.get("/healthz")
    assert resp.status_code == 200
    assert resp.get_json() == {"status": "ok"}


def test_index_reports_runtime_facts(client):
    data = client.get("/").get_json()
    expected = {
        "hostname", "pid", "uid", "gid", "kernel", "machine",
        "distro", "python", "version", "cpu_count", "cgroup",
    }
    assert expected <= data.keys()
    assert isinstance(data["uid"], int)


def test_unknown_route_is_404(client):
    assert client.get("/nope").status_code == 404


def test_cgroup_limits_tolerate_missing_files(tmp_path, monkeypatch):
    # Outside a container (or on cgroup v1) the files may not exist.
    monkeypatch.setattr(main, "CGROUP_ROOT", tmp_path)
    assert main.cgroup_limits() == {"memory_max": None, "cpu_max": None}


def test_cgroup_limits_read_values(tmp_path, monkeypatch):
    (tmp_path / "memory.max").write_text("67108864\n")
    (tmp_path / "cpu.max").write_text("50000 100000\n")
    monkeypatch.setattr(main, "CGROUP_ROOT", tmp_path)
    assert main.cgroup_limits() == {"memory_max": "67108864", "cpu_max": "50000 100000"}


def test_distro_parses_pretty_name(tmp_path, monkeypatch):
    release = tmp_path / "os-release"
    release.write_text('ID=debian\nPRETTY_NAME="Debian GNU/Linux 13 (trixie)"\n')
    monkeypatch.setattr(main, "OS_RELEASE", release)
    assert main.distro() == "Debian GNU/Linux 13 (trixie)"
