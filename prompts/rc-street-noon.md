# Wave 4 task: rc-street-noon (kind: refcam)

Branch `wt/rc-street-noon`, stills on `shots/rc-street-noon`.

Reference camera street_noon (Flower at Olympic, downtown, eye height, 12:00 clear): what reads fake first at eye level at noon. Likely: the pavement and kerb up close, the parked cars' tyres and their contact, the building bases and doors, people's faces and walks, the traffic's spacing, the sky's brightness against the street. Fix the worst three to five, hold the other nine cameras.

If `origin/wt/rc-street-noon` already exists (an earlier launch of this task, or a paused session, pushed it), CONTINUE it: check it out and merge origin/main into it. Same for `shots/rc-street-noon`.
Push your branch as soon as you have a first commit and at least every hour; before the final push merge origin/main and pass `SHARDS=3 tests/headless_check.sh`. End with the report the brief asks for.
