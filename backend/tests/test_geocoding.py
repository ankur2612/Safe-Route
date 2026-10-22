"""Location search across India. Photon is mocked so these tests never need the network."""
import os

import httpx
import pytest

from app.config import BBOX, GEOCODE_BBOX
from app.geo import in_bbox
from app.services import geocoding

REAL_ASYNC_CLIENT = httpx.AsyncClient


def _feature(name, lat, lon, countrycode="IN", **props):
    return {
        "type": "Feature",
        "properties": {
            "name": name,
            "osm_type": "N",
            "osm_id": abs(hash((name, lat, lon))) % 10**9,
            "osm_key": "place",
            "osm_value": "suburb",
            "countrycode": countrycode,
            **props,
        },
        "geometry": {"type": "Point", "coordinates": [lon, lat]},
    }


KORAMANGALA = _feature(
    "Koramangala", 12.9352, 77.6245, district="Koramangala", county="Bangalore South",
    city="Bengaluru", state="Karnataka", postcode="560034",
)


class FakePhoton:
    def __init__(self):
        self.requests: list[httpx.Request] = []
        self.respond = lambda request: httpx.Response(200, json={"features": [KORAMANGALA]})

    def __call__(self, request):
        self.requests.append(request)
        return self.respond(request)


@pytest.fixture
def photon(monkeypatch):
    """Serves Photon from ``FakePhoton.respond`` and records the requests."""
    fake = FakePhoton()

    def client(**kwargs):
        return REAL_ASYNC_CLIENT(transport=httpx.MockTransport(fake), **kwargs)

    monkeypatch.setattr(geocoding.httpx, "AsyncClient", client)
    monkeypatch.setattr(geocoding, "_backoff_until", 0.0)
    geocoding._cache.clear()
    return fake


def _search(client, q, **params):
    return client.get("/api/v1/locations/search", params={"q": q, **params})


def _answer(photon, *features):
    photon.respond = lambda request: httpx.Response(200, json={"features": list(features)})


# --- request shape -----------------------------------------------------------


def test_partial_query_searches_all_of_india_with_bengaluru_bias(client, photon):
    r = _search(client, "kora")
    assert r.status_code == 200
    params = photon.requests[0].url.params
    assert params["q"] == "kora"
    # India-wide box, not the Bengaluru crime-data box.
    expected = ",".join(str(GEOCODE_BBOX[k]) for k in ("min_lon", "min_lat", "max_lon", "max_lat"))
    assert params["bbox"] == expected
    assert (float(params["lat"]), float(params["lon"])) == (12.9716, 77.5946)


def test_callers_position_biases_the_ranking(client, photon):
    _search(client, "bandra", latitude=19.06, longitude=72.84)
    params = photon.requests[0].url.params
    assert (float(params["lat"]), float(params["lon"])) == (19.06, 72.84)


def test_multiword_query_is_normalised_and_cached(client, photon):
    _search(client, "  Connaught   PLACE ")
    _search(client, "connaught place")
    assert len(photon.requests) == 1
    assert photon.requests[0].url.params["q"] == "connaught place"


def test_cache_is_per_bias_area(client, photon):
    _search(client, "mg road")
    _search(client, "mg road", latitude=19.06, longitude=72.84)
    assert len(photon.requests) == 2


# --- response shape ----------------------------------------------------------


def test_result_has_name_address_coordinates_id_category_and_coverage(client, photon):
    body = _search(client, "koramangala").json()
    place = body["results"][0]
    assert body["degraded"] is False
    assert place["name"] == "Koramangala"
    assert place["address"] == "Bengaluru, Bangalore South, Karnataka 560034"
    assert place["locality"] == "Koramangala"
    assert place["category"] == "suburb"
    assert place["place_id"].startswith("osm:N")
    assert place["crime_data_available"] is True


@pytest.mark.parametrize(
    "name, lat, lon, state",
    [
        ("Baga", 15.5553, 73.7517, "Goa"),
        ("Connaught Place", 28.6315, 77.2167, "Delhi"),
        ("Bandra West", 19.0596, 72.8295, "Maharashtra"),
        ("HITEC City", 17.4504, 78.3808, "Telangana"),
        ("Salt Lake", 22.5800, 88.4155, "West Bengal"),
        ("T. Nagar", 13.0418, 80.2341, "Tamil Nadu"),
    ],
)
def test_places_in_other_cities_are_returned_without_crime_coverage(client, photon, name, lat, lon, state):
    _answer(photon, _feature(name, lat, lon, state=state))
    place = _search(client, name[:4]).json()["results"][0]
    assert place["name"] == name
    assert (place["latitude"], place["longitude"]) == (lat, lon)
    assert state in place["address"]
    assert place["crime_data_available"] is False


BENGALURU = [
    ("Indiranagar", 12.9784, 77.6408),
    ("Koramangala", 12.9352, 77.6245),
    ("Bagalur Cross", 13.1373, 77.6697),
    ("Hunasamaranahalli", 13.1453, 77.6201),
    ("Whitefield", 12.9698, 77.7500),
    ("Electronic City", 12.8452, 77.6602),
    ("MG Road", 12.9757, 77.6070),
    ("Jayanagar", 12.9279, 77.5937),
]


@pytest.mark.parametrize("name, lat, lon", BENGALURU)
def test_bengaluru_localities_come_from_the_geocoder(client, photon, name, lat, lon):
    _answer(photon, _feature(name, lat, lon, city="Bengaluru", state="Karnataka"))
    body = _search(client, f"{name[: max(3, len(name) // 2)]} bengaluru").json()
    assert body["degraded"] is False
    place = body["results"][0]
    assert place["name"] == name
    assert in_bbox(place["latitude"], place["longitude"], BBOX)
    assert place["crime_data_available"] is True


def test_drops_foreign_malformed_and_unusable_results(client, photon):
    _answer(
        photon,
        _feature("Baga", 15.5553, 73.7517, state="Goa"),
        # Inside the India box but another country.
        _feature("Bagan", 21.17, 94.86, countrycode="MM"),
        _feature("Lahore", 31.55, 74.34, countrycode="PK"),
        # Outside the box entirely.
        _feature("Bagamoyo", -6.44, 38.90),
        {"type": "Feature", "properties": {"name": "No geometry", "countrycode": "IN"}},
        {"type": "Feature", "properties": {"name": "Bad", "countrycode": "IN"}, "geometry": {"coordinates": ["x", "y"]}},
        _feature("", 15.55, 73.75),
        _feature("Metro (proposed)", 15.56, 73.75, osm_value="proposed"),
        "not a feature",
    )
    names = [p["name"] for p in _search(client, "baga").json()["results"]]
    assert names == ["Baga"]


def test_duplicate_results_are_merged_but_distinct_places_kept(client, photon):
    _answer(
        photon,
        # Village point and its boundary centre, 2.6 km apart, same locality.
        _feature("Bagaluru", 13.1332, 77.6687, osm_value="village", county="Yelahanka taluku"),
        _feature("Bagaluru", 13.1114, 77.6609, osm_value="administrative", county="Yelahanka taluku"),
        # One road through different neighbourhoods: distinct choices.
        _feature("Sarjapur Road", 12.9242, 77.6289, district="Kormangala West"),
        _feature("Sarjapur Road", 12.9204, 77.6654, district="Kasavanahalli"),
        # Same name in two cities.
        _feature("MG Road", 12.9757, 77.6070, city="Bengaluru"),
        _feature("MG Road", 18.5196, 73.8762, city="Pune"),
    )
    names = [p["name"] for p in _search(client, "bagalur").json()["results"]]
    assert names.count("Bagaluru") == 1
    assert names.count("Sarjapur Road") == 2
    assert names.count("MG Road") == 2


def test_no_match_is_an_empty_list(client, photon):
    _answer(photon)
    r = _search(client, "zzqxv")
    assert r.status_code == 200
    assert r.json() == {"results": [], "degraded": False}


# --- invalid input -----------------------------------------------------------


@pytest.mark.parametrize("q", ["", "k", "   ", " k "])
def test_empty_or_too_short_query_is_rejected(client, photon, q):
    r = _search(client, q)
    assert r.status_code == 422 and isinstance(r.json()["detail"], str)
    assert not photon.requests


def test_overlong_query_and_half_a_position_are_rejected(client, photon):
    assert _search(client, "a" * 101).status_code == 422
    assert _search(client, "baga", latitude=15.5).status_code == 422
    assert _search(client, "baga", latitude=95, longitude=73).status_code == 422
    assert not photon.requests


# --- provider failures -------------------------------------------------------


@pytest.mark.parametrize(
    "response",
    [
        httpx.Response(500, text="error"),
        httpx.Response(200, text="<html>not json</html>"),
        httpx.Response(200, json={"unexpected": True}),
    ],
)
def test_provider_failure_without_fallback_match_is_503_not_empty(client, photon, response):
    photon.respond = lambda request: response
    r = _search(client, "bandra")
    assert r.status_code == 503
    assert "temporarily unavailable" in r.json()["detail"]
    assert not geocoding._cache


def test_provider_timeout_is_503(client, photon):
    def timeout(request):
        raise httpx.ReadTimeout("slow", request=request)

    photon.respond = timeout
    assert _search(client, "bandra").status_code == 503


def test_rate_limit_is_429_and_pauses_requests(client, photon):
    photon.respond = lambda request: httpx.Response(429, text="Too many requests")
    first = _search(client, "bandra")
    assert first.status_code == 429 and "Too many searches" in first.json()["detail"]

    # While backing off, Photon is not called again.
    second = _search(client, "salt lake")
    assert second.status_code == 429
    assert len(photon.requests) == 1


def test_provider_failure_with_local_match_is_labelled_degraded(client, photon):
    photon.respond = lambda request: httpx.Response(502, text="bad gateway")
    body = _search(client, "kora").json()
    assert body["degraded"] is True
    assert body["results"][0]["name"] == "Koramangala"
    assert not geocoding._cache


# --- local fallback matching ---------------------------------------------------


@pytest.mark.parametrize(
    "query, expected",
    [
        ("kora", "Koramangala"),
        ("korma", "Koramangala"),
        ("kormangala", "Koramangala"),
        ("hsr", "HSR Layout"),
        ("btm lay", "BTM Layout"),
        ("marathalli", "Marathahalli"),
        ("YELAHANKA", "Yelahanka"),
    ],
)
def test_local_fallback_matches_partial_and_misspelt_names(query, expected):
    assert expected in [p.name for p in geocoding.search_local(query)]


def test_local_fallback_does_not_match_unrelated_short_input():
    assert geocoding.search_local("qz") == []


# --- live provider check (opt-in) --------------------------------------------

LIVE_QUERIES = [
    ("indiranagar bengaluru", "Indiranagar"),
    ("koramangala", "Koramangala"),
    ("bagalur cross", "Bagalur Cross"),
    ("hunasamaranahalli", "Hunasamaranahalli"),
    ("hunsmaranahalli", "Hunasamaranahalli"),
    ("whitefield", "Whitefield"),
    ("electronic city", "Electronic City"),
    ("mg road bengaluru", "MG Road"),
    ("jayanagar", "Jayanagar"),
    ("baga goa", "Baga"),
    ("connaught place", "Connaught Place"),
    ("bandra", "Bandra"),
    ("hitec city", "HITEC City"),
    ("salt lake kolkata", "Salt Lake"),
]


@pytest.mark.skipif(os.getenv("LIVE_GEOCODER") != "1", reason="live provider check is opt-in")
@pytest.mark.parametrize("query, expected", LIVE_QUERIES)
def test_live_photon_finds_sample_places(query, expected):
    import asyncio

    geocoding._cache.clear()
    geocoding._backoff_until = 0.0
    result = asyncio.run(geocoding.search(query))
    assert not result.degraded
    names = [p.name.lower() for p in result.places]
    assert any(expected.lower() in n for n in names), names


# --- curated landmarks for ambiguous short prefixes --------------------------


INDRI = _feature("Indri", 29.8921, 77.0910, state="Haryana", postcode="132041")


def test_spelling_variant_of_a_landmark_is_included_after_exact_matches(client, photon):
    # "indr" is how many people start "Indranagar"; OSM's prefix matches stay first.
    _answer(photon, INDRI, _feature("Indraprastha Invictus", 12.9662, 77.6046, city="Bengaluru"))
    results = _search(client, "indr").json()["results"]
    names = [p["name"] for p in results]
    assert names[:2] == ["Indri", "Indraprastha Invictus"]
    assert names[-1] == "Indiranagar"
    assert (results[-1]["latitude"], results[-1]["longitude"]) == (12.9784, 77.6408)


def test_close_spelling_landmark_survives_a_full_provider_page(client, photon):
    _answer(photon, *[_feature(f"Indra {i}", 20 + i, 78.0) for i in range(12)])
    names = [p["name"] for p in _search(client, "indr").json()["results"]]
    assert len(names) == geocoding.LIMIT and names[-1] == "Indiranagar"


def test_prefix_landmark_leads(client, photon):
    _answer(photon, INDRI)
    assert _search(client, "indira").json()["results"][0]["name"] == "Indiranagar"


def test_landmark_known_by_another_name_in_osm_is_found(client, photon):
    _answer(photon, _feature("Majestic Fortune", 12.8941, 77.5754, city="Bengaluru"))
    first = _search(client, "majestic").json()["results"][0]
    assert first["name"] == "Majestic (KSR Bengaluru City Junction)"
    assert (first["latitude"], first["longitude"]) == (12.9778, 77.5724)
    assert first["crime_data_available"] is True


def test_provider_entry_replaces_its_landmark_duplicate(client, photon):
    airport = _feature(
        "Kempegowda International Airport", 13.1976, 77.7075, osm_value="aerodrome",
        county="Devanahalli taluku", state="Karnataka",
    )
    _answer(photon, airport)
    results = _search(client, "kempegowda international airport").json()["results"]
    assert [p["name"] for p in results].count("Kempegowda International Airport") == 1
    assert results[0]["place_id"].startswith("osm:")  # the richer provider entry
    assert results[0]["category"] == "aerodrome"


def test_landmarks_do_not_lead_searches_centred_elsewhere(client, photon):
    _answer(photon, _feature("MG Road", 19.0760, 72.8777, city="Mumbai"))
    results = _search(client, "mg road", latitude=19.07, longitude=72.87).json()["results"]
    assert [p["name"] for p in results] == ["MG Road"]
    assert results[0]["crime_data_available"] is False


def test_landmarks_need_three_characters_and_a_real_resemblance(client, photon):
    _answer(photon)
    assert _search(client, "in").json()["results"] == []
    assert _search(client, "qzx").json()["results"] == []
    # One swapped letter in a 5-letter query is a spelling variant.
    assert [p["name"] for p in _search(client, "korma").json()["results"]] == ["Koramangala"]


def test_same_name_and_address_is_merged(client, photon):
    _answer(photon, INDRI, _feature("Indri", 29.8790, 77.0620, state="Haryana", postcode="132041"))
    names = [p["name"] for p in _search(client, "indri").json()["results"]]
    assert names.count("Indri") == 1


def test_spelling_matches_must_share_the_first_letters():
    # One edit away, but starting differently: not suggested.
    assert geocoding.landmark_matches("baga") == ([], [])
    # Same start, one letter missing: suggested.
    assert [p.name for p in geocoding.landmark_matches("indr")[1]] == ["Indiranagar"]


def test_nearby_place_with_another_name_does_not_replace_a_landmark(client, photon):
    # Live Photon returns this footbridge 25 m from the Majestic landmark.
    _answer(photon, _feature("Majestic Foot Over Bridge", 12.9776, 77.5725, city="Bengaluru"))
    names = [p["name"] for p in _search(client, "majestic").json()["results"]]
    assert names == ["Majestic (KSR Bengaluru City Junction)", "Majestic Foot Over Bridge"]
