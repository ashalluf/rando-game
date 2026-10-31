# Wave 4 task: night-lamps-review (kind: new)

Branch `wt/night-lamps-review`, stills on `shots/night-lamps-review`.

Street lamps at night at eye level: the lamp heads' glare and halo size, the pools' shape and colour (sodium vs LED per patch), the shadows under cars and people from the nearest lamps (the OmniLights cast none: a budgeted shadow on the nearest two on HIGH), the lit faces of the facades. NightAtmos / StreetLamps / DayNight.lamp_scale; a small Forward+ scene under lavapipe; hold the night refcam's numbers within tolerance. Use tools/night_street/shoot_fwd.sh. wet-road-mirror owns road.gdshader's mirrored_city(); rc-street-night judges the whole frame. You own the lamps and their light.

If `origin/wt/night-lamps-review` already exists (an earlier launch of this task, or a paused session, pushed it), CONTINUE it: check it out and merge origin/main into it. Same for `shots/night-lamps-review`.
Push your branch as soon as you have a first commit and at least every hour; before the final push merge origin/main and pass `SHARDS=3 tests/headless_check.sh`. End with the report the brief asks for.
