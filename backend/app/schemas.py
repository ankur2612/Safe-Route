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
    # "low" | "moderate" | "high", or "unknown" when there is no data to
    # estimate from (then ``score`` is null).
    risk: str
    score: float | None
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
    # "full" when both ends are inside the crime-data area (Bengaluru),
    # "none" otherwise: routes are then returned without a risk estimate.
    risk_coverage: str = "full"
    coverage_message: str | None = None


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


class RouteCrimesRequest(BaseModel):
    geometry: list[list[float]] = Field(min_length=2, max_length=20000)
    limit: int = Field(default=150, ge=1, le=500)


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
    # Neighbourhood or district the place is in, when the geocoder knows it.
    locality: str | None = None
    # Kind of place ("suburb", "station", "primary" road ...), when known.
    category: str | None = None
    # Provider identifier, e.g. "osm:N123".
    place_id: str | None = None
    # Whether SafeRoute has crime data here (Bengaluru only). Any place can be
    # chosen; outside this area routes come without a risk estimate.
    crime_data_available: bool


class LocationsResponse(BaseModel):
    results: list[LocationOut]
    # True when the geocoding provider failed and only a short built-in list
    # of Bengaluru places answered.
    degraded: bool = False
