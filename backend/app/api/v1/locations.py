from fastapi import APIRouter, Query

from ...schemas import LocationOut, LocationsResponse
from ...services import geocoding

router = APIRouter()


@router.get("/locations/search", response_model=LocationsResponse)
async def search(q: str = Query(min_length=1, max_length=100)) -> LocationsResponse:
    places = await geocoding.search(q)
    return LocationsResponse(
        results=[
            LocationOut(name=p.name, address=p.address, latitude=p.latitude, longitude=p.longitude)
            for p in places
        ]
    )
