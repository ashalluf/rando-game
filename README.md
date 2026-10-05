# Stills: traffic-ai (branch wt/traffic-ai)

opengl3 (Compatibility) stills from `tools/glshot/still_shot.gd` with `TRAFFIC=... TRAFFIC_STEPS=...`,
1280x720, 16:30, default spawn. Not the Mac's Forward+. The staged traffic moves only between the
frames of a sequence (TrafficAI.advance_shot), so each sequence is one continuous moment.

- `bus_t1.jpg` - a car coming up behind a bus at its stop, indicator on (TRAFFIC=bus, +0.9 s)
- `bus_t2.jpg` - moving over into the inner lane, nosed toward it (+1.8 s)
- `bus_t3.jpg` - alongside the bus in the inner lane, passing it (+3.6 s)
- `merge_t1.jpg` - from above: a car near the top of an on-ramp, the outer lane busy (TRAFFIC=merge)
- `merge_t2.jpg` - waiting at the merge point for a gap
- `merge_t3.jpg` - merged, on the deck in the outer lane (note: it crosses the deck's edge barrier, which the existing ramp geometry does not open)
- `pullout_t1.jpg` - a parked car signalling while a car passes in the kerb lane (TRAFFIC=pullout)
- `pullout_t2.jpg` - pulling out of the parking lane
- `pullout_t3.jpg` - in the lane, driving off

Frame cost (tools/geo_count.gd, 800x600, default spawn): TRAFFIC_AI=0 3.651 M tris / 3,656 draws,
TRAFFIC_AI=1 3.654 M / 3,660. Traffic tick (headless, 30 street + 70 freeway cars): 5.99 ms off,
6.50 ms on.
