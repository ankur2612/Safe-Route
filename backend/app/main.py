"""SafeRoute API. Run with: uvicorn app.main:app --host 0.0.0.0 --port 8000"""
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from .api.v1 import crimes, health, locations, risk, routes
from .deps import init_engine


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Fails loudly (and refuses to start) if the dataset is missing or empty.
    init_engine()
    yield


app = FastAPI(title="SafeRoute API", version="1.0.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"]
)


@app.exception_handler(RequestValidationError)
async def validation_error(_: Request, exc: RequestValidationError) -> JSONResponse:
    # The app shows `detail` when it is a string, so flatten FastAPI's list.
    first = exc.errors()[0] if exc.errors() else {}
    where = ".".join(str(p) for p in first.get("loc", ())[1:])
    message = f"Invalid request: {where} - {first.get('msg', 'invalid value')}" if where else "Invalid request."
    return JSONResponse(status_code=422, content={"detail": message})


for module in (health, routes, risk, crimes, locations):
    app.include_router(module.router, prefix="/api/v1")
