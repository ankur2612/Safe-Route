from fastapi import APIRouter, HTTPException

from ...config import BBOX
from ...deps import get_engine
from ...geo import in_bbox
from ...schemas import RiskOut, RiskRouteRequest, RiskRouteResponse

router = APIRouter()


@router.post("/risk/route", response_model=RiskRouteResponse)
def risk_route(body: RiskRouteRequest) -> RiskRouteResponse:
    points: list[tuple[float, float]] = []
    for pair in body.geometry:
        if len(pair) < 2:
            raise HTTPException(422, "Each geometry point needs [latitude, longitude].")
        points.append((pair[0], pair[1]))
    if not all(in_bbox(lat, lon, BBOX) for lat, lon in points):
        raise HTTPException(422, "Route is outside the supported area (Bengaluru).")

    result = get_engine().score_path(points)
    return RiskRouteResponse(risk=RiskOut(risk=result.level, score=result.score, reason=result.reason))
