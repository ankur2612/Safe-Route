"""Settings read from environment variables, with safe defaults."""
import os
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent

CRIMES_CSV = Path(os.getenv("CRIMES_CSV", BASE_DIR / "data" / "crimes.csv"))

OSRM_URL = os.getenv("OSRM_URL", "https://router.project-osrm.org").rstrip("/")
# Photon (OpenStreetMap data) is built for search-as-you-type; Nominatim's
# usage policy forbids autocomplete and it does not match partial words.
PHOTON_URL = os.getenv("PHOTON_URL", "https://photon.komoot.io").rstrip("/")
USER_AGENT = os.getenv("USER_AGENT", "SafeRouteCollegeProject/1.0")

HTTP_TIMEOUT = float(os.getenv("HTTP_TIMEOUT", "10"))
# Autocomplete must answer quickly or fall back to the local list.
GEOCODER_TIMEOUT = float(os.getenv("GEOCODER_TIMEOUT", "5"))

# Crime-risk coverage: Bengaluru, where the crime dataset is. Crime and risk
# endpoints reject points outside it; routes outside it get no risk estimate.
BBOX = {"min_lat": 12.70, "max_lat": 13.30, "min_lon": 77.35, "max_lon": 77.80}
CITY_CENTER = (12.9716, 77.5946)

# Geocoding coverage: destination search covers India. The box is only a
# coarse pre-filter; results must also carry this country code.
GEOCODE_BBOX = {"min_lat": 6.5, "max_lat": 35.7, "min_lon": 68.1, "max_lon": 97.5}
GEOCODE_COUNTRY = os.getenv("GEOCODE_COUNTRY", "IN").upper()
