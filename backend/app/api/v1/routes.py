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
from ...services.risk import RiskResult
from ...services.routing import RoutingError, get_routes

router = APIRouter()

OUTSIDE_COVERAGE_REASON = (
    "SafeRoute has historical crime data for Bengaluru only, so no crime-risk "
    "estimate is given for this route."
)
OUTSIDE_COVERAGE_MESSAGE = (
    "Crime-risk estimates are available only for trips within Bengaluru. These "
    "routes show travel time and distance only; they are not rated for crime "
    "exposure."
)
OUTSIDE_COVERAGE_RECOMMENDATION = (
    "This is the quickest option. No crime-risk estimate is available outside "
    "Bengaluru."
)


def _risk_out(result: RiskResult) -> RiskOut:
    # "unknown" means no data: send no score rather than a misleading 0.
    score = None if result.level == "unknown" else result.score
    return RiskOut(risk=result.level, score=score, reason=result.reason)


@router.post("/routes", response_model=RoutesResponse)
async def generate_routes(body: RouteRequest) -> RoutesResponse:
    start = (body.start.latitude, body.start.longitude)
    dest = (body.destination.latitude, body.destination.longitude)

    if haversine_m(*start, *dest) < 100:
        raise HTTPException(422, "Start and destination are too close together.")

    # Routing works anywhere the routing provider covers; crime risk only
    # where the dataset is. Outside it, routes are returned unrated.
    risk_covered = in_bbox(*start, BBOX) and in_bbox(*dest, BBOX)

    try:
        raw_routes = await get_routes(start, dest)
    except RoutingError as err:
        raise HTTPException(err.status, err.message)

    engine = get_engine()
    routes: list[RouteOut] = []
    candidates: list[Candidate] = []
    for index, raw in enumerate(raw_routes):
        if risk_covered:
            result = engine.score_path(raw.points)
            segments = [
                SegmentOut(
                    geometry=[[round(lat, 6), round(lon, 6)] for lat, lon in chunk],
                    risk=_risk_out(seg),
                    label=f"Section {i + 1}",
                )
                for i, (chunk, seg) in enumerate(engine.segment_scores(raw.points))
            ]
        else:
            result = RiskResult(level="unknown", score=0.0, reason=OUTSIDE_COVERAGE_REASON)
            segments = []
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
                segments=segments,
            )
        )
        candidates.append(
            Candidate(
                id=route_id,
                duration_minutes=minutes,
                score=result.score,
                known=result.level != "unknown",
            )
        )

    if risk_covered:
        route_id, reason = recommend(candidates, body.preference)
    else:
        route_id = min(candidates, key=lambda c: c.duration_minutes).id
        reason = OUTSIDE_COVERAGE_RECOMMENDATION
    return RoutesResponse(
        routes=routes,
        recommendation=RecommendationOut(route_id=route_id, reason=reason),
        risk_coverage="full" if risk_covered else "none",
        coverage_message=None if risk_covered else OUTSIDE_COVERAGE_MESSAGE,
    )
