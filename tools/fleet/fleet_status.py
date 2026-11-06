"""Summarise the fleet from a saved list_sessions dump.

usage: python3 tools/fleet/fleet_status.py <list_sessions output file> <roster file>
The roster file has one "<slug> <session id>" per line. The dump is what the claude-code-remote
list_sessions tool saves when its result is too long to show (JSON after a short header).
Prints slug, session status, status bucket, last update and the session's own one-line summary.
"""
import json, sys
s = open(sys.argv[1]).read()
i = s.find('{'); d, _ = json.JSONDecoder().raw_decode(s[i:])
roster = {}
for ln in open(sys.argv[2]):
    p = ln.split()
    if len(p) == 2: roster[p[1]] = p[0]
for it in d['ccr']['data']:
    sid = it['id']
    if sid not in roster: continue
    em = it.get('external_metadata') or {}
    pts = em.get('post_turn_summary') or {}
    print(roster[sid].ljust(18), it['session_status'].replace('SESSION_STATUS_', '').ljust(8),
          (it.get('status_bucket') or '').replace('SESSION_STATUS_BUCKET_', '').ljust(13),
          it.get('updated_at', '')[11:19], (pts.get('status_detail') or '')[:70])
