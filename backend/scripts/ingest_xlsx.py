"""One-off: convert the Bengaluru crime xlsx into a cleaned CSV.

Uses only the standard library (an .xlsx is a zip of XML files).

    python scripts/ingest_xlsx.py
"""
import csv
import re
import sys
import zipfile
import xml.etree.ElementTree as ET
from datetime import date, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
from app.config import BBOX  # noqa: E402

SRC = ROOT / "data" / "source" / "bengaluru_crime_dataset.xlsx"
OUT = ROOT / "data" / "crimes.csv"
NS = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"


def read_sheet1(path: Path) -> list[dict[str, str]]:
    z = zipfile.ZipFile(path)
    shared = [
        "".join(t.text or "" for t in si.iter(NS + "t"))
        for si in ET.fromstring(z.read("xl/sharedStrings.xml")).findall(NS + "si")
    ]
    rows = []
    for r in ET.fromstring(z.read("xl/worksheets/sheet1.xml")).iter(NS + "row"):
        cells = {}
        for c in r.findall(NS + "c"):
            v = c.find(NS + "v")
            if v is None:
                continue
            col = re.match(r"[A-Z]+", c.get("r")).group()
            cells[col] = shared[int(v.text)] if c.get("t") == "s" else v.text
        rows.append(cells)
    header = rows[0]
    return [{header[k]: v for k, v in row.items() if k in header} for row in rows[1:]]


def main() -> None:
    records = read_sheet1(SRC)
    kept, dropped = [], []
    for rec in records:
        try:
            lat, lon = float(rec["Latitude"]), float(rec["Longitude"])
            when = date(1899, 12, 30) + timedelta(days=int(float(rec["Date"])))
        except (KeyError, ValueError):
            dropped.append((rec.get("#"), "bad number/date"))
            continue
        if not (BBOX["min_lat"] <= lat <= BBOX["max_lat"] and BBOX["min_lon"] <= lon <= BBOX["max_lon"]):
            dropped.append((rec.get("#"), f"outside Bengaluru ({lat}, {lon})"))
            continue
        kept.append({
            "id": f"incident-{rec['#']}",
            "type": rec["Crime Type"].strip(),
            "description": rec.get("Description", "").strip(),
            "area": rec.get("Location", "").strip(),
            "district": rec.get("District", "").strip(),
            "date": when.isoformat(),
            "latitude": f"{lat:.5f}",
            "longitude": f"{lon:.5f}",
        })

    OUT.parent.mkdir(parents=True, exist_ok=True)
    with OUT.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(kept[0]))
        w.writeheader()
        w.writerows(kept)

    print(f"read {len(records)}, kept {len(kept)}, dropped {len(dropped)} -> {OUT}")
    for rid, why in dropped[:20]:
        print(f"  dropped #{rid}: {why}")


if __name__ == "__main__":
    main()
