# rc5-hill-home-dusk stills (refcam `hill_home_dusk`, tools/refcams/cameras_w8.json)

opengl3 (Compatibility) stills, 1280x720, from tools/refcams/refcams.py.

- 01_before_hill_home_dusk.jpg - main before the fixes: the camera (estate 392's pool deck, 19:15 clear).
- 02_before_alt_framing_downtown.jpg - a framing tried and not taken (the freeway deck fills it).
- 03_after_hill_home_dusk.jpg - after: the open-plan room lit in downlight pools, the lamp-lit pool mirroring the glass, spill light on the paving, chaise loungers, the terrace olive gone from the pool's view.
- 04_before_forward_plus_lavapipe.jpg / 05_after_forward_plus_lavapipe.jpg - the same deck on Forward+ (lavapipe, hill_ground_shot.tscn with DAYNIGHT=1 --hour=19.25: the hill chunks only, no city below), RC5_HILL_HOME=0 against on.
- 06_debug_glass_speckle_before_fix_crop.jpg - the per-pixel speckle on lit glass (an interpolated pane random through a sin hash), fixed by quantising it.
- 07_ten_refcams_pass_off_over_on.jpg - the ten original refcams, RC5_HILL_HOME=0 over on (refcams.py compare): only `freeway` flagged, by live traffic (a different car in front of the lens), none of the pass's surfaces are in it.
