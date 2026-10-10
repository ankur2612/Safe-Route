from fastapi import APIRouter, HTTPException, Query

from ...config import BBOX
from ...deps import get_engine, get_store
from ...geo import in_bbox
from ...schemas import CrimeOut, CrimesResponse, HeatmapPointOut, HeatmapResponse

router = APIRouter()

CELL_DEG = 0.003  # ~330 m heatmap cells
MAX_RADIUS_KM = 10.0
MAX_HEATMAP_CELLS = 600


def _check_area(lat: float, lon: float) -> None:
    if not in_bbox(lat, lon, BBOX):
        raise HTTPException(422, "Crime data is only available for Bengaluru.")


@router.get("/crimes", response_model=CrimesResponse)
def crimes(
    latitude: float = Query(ge=-90, le=90),
    longitude: float = Query(ge=-180, le=180),
    radius_km: float = Query(default=3.0, gt=0, le=MAX_RADIUS_KM),
    limit: int = Query(default=200, ge=1, le=500),
) -> CrimesResponse:
    _check_area(latitude, longitude)
    nearby = sorted(get_store().near(latitude, longitude, radius_km * 1000), key=lambda t: t[0])
    return CrimesResponse(
        crimes=[
            CrimeOut(
                id=inc.id,
                type=inc.type,
                latitude=inc.latitude,
                longitude=inc.longitude,
                date=inc.date.isoformat(),
                area=inc.area or inc.district,
                description=inc.description,
            )
            for _, inc in nearby[:limit]
        ]
    )


@router.get("/crimes/heatmap", response_model=HeatmapResponse)
def heatmap(
    latitude: float = Query(ge=-90, le=90),
    longitude: float = Query(ge=-180, le=180),
    radius_km: float = Query(default=4.0, gt=0, le=MAX_RADIUS_KM),
) -> HeatmapResponse:
    _check_area(latitude, longitude)
    engine = get_engine()
    cells: dict[tuple[int, int], float] = {}
    sums: dict[tuple[int, int], list[float]] = {}
    for _, inc in get_store().near(latitude, longitude, radius_km * 1000):
        key = (int(inc.latitude // CELL_DEG), int(inc.longitude // CELL_DEG))
        cells[key] = cells.get(key, 0.0) + engine.weight_of(inc)
        s = sums.setdefault(key, [0.0, 0.0, 0.0])
        s[0] += inc.latitude
        s[1] += inc.longitude
        s[2] += 1

    if not cells:
        return HeatmapResponse(points=[])

    ranked = sorted(cells.items(), key=lambda kv: kv[1], reverse=True)[:MAX_HEATMAP_CELLS]
    top = ranked[0][1]
    values = sorted(v for _, v in ranked)
    low_cut = values[len(values) // 3]
    high_cut = values[(2 * len(values)) // 3]

    points = []
    for key, weight in ranked:
        lat_sum, lon_sum, n = sums[key]
        exposure = "high" if weight >= high_cut else "moderate" if weight >= low_cut else "low"
        points.append(
            HeatmapPointOut(
                latitude=round(lat_sum / n, 5),
                longitude=round(lon_sum / n, 5),
                exposure=exposure,
                intensity=round(weight / top, 2),
            )
        )
    return HeatmapResponse(points=points)
