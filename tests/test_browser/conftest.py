# tests/test_browser/conftest.py
import socket
import subprocess
import time

import pytest


def _find_free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("", 0))
        return s.getsockname()[1]


def _db_reachable() -> bool:
    try:
        with socket.create_connection(("localhost", 1433), timeout=2):
            return True
    except OSError:
        return False


@pytest.fixture(scope="session")
def live_server():
    """Start a real uvicorn server subprocess and yield its base URL."""
    port = _find_free_port()
    proc = subprocess.Popen(
        [
            "uv", "run", "uvicorn", "app.main:app",
            "--host", "127.0.0.1",
            "--port", str(port),
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    # Wait up to 15 seconds for the server to accept connections
    for _ in range(30):
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.5):
                break
        except OSError:
            time.sleep(0.5)
    else:
        proc.terminate()
        proc.wait(timeout=5)
        pytest.fail("live_server did not start within 15 seconds")

    yield f"http://127.0.0.1:{port}"

    proc.terminate()
    proc.wait(timeout=5)


def pytest_collection_modifyitems(items: list) -> None:
    """Skip requires_db tests when SQL Server is not reachable."""
    if _db_reachable():
        return
    skip = pytest.mark.skip(
        reason="SQL Server not reachable at localhost:1433 — run `make db-start`"
    )
    for item in items:
        if item.get_closest_marker("requires_db"):
            item.add_marker(skip)
