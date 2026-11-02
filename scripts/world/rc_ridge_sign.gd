class_name RcRidgeSign
## The ridge-sign reference camera's fixes (fleet wave 6, `rc3-ridge-sign`; docs/HANDOFF.md "The
## ridge sign refcam"): what read fake in the big sign on the front range from 120 m at 16:30.
## `RC3_SIGN=0` in the environment is the A/B - every fix below goes back to main's look.
##
## - The letters: each stroke a mitred ribbon (clean bowls and corners, no box notches or coplanar
##   faces fighting), on a sheet-metal shader (4 x 8 ft panels, seams, dust at the foot, streaks
##   from the fixings) instead of one flat cream colour (HillSignLetters._letters_v2()).
## - The frame: braced to the slope (raking struts), not a cage of bare poles hanging below.
## - The hill round it: the code-built shrubs gathered into thickets with gaps by RcHills' cluster
##   field and sized by it (CityChunk._plant_hills), not one even scatter of identical green balls.

static var _on: int = -1


static func on() -> bool:
	if _on < 0:
		_on = 0 if OS.get_environment("RC3_SIGN") == "0" else 1
	return _on == 1
