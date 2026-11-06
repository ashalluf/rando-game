class_name WaterReview
## The water review (docs/HANDOFF.md "The water from the beach and the pier"): the near sea and the
## swash seen from the beach and the pier at 14:00 and 21:00. All of it is in the shaders this switch
## gates (`water_review` shader global):
##   - foam that is churned, not a pattern (surf.gdshaderinc surf_foam(): a warped multi-octave cut,
##     holes of every size), used by the surf's bores and old lace, the open water's lace and the
##     swash's foam edge; a ragged bore front and sections along the shore;
##   - clear shallows (ocean.gdshader + ocean_closeup.gdshaderinc oc_seabed() / oc_sea_floor()): the
##     view ray refracted down to the beach's own underwater profile (SeaSurface.seabed()), wet sand
##     with ripple marks and caustics, dimmed by the water red first;
##   - the swash sheet showing its sand (lighter, warmer) with the same caustics (surf_caustic());
##   - the night mirror: the piers' lamps as long columns down the water, and the pier park's Ferris
##     wheel mirrored (oc_wheel_mirror(), its hub from wheel_hub() below).
##
## WATER_REVIEW=0 in the environment is the A/B: the global goes to 0 and every shader draws what it
## drew before.


static func enabled() -> bool:
	return OS.get_environment("WATER_REVIEW") != "0"


## Sets the A/B global. Called by OceanCloseup.apply() (Weather, when it pushes the coast).
static func apply() -> void:
	RenderingServer.global_shader_parameter_set("water_review", 1.0 if enabled() else 0.0)
