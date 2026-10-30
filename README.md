# shots/explosions-2 (fleet wave 3)

The rocket / car explosion, frame by frame (BlastFX, branch wt/explosions-2). EXPLOSIONS_2=0 is the before.

- 01 before, downtown noon (opengl3): 0.03, 0.1, 0.25, 0.5 / 1, 2.5, 6, 12 s. A small fireball, smoke gone by 6 s.
- 02 after, same camera and times (first version of the column; the column was made denser and longer after this).
- 03 after, a night street on Forward+ (lavapipe): 0.03 (the flash), 0.1, 0.3 / 1, 3, 8 s.
- 04 after, a parked car's own explosion on Forward+ by day: 0.05, 0.2, 0.5 / 1, 3, 10 s (the fuel fireball, the car tossed, burning debris, the column). The beaded column is the harness's 0.27 s frames: see 05.
- 05 the column at 4 s with a fine clock (left, 0.05 s frames) and the coarse one (right): continuous at real frame rates.
- 06-10 single frames.
- 11 before and 12 after, downtown noon at 0.03, 0.1, 0.25 / 0.5, 1, 2.5 / 6, 12, 18 s (opengl3, fine clock). In 12 the column leaves the frame by 18 s: its drift was an acceleration, fixed after (13).
- 13 after the drift fix, the column at 6, 12, 18 s in the small street (opengl3): it stays over its fire.

Not verified on the Mac at 60 fps; lavapipe ghosts particles through TAA (judge shapes, not smears).
