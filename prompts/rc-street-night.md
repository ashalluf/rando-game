# Wave 4 task: rc-street-night (kind: refcam)

Branch `wt/rc-street-night`, stills on `shots/rc-street-night`.

Reference camera street_night (Flower at Olympic, 21:30, rain): what reads fake first at night in the rain. Coordinate with nobody: wet-road-mirror owns road.gdshader's mirrored_city(), so leave that function alone and work on everything else in the frame: lamp halos and their colour, lit windows and signs, the people's wet clothes and umbrellas, the rain's visibility, car lights on the wet road, the sky's glow. Fix the worst three to five, hold the other nine cameras.

If `origin/wt/rc-street-night` already exists (an earlier launch of this task, or a paused session, pushed it), CONTINUE it: check it out and merge origin/main into it. Same for `shots/rc-street-night`.
Push your branch as soon as you have a first commit and at least every hour; before the final push merge origin/main and pass `SHARDS=3 tests/headless_check.sh`. End with the report the brief asks for.
