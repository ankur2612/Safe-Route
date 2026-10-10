from fastapi import APIRouter

from ...deps import get_store

router = APIRouter()


@router.get("/health")
def health() -> dict:
    return {"status": "ok", "incidents": len(get_store().incidents)}
