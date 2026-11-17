import pytest

from app import main


@pytest.fixture
def client():
    flask_app = main.create_app()
    flask_app.config.update(TESTING=True)
    return flask_app.test_client()


def test_health_ok(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.get_json() == {"status": "ok"}


def test_index_reports_runtime_facts(client):
    data = client.get("/").get_json()
    assert {"version", "identity", "os", "system", "python"} == data.keys()
    assert isinstance(data["identity"]["uid"], int)
    assert {"node", "release", "machine"} <= data["system"].keys()


def test_index_survives_a_missing_os_release(client, monkeypatch):
    def missing():
        raise OSError

    monkeypatch.setattr(main.platform, "freedesktop_os_release", missing)
    assert client.get("/").get_json()["os"] == {}


def test_index_does_not_expose_the_environment(client, monkeypatch):
    monkeypatch.setenv("DB_PASSWORD", "hunter2")
    assert "hunter2" not in client.get("/").get_data(as_text=True)


def test_unknown_route_is_404(client):
    assert client.get("/nope").status_code == 404
