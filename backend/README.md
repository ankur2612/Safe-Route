# SafeRoute backend

FastAPI service for the SafeRoute Flutter app. All data is held in memory; there is no database.

## Run

```bash
cd backend
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
.venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Interactive docs: http://localhost:8000/docs  ·  Health: `GET /api/v1/health`

Tests: `.venv/bin/python -m pytest -q`

## Data

`data/source/bengaluru_crime_dataset.xlsx` is a **synthetic** dataset (see its "DISCLAIMER" sheet),
so risk scores are illustrative only. `scripts/ingest_xlsx.py` converts it to `data/crimes.csv`
(Excel date serials -> ISO dates, rows outside the Bengaluru bounding box dropped). The server loads
the CSV once at startup and refuses to start if it is missing or empty. Re-run the script only if
the xlsx changes. All dataset access goes through `app/data/store.py`.

## Endpoints (`/api/v1`)

| Endpoint | Purpose |
| --- | --- |
| `POST /routes` | OSRM routes (up to 3) + risk per route + recommendation for the preference |
| `POST /risk/route` | risk for one geometry |
| `GET /crimes` | nearest historical incidents |
| `GET /crimes/heatmap` | ~330 m exposure cells |
| `GET /locations/search` | Bengaluru places: local list first, Nominatim after (works if Nominatim is down) |
| `GET /health` | status |

Requests outside Bengaluru return `422` with a plain-text `detail`, which the app shows directly.
Routing failures return `404` (no route), `502` or `504`.

## Risk formula

* incident weight = severity (1-5 by crime type, see `app/services/risk.py`) x recency decay
  (half-life 3 years from the newest record);
* route exposure = total weight of distinct incidents within 300 m of the route, per km;
* score = exposure / "high reference" (90th percentile over the city, computed from the data at
  startup), capped at 1. Level: below 0.33 low, below 0.66 moderate, otherwise high.

Recommendation: `fastest` = shortest time; `lower_risk` = lowest score; `balanced` = best mix of
extra travel time (capped at +50%) and score. Wording always says "estimated historical crime
exposure" and never calls a route safe.

## Configuration (environment variables, all optional)

`OSRM_URL`, `NOMINATIM_URL`, `USER_AGENT`, `HTTP_TIMEOUT`, `CRIMES_CSV` - see `.env.example`.
The public OSRM and Nominatim servers are for light demo use only.
