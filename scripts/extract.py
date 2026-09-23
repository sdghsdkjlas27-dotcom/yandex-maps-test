#!/usr/bin/env python3
"""Extract search results from a uiautomator dump and build result.json.

Only texts actually present in the UI dump are used. No fabricated data.
"""
import json
import os
import re
import sys
import xml.etree.ElementTree as ET

CHROME = {
    "search here", "поиск здесь", "search", "поиск", "search here…",
    "where to?", "где?", "navigator", "навигатор", "transport", "транспорт",
    "ride", "поездки", "nearby", "рядом", "favourites", "избранное",
    "downloads", "загрузки", "later", "позже", "allow", "разрешить",
    "don't allow", "ok", "ок", "accept", "accept all", "maps", "карты",
    "for you", "для вас", "weather", "погода", "settings", "настройки",
    "log in", "войти", "sign in", "offline maps", "офлайн-карты",
    "get started", "начать", "skip", "пропустить", "my location",
    "моё местоположение", "route", "маршрут", "traffic", "пробки",
    "zoom in", "zoom out", "compass", "layers", "слои", "user interface",
    "план", "scheme", "схема", "satellite", "спутник",
}
DISTANCE = re.compile(r"^\d+\s*(m|м|km|км|min|мин|h|ч|сут|дн)\.?$", re.I)
TIME = re.compile(r"^\d{1,2}:\d{2}$")
ADDRESS = re.compile(
    r"(ул\.|улица|шоссе|ш\.|проспект|просп|пр-т|пр-д|проезд|наб\.|"
    r"street|road|highway|blvd|ave|drive|lane|"
    r"д\.|дом|вл\d|к\d|корп|строф|владен)",
    re.I,
)


def nodes(root):
    yield root
    for child in root:
        yield from nodes(child)


def significant_texts(path):
    tree = ET.parse(path)
    seen = set()
    out = []
    for n in nodes(tree.getroot()):
        for attr in ("text", "content-desc"):
            t = (n.get(attr) or "").strip()
            if not t or len(t) < 2:
                continue
            key = t.lower()
            if key in CHROME or DISTANCE.match(t) or TIME.match(t):
                continue
            if t in seen:
                continue
            seen.add(t)
            out.append(t)
    return out


def main(xml_path, out_path):
    query = os.environ.get("QUERY", "")
    lat = os.environ.get("LAT", "")
    lon = os.environ.get("LON", "")
    gps_verified = os.environ.get("GPS_VERIFIED", "false") == "true"
    search_method = os.environ.get("SEARCH_METHOD", "unknown")

    result = {
        "query": query,
        "latitude": float(lat) if lat else None,
        "longitude": float(lon) if lon else None,
        "gps_verified": gps_verified,
        "search_method": search_method,
        "success": False,
        "results": [],
    }

    try:
        texts = significant_texts(xml_path)
    except Exception as e:
        result["error"] = f"failed to parse UI dump: {e}"
        texts = []

    result["extracted_texts"] = texts[:30]

    # pair name -> following address-like text
    results = []
    pending_addr = None
    for t in texts:
        is_addr = bool(re.search(r"\d", t)) and (ADDRESS.search(t) or "," in t)
        if is_addr:
            if results and not results[-1].get("address"):
                results[-1]["address"] = t
            else:
                pending_addr = t
        else:
            entry = {"name": t, "address": ""}
            if pending_addr:
                entry["address"] = pending_addr
                pending_addr = None
            results.append(entry)
    result["results"] = results[:10]
    result["success"] = len(results) > 0

    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, indent=2)
    print(f"extracted {len(results)} results, {len(texts)} raw texts")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2]))
