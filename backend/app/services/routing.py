"""Route generation through OSRM. Returns geometry and timings only."""
import math
from dataclasses import dataclass

import httpx

from ..config import HTTP_TIMEOUT, OSRM_URL, USER_AGENT
from ..geo import haversine_m

MAX_ROUTES = 3


class RoutingError(Exception):
    """The routing provider failed. ``status`` is the HTTP code to return."""

    def __init__(self, message: str, status: int = 502):
        super().__init__(message)
        self.message = message
        self.status = status


@dataclass(frozen=True)
class RawRoute:
    duration_s: float
    distance_m: float
    points: list[tuple[float, float]]  # (lat, lon)


async def _fetch(client: httpx.AsyncClient, coords: list[tuple[float, float]], alternatives: bool) -> list[RawRoute]:
    path = ";".join(f"{lon:.6f},{lat:.6f}" for lat, lon in coords)
    params = {"overview": "full", "geometries": "geojson", "steps": "false"}
    if alternatives:
        params["alternatives"] = "3"
    try:
        resp = await client.get(f"{OSRM_URL}/route/v1/driving/{path}", params=params)
    except httpx.TimeoutException:
        raise RoutingError("The routing service took too long to respond.", 504)
    except httpx.HTTPError:
        raise RoutingError("The routing service is unavailable right now.", 502)

    if resp.status_code != 200:
        # OSRM answers 400 with code NoRoute / InvalidQuery for unroutable points.
        code = ""
        try:
            code = resp.json().get("code", "")
        except ValueError:
            pass
        if code in ("NoRoute", "NoSegment"):
            raise RoutingError("No route could be found between these points.", 404)
        raise RoutingError("The routing service returned an error.", 502)

    try:
        body = resp.json()
        return [
            RawRoute(
                duration_s=float(r["duration"]),
                distance_m=float(r["distance"]),
                points=[(c[1], c[0]) for c in r["geometry"]["coordinates"]],
            )
            for r in body.get("routes", [])
            if len(r["geometry"]["coordinates"]) >= 2
        ]
    except (KeyError, TypeError, ValueError):
        raise RoutingError("The routing service sent an unexpected response.", 502)


def _too_similar(a: RawRoute, b: RawRoute) -> bool:
    if abs(a.distance_m - b.distance_m) / max(a.distance_m, 1) > 0.03:
        return False
    ma, mb = a.points[len(a.points) // 2], b.points[len(b.points) // 2]
    return haversine_m(ma[0], ma[1], mb[0], mb[1]) < 150


def _detour_waypoint(start: tuple[float, float], dest: tuple[float, float]) -> tuple[float, float]:
    """A point to the side of the midpoint, ~20% of the trip length away."""
    mid_lat, mid_lon = (start[0] + dest[0]) / 2, (start[1] + dest[1]) / 2
    d_lat, d_lon = dest[0] - start[0], dest[1] - start[1]
    return (mid_lat - d_lon * 0.2, mid_lon + d_lat * 0.2)


async def get_routes(start: tuple[float, float], dest: tuple[float, float]) -> list[RawRoute]:
    async with httpx.AsyncClient(timeout=HTTP_TIMEOUT, headers={"User-Agent": USER_AGENT}) as client:
        routes = await _fetch(client, [start, dest], alternatives=True)
        if not routes:
            raise RoutingError("No route could be found between these points.", 404)

        # Public OSRM often returns a single route; try side detours so the
        # app has something to compare.
        if len(routes) < 2:
            lat, lon = _detour_waypoint(start, dest)
            for waypoint in ((lat, lon), (2 * (start[0] + dest[0]) / 2 - lat, 2 * (start[1] + dest[1]) / 2 - lon)):
                try:
                    extra = await _fetch(client, [start, waypoint, dest], alternatives=False)
                except RoutingError:
                    continue
                for candidate in extra:
                    direct_km = haversine_m(*start, *dest) / 1000
                    # Ignore absurd detours.
                    if candidate.distance_m / 1000 <= max(direct_km * 2.5, direct_km + 5) and not any(
                        _too_similar(candidate, r) for r in routes
                    ):
                        routes.append(candidate)

    unique: list[RawRoute] = []
    for r in routes:
        if not any(_too_similar(r, u) for u in unique):
            unique.append(r)
    return unique[:MAX_ROUTES]
