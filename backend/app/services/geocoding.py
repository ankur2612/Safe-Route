"""Destination search across India: Photon (OpenStreetMap) with a local fallback.

Photon is designed for search-as-you-type: it matches partial words
("kora" -> Koramangala) and tolerates small spelling mistakes. Results cover
India (``GEOCODE_BBOX`` + ``GEOCODE_COUNTRY``), ranked towards the user's
position or Bengaluru. This scope is deliberately wider than crime-risk
coverage (``BBOX``): any place can be found, but only places in Bengaluru get
a risk estimate.

Everything provider-specific lives in the ``_photon*`` functions, so a
different provider only needs a replacement for those.

If Photon fails, a short local list of Bengaluru places answers instead and
the result is marked ``degraded``; with no local match the caller gets
``GeocoderUnavailable`` (never an empty "not found").
"""
import asyncio
import math
import re
import time
from collections import OrderedDict
from dataclasses import dataclass

import httpx

from ..config import (
    BBOX,
    CITY_CENTER,
    GEOCODE_BBOX,
    GEOCODE_COUNTRY,
    GEOCODER_TIMEOUT,
    PHOTON_URL,
    USER_AGENT,
)
from ..data.store import get_store
from ..geo import haversine_m, in_bbox

LIMIT = 8
CACHE_SIZE = 300
CACHE_TTL_S = 6 * 3600
MIN_QUERY_CHARS = 2  # Photon rejects single-character queries
MIN_LANDMARK_CHARS = 3
# Fair use of the public Photon server: a few requests at a time, and a pause
# after it answers 429 instead of retrying straight away.
MAX_CONCURRENT_REQUESTS = 4
RATE_LIMIT_BACKOFF_S = 30.0
# How strongly results near the bias point are preferred (Photon's default is
# 0.2; higher keeps far-away exact matches like "Baga, Goa" visible).
LOCATION_BIAS_SCALE = "0.5"
# The same name this close together is one place (Photon often returns a
# village, its boundary and its bus stop separately). Within the same
# locality a boundary's centre can sit further away, hence the wider radius.
DUPLICATE_M = 1500
DUPLICATE_SAME_LOCALITY_M = 5000
# Mapped, but not somewhere you can drive to.
SKIP_VALUES = {"proposed", "construction", "abandoned", "disused", "razed"}


class GeocoderUnavailable(Exception):
    """The provider failed and the local list had no match either."""

    def __init__(self, message: str, rate_limited: bool = False):
        super().__init__(message)
        self.rate_limited = rate_limited


class _RateLimited(Exception):
    pass


@dataclass(frozen=True)
class Place:
    name: str
    address: str
    latitude: float
    longitude: float
    locality: str | None = None
    # Kind of place, e.g. "suburb", "station", "primary" (a main road).
    category: str | None = None
    # Provider identifier, e.g. "osm:N123"; None for the local list.
    place_id: str | None = None

    @property
    def crime_data_available(self) -> bool:
        """Whether SafeRoute can estimate crime risk here (Bengaluru only)."""
        return in_bbox(self.latitude, self.longitude, BBOX)


@dataclass(frozen=True)
class SearchResult:
    places: list[Place]
    # True when the provider failed and only the local list answered.
    degraded: bool = False


LANDMARKS = [
    Place("Majestic (KSR Bengaluru City Junction)", "Bengaluru", 12.9778, 77.5724),
    Place("MG Road", "Bengaluru", 12.9757, 77.6070),
    Place("Cubbon Park", "Bengaluru", 12.9763, 77.5929),
    Place("Lalbagh Botanical Garden", "Bengaluru", 12.9507, 77.5848),
    Place("Vidhana Soudha", "Bengaluru", 12.9794, 77.5907),
    Place("Bangalore Palace", "Bengaluru", 12.9988, 77.5921),
    Place("Indiranagar", "Bengaluru", 12.9784, 77.6408),
    Place("Koramangala", "Bengaluru", 12.9352, 77.6245),
    Place("Jayanagar", "Bengaluru", 12.9279, 77.5937),
    Place("Whitefield", "Bengaluru", 12.9698, 77.7500),
    Place("Electronic City", "Bengaluru", 12.8452, 77.6602),
    Place("HSR Layout", "Bengaluru", 12.9116, 77.6389),
    Place("BTM Layout", "Bengaluru", 12.9166, 77.6101),
    Place("Marathahalli", "Bengaluru", 12.9569, 77.7011),
    Place("Malleshwaram", "Bengaluru", 13.0035, 77.5646),
    Place("Rajajinagar", "Bengaluru", 12.9916, 77.5520),
    Place("Yeshwanthpur", "Bengaluru", 13.0285, 77.5409),
    Place("Hebbal", "Bengaluru", 13.0358, 77.5970),
    Place("Banashankari", "Bengaluru", 12.9255, 77.5468),
    Place("JP Nagar", "Bengaluru", 12.9063, 77.5857),
    Place("Basavanagudi", "Bengaluru", 12.9422, 77.5755),
    Place("Shivajinagar", "Bengaluru", 12.9857, 77.6057),
    Place("Commercial Street", "Bengaluru", 12.9822, 77.6083),
    Place("Sadashivanagar", "Bengaluru", 13.0070, 77.5810),
    Place("Kempegowda International Airport", "Devanahalli, Bengaluru", 13.1986, 77.7066),
    Place("Orion Mall", "Rajajinagar, Bengaluru", 13.0107, 77.5550),
    Place("UB City", "Vittal Mallya Road, Bengaluru", 12.9719, 77.5963),
    Place("Silk Board Junction", "Bengaluru", 12.9173, 77.6228),
    Place("Yelahanka", "Bengaluru", 13.1007, 77.5963),
    Place("Ulsoor Lake", "Bengaluru", 12.9830, 77.6195),
]

_cache: "OrderedDict[str, tuple[float, list[Place]]]" = OrderedDict()
_semaphore = asyncio.Semaphore(MAX_CONCURRENT_REQUESTS)
_backoff_until = 0.0
_dataset_places: list[Place] | None = None


def normalize_query(query: str) -> str:
    """Lower-case with runs of whitespace collapsed, used as the cache key."""
    return " ".join(query.split()).lower()


def _fold(text: str) -> str:
    """Letters and digits only, so "H.S.R Layout" and "hsrlayout" compare equal."""
    return re.sub(r"[^0-9a-z]", "", text.lower())


def _prefix_distance(needle: str, hay: str) -> int:
    """Edit distance (with adjacent swaps) from ``needle`` to the closest prefix of ``hay``."""
    m, n = len(needle), len(hay)
    d = [[0] * (n + 1) for _ in range(m + 1)]
    for i in range(m + 1):
        d[i][0] = i
    for j in range(n + 1):
        d[0][j] = j
    for i in range(1, m + 1):
        for j in range(1, n + 1):
            cost = 0 if needle[i - 1] == hay[j - 1] else 1
            d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
            if i > 1 and j > 1 and needle[i - 1] == hay[j - 2] and needle[i - 2] == hay[j - 1]:
                d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1)
    return min(d[m])


def _match_rank(needle: str, name: str) -> int | None:
    """Lower is better; None means no match. ``needle`` must already be folded."""
    hay = _fold(name)
    if hay.startswith(needle):
        return 0
    if any(_fold(word).startswith(needle) for word in name.split()):
        return 1
    if needle in hay:
        return 2
    # Spelling variations ("kormangala", "marathalli") on longer input only,
    # so two or three letters never match half the city.
    if len(needle) >= 4 and _prefix_distance(needle, hay) <= (1 if len(needle) < 7 else 2):
        return 3
    return None


def _dataset_localities() -> list[Place]:
    """Areas named in the crime dataset, at their average coordinates."""
    global _dataset_places
    if _dataset_places is None:
        groups: dict[str, list[tuple[float, float]]] = {}
        for inc in get_store().incidents:
            groups.setdefault(inc.area, []).append((inc.latitude, inc.longitude))
        _dataset_places = [
            Place(
                name=name,
                address="Bengaluru",
                latitude=sum(p[0] for p in pts) / len(pts),
                longitude=sum(p[1] for p in pts) / len(pts),
            )
            for name, pts in groups.items()
            if len(name) >= 3
        ]
    return _dataset_places


def landmark_matches(query: str) -> tuple[list[Place], list[Place]]:
    """Curated Bengaluru landmarks matching ``query``: (by prefix, by close spelling).

    Short prefixes are ambiguous across India ("indr" -> Indri, Haryana, while
    the user usually means Indiranagar, often spelt "Indranagar"), and some
    well-known names are not what OpenStreetMap calls the place ("Majestic" is
    mapped as Kempegowda Bus Station). Spelling tolerance is the same as the
    fallback search: none below 4 characters, one edit up to 6, two beyond.
    """
    needle = _fold(query)
    if len(needle) < MIN_LANDMARK_CHARS:
        return [], []
    prefix: list[Place] = []
    close: list[Place] = []
    for place in LANDMARKS:
        rank = _match_rank(needle, place.name)
        if rank is None:
            continue
        # A spelling match must start like the name: typos rarely hit the
        # first letters, and "baga" must not suggest Bangalore Palace.
        if rank == 3 and _fold(place.name)[:3] != needle[:3]:
            continue
        # Name or word prefix leads; substring or spelling matches follow.
        (prefix if rank <= 1 else close).append(place)
    return prefix, close


def _merge_landmarks(prefix: list[Place], close: list[Place], remote: list[Place]) -> list[Place]:
    """Prefix landmarks first, provider results next, close-spelling landmarks
    last but still within ``LIMIT``. Where the provider has the same place,
    its richer entry is used instead of the landmark."""

    def same(a: Place, b: Place) -> bool:
        # Same name too: a footbridge 25 m from Majestic is not Majestic.
        return _fold(a.name) == _fold(b.name) and _is_duplicate(a, b)

    def resolved(landmarks: list[Place]) -> list[Place]:
        return [next((r for r in remote if same(l, r)), l) for l in landmarks]

    lead = _dedupe(resolved(prefix))
    tail = [p for p in _dedupe(resolved(close)) if not any(same(p, q) for q in lead + remote)]
    middle = [r for r in _dedupe(remote) if not any(same(r, q) for q in lead)]
    room = max(LIMIT - len(lead) - len(tail), 0)
    return (lead + middle[:room] + tail)[:LIMIT]


def search_local(query: str) -> list[Place]:
    needle = _fold(query)
    if not needle:
        return []
    ranked = []
    for order, place in enumerate(LANDMARKS + _dataset_localities()):
        rank = _match_rank(needle, place.name)
        if rank is not None:
            ranked.append((rank, order, place))
    ranked.sort(key=lambda t: (t[0], t[1]))
    return [place for _, _, place in ranked[:LIMIT]]


def _photon_place(feature: dict) -> Place | None:
    """One Photon GeoJSON feature as a Place, or None if unusable."""
    try:
        props = feature["properties"]
        lon, lat = (float(v) for v in feature["geometry"]["coordinates"][:2])
    except (KeyError, TypeError, ValueError):
        return None
    if not (math.isfinite(lat) and math.isfinite(lon)) or not in_bbox(lat, lon, GEOCODE_BBOX):
        return None
    # The box also covers parts of neighbouring countries.
    if str(props.get("countrycode") or "").upper() != GEOCODE_COUNTRY:
        return None
    if props.get("osm_value") in SKIP_VALUES:
        return None

    name = str(props.get("name") or "").strip()
    if not name and props.get("street"):
        name = " ".join(str(p) for p in (props.get("housenumber"), props["street"]) if p)
    if not name:
        return None

    parts: list[str] = []
    for key in ("street", "locality", "district", "city", "county", "state"):
        value = str(props.get(key) or "").strip()
        if value and value.lower() != name.lower() and value.lower() not in (p.lower() for p in parts):
            parts.append(value)
    # Keep the address short: the nearest three parts, then always the state.
    state = str(props.get("state") or "").strip()
    shown = [p for p in parts if p != state][:3] + ([state] if state and state.lower() != name.lower() else [])
    postcode = str(props.get("postcode") or "").strip()
    address = ", ".join(shown) or "India"
    if postcode and postcode != name:
        address = f"{address} {postcode}"

    locality = next(
        (str(props[k]).strip() for k in ("district", "locality", "city", "county") if props.get(k)),
        None,
    )
    osm_type, osm_id = props.get("osm_type"), props.get("osm_id")
    category = str(props.get("osm_value") or "").strip().replace("_", " ") or None
    return Place(
        name=name,
        address=address,
        latitude=lat,
        longitude=lon,
        locality=locality,
        category=None if category == "yes" else category,
        place_id=f"osm:{osm_type}{osm_id}" if osm_type and osm_id else None,
    )


async def _photon(query: str, bias: tuple[float, float]) -> list[Place]:
    global _backoff_until
    if time.monotonic() < _backoff_until:
        raise _RateLimited()
    params = {
        "q": query,
        "limit": str(LIMIT * 2),  # extra room for entries dropped below
        "lang": "en",
        "lat": str(bias[0]),
        "lon": str(bias[1]),
        "location_bias_scale": LOCATION_BIAS_SCALE,
        "bbox": ",".join(
            str(GEOCODE_BBOX[k]) for k in ("min_lon", "min_lat", "max_lon", "max_lat")
        ),
    }
    async with _semaphore:
        async with httpx.AsyncClient(timeout=GEOCODER_TIMEOUT, headers={"User-Agent": USER_AGENT}) as client:
            resp = await client.get(f"{PHOTON_URL}/api", params=params)
    if resp.status_code == 429:
        _backoff_until = time.monotonic() + RATE_LIMIT_BACKOFF_S
        raise _RateLimited()
    resp.raise_for_status()
    body = resp.json()
    if not isinstance(body, dict) or not isinstance(body.get("features"), list):
        raise ValueError("Unexpected geocoder response.")
    return [p for p in (_photon_place(f) for f in body["features"] if isinstance(f, dict)) if p]


def _is_duplicate(a: Place, b: Place) -> bool:
    apart = haversine_m(a.latitude, a.longitude, b.latitude, b.longitude)
    if apart < 50:
        return True
    if _fold(a.name) != _fold(b.name):
        return False
    same_area = (a.locality is not None and a.locality == b.locality) or a.address == b.address
    return apart < (DUPLICATE_SAME_LOCALITY_M if same_area else DUPLICATE_M)


def _dedupe(places: list[Place]) -> list[Place]:
    out: list[Place] = []
    for place in places:
        if not any(_is_duplicate(p, place) for p in out):
            out.append(place)
    return out


def _cache_get(key: str) -> list[Place] | None:
    entry = _cache.get(key)
    if entry is None:
        return None
    stored_at, places = entry
    if time.monotonic() - stored_at > CACHE_TTL_S:
        del _cache[key]
        return None
    _cache.move_to_end(key)
    return places


def _cache_put(key: str, places: list[Place]) -> None:
    _cache[key] = (time.monotonic(), places)
    _cache.move_to_end(key)
    if len(_cache) > CACHE_SIZE:
        _cache.popitem(last=False)


async def search(query: str, near: tuple[float, float] | None = None) -> SearchResult:
    """Places matching ``query``, ranked towards ``near`` (default: Bengaluru)."""
    text = normalize_query(query)
    if len(_fold(text)) < MIN_QUERY_CHARS:
        return SearchResult(places=[])

    bias = near if near is not None else CITY_CENTER
    # Bias rounded to ~50 km so nearby users share cache entries.
    key = f"{text}|{round(bias[0] * 2) / 2},{round(bias[1] * 2) / 2}"
    cached = _cache_get(key)
    if cached is not None:
        return SearchResult(places=cached)

    try:
        remote = await _photon(text, bias)
    except (httpx.HTTPError, ValueError, _RateLimited) as err:
        rate_limited = isinstance(err, _RateLimited)
        # Degraded answer from the local list, never cached, so the next
        # keystroke can reach Photon again.
        local = search_local(text)
        if local:
            return SearchResult(places=local, degraded=True)
        raise GeocoderUnavailable(
            "Too many searches right now. Please wait a moment and try again."
            if rate_limited
            else "Location search is temporarily unavailable. Please try again.",
            rate_limited=rate_limited,
        )

    # Curated landmarks lead only when the search is centred on Bengaluru.
    prefix, close = landmark_matches(text) if in_bbox(bias[0], bias[1], BBOX) else ([], [])
    places = _merge_landmarks(prefix, close, remote)
    _cache_put(key, places)
    return SearchResult(places=places)
