# rc3-airport-night stills

New reference camera `airport_night` (tools/refcams/cameras_w6.json): the airfield at 21:30 clear
from the first stand west of the concourse, looking east down the gate line, a jet staged in the flare
over the 27L threshold. Every "before" is `AIRPORT_NIGHT=0` on the same branch and camera row (=
main's look), every "after" the branch.

- 01_before_airport_night_2130.jpg - main 484a7897, the first framing (the staged jet hid behind the hangar domes).
- 02_before_airport_night_2130_AB.jpg - the final framing, AIRPORT_NIGHT=0: masts light nothing, grey toy jets, a solid searchlight wedge, the landing jet a dark shape.
- 03_after_airport_night_2130.jpg - the branch: lit stands, floodlit jets with logo lights on the fins, the landing jet's glare and its light on the runway, a faint patrol beam.
- 04 / 05 - the gate line, before / after (crop, 2x).
- 06 / 07 - the landing jet over the threshold, before / after (crop, 4x).
- 08_jet_alone_night_opengl3_left_forwardplus_right.jpg - tools/airport_apron/jet_shot.gd NIGHT=1: top row AN=0, bottom row the floods and logo lights; left opengl3, right Forward+ (lavapipe).
- 09_ten_refcams_compare_AB.jpg - the ten original cameras, AIRPORT_NIGHT=0 vs on (refcams compare): seven ok; street_noon, street_night, freeway flagged by traffic only.
