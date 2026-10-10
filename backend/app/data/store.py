"""In-memory crime data. This is the only module that reads the dataset."""
import csv
import math
from dataclasses import dataclass
from datetime import date
from pathlib import Path

from ..config import CRIMES_CSV
from ..geo import haversine_m

# ~330 m cells; small enough that a radius query touches few buckets.
CELL_DEG = 0.003


@dataclass(frozen=True)
class Incident:
    id: str
    type: str
    description: str
    area: str
    district: str
    date: date
    latitude: float
    longitude: float


def _cell(lat: float, lon: float) -> tuple[int, int]:
    return (math.floor(lat / CELL_DEG), math.floor(lon / CELL_DEG))


class CrimeStore:
    def __init__(self, incidents: list[Incident]):
        if not incidents:
            raise RuntimeError("Crime dataset is empty.")
        self.incidents = incidents
        self.latest_date = max(i.date for i in incidents)
        self._grid: dict[tuple[int, int], list[Incident]] = {}
        for inc in incidents:
            self._grid.setdefault(_cell(inc.latitude, inc.longitude), []).append(inc)

    @classmethod
    def load(cls, path: Path = CRIMES_CSV) -> "CrimeStore":
        if not Path(path).exists():
            raise RuntimeError(
                f"Crime data file not found: {path}. Run scripts/ingest_xlsx.py first."
            )
        with open(path, newline="", encoding="utf-8") as f:
            incidents = [
                Incident(
                    id=row["id"],
                    type=row["type"],
                    description=row["description"],
                    area=row["area"],
                    district=row["district"],
                    date=date.fromisoformat(row["date"]),
                    latitude=float(row["latitude"]),
                    longitude=float(row["longitude"]),
                )
                for row in csv.DictReader(f)
            ]
        return cls(incidents)

    def near(self, lat: float, lon: float, radius_m: float) -> list[tuple[float, Incident]]:
        """Incidents within ``radius_m`` of a point as (distance_m, incident)."""
        lat_span = math.ceil(radius_m / 111_000 / CELL_DEG) + 1
        lon_scale = max(math.cos(math.radians(lat)), 0.01)
        lon_span = math.ceil(radius_m / (111_000 * lon_scale) / CELL_DEG) + 1
        ci, cj = _cell(lat, lon)
        found = []
        for i in range(ci - lat_span, ci + lat_span + 1):
            for j in range(cj - lon_span, cj + lon_span + 1):
                for inc in self._grid.get((i, j), ()):
                    d = haversine_m(lat, lon, inc.latitude, inc.longitude)
                    if d <= radius_m:
                        found.append((d, inc))
        return found


_store: CrimeStore | None = None


def init_store(store: CrimeStore | None = None) -> CrimeStore:
    global _store
    _store = store or CrimeStore.load()
    return _store


def get_store() -> CrimeStore:
    if _store is None:
        raise RuntimeError("Crime store not initialised.")
    return _store
