"""Destination search: local Bengaluru places first, Nominatim after."""
import asyncio
import time
from collections import OrderedDict
from dataclasses import dataclass

import httpx

from ..config import BBOX, HTTP_TIMEOUT, NOMINATIM_URL, USER_AGENT
from ..data.store import get_store

LIMIT = 8
CACHE_SIZE = 300
MIN_INTERVAL_S = 1.1  # Nominatim usage policy: max 1 request per second


@dataclass(frozen=True)
class Place:
    name: str
    address: str
    latitude: float
    longitude: float


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

_cache: "OrderedDict[str, list[Place]]" = OrderedDict()
_lock = asyncio.Lock()
_last_call = 0.0
_dataset_places: list[Place] | None = None


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


def search_local(query: str) -> list[Place]:
    needle = query.strip().lower()
    if not needle:
        return []
    starts, contains = [], []
    for place in LANDMARKS + _dataset_localities():
        hay = place.name.lower()
        if hay.startswith(needle):
            starts.append(place)
        elif needle in hay:
            contains.append(place)
    return (starts + contains)[:LIMIT]


async def _nominatim(query: str) -> list[Place]:
    global _last_call
    params = {
        "q": query,
        "format": "jsonv2",
        "limit": str(LIMIT),
        "countrycodes": "in",
        "viewbox": f"{BBOX['min_lon']},{BBOX['max_lat']},{BBOX['max_lon']},{BBOX['min_lat']}",
        "bounded": "1",
    }
    async with _lock:
        wait = MIN_INTERVAL_S - (time.monotonic() - _last_call)
        if wait > 0:
            await asyncio.sleep(wait)
        _last_call = time.monotonic()
        async with httpx.AsyncClient(timeout=HTTP_TIMEOUT, headers={"User-Agent": USER_AGENT}) as client:
            resp = await client.get(f"{NOMINATIM_URL}/search", params=params)
    resp.raise_for_status()
    places = []
    for item in resp.json():
        try:
            display = str(item["display_name"])
            head, _, tail = display.partition(",")
            places.append(
                Place(
                    name=item.get("name") or head.strip(),
                    address=tail.strip() or "Bengaluru",
                    latitude=float(item["lat"]),
                    longitude=float(item["lon"]),
                )
            )
        except (KeyError, TypeError, ValueError):
            continue
    return places


async def search(query: str) -> list[Place]:
    key = query.strip().lower()
    if not key:
        return []
    if key in _cache:
        _cache.move_to_end(key)
        return _cache[key]

    local = search_local(key)
    remote: list[Place] = []
    remote_ok = True
    try:
        remote = await _nominatim(key)
    except (httpx.HTTPError, ValueError):
        remote_ok = False

    merged: list[Place] = list(local)
    for place in remote:
        if not any(abs(place.latitude - p.latitude) < 0.0005 and abs(place.longitude - p.longitude) < 0.0005 for p in merged):
            merged.append(place)
    merged = merged[:LIMIT]

    # Do not cache a degraded answer, so a later retry can reach Nominatim.
    if remote_ok:
        _cache[key] = merged
        if len(_cache) > CACHE_SIZE:
            _cache.popitem(last=False)
    return merged
