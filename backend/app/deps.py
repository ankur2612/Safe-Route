"""Shared singletons (crime store + risk engine) created at startup."""
from .data.store import CrimeStore, get_store, init_store
from .services.risk import RiskEngine

_engine: RiskEngine | None = None


def init_engine(store: CrimeStore | None = None) -> RiskEngine:
    global _engine
    _engine = RiskEngine(init_store(store))
    return _engine


def get_engine() -> RiskEngine:
    if _engine is None:
        raise RuntimeError("Risk engine not initialised.")
    return _engine


__all__ = ["get_engine", "get_store", "init_engine"]
