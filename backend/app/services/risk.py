"""Historical crime exposure scoring.

The formula is deliberately simple and documented in the README:

* every incident has a weight = severity (1-5) x recency decay
  (half-life 3 years, measured from the newest record in the dataset);
* a route's exposure is the total weight of incidents within 300 m of the
  route, per km of route;
* the score is that exposure divided by a "high" reference taken from the
  dataset itself (90th percentile over the city), capped at 1;
* a route with no records anywhere near it is "unknown", not "low": an
  absence of data is not evidence of low exposure.

The output describes *estimated historical exposure*. It is not a prediction
and says nothing about safety.
"""
import math
from dataclasses import dataclass

from ..data.store import CrimeStore, Incident
from ..geo import densify, path_length_km

NEAR_ROUTE_M = 300.0
HALF_LIFE_YEARS = 3.0
LOW_BELOW = 0.33
MODERATE_BELOW = 0.66
# A route point counts as covered by the dataset when any record lies this
# close (the same "populated" test the calibration uses).
COVERAGE_RADIUS_M = 1500.0
PARTIAL_COVERAGE_BELOW = 0.5

SEVERITY = {
    "Murder": 5, "Sexual Assault": 5, "Acid Attack": 5, "Kidnapping": 5,
    "Robbery": 4, "Assault": 4, "Rioting": 4, "Arson": 4,
    "Burglary": 3, "Extortion": 3, "Stalking": 3, "Hit and Run": 3,
    "Drug Trafficking": 3, "Organised Crime": 3,
    "Theft": 2, "Vehicle Crime": 2, "Cheating": 2, "Land Grabbing": 2,
}
DEFAULT_SEVERITY = 2

REASONS = {
    "low": "Lower estimated historical crime exposure along this route.",
    "moderate": "Moderate estimated historical crime exposure along parts of this route.",
    "high": "Higher estimated historical crime exposure along this route.",
    "unknown": "No historical crime records are available near this route, so its "
    "exposure cannot be estimated.",
}
PARTIAL_NOTE = " Historical crime data covers only part of this route, so this estimate may be incomplete."


@dataclass(frozen=True)
class RiskResult:
    level: str
    score: float
    reason: str


def level_for(score: float) -> str:
    if score < LOW_BELOW:
        return "low"
    if score < MODERATE_BELOW:
        return "moderate"
    return "high"


class RiskEngine:
    def __init__(self, store: CrimeStore):
        self.store = store
        self._weights = {inc.id: self._weight(inc) for inc in store.incidents}
        self.high_reference = self._calibrate()

    def _weight(self, inc: Incident) -> float:
        age_years = max((self.store.latest_date - inc.date).days, 0) / 365.25
        recency = 0.5 ** (age_years / HALF_LIFE_YEARS)
        return SEVERITY.get(inc.type, DEFAULT_SEVERITY) * recency

    def weight_of(self, inc: Incident) -> float:
        return self._weights[inc.id]

    def _calibrate(self) -> float:
        """90th percentile of exposure density over populated parts of the city."""
        lats = [i.latitude for i in self.store.incidents]
        lons = [i.longitude for i in self.store.incidents]
        step = 0.012  # ~1.3 km
        densities = []
        lat = min(lats)
        while lat <= max(lats):
            lon = min(lons)
            while lon <= max(lons):
                # Only count places inside the populated area.
                if self.store.near(lat, lon, 1500):
                    total = sum(self._weights[i.id] for _, i in self.store.near(lat, lon, NEAR_ROUTE_M))
                    densities.append(total / (2 * NEAR_ROUTE_M / 1000))
                lon += step
            lat += step
        if not densities:
            return 1.0
        densities.sort()
        ref = densities[min(len(densities) - 1, int(0.9 * len(densities)))]
        return ref if ref > 0 else 1.0

    def _exposure(self, points: list[tuple[float, float]]) -> float:
        """Total weight of distinct incidents within range of the path."""
        return sum(self._weights[inc.id] for inc in self.store.near_path(points, NEAR_ROUTE_M))

    def coverage(self, points: list[tuple[float, float]]) -> float:
        """Share of the path (0-1) that has any historical record nearby."""
        dense = densify(points)
        if not dense:
            return 0.0
        covered = sum(1 for lat, lon in dense if self.store.near(lat, lon, COVERAGE_RADIUS_M))
        return covered / len(dense)

    def score_path(self, points: list[tuple[float, float]]) -> RiskResult:
        coverage = self.coverage(points)
        if coverage == 0:
            return RiskResult(level="unknown", score=0.0, reason=REASONS["unknown"])
        km = max(path_length_km(points), 0.3)
        density = self._exposure(points) / km
        score = round(min(1.0, density / self.high_reference), 2)
        level = level_for(score)
        reason = REASONS[level] + (PARTIAL_NOTE if coverage < PARTIAL_COVERAGE_BELOW else "")
        return RiskResult(level=level, score=score, reason=reason)

    def segment_scores(
        self, points: list[tuple[float, float]], max_segments: int = 8
    ) -> list[tuple[list[tuple[float, float]], RiskResult]]:
        """Split a path into chunks and score each one."""
        n = min(max_segments, len(points) // 5)
        if n < 2:
            return []
        size = math.ceil((len(points) - 1) / n)
        segments = []
        for start in range(0, len(points) - 1, size):
            chunk = points[start : start + size + 1]
            if len(chunk) >= 2:
                segments.append((chunk, self.score_path(chunk)))
        return segments
