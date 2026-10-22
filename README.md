# SafeRoute — Mobile App (Flutter)

Frontend for SafeRoute, a route comparison app that considers historical crime
exposure alongside travel time and distance.

This repository contains the **Flutter app** (repo root) and the **FastAPI
backend** (`backend/`, see `backend/README.md`). Route generation, crime
analysis and all risk calculation belong to the backend; the app displays what
the backend returns. The supported area is Bengaluru.

## Running

```bash
flutter pub get
flutter run
```

### Configuration

The backend URL and the sample-data switch are supplied with `--dart-define`,
so nothing environment-specific is committed:

```bash
# Against a local backend (10.0.2.2 is the host machine from an Android emulator)
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000 --dart-define=USE_MOCK_DATA=false

# Using built-in sample data (default, backend not required)
flutter run --dart-define=USE_MOCK_DATA=true
```

| Key             | Default                | Purpose                                   |
| --------------- | ---------------------- | ----------------------------------------- |
| `API_BASE_URL`  | `http://10.0.2.2:8000` | Base URL of the FastAPI backend           |
| `USE_MOCK_DATA` | `true` in debug, `false` in release | Serve sample data instead of calling APIs |

**Sample data is on by default in debug builds only**, so `flutter run` works
without the backend. All of it lives in `lib/data/mock_data.dart`. Sample mode
is for UI work only: search knows eight places (the search screen shows a
"Sample data mode" banner), the routes, risk levels and recommendation are
written by hand, and crime markers are generated around whatever point is asked
for. **Release builds use the real backend** unless `USE_MOCK_DATA=true` is
passed, so an APK never presents the sample list as real search. India-wide
search, real routes, real historical records and route-corridor markers all
need the backend. Start it (`backend/README.md`) and pass its URL:

| Where the app runs | `API_BASE_URL` |
| --- | --- |
| Android emulator | `http://10.0.2.2:8000` (default) |
| iOS simulator | `http://localhost:8000` |
| Physical phone | `http://<your computer's LAN IP>:8000` (same Wi-Fi) |

Plain `http` is allowed in debug and profile builds only (Android debug/profile
manifests and an iOS local-networking exception). A release build needs an
`https` backend.

Routes start from the device's position, anywhere in India (central
Bengaluru only when there is no GPS fix). Crime-risk estimates and crime
markers exist only for Bengaluru; see "Coverage" below.

### Release APK against a backend

```bash
flutter build apk --release --dart-define=API_BASE_URL=https://your-backend.example.com
```

`API_BASE_URL` must be `https` for a release build. For a quick test on a
phone on the same Wi-Fi, use a debug build instead:

```bash
flutter run --dart-define=USE_MOCK_DATA=false --dart-define=API_BASE_URL=http://<your computer's LAN IP>:8000
```

The backend must listen on all interfaces (`uvicorn ... --host 0.0.0.0`), and
Windows Firewall must allow port 8000; check from the phone's browser that
`http://<LAN IP>:8000/api/v1/health` answers before testing the app.

### Troubleshooting connection errors

The app names the failure instead of assuming the phone is offline:

| Message starts with | Meaning |
| --- | --- |
| "This build is not connected to a SafeRoute server" | Release build made without `API_BASE_URL`, so it still points at `10.0.2.2` (the emulator's alias for the development computer). Rebuild with the server's URL. |
| "Couldn't connect to the SafeRoute server (host:port)" | Nothing answered at that address: server stopped, wrong IP, firewall, or phone on another network. |
| "Couldn't find the SafeRoute server" | The server's name did not resolve (wrong hostname, or no internet). |
| "Couldn't make a secure connection" | TLS/certificate problem with the https server. |
| "... did not respond in time" | The server was reached but too slow (search waits 12 s, other requests 20 s). |
| "Location search is temporarily unavailable" / "Too many searches" | The backend works but its geocoder (Photon) failed or rate-limited it. |

## Project structure

```text
lib/
├── data/          sample data used only while the backend is unavailable
├── models/        API response models (route, risk, crime, heatmap, location)
├── navigation/    named routes
├── providers/     app state (location, routes, crime data)
├── screens/       splash, map/home, destination search, comparison, about risk
├── services/      HTTP client and one service per API area
├── utils/         config, theme, JSON helpers
├── widgets/       reusable UI (map, cards, risk badge, states)
└── main.dart
```

## Backend endpoints used

| Endpoint                     | Used by                          |
| ---------------------------- | -------------------------------- |
| `POST /api/v1/routes`        | `RouteService.generateRoutes`    |
| `POST /api/v1/risk/route`    | `RouteService.calculateRouteRisk` |
| `GET  /api/v1/crimes`        | `CrimeService.fetchCrimes`       |
| `POST /api/v1/crimes/route`  | `CrimeService.fetchRouteCrimes`  |
| `GET  /api/v1/crimes/heatmap`| `CrimeService.fetchHeatmap`      |
| `GET  /api/v1/locations/search` | `LocationSearchService.search` |

### Destination search

Search covers **all of India** through the backend's geocoder (Photon /
OpenStreetMap, see `backend/README.md`): cities, neighbourhoods, layouts,
roads, landmarks, stations and pincodes, including partial names and small
misspellings. There is no built-in place list behind it.

The search screen queries 300 ms after typing stops, from 2 characters (the
geocoder rejects single characters). The device position is sent so nearby
places rank first. Replies for text the user has since changed or cleared are
dropped, earlier suggestions stay visible (with a progress bar) while the next
ones load, and answers are cached for ten minutes. "No results" appears only
after a successful search; network failures, rate limits and geocoder outages
show an error with **Try Again**. Results outside Bengaluru are marked "No
crime-risk estimate here".

### Coverage

| | Where | What happens outside |
| --- | --- | --- |
| Search (geocoding) | India | — |
| Routing | wherever the routing server (OSRM) has roads | `404` "No route could be found" |
| Crime risk and crime markers | Bengaluru (the crime dataset) | Routes come back with risk **N/A** (no score) and the message "Crime-risk estimates are available only for trips within Bengaluru"; the recommendation is the quickest route, never a "safer" one |

### Crime layers

The map shows historical records around the **start**, around the
**destination**, and within the 300 m corridor of **every candidate route**
(the same corridor the risk score counts). Each area is requested once and
cached, records returned by several areas appear once, and the markers stay on
the map while the preference changes. Routes are framed with both endpoints in
view. When an area has no records the app says that this means *no data*,
never lower exposure, and a failed request is shown as an error, not as an
empty area.

### Open in Google Maps

Every route card has an **Open in Google Maps** action. It opens a Google Maps
directions link (`https://www.google.com/maps/dir/?api=1&...`, driving) with
the trip's start and destination coordinates and up to three points from that
route's geometry as waypoints, so Google Maps follows roughly the same
corridor. Google Maps still calculates its own route and may pick different
roads; SafeRoute's risk estimate applies only to the route SafeRoute
calculated, and the app says so under the route list. The link opens in the
Google Maps app when installed, otherwise the browser; if neither can open it
the app shows a message.

`POST /api/v1/incidents` (user incident reports) is a future feature and is not
implemented. `test/fixtures/*.json` are real backend responses, and
`test/backend_contract_test.dart` checks the app's models against them.

### Expected response shapes

The models accept reasonable variations and skip malformed entries rather than
failing. Routes:

```json
{
  "routes": [
    {
      "id": "route-b",
      "name": "Route B",
      "duration_minutes": 18,
      "distance_km": 6.0,
      "geometry": [[28.61, 77.21], [28.63, 77.23]],
      "risk": {
        "risk": "low",
        "score": 0.24,
        "reason": "Lower estimated historical crime exposure"
      }
    }
  ],
  "recommendation": {
    "route_id": "route-b",
    "reason": "Lower estimated historical crime exposure than the alternatives."
  }
}
```

`duration`/`distance` in seconds and metres are also accepted. A missing or
unrecognised `risk` becomes `N/A` in the UI — never a guessed level. The
backend sends `"unknown"` for a route with no historical records near it,
which is shown as `N/A`.

Location results also carry an optional `locality` (neighbourhood/district).

## Risk calculation

The app performs **no** risk calculation. Crime density, severity, recency and
any ML prediction are the backend's responsibility. The frontend reads
`risk`, `score` and `reason` and renders them.

Risk wording follows the PRD's safety rules: the app never describes a route as
safe, only as having lower, moderate or higher *estimated historical crime
exposure*, and it always states that the result comes from historical data.

## Tests

```bash
flutter test
```

Covers splash navigation, destination search and autocomplete (debounce,
stale replies, loading/empty/error states, normalisation, caching), route cards
and the Google Maps action (URL format, encoding, waypoints, launch fallback),
crime layers for origin/destination/routes (deduplication, persistence across
preference changes, empty vs failed), risk badges, preference selection, the
recommendation, model parsing of imperfect responses, and the home screen's
loading/empty/error states. Network calls are faked; no test needs the
internet.

## Permissions

Location (`ACCESS_FINE_LOCATION` / `NSLocationWhenInUseUsageDescription`) is
requested to show the user's position. Denial is handled in the UI and does not
crash the app.

Map tiles come from OpenStreetMap. Review the
[OSM tile usage policy](https://operations.osmfoundation.org/policies/tiles)
before any public deployment.
