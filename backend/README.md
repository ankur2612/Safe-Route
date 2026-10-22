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
| `POST /crimes/route` | incidents within 300 m of a route geometry, spread evenly along it when over `limit` |
| `GET /crimes/heatmap` | ~330 m exposure cells |
| `GET /locations/search` | places anywhere in India (Photon), with a short local fallback |
| `GET /health` | status |

Three coverage areas are kept separate:

* **Geocoding** (`/locations/search`): India (`GEOCODE_BBOX` + country code `IN`).
* **Routing** (`/routes`): wherever OSRM has roads. Routing failures return `404` (no route), `502`
  or `504`.
* **Crime risk** (`/risk/route`, `/crimes`, `/crimes/heatmap`, `/crimes/route`): Bengaluru (`BBOX`),
  where the dataset is. These endpoints return `422` with a plain-text `detail` outside it
  (`/crimes/route` accepts a route that leaves Bengaluru and returns only the records inside it).
  `/routes` for a trip with an endpoint outside Bengaluru still returns routes, but every route has
  `risk: "unknown"`, `score: null`, `segments: []`, the response has `risk_coverage: "none"` and a
  `coverage_message`, and the recommendation is the quickest route with a reason saying no risk
  estimate is available. Bengaluru records are never used to rate another place.

## Location search

`GET /locations/search?q=...` uses [Photon](https://photon.komoot.io) (OpenStreetMap data), which is
built for search-as-you-type: "kora" finds Koramangala and "korma" finds Kormangala. Nominatim was
used before, but it only matches whole words (so partial input returned nothing) and its usage
policy forbids autocomplete.

* Queries are trimmed, whitespace-collapsed and lower-cased. Fewer than 2 characters returns `422`
  (Photon rejects single characters); so do half a position or values out of range.
* Results cover India: Photon is asked for the India bounding box and every result must have country
  code `IN` (the box also overlaps neighbouring countries). Optional `latitude`/`longitude` (the
  user's position) rank nearby places first; without them the ranking leans towards Bengaluru. A
  short name that exists in many places ("baga") favours the nearby one; adding the city ("baga
  goa") finds the other. Entries without valid coordinates or for proposed/abandoned features are
  dropped; the same place returned several times is merged.
* Each result has `name`, `address` (nearest parts, state and pincode), `latitude`, `longitude`,
  `locality`, `category` (e.g. `suburb`, `station`, `primary` road), `place_id` (`osm:<type><id>`)
  and `crime_data_available` (inside Bengaluru). The response also has `degraded`.
* Successful answers are cached in memory for 6 hours, per query and ~50 km bias area.
* Throttling: at most 4 Photon requests at a time; after Photon answers `429` the backend stops
  calling it for 30 s.
* Failures are never reported as "no results". If Photon times out, errors or sends a malformed
  reply, a short built-in list of Bengaluru places answers if it matches, with `degraded: true`
  (the app labels it) and nothing cached; otherwise the endpoint returns `503`, or `429` when rate
  limited, each with a plain-text `detail`.
* Coverage depends on OpenStreetMap: a place missing or named differently there cannot be found
  (e.g. Chennai's T. Nagar is mapped as "Thyagaraya Nagar").
* Provider code is isolated in the `_photon*` functions of `app/services/geocoding.py`; replacing
  the provider means replacing those. No API key is needed. A keyed provider would read its key
  from an environment variable on the backend; it never belongs in the app.
* The public Photon server is free for fair, light use and needs a `User-Agent`; set `USER_AGENT`
  with a contact address, or point `PHOTON_URL` at your own Photon instance for heavier use. Results
  are OpenStreetMap data (© OpenStreetMap contributors, ODbL).

## Risk formula

* incident weight = severity (1-5 by crime type, see `app/services/risk.py`) x recency decay
  (half-life 3 years from the newest record);
* route exposure = total weight of distinct incidents within 300 m of the route, per km;
* score = exposure / "high reference" (90th percentile over the city, computed from the data at
  startup), capped at 1. Level: below 0.33 low, below 0.66 moderate, otherwise high.
* coverage: a route point is covered when any record lies within 1.5 km. A route with **no** covered
  points is `unknown` (shown as N/A), not `low` — an absence of records is not evidence of low
  exposure. When less than half of a route is covered, the reason says the estimate may be
  incomplete.

Recommendation: `fastest` = shortest time; `lower_risk` = lowest score; `balanced` = best mix of
extra travel time (capped at +50%) and score. Routes with `unknown` risk never win `lower_risk` or
`balanced`; if every route is `unknown`, the quickest is recommended and the reason says no data is
available. Wording always says "estimated historical crime exposure" and never calls a route safe.

## Configuration (environment variables, all optional)

`OSRM_URL`, `PHOTON_URL`, `USER_AGENT`, `HTTP_TIMEOUT`, `GEOCODER_TIMEOUT` (default 5 s),
`GEOCODE_COUNTRY` (default `IN`), `CRIMES_CSV` - see `.env.example`. The public OSRM and Photon
servers are for light demo use only.

## Tests

`.venv/bin/python -m pytest -q` runs offline: Photon and OSRM are mocked. `LIVE_GEOCODER=1` adds a
check that the real Photon server finds the sample places listed in `tests/test_geocoding.py`
(Bengaluru localities and places in other cities). A handful of passing samples does not prove
every Indian locality is searchable; that depends on OpenStreetMap's data.
