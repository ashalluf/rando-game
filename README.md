# shots/rc5-fire-station-night

Refcam `fire_station_night` (tools/refcams/cameras_w8.json): STATION 79 on 7th St downtown, 21:00
clear, from the far pavement as an engine goes out on a call. opengl3 (Compatibility) stills from
`refcams.py run --only fire_station_night`.

| file | what |
|---|---|
| 01_before_fire_station_night.jpg | main (12042fe2) with the same staging at FS_T=0.6: the engine appears on the street (clipping a box truck), the doors shut, the firehouse 40 m back and hidden, no light on the street |
| 02_after_fire_station_night.jpg | this branch, t = 8.1 s after the call: the engine nosing out of the open bay, door lamps on the brick, the lit bay, the firefighter at the kerb, the warning lights' red wash on the road, traffic stopped |
| 03_after_wider_framing.jpg | an earlier eye 5 m further east (same branch, before the final framing) |

Numbers (refcams report): before p5/p50/p95 5/54/173, 6.97 M tris, 3,864 draws;
after 5/57/174, 6.46 M tris, 3,624 draws (the box truck the before's engine hit is out of frame in
the after; the station's own additions are a few draws).
