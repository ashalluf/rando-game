# beach-golden stills (opengl3 / Compatibility, 1280x720, --quality=0, clear)

Before = `BEACH_GOLDEN=0`, after = the branch; the same EYEs and hours from one city load each.

- 01/02 sand toward the sea, 13:00 (`EYE=-725,1.7,610,90,-3`)
- 03/04 the same, 17:45 (golden hour: hummocks, ripples near the camera, the damp band)
- 05/06 the same, 18:30
- 07/08 the pier from the beach, 13:00 (`-945,1.8,-235,61.7,7`): the damp tide band
- 09/10 the pier from the beach, 17:45: the wet sand mirroring the sunset, pools, the sun path
- 11/12 the pier from the beach, 18:30
- 13/14 down the pier deck at 18:30 (lights on; unchanged)
- 15/16 low over the sand toward the sun, 17:45 (`-735,1.4,600,120,-12`)
- 17/18 the beach-life bookmark, 13:00 (`-725,1.7,610,160,-6`)
- 19 the weathered lifeguard tower close up, 13:00 (block_shot: faded, chalked blue, grooves,
  grime runs, silvered posts)

The after set was rendered with `band_mirror` 0.22; the branch ships 0.16 (a little darker band).

Forward+ (lavapipe, `tools/glshot/fwd_block_shot.tscn`, 960x540, the city's DayNight; only the
blocks round each eye): `fwd_before_*` / `fwd_after_*` - the sand toward the sea and toward the sun
at 17:45, the tower at 13:00 (faded paint, silvered posts). The clouds differ between the two
loads (they run on the clock).
