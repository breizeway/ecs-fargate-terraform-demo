import pytest

from app import main


@pytest.fixture
def client():
    flask_app = main.create_app()
    flask_app.config.update(TESTING=True)
    return flask_app.test_client()


@pytest.mark.parametrize("path", ["/health", "/healthz"])
def test_health_ok(client, path):
    resp = client.get(path)
    assert resp.status_code == 200
    assert resp.get_json() == {"status": "ok"}


def test_index_reports_runtime_facts(client):
    data = client.get("/").get_json()
    assert {"hostname", "uid", "machine", "distro", "kernel", "version"} == data.keys()
    assert isinstance(data["uid"], int)


def test_unknown_route_is_404(client):
    assert client.get("/nope").status_code == 404
