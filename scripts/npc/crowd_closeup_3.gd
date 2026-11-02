class_name CrowdCloseup3
extends RefCounted
## The crowd at 2-6 m, third pass (docs/HANDOFF.md "The crowd up close, third pass"). Most of it is
## baked into the rigs by tools/crowd (soles, outsoles, laces and eyelets on the shoes:
## tools/crowd/crowd_shoes.py and shoe_paint.py; hands with their own triangle budget and a relaxed
## pose with the thumb along the index: build_character.py). What runs in the game is here:
##  - strides: the rate a rig's OWN walk, run and jog clips play at comes from that rig's measured
##    planted-foot speed (CrowdStrideTable, tools/crowd_closeup_3/stride_fit.gd), not one constant
##    for every rig - a tall rig on WALK_CLIP_SPEED 0.8 skated (its foot travels 0.91 m/s), a short
##    one shuffled (0.67); runners slid by up to a quarter
##  - the hair cards' edges (crowd_hair.gdshader `closeup`): strand-broken cuts, thinned
##    silhouettes, a better dither
## CROWD_CLOSEUP_3=0 in the environment is the A/B for both (the old constants, the old cut).

static var _on: int = -1


static func enabled() -> bool:
	if _on < 0:
		_on = 0 if OS.get_environment("CROWD_CLOSEUP_3") == "0" else 1
	return _on == 1


## The rig's measured clip speeds (m/s at speed_scale 1): {"walk", "run", "jog"}, or {}.
static func strides(model_path: String) -> Dictionary:
	if not enabled():
		return {}
	return CrowdStrideTable.TABLE.get(model_path.get_file().get_basename(), {})


## Sets a pedestrian's own-clip speeds from its rig's row (Pedestrian._add_model, after CrowdGait):
## the walk only while it walks the rig's own clip (a gait library clip carries its own speed).
static func fit_strides(ped: Pedestrian) -> void:
	var row := strides(ped._model_path)
	if row.is_empty():
		return
	ped._own_walk_speed = float(row.get("walk", ped._own_walk_speed))
	ped._run_clip_speed = float(row.get("run", ped._run_clip_speed))
	ped._jog_clip_speed = float(row.get("jog", ped._jog_clip_speed))
	if ped._walk_clip == Pedestrian.WALK_CLIP:
		ped._walk_clip_speed = ped._own_walk_speed


## The value of crowd_hair.gdshader's `closeup` for a new hair material.
static func hair_closeup() -> float:
	return 1.0 if enabled() else 0.0
