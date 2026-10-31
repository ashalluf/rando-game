# Wave 4 task: car-exterior-closeup (kind: new)

Branch `wt/car-exterior-closeup`, stills on `shots/car-exterior-closeup`.

Cars at arm's length: panel gaps and shut lines on every lofted body, door handles, mirrors with glass, badges (CarDetail landed: finish), wheel arches' inner lining, brake discs and calipers through the spokes, exhaust tips, the underbody not a flat plane. tools/make_road_cars.py / make_more_cars.py / make_cars_3.py. Keep the far twin's cost; measure with car_shot.gd and geo_count. Blender via tools/road_cars_setup.sh or `pip install bpy==4.2.0`. Re-import after every rebuilt .glb and commit the .glb plus every .import.

If `origin/wt/car-exterior-closeup` already exists (an earlier launch of this task, or a paused session, pushed it), CONTINUE it: check it out and merge origin/main into it. Same for `shots/car-exterior-closeup`.
Push your branch as soon as you have a first commit and at least every hour; before the final push merge origin/main and pass `SHARDS=3 tests/headless_check.sh`. End with the report the brief asks for.
