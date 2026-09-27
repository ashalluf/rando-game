# Crowd animation (VISUAL_ROADMAP #28) - before / after

Rendered with `tools/crowd/crowd_lab.tscn` (opengl3, flat 0.5 m grid), 0.2 s between frames.

- `crowd_01_turn.jpg` - an about-turn. Before: spins round mid-stride. After: slows, steps round on the spot, sets off.
- `crowd_02_start_stop.jpg` - setting off from standing. Before: full pace instantly. After: pivots to face the way, short first steps, then pace.
- `crowd_03_head_look.jpg` - heads turn to a car passing, the player walking by and a gunshot (before: nothing).
- `crowd_04_crowd.jpg` - thirty people wandering a block's pavement.

Numbers: planted-foot slide 0.76 m/s -> 0.23 m/s (walk clip rate now matched to ground speed).
CPU per 100 pedestrians per physics tick (median of 3): near 2.98 -> 3.90 ms, 50 m 1.02 -> 1.09, 100 m 0.64 -> 0.74, 200 m 0.40 -> 0.49.
