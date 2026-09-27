# Wet streets (VISUAL_ROADMAP #9) - branch wt/wet-streets

All stills are the opengl3 (Compatibility) harness at 960x540, --quality=0. No SSR here: on the Mac
(Forward+) SSR adds real reflections on top of what is shown.

- wet_01_downtown_night_rain.jpg - downtown bookmark, 21:30, rain. After: the puddles and gutter
  mirror a lit street canyon (shop fronts, office windows) instead of the black night sky.
- wet_02_street_night_rain.jpg - looking down the avenue in the rain. Looking steeply down, the
  near puddles mirror the sky (correct); the far crossing holds the lit windows.
- wet_03_drying_day.jpg - after the rain (--wetness=0.45 --weather=clear), 10:00. Before: the
  street dries as one even sheet. After: blotchy drying, wheel tracks and crown drier, kerb side
  and low spots wetter. Subtle by day on this renderer.
- wet_04_drying_night.jpg - the same at 21:30.
- wet_05_downtown_noon_dry.jpg - dry noon: unchanged (road region mean diff 0.65/255).
- wet_06_tyre_spray_standin.jpg - tyre spray in a stand-in scene (box car, 20 m/s, wet slab).
