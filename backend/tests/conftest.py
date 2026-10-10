import warnings

import pytest
from fastapi.testclient import TestClient

from app.main import app

warnings.filterwarnings("ignore")


@pytest.fixture(scope="session")
def client():
    with TestClient(app) as c:
        yield c
