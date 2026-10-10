"""Settings read from environment variables, with safe defaults."""
import os
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent

CRIMES_CSV = Path(os.getenv("CRIMES_CSV", BASE_DIR / "data" / "crimes.csv"))

OSRM_URL = os.getenv("OSRM_URL", "https://router.project-osrm.org").rstrip("/")
NOMINATIM_URL = os.getenv("NOMINATIM_URL", "https://nominatim.openstreetmap.org").rstrip("/")
USER_AGENT = os.getenv("USER_AGENT", "SafeRouteCollegeProject/1.0")

HTTP_TIMEOUT = float(os.getenv("HTTP_TIMEOUT", "10"))

# Supported area: Bengaluru. Anything outside is rejected or filtered.
BBOX = {"min_lat": 12.70, "max_lat": 13.30, "min_lon": 77.35, "max_lon": 77.80}
CITY_CENTER = (12.9716, 77.5946)
