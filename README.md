# shots/sky-day-review: the day sky (09:00-16:00)

Each image is BEFORE (main, left) | AFTER (wt/sky-day-review, right).

- 01-07 `*_fwd.jpg`: tools/sky/sky_shot.gd on **Forward+** (lavapipe), the cumulus volume: noon toward the sun,
  east, north, 10:30, 14:00, and from 300-400 m. The radiating cirrus "beams" are gone (wisps instead), the
  blue comes down to the horizon band, the noon sun's wide beige halo is a tight white one, cumulus tops
  whiter with cooler bases, fewer fragments carpeting the horizon, no crepuscular blot round a high sun.
- 08-09 `*_web.jpg`: the same on **opengl3** (the web's painted clouds): the smooth pale "ellipse" behind
  the sun (the mid deck) is thinned.
- 10-13 `refcam_*.jpg`: the reference cameras (opengl3, `--strict`). The city's own light stays within a
  level (the radiance / ambient cubemap gets only a quarter of the day look). The refcam AFTER was shot
  with day_mid 0.3 (final is 0.15: a little less mid deck still).
- 14: 18:00 - bit-identical (0 pixels differ). Every hour outside 09:00-16:00 was diffed (03:00, 05:30,
  07:00, 08:30, 09:00, 16:00, 16:30, 18:00, 19:00, 22:00) on both renderers: 0 pixels differ.
