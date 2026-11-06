class_name CrowdDress
extends RefCounted
## Who is dressed how (rc2-crowd-plaza, refcam `crowd_plaza`). Pedestrian.character_material()
## seeded each look's garment colours by the LOOK alone (4200 + look), so look 5's top was the
## same green on every one of the 32 crowd rigs: twelve recolours for the whole city. And every
## even look kept the rig's own outfit, so two copies of a rig with even looks were identical
## twins - with 140 people on a plaza and 32 rigs, a twin pair in every view. Here (crowd rigs
## only: the ones with region masks, whose recolour is exact):
## - `look_seed()`: the colours are rolled from the look AND the rig, so the same look on two rigs
##   is two outfits (24 materials a rig as before, nothing more is made or shared differently).
## - `plain()`: only every PLAIN_EVERY-th look keeps the rig's own outfit (6 of 24, not 12).
## CROWD_DRESS=0 in the environment is the A/B (the old rolls, bit for bit).

static var enabled: bool = OS.get_environment("CROWD_DRESS") != "0"

## One look in this many keeps the rig's own garments.
const PLAIN_EVERY := 4


static func look_seed(albedo: Texture2D, look: int, crowd_rig: bool) -> int:
	if not enabled or not crowd_rig:
		return 4200 + look
	# The rig by its texture's file name (stable run to run, unlike an instance id).
	return hash([4200 + look, albedo.resource_path.get_file()])


static func plain(look: int, crowd_rig: bool) -> bool:
	if not enabled or not crowd_rig:
		return look % 2 == 0
	return look % PLAIN_EVERY == 0


## The most saturated a recoloured top or bottom may be, and how much of its rolled saturation it
## keeps: the "something bright" bucket rolled 0.45-0.80 at value 0.45-0.78, which is a sports
## kit's colour - a plaza at lunch (crowd plaza refcam) read as a toy box of orange, pink, yellow
## and teal tees. Muted, a bright top is still the brightest thing on the street.
const SAT_KEEP := 0.72
const SAT_MAX := 0.5


## Called by Pedestrian.character_material() once a look's colours are rolled (after every roll,
## so the rolls themselves are unchanged).
static func tame(mat: ShaderMaterial, crowd_rig: bool) -> void:
	if not enabled or not crowd_rig or mat == null:
		return
	for part: String in ["cloth_sat", "pants_sat"]:
		var s: Variant = mat.get_shader_parameter(part)
		if s != null:
			mat.set_shader_parameter(part, minf(float(s) * SAT_KEEP, SAT_MAX))
