#!/usr/bin/env python3
"""Resolve a merge conflict in tools/refcams/cameras_w5.json by keeping every camera row.

usage (inside the checkout with the conflicted merge):
    python3 tools/fleet/resolve_cameras.py

Wave 5's refcam2 sessions each append one row to the same file, so every merge after the first
conflicts there. This reads our side (:2:) and theirs (:3:), keeps the longer "_doc", the
resolution, and the union of the camera rows by name (ours first, a name in both: theirs wins),
writes one row a line and stages the file.
"""
import json
import subprocess

PATH = "tools/refcams/cameras_w5.json"


def side(n):
	r = subprocess.run(["git", "show", f":{n}:{PATH}"], capture_output=True, text=True)
	return json.loads(r.stdout) if r.returncode == 0 and r.stdout.strip() else {"cameras": []}


ours, theirs = side(2), side(3)
doc = max(ours.get("_doc", ""), theirs.get("_doc", ""), key=len)
res = theirs.get("resolution") or ours.get("resolution") or [1280, 720]
rows = {}
for c in ours.get("cameras", []) + theirs.get("cameras", []):
	rows[c["name"]] = c
lines = ",\n".join("\t\t" + json.dumps(c) for c in rows.values())
out = "{\n\t\"_doc\": %s,\n\t\"resolution\": %s,\n\t\"cameras\": [\n%s\n\t]\n}\n" % (json.dumps(doc), json.dumps(res), lines)
json.loads(out)
open(PATH, "w").write(out)
subprocess.run(["git", "add", PATH], check=True)
print("cameras_w5.json: %d rows (%s)" % (len(rows), ", ".join(rows)))
