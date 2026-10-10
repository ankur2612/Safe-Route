from fastapi import APIRouter, HTTPException

from ...config import BBOX
from ...deps import get_engine
from ...geo import haversine_m, in_bbox
from ...schemas import (
    RecommendationOut,
    RiskOut,
    RouteOut,
    RoutesResponse,
    RouteRequest,
    SegmentOut,
)
from ...services.recommend import Candidate, recommend
from ...services.routing import RoutingError, get_routes

router = APIRouter()


def _risk_out(result) -> RiskOut:
    return RiskOut(risk=result.level, score=result.score, reason=result.reason)


@router.post("/routes", response_model=RoutesResponse)
async def generate_routes(body: RouteRequest) -> RoutesResponse:
    start = (body.start.latitude, body.start.longitude)
    dest = (body.destination.latitude, body.destination.longitude)

    for lat, lon in (start, dest):
        if not in_bbox(lat, lon, BBOX):
            raise HTTPException(
                422, "SafeRoute currently supports routes within Bengaluru only."
            )
    if haversine_m(*start, *dest) < 100:
        raise HTTPException(422, "Start and destination are too close together.")

    try:
        raw_routes = await get_routes(start, dest)
    except RoutingError as err:
        raise HTTPException(err.status, err.message)

    engine = get_engine()
    routes: list[RouteOut] = []
    candidates: list[Candidate] = []
    for index, raw in enumerate(raw_routes):
        result = engine.score_path(raw.points)
        minutes = max(1, round(raw.duration_s / 60))
        route_id = f"route-{chr(97 + index)}"
        routes.append(
            RouteOut(
                id=route_id,
                name=f"Route {chr(65 + index)}",
                duration_minutes=minutes,
                distance_km=round(raw.distance_m / 1000, 1),
                geometry=[[round(lat, 6), round(lon, 6)] for lat, lon in raw.points],
                risk=_risk_out(result),
                segments=[
                    SegmentOut(
                        geometry=[[round(lat, 6), round(lon, 6)] for lat, lon in chunk],
                        risk=_risk_out(seg),
                        label=f"Section {i + 1}",
                    )
                    for i, (chunk, seg) in enumerate(engine.segment_scores(raw.points))
                ],
            )
        )
        candidates.append(Candidate(id=route_id, duration_minutes=minutes, score=result.score))

    route_id, reason = recommend(candidates, body.preference)
    return RoutesResponse(
        routes=routes,
        recommendation=RecommendationOut(route_id=route_id, reason=reason),
    )
