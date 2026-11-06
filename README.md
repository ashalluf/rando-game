# shots/web-review-5: the web build after wave 8

Browser stills (headless Chromium 1243, SwiftShader WebGL2, 960x540, 7 minutes of streaming,
`tools/webshot/bookmarks.sh`) of the web export of main 9edd6b1e (batch 57). "before" = main's
export as it is.

- 01-08 `*_before_web_<bookmark>.jpg`: the eight standing bookmarks. Every one loads with a clean
  console (only the template's occlusion warning and Chrome's autoplay notice). They match wave 4's
  stills (shots/web-build-5) except: the storm's street is now a dark wet mirror (wave 4: a pale
  sheet), and in the rain the hero reads near-black, not blue, and the pale sky wedges are gone.
- 09-12 `*_before_web_<bookmark>.jpg`: the four new bookmarks (wave 5-8 night / weather views),
  main 9edd6b1e. All load clean. 09: the lit bonfire ring has its glow, pool, logs and smoke but no
  flames (web only, open). 12: the Santa Ana corner framed looking up (pitch +12): a flat grey sheet
  under the horizon and a near-black band at the bottom.
- 13 the same Santa Ana spawn natively (opengl3 city_shot.gd): the same band, so not the web - the
  third-person camera drops to 0.40 m over the road when looking up. The bookmark now looks level.
- 14 the native refcam `bonfire_night` (rc4-bonfire-night): what the flames should look like.
- 15/16 tools/web_probe/fx_room.tscn bonfire=1 night=1: natively with the web's materials the flames
  draw (15); the same room exported and run in the browser draws no flames (16).
- 17/18 browser bisection: every flame setting changed to the visible row fire's (17) still draws
  nothing; with local_coords on (18, rightmost) a small flame shows.
- 19 render_bisect.gd steps for the Santa Ana band (none / Weather / Player / Ground / chunks /
  vignette ...): only hiding the chunks' ground removes it.
- 20-31 `*_after_web_<bookmark>.jpg`: the twelve bookmarks on the web export of the branch head
  (main batch 63 merged; no game code changed on the branch). All clean consoles; they match the
  befores. 31 Santa Ana now looks level (pitch -4): no band, the brush fire and its smoky dusk.
