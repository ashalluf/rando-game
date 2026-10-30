class_name GiTuning
## The indirect light's numbers per Quality level (fleet wave 3, `gi-review`; docs/HANDOFF.md,
## "Grounded light"). Quality._apply_render() switches the effects on and off per level; this
## sets how they are tuned, in ONE table, so the smoke test (tests/gi_review_checks.gd) pins them
## and a lavapipe A/B (tools/gi_review/gi_shot.gd ENV=) changes one at a time. GI_REVIEW=0 leaves
## city.tscn's numbers as they were (the A/B), and ContactShadows off with them.
##
## What the review found (Forward+ under lavapipe, small scenes with the player's auto exposure;
## the HANDOFF section has the stills, the numbers and the GPU shares):
## - HIGH's shade comes from SDFGI alone: Godot ignores ambient_light_energy while the sky
##   contribution is 1.0 (DayNight's day value), so day_ambient_energy never did anything by day.
##   A shaded alley sat at 33/255 at HIGH against 57 at MEDIUM, an underpass at 13 against 85.
##   SDFGI energy x1.35 and bounce feedback 0.9 lift the alley and warm it off the sunlit wall;
##   a coarser cell (1.6 m) lit the freeway soffit only by leaking the deck top through it.
## - With SDFGI off (MEDIUM and below) the sky fill is unoccluded: twice HIGH's shade, flat and
##   blue. The sky contribution goes to 0.7 there (the rest is day_ambient at its energy).
## - SSAO was a wide soft veil (radius 2.1 m, detail 0.6); tighter with full detail it sits in the
##   creases. SSIL reached a quarter of a street. Neither moved its GPU share (~1 % / ~2 %).

static var enabled: bool = OS.get_environment("GI_REVIEW") != "0"
## What DayNight multiplies its SDFGI energy and its sky fill by, set by apply() per level (1
## with GI_REVIEW=0).
static var gi_scale: float = 1.0
static var ambient_scale: float = 1.0
## DayNight's daytime ambient_light_sky_contribution (it eases to 0.35 by night): Godot ignores
## ambient_light_energy while this is 1.0, so it is the only way to turn the sky fill down.
static var sky_contribution: float = 1.0

## Per level: HIGH, MEDIUM, LOW, LOWEST. Only what the level has switched on matters.
const SSAO := {
	"radius": [1.2, 1.2, 1.0, 1.0],
	"intensity": [2.4, 2.4, 2.2, 2.2],
	"power": [1.6, 1.6, 1.6, 1.6],
	"detail": [1.0, 1.0, 0.8, 0.8],
	"light_affect": [0.12, 0.3, 0.3, 0.3],
	"ao_channel_affect": [0.35, 0.35, 0.35, 0.35],
}
const SSIL := {
	"radius": [6.0, 5.0, 5.0, 5.0],
	"intensity": [0.8, 0.9, 0.9, 0.9],
	"sharpness": [0.98, 0.98, 0.98, 0.98],
	"normal_rejection": [0.6, 0.6, 0.6, 0.6],
}
const SDFGI := {
	"bounce_feedback": [0.9, 0.9, 0.9, 0.9],
	"energy": [1.35, 1.0, 1.0, 1.0],
}
## The sky fill per level, felt only where SDFGI is off: the daytime sky contribution (the rest of
## the ambient is DayNight's day_ambient colour at its energy, a dim blue-grey) and a multiplier
## on that energy.
const SKY_FILL := [1.0, 0.7, 0.7, 0.7]
## The freeway structure's daylight under-fill (freeway_structure.gdshader `under_fill`): HIGH
## only - below it the unoccluded sky already lights a soffit like the open street.
const UNDER_FILL := [0.06, 0.0, 0.0, 0.0]
const AMBIENT := [1.0, 1.0, 1.0, 1.0]


static func _pick(table: Dictionary, key: String, level: int) -> float:
	var row: Array = table[key]
	return float(row[clampi(level, 0, row.size() - 1)])


## Sets the environment's tuning for `level` (Quality.Level as an int). Never switches an effect
## on or off: that is Quality's.
static func apply(env: Environment, _sun: DirectionalLight3D, level: int) -> void:
	if env == null or not enabled:
		gi_scale = 1.0
		ambient_scale = 1.0
		sky_contribution = 1.0
		if env != null:
			FreewayKit.structure_material().set_shader_parameter("under_fill", 0.0)
		return
	env.ssao_radius = _pick(SSAO, "radius", level)
	env.ssao_intensity = _pick(SSAO, "intensity", level)
	env.ssao_power = _pick(SSAO, "power", level)
	env.ssao_detail = _pick(SSAO, "detail", level)
	env.ssao_light_affect = _pick(SSAO, "light_affect", level)
	env.ssao_ao_channel_affect = _pick(SSAO, "ao_channel_affect", level)
	env.ssil_radius = _pick(SSIL, "radius", level)
	env.ssil_intensity = _pick(SSIL, "intensity", level)
	env.ssil_sharpness = _pick(SSIL, "sharpness", level)
	env.ssil_normal_rejection = _pick(SSIL, "normal_rejection", level)
	env.sdfgi_bounce_feedback = _pick(SDFGI, "bounce_feedback", level)
	gi_scale = _pick(SDFGI, "energy", level)
	ambient_scale = float(AMBIENT[clampi(level, 0, 3)])
	sky_contribution = float(SKY_FILL[clampi(level, 0, 3)])
	FreewayKit.structure_material().set_shader_parameter("under_fill", float(UNDER_FILL[clampi(level, 0, 3)]))
