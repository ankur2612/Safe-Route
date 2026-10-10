"""Pick which route to recommend for a preference."""
from dataclasses import dataclass


@dataclass(frozen=True)
class Candidate:
    id: str
    duration_minutes: int
    score: float


def _balanced_cost(c: Candidate, fastest_minutes: int) -> float:
    # Extra travel time relative to the fastest route, saturating at +50%.
    extra = (c.duration_minutes / max(fastest_minutes, 1)) - 1
    time_cost = min(max(extra, 0.0) / 0.5, 1.0)
    return 0.5 * time_cost + 0.5 * c.score


def recommend(candidates: list[Candidate], preference: str) -> tuple[str, str]:
    """Return (route_id, reason). ``candidates`` must be non-empty."""
    fastest = min(candidates, key=lambda c: (c.duration_minutes, c.score))
    lowest = min(candidates, key=lambda c: (c.score, c.duration_minutes))

    if preference == "fastest":
        return fastest.id, (
            "This is the quickest option."
            if fastest.id == lowest.id
            else "This is the quickest option, though other routes have lower "
            "estimated historical crime exposure."
        )

    if preference == "lower_risk":
        extra = lowest.duration_minutes - fastest.duration_minutes
        if lowest.id == fastest.id:
            return lowest.id, (
                "Lowest estimated historical crime exposure, and also the quickest."
            )
        return lowest.id, (
            "Lowest estimated historical crime exposure of the options, "
            f"for about {max(extra, 0)} extra minutes of travel."
        )

    best = min(candidates, key=lambda c: (_balanced_cost(c, fastest.duration_minutes), c.duration_minutes))
    extra = best.duration_minutes - fastest.duration_minutes
    if best.id == fastest.id:
        return best.id, "Best balance of travel time and estimated historical crime exposure."
    return best.id, (
        f"Only about {max(extra, 0)} minutes slower than the quickest route, with lower "
        "estimated historical crime exposure."
    )
