# shots/fwd-review-a: Forward+ review A

All stills are the REAL Forward+ renderer (the owner's Mac pipeline) run on lavapipe, small
scenes only: `block_shot.tscn` (a few FULL blocks, `--rendering-driver vulkan`) for the canals,
pier, police station and port; `hero_moves_shot.gd` and `photo_shot.gd ROOM=1` for the hero and
photo mode. Night stills use block_shot's crude night (no DayNight exposure), so overall levels
are darker/harsher than the game; judge materials and fixes, not exposure.

Before / after of the fixes:
- 01/02 canal crossing by day: the crossing water mirrored a phantom house front with a seam; now it carries the canal's own reflection.
- 03/04 down a canal by day (sky_tint now decoded in the water).
- 05/06, 07/08 canals at night: the harness left sky_tint at day (walls mirrored daylit) and the made-up windows were 8 m wide; now dark water with window-sized reflections.
- 09/10, 11/12 pier at night: the deck's light pools were clipped flat discs (magenta by the arcade); now softer, dimmer pools.

Forward+ look, no change needed:
- 13-15 pier by day; 16 hero moves (idle, flight, landing, roll, fall, flinch); 17 photo mode (panel, DOF + grade, letterbox Noir, saved PNG);
- 18-21 police station day / night; 22-25 port quay and yard day / night.
