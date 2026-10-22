"""Crime records along a route, and risk where the dataset has no records."""
from app.api.v1 import routes as routes_module
from app.deps import get_engine
from app.geo import densify, haversine_m
from app.services.recommend import Candidate, recommend
from app.services.risk import NEAR_ROUTE_M, PARTIAL_NOTE
from app.services.routing import RawRoute

# Through the busy centre (Cubbon Park -> MG Road).
BUSY = [[12.9763, 77.5929], [12.9757, 77.6070]]
# Far north-west corner of the service area, where the dataset has no records.
EMPTY = [[13.28, 77.37], [13.29, 77.38]]


def _line(a, b, n=40):
    return [(a[0] + (b[0] - a[0]) * i / n, a[1] + (b[1] - a[1]) * i / n) for i in range(n + 1)]


def test_route_crimes_are_real_records_inside_the_corridor(client):
    r = client.post("/api/v1/crimes/route", json={"geometry": BUSY, "limit": 500})
    assert r.status_code == 200
    crimes = r.json()["crimes"]
    assert crimes
    assert set(crimes[0]) == {"id", "type", "latitude", "longitude", "date", "area", "description"}
    assert len({c["id"] for c in crimes}) == len(crimes)
    path = densify([tuple(p) for p in BUSY])
    for c in crimes:
        nearest = min(haversine_m(c["latitude"], c["longitude"], lat, lon) for lat, lon in path)
        assert nearest <= NEAR_ROUTE_M + 1


def test_route_crimes_limit_spreads_along_the_route(client):
    full = client.post("/api/v1/crimes/route", json={"geometry": BUSY, "limit": 500}).json()["crimes"]
    assert len(full) > 4
    few = client.post("/api/v1/crimes/route", json={"geometry": BUSY, "limit": 4}).json()["crimes"]
    assert len(few) == 4
    order = [c["id"] for c in full]
    # Sampled evenly, not just the first four the path reaches.
    assert [order.index(c["id"]) for c in few] != [0, 1, 2, 3]


def test_route_crimes_with_no_records_is_empty_not_invented(client):
    r = client.post("/api/v1/crimes/route", json={"geometry": EMPTY})
    assert r.status_code == 200 and r.json()["crimes"] == []


def test_route_crimes_validation(client):
    outside = client.post("/api/v1/crimes/route", json={"geometry": [[28.6, 77.2], [28.7, 77.3]]})
    assert outside.status_code == 422 and isinstance(outside.json()["detail"], str)
    short = client.post("/api/v1/crimes/route", json={"geometry": [[12.97, 77.59]]})
    assert short.status_code == 422


def test_partial_coverage_is_disclosed_in_the_reason(client):
    engine = get_engine()
    # Mostly through the empty corner, briefly through the city.
    pts = _line((13.29, 77.36), (13.20, 77.36)) + _line((13.20, 77.36), (13.0, 77.55), 10)
    result = engine.score_path(pts)
    assert 0 < engine.coverage(pts) < 0.5
    assert result.level != "unknown"
    assert result.reason.endswith(PARTIAL_NOTE)


def test_busy_route_has_full_coverage_and_no_note(client):
    result = get_engine().score_path([tuple(p) for p in BUSY])
    assert result.level in ("low", "moderate", "high")
    assert PARTIAL_NOTE not in result.reason


def test_unknown_route_never_wins_on_risk():
    known = Candidate(id="route-a", duration_minutes=20, score=0.5)
    nodata = Candidate(id="route-b", duration_minutes=25, score=0.0, known=False)
    assert recommend([known, nodata], "lower_risk")[0] == "route-a"
    assert recommend([known, nodata], "balanced")[0] == "route-a"
    assert recommend([known, nodata], "fastest")[0] == "route-a"


def test_all_routes_unknown_falls_back_to_fastest_with_honest_reason():
    a = Candidate(id="route-a", duration_minutes=20, score=0.0, known=False)
    b = Candidate(id="route-b", duration_minutes=25, score=0.0, known=False)
    for pref in ("fastest", "balanced", "lower_risk"):
        route_id, reason = recommend([a, b], pref)
        assert route_id == "route-a"
        assert "not available" in reason


def test_preferences_still_pick_by_their_objective():
    fast_busy = Candidate(id="route-a", duration_minutes=20, score=0.9)
    slow_quiet = Candidate(id="route-b", duration_minutes=40, score=0.1)
    middle = Candidate(id="route-c", duration_minutes=22, score=0.3)
    cands = [fast_busy, slow_quiet, middle]
    assert recommend(cands, "fastest")[0] == "route-a"
    assert recommend(cands, "lower_risk")[0] == "route-b"
    assert recommend(cands, "balanced")[0] == "route-c"


def test_routes_endpoint_marks_no_data_route_unknown(client, monkeypatch):
    busy = RawRoute(1200, 9000, _line((12.9352, 77.6245), (13.0358, 77.5970)))
    empty = RawRoute(1300, 9500, _line((13.28, 77.37), (13.29, 77.38)))

    async def fake(start, dest):
        return [busy, empty]

    monkeypatch.setattr(routes_module, "get_routes", fake)
    body = {
        "start": {"latitude": 12.9352, "longitude": 77.6245},
        "destination": {"latitude": 13.0358, "longitude": 77.5970},
        "preference": "lower_risk",
    }
    j = client.post("/api/v1/routes", json=body).json()
    assert [r["risk"]["risk"] for r in j["routes"]][1] == "unknown"
    assert j["recommendation"]["route_id"] == "route-a"


def test_trip_leaving_bengaluru_gets_routes_but_no_risk_estimate(client, monkeypatch):
    # Koramangala -> Mysuru: routable, but the destination has no crime data.
    road = _line((12.9352, 77.6245), (12.2958, 76.6394))
    long_way = _line((12.9352, 77.6245), (12.6, 77.3)) + _line((12.6, 77.3), (12.2958, 76.6394))

    async def fake(start, dest):
        return [RawRoute(10800, 145000, road), RawRoute(11500, 160000, long_way)]

    monkeypatch.setattr(routes_module, "get_routes", fake)
    body = {
        "start": {"latitude": 12.9352, "longitude": 77.6245},
        "destination": {"latitude": 12.2958, "longitude": 76.6394},
        "preference": "lower_risk",
    }
    r = client.post("/api/v1/routes", json=body)
    assert r.status_code == 200
    j = r.json()
    assert j["risk_coverage"] == "none"
    assert all(rt["risk"]["score"] is None and rt["risk"]["risk"] == "unknown" for rt in j["routes"])
    # Bengaluru records are never reused to rate the Mysuru trip.
    assert "safe" not in j["recommendation"]["reason"].lower()
    assert j["recommendation"]["route_id"] == "route-a"


def test_crime_and_risk_endpoints_stay_bengaluru_only(client):
    delhi = [[28.61, 77.21], [28.63, 77.23]]
    assert client.post("/api/v1/risk/route", json={"geometry": delhi}).status_code == 422
    assert client.post("/api/v1/crimes/route", json={"geometry": delhi}).status_code == 422
    assert client.get("/api/v1/crimes/heatmap", params={"latitude": 28.61, "longitude": 77.21}).status_code == 422


def test_corridor_records_for_a_route_that_leaves_bengaluru_are_only_bengaluru_records(client):
    geometry = BUSY + [[12.2958, 76.6394]]
    r = client.post("/api/v1/crimes/route", json={"geometry": geometry, "limit": 500})
    assert r.status_code == 200
    crimes = r.json()["crimes"]
    assert crimes
    assert all(12.70 <= c["latitude"] <= 13.30 and 77.35 <= c["longitude"] <= 77.80 for c in crimes)
