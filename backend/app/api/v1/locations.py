from fastapi import APIRouter, HTTPException, Query

from ...schemas import LocationOut, LocationsResponse
from ...services import geocoding

router = APIRouter()


@router.get("/locations/search", response_model=LocationsResponse)
async def search(
    q: str = Query(min_length=1, max_length=100),
    latitude: float | None = Query(default=None, ge=-90, le=90),
    longitude: float | None = Query(default=None, ge=-180, le=180),
) -> LocationsResponse:
    """Places in India matching ``q``, ranked towards ``latitude``/``longitude`` if given."""
    if len(geocoding.normalize_query(q).replace(" ", "")) < geocoding.MIN_QUERY_CHARS:
        raise HTTPException(422, f"Type at least {geocoding.MIN_QUERY_CHARS} characters to search.")
    if (latitude is None) != (longitude is None):
        raise HTTPException(422, "Give both latitude and longitude, or neither.")
    near = (latitude, longitude) if latitude is not None and longitude is not None else None

    try:
        result = await geocoding.search(q, near=near)
    except geocoding.GeocoderUnavailable as err:
        # Distinct from an empty result: the app shows a retryable error
        # instead of "no match".
        raise HTTPException(429 if err.rate_limited else 503, str(err))
    return LocationsResponse(
        results=[
            LocationOut(
                name=p.name,
                address=p.address,
                latitude=p.latitude,
                longitude=p.longitude,
                locality=p.locality,
                category=p.category,
                place_id=p.place_id,
                crime_data_available=p.crime_data_available,
            )
            for p in result.places
        ],
        degraded=result.degraded,
    )
