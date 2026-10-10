"""Small geometry helpers. Distances are metres unless stated."""
import math

EARTH_RADIUS_M = 6_371_000.0


def haversine_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = p2 - p1
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * EARTH_RADIUS_M * math.asin(math.sqrt(a))


def path_length_km(points: list[tuple[float, float]]) -> float:
    return sum(
        haversine_m(a[0], a[1], b[0], b[1]) for a, b in zip(points, points[1:])
    ) / 1000


def densify(points: list[tuple[float, float]], step_m: float = 100.0) -> list[tuple[float, float]]:
    """Insert points so no gap is longer than ``step_m``.

    Without this a long straight segment would only be checked at its two
    ends and incidents beside its middle would be missed.
    """
    if len(points) < 2:
        return list(points)
    out = [points[0]]
    for a, b in zip(points, points[1:]):
        gap = haversine_m(a[0], a[1], b[0], b[1])
        n = int(gap // step_m)
        for i in range(1, n + 1):
            t = i / (n + 1)
            out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
        out.append(b)
    return out


def in_bbox(lat: float, lon: float, bbox: dict[str, float]) -> bool:
    return (
        bbox["min_lat"] <= lat <= bbox["max_lat"]
        and bbox["min_lon"] <= lon <= bbox["max_lon"]
    )
