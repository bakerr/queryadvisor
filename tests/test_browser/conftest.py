# tests/test_browser/conftest.py
import os
import socket
import subprocess
import time
from pathlib import Path

import pytest

_REPO_ROOT = Path(__file__).parent.parent.parent


def _load_dotenv() -> dict[str, str]:
    """Load key=value pairs from .env at repo root, ignoring comments and blanks.

    Strips matching surrounding single or double quotes from values.
    Does not handle escaped quotes inside values (e.g. "it\\'s" stays as-is).
    """
    env: dict[str, str] = {}
    dotenv = _REPO_ROOT / ".env"
    try:
        for line in dotenv.read_text().splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" in line:
                key, _, value = line.partition("=")
                value = value.strip()
                if len(value) >= 2 and value[0] == value[-1] and value[0] in ('"', "'"):
                    value = value[1:-1]
                env[key.strip()] = value
    except FileNotFoundError:
        pass
    return env


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
    env = {**os.environ, **_load_dotenv()}
    proc = subprocess.Popen(
        [
            "uv", "run", "uvicorn", "app.main:app",
            "--host", "127.0.0.1",
            "--port", str(port),
        ],
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    # Wait up to 15 seconds for the server to accept connections
    for _ in range(30):
        try:
            with socket.create_connection(("127.0.0.1", port)):
                break
        except OSError:
            time.sleep(0.5)
    else:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
        pytest.fail("live_server did not start within 15 seconds")

    yield f"http://127.0.0.1:{port}"

    proc.terminate()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()


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
