# Swimming stills (wt/swimming)

opengl3 (Compatibility) stills from `tools/glshot/still_shot.gd` with
`SWIM_STAGE=... SWIM_HOLD=1 EYE_KEEP_PLAYER=1` (the stick faked, the swimmer held on the spot so a
fixed camera frames him). Not Forward+: the lighting is the flat Compatibility path.

- `01_before_sea_1530.jpg` - BEFORE (`SWIMMING=0`): off Rando Pier the hero runs on the sea, which
  was a floor (the city's ground box under the water).
- `02_after_crawl_1530.jpg` - the front crawl at the surface, from above: the body prone and awash,
  the wake's foam at his chest and the ring of foam his entry left.
- `03_after_tread_1530.jpg` - treading water under the pier, head and shoulders out, riding the
  drawn swell (SeaSurface: the ocean shader's Gerstner height in GDScript).
- `04_after_underwater_1530.jpg` - under the water, 3 m down, looking up at him gliding just
  under the surface: the underwater pass (absorbed red-first by each pixel's real distance, fogged
  into the water's colour) and the pier's piles fading out.
- `05_after_dolphin_1530.jpg` - the boost at the surface: porpoising out of the water like a
  dolphin, streamlined, spray off him.
- `06_after_park_pool_1530.jpg` - the front crawl in a rec park's 25 m pool, held in its tank.
- `07_after_macarthur_lake_1530.jpg` - treading water in MacArthur Park's lake.
- `08_after_dolphin_1840.jpg` - a dolphin leap's splash at dusk, the pier's lamps in the water.
