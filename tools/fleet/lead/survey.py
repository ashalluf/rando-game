import json,sys
s=open(sys.argv[1]).read()
i=s.find('{"ccr"'); j=s.rfind('}')
d=json.loads(s[i:j+1])
wave="star-boulevard fashion-district parklets prop-destruction car-panic onlookers rain-crowd motorcycles lowriders engine-audio freeway-incidents coast-highway backyards garage-drive-in walk-in-store swimming heli-flyable apartments tower-gondolas street-furniture wingsuit stunt-ramps car-cabins ragdolls news-crews".split()
for r in d["ccr"]["data"]:
    t=r.get("title","").replace("fleet2: ","")
    if t in wave:
        meta=r.get("external_metadata",{}) or {}
        ps=(meta.get("post_turn_summary") or {}).get("status_detail","")
        print(f'{t:18} {r.get("status_bucket","").replace("SESSION_STATUS_BUCKET_",""):12} {r.get("updated_at","")[11:16]} {ps[:90]}')
