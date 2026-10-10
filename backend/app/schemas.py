"""Request/response shapes. These mirror what the Flutter models parse."""
from pydantic import BaseModel, Field


class Point(BaseModel):
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)


class RouteRequest(BaseModel):
    start: Point
    destination: Point
    preference: str = Field(default="balanced", pattern="^(fastest|balanced|lower_risk)$")


class RiskOut(BaseModel):
    risk: str
    score: float
    reason: str


class SegmentOut(BaseModel):
    geometry: list[list[float]]
    risk: RiskOut
    label: str


class RouteOut(BaseModel):
    id: str
    name: str
    duration_minutes: int
    distance_km: float
    geometry: list[list[float]]
    risk: RiskOut
    segments: list[SegmentOut] = []


class RecommendationOut(BaseModel):
    route_id: str
    reason: str


class RoutesResponse(BaseModel):
    routes: list[RouteOut]
    recommendation: RecommendationOut


class RiskRouteRequest(BaseModel):
    route_id: str | None = None
    geometry: list[list[float]] = Field(min_length=2, max_length=20000)


class RiskRouteResponse(BaseModel):
    risk: RiskOut


class CrimeOut(BaseModel):
    id: str
    type: str
    latitude: float
    longitude: float
    date: str
    area: str
    description: str


class CrimesResponse(BaseModel):
    crimes: list[CrimeOut]


class HeatmapPointOut(BaseModel):
    latitude: float
    longitude: float
    exposure: str
    intensity: float


class HeatmapResponse(BaseModel):
    points: list[HeatmapPointOut]


class LocationOut(BaseModel):
    name: str
    address: str
    latitude: float
    longitude: float


class LocationsResponse(BaseModel):
    results: list[LocationOut]
