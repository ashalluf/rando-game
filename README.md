# shots/fwd-review-i: Forward+ review i (waves 7-8 on the Mac's renderer)

Small scenes rendered on lavapipe Forward+ (`vulkan`, what the Mac draws) beside opengl3
(Compatibility, what the stills are). Trios: Forward+ before | Forward+ after | opengl3.

- 01_runway_pools_beam_fwd_before_fwd_after_gl3.jpg - JetTakeoff's edge-light pools and a landing-light beam
  (`tools/fwd_review_i/night_bits.gd SCENE=runway CAM=-90,6,-40 LOOK=40,0,30`). Before: bright blue/cream discs and a solid beam rod.
- 02_runway_infield_beam_before_fwd_vs_gl3.jpg - the beam from the infield eye, before (Forward+ | opengl3).
- 03_brush_fire_glow_fwd_before_fwd_after_gl3.jpg - the Santa Ana brush fire's glow card 3 km off (`SCENE=fire`). Before: an orange box round the line.
- 04 taco truck at night, 05 farmers' market, 06 fireworks (look5) - Forward+ | opengl3, agree.
- 07_police_led_bar_fwd_vs_gl3.jpg - the pursuit LED bar close (`police_shot.gd VIEW=bar`): holds (Forward+ has the real strobe lights).
- 08_police_street_fwd_only_hard_rectangle_preexisting.jpg - a hard-edged lit rectangle on the road under a cruiser's headlights,
  Forward+ only, present with PURSUIT/POLICE_NIGHT looks off: older than waves 7-8, NOT fixed (see HANDOFF).
- 09_ocean_wakes_1736_fwd_vs_gl3.jpg - vessel wakes at 17:36 (`ocean_traffic/vessel_shot.tscn`): the usual sea-tone gap only.
- 10_road_patch_under_headlights_before_after_fwd.jpg - still 08's box, bisected and fixed (Forward+, `police_shot.gd`):
  left `FWD_REVIEW_I=0` (a resurfacing patch up to 30 % smoother, lit as a box by the cruiser's grazing
  headlight spot), right the fix (a patch is never smoother: a faint darker cell). Not a cluster bug: the
  box stayed put with the spots' range 28 -> 40 m and went with `patch_amount` 0.
