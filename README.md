# loading-first-frame stills (charts: an infra task)

- `01_first_minute_before_after.jpg` - the first 30 s after the loading screen lifts (headless
  loading screen, LOAD_FIRST_MINUTE=30): LOD blocks the streamer's window wants that are not standing,
  chunk swaps (each a visible pop-in), traffic. Before: the wide FULL preload rebuilt as LOD for 30 s
  (43 swaps), the freeway filling over 4 s. After: the streamer's own window (13 swaps; this run
  predates the last immediate streaming pass before the fade, which builds the 9 left), traffic full
  at t=1 (FirstFill).
- `02_first_use_wave3.jpg` - the worst frame the first time each of wave 3's things appears
  (opengl3/llvmpipe, a normal frame ~0.55 s), the loading screen's rehearsal without and with its
  wave-3 stages.
