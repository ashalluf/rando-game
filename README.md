# web-build stills

The merged city (wt/web-build = fleet/base + the web fixes) exported with the 4.7.2 web template
(`web_nothreads_release`) and shot in headless Chromium (WebGL 2.0 on SwiftShader, Compatibility
renderer) by `tools/webshot/webshot.js`, 960x540, ~7 minutes of streaming before each shot.
These are what a browser draws, not the Mac's Forward+.

- `01_web_downtown_noon.jpg` - Flower St at Olympic, noon (`?spawn=2359.4,880,0,12,2&hour=12`). Console: no errors.
- `02_web_downtown_night_2130.jpg` - the same corner at 21:30: lit offices, shop neon, lamp light. Console clean.
- `03_web_esplanade_dusk_1836.jpg` - the Esplanade replica at 18:36. Console clean.
- `04_web_marina_1700.jpg` - the marina's waterfront at 17:00 (`?spawn=-560,200,90,-8`). Console clean.
- `05_web_stack_interchange_deck_1300.jpg` - on the four-level stack's deck (spawned at 120 m, fell onto it). Console clean.
- `06_web_marina_carpark_band_1200.jpg` / `07_native_opengl3_marina_carpark_band_1200.jpg` - the marina car park
  looking north (`spawn=-735,30,0,-20`): a flat purple/teal band over the lower half. Identical on the native
  Compatibility renderer, so not a web bug; reported to the lead (a face right in front of the spawn camera).
