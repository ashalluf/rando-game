# Micromobility stills (branch wt/scooters, HANDOFF 9bu)

opengl3 (Compatibility) stills, 1280x720, `--quality=0`; the "before" frames are the same EYE with `MICROMOBILITY=0`.

- `lane_day.jpg` / `lane_day_before.jpg` - Grand Ave's protected green bike lane at noon (delineators, stencil, hatched buffer), a cyclist and a second rider; before: the parking lane with parked cars.
- `station.jpg` / `station_before.jpg` - a BASIN BIKE share station downtown (solar kiosk, docks, docked bikes), a rack.
- `pile.jpg` - a mixed SKOOTA / KWIKR cluster with knocked-over scooters by a street tree.
- `gutter.jpg` - a SKOOTA cluster with one scooter lying in the gutter.
- `scooter_night.jpg` / `scooter_night_before.jpg` - a scooter rider in the green lane at 21:00, lamp lit, its pool on the road.
- `riders_row.jpg`, `road_bike.jpg` - `tools/glshot/micro_shot.gd RIDERS=1`: every kind ridden (KWIKR and SKOOTA scooters, share bike, longtail cargo bike with kid seat, cruiser, road bike with a helmet), posed by the per-frame solve.
- `vehicles_row.jpg` - the parked vehicles alone (micro_shot.gd).

## After the merge with fleet/base (2026-10-05, wave 2)

- `merged_riders_crowd_m/o/q/r/t.jpg` - `micro_shot.gd RIDERS=1 RIG=12/14/16/17/19`: the eight crowd rigs fleet/base added (crowd_m..t) on every kind, fitted by the same solve; crowd_r's headscarf takes no helmet now.
