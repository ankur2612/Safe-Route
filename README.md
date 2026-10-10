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
| `USE_MOCK_DATA` | `true`                 | Serve sample data instead of calling APIs |

**Sample data is on by default**, so the app runs without the backend. All of
it lives in `lib/data/mock_data.dart`. To use the real backend, start it
(`backend/README.md`) and run with `USE_MOCK_DATA=false`:

| Where the app runs | `API_BASE_URL` |
| --- | --- |
| Android emulator | `http://10.0.2.2:8000` (default) |
| iOS simulator | `http://localhost:8000` |
| Physical phone | `http://<your computer's LAN IP>:8000` (same Wi-Fi) |

Plain `http` is allowed in debug and profile builds only (Android debug/profile
manifests and an iOS local-networking exception). A release build needs an
`https` backend.

If the device's GPS is outside Bengaluru, the app uses central Bengaluru
instead, because the data and routing cover Bengaluru only.

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
| `GET  /api/v1/crimes/heatmap`| `CrimeService.fetchHeatmap`      |
| `GET  /api/v1/locations/search` | `LocationSearchService.search` |

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
unrecognised `risk` becomes `N/A` in the UI — never a guessed level.

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

Covers splash navigation, destination search, route cards, risk badges,
preference selection, the recommendation, provider state transitions, model
parsing of imperfect responses, and the home screen's loading/empty/error
states.

## Permissions

Location (`ACCESS_FINE_LOCATION` / `NSLocationWhenInUseUsageDescription`) is
requested to show the user's position. Denial is handled in the UI and does not
crash the app.

Map tiles come from OpenStreetMap. Review the
[OSM tile usage policy](https://operations.osmfoundation.org/policies/tiles)
before any public deployment.
