"""Contract tests: response keys must match what lib/models/*.dart parses."""
import pytest

from app.api.v1 import routes as routes_module
from app.services import geocoding
from app.services.routing import RawRoute, RoutingError

CENTER = {"latitude": 12.9716, "longitude": 77.5946}


def test_health(client):
    body = client.get("/api/v1/health").json()
    assert body["status"] == "ok" and body["incidents"] > 1000


def test_crimes_contract(client):
    r = client.get("/api/v1/crimes", params={**CENTER, "radius_km": 2, "limit": 5})
    assert r.status_code == 200
    crimes = r.json()["crimes"]
    assert 0 < len(crimes) <= 5
    assert set(crimes[0]) == {"id", "type", "latitude", "longitude", "date", "area", "description"}


def test_heatmap_contract(client):
    pts = client.get("/api/v1/crimes/heatmap", params=CENTER).json()["points"]
    assert pts
    assert set(pts[0]) == {"latitude", "longitude", "exposure", "intensity"}
    assert {p["exposure"] for p in pts} <= {"low", "moderate", "high"}
    assert all(0 <= p["intensity"] <= 1 for p in pts)


def test_crimes_outside_bengaluru_is_422_with_string_detail(client):
    r = client.get("/api/v1/crimes", params={"latitude": 28.6, "longitude": 77.2})
    assert r.status_code == 422 and isinstance(r.json()["detail"], str)


def test_invalid_params_give_string_detail(client):
    r = client.get("/api/v1/crimes", params={"latitude": "x", "longitude": 77.5})
    assert r.status_code == 422 and isinstance(r.json()["detail"], str)


def test_search_local_results(client, monkeypatch):
    async def down(_):
        raise geocoding.httpx.ConnectError("offline")

    monkeypatch.setattr(geocoding, "_nominatim", down)
    geocoding._cache.clear()
    results = client.get("/api/v1/locations/search", params={"q": "koramangala"}).json()["results"]
    assert results and set(results[0]) == {"name", "address", "latitude", "longitude"}
    assert not geocoding._cache  # degraded answers are not cached


def _fake_routes(monkeypatch, routes):
    async def fake(start, dest):
        return routes

    monkeypatch.setattr(routes_module, "get_routes", fake)


def _line(a, b, n=40):
    return [(a[0] + (b[0] - a[0]) * i / n, a[1] + (b[1] - a[1]) * i / n) for i in range(n + 1)]


BODY = {
    "start": {"latitude": 12.9352, "longitude": 77.6245},
    "destination": {"latitude": 13.0358, "longitude": 77.5970},
    "preference": "balanced",
}


def test_routes_contract_and_recommendation(client, monkeypatch):
    # Through the Cubbon Park cluster vs a path far out west with few incidents.
    busy = RawRoute(1200, 9000, _line((12.9352, 77.6245), (13.0358, 77.5970)))
    quiet_pts = _line((12.9352, 77.6245), (12.99, 77.52)) + _line((12.99, 77.52), (13.0358, 77.5970))
    quiet = RawRoute(1500, 11000, quiet_pts)
    _fake_routes(monkeypatch, [busy, quiet])

    for pref in ("fastest", "balanced", "lower_risk"):
        r = client.post("/api/v1/routes", json={**BODY, "preference": pref})
        assert r.status_code == 200
        j = r.json()
        assert set(j) == {"routes", "recommendation"}
        route = j["routes"][0]
        assert {"id", "name", "duration_minutes", "distance_km", "geometry", "risk", "segments"} <= set(route)
        assert set(route["risk"]) == {"risk", "score", "reason"}
        assert route["risk"]["risk"] in ("low", "moderate", "high")
        assert "safe" not in route["risk"]["reason"].lower().replace("estimated", "")
        assert j["recommendation"]["route_id"] in {x["id"] for x in j["routes"]}

    fastest = client.post("/api/v1/routes", json={**BODY, "preference": "fastest"}).json()
    assert fastest["recommendation"]["route_id"] == "route-a"


def test_risk_ordering_dense_vs_empty_area(client):
    dense = client.post("/api/v1/risk/route", json={"geometry": [[12.9763, 77.5929], [12.9800, 77.5990]]}).json()
    empty = client.post("/api/v1/risk/route", json={"geometry": [[13.28, 77.37], [13.29, 77.38]]}).json()
    assert dense["risk"]["score"] > empty["risk"]["score"]
    assert empty["risk"]["risk"] == "low"


def test_routes_outside_area_and_same_point(client):
    far = {**BODY, "start": {"latitude": 28.6, "longitude": 77.2}}
    assert client.post("/api/v1/routes", json=far).status_code == 422
    same = {**BODY, "destination": BODY["start"]}
    assert client.post("/api/v1/routes", json=same).status_code == 422


@pytest.mark.parametrize("status", [502, 504, 404])
def test_routing_failure_is_passed_on(client, monkeypatch, status):
    async def boom(start, dest):
        raise RoutingError("routing problem", status)

    monkeypatch.setattr(routes_module, "get_routes", boom)
    r = client.post("/api/v1/routes", json=BODY)
    assert r.status_code == status and r.json()["detail"] == "routing problem"


def test_bad_preference_rejected(client):
    assert client.post("/api/v1/routes", json={**BODY, "preference": "scenic"}).status_code == 422
