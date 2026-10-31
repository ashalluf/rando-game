# night-lamps-review stills (first batch)

Forward+ under lavapipe (the Mac's renderer), `tools/night_lamps/lamp_street.tscn`: a small street
with the real lamp kit, Buildings, a car and people, the city's own DayNight at 21:30.
"before" = `NIGHT_LAMPS=0` (main's lamps), "after" = this branch.

- 01 / 02: down the street (02 is the after in rain: wet streaks flare and glint).
- 03 / 04: the twin lamp with a car and a person: the street is lit now, and the two nearest lamps cast real shadows.
- 05: a sodium patch: deep amber light, pools under each lamp falling off between them.
- 06 / 07: wet road: the reflections were pencil-thin rods; now broken, flaring columns.
- 08 / 09: a cobra: its light now reaches the road and the facades.

Second batch (opengl3, the Compatibility renderer = web; not the Mac):
- 10 / 11: the street_night refcam before / after the first pass (p50 34 -> 37, p95 138 -> 143).
  The first pass's wet streaks read as glowing cones there; 12 / 13 are the final soft, tapering
  streaks on the lamp street (the refcam is re-shot at the end).
- 14: the street_night refcam, final (p5/p50/p95 8/39/139 against 8/34/138 before; pier_night unchanged).
