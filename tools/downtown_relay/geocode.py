#!/usr/bin/env python3
"""Geocode a fixed list of downtown LA landmark / anchor points through Nominatim.

Strictly one request per 1.2 s, every answer cached in geocode_cache.json (never re-fetched).
Usage: python3 geocode.py points.txt   (lines: key|query ; '#' comments)
"""
import json, os, sys, time, urllib.parse, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, "geocode_cache.json")
UA = "rando-game-dev/0.1"
GAP = 3.0


def load():
    if os.path.exists(CACHE):
        with open(CACHE) as f:
            return json.load(f)
    return {}


def save(c):
    with open(CACHE + ".tmp", "w") as f:
        json.dump(c, f, indent=1, sort_keys=True)
    os.replace(CACHE + ".tmp", CACHE)


def main():
    cache = load()
    lines = [l.strip() for l in open(sys.argv[1]) if l.strip() and not l.startswith("#")]
    last = 0.0
    for l in lines:
        parts = [s.strip() for s in l.split("|")]
        key, q = parts[0], parts[1]
        params = {"q": q, "format": "json", "limit": 3}
        if len(parts) > 2:
            # Street centre-line points: every OSM way of that name inside the downtown box.
            params.update({"limit": 10, "dedupe": 0, "bounded": 1,
                "viewbox": "-118.2860,34.0680,-118.2250,34.0280"})
            if parts[2] != "street":
                params["viewbox"] = parts[2]
        if key in cache and cache[key].get("query") == q:
            continue
        url = "https://nominatim.openstreetmap.org/search?" + urllib.parse.urlencode(params)
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        res = None
        for attempt in range(4):
            wait = GAP - (time.time() - last)
            if wait > 0:
                time.sleep(wait)
            last = time.time()
            try:
                with urllib.request.urlopen(req, timeout=30) as r:
                    res = json.load(r)
                break
            except Exception as e:  # 429: the IP is shared with other agents; back off hard
                print("ERR", key, e, flush=True)
                time.sleep(30 * (attempt + 1))
        if res is None:
            continue
        cache[key] = {"query": q, "results": [
            {k: x.get(k) for k in ("lat", "lon", "class", "type", "osm_type", "osm_id", "display_name", "boundingbox")}
            for x in res]}
        save(cache)
        top = res[0] if res else None
        print(key, "->", (top["lat"], top["lon"], top["class"], top["type"], top["display_name"][:90]) if top else "NONE")
    print("cached:", len(cache))


if __name__ == "__main__":
    main()
