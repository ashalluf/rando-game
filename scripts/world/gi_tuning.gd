class_name GiTuning
## The indirect light's numbers per Quality level (fleet wave 3, `gi-review`; docs/HANDOFF.md,
## "Grounded light"). Quality._apply_render() switches the effects on and off per level; this
## sets how they are tuned, in ONE table, so the smoke test (tests/gi_review_checks.gd) pins them
## and a lavapipe A/B (tools/gi_review/gi_shot.gd ENV=) changes one at a time. GI_REVIEW=0 leaves
## city.tscn's numbers as they were (the A/B), and ContactShadows off with them.
##
## What the review found (Forward+ under lavapipe, five small scenes; the HANDOFF section has the
## stills and the GPU shares):
## - SSAO was a wide, soft dimming (radius 2.1 m, detail 0.6): it greyed whole facades and gave
##   no contact where a tyre, a bench leg or a kerb meets the ground. A tighter radius with more
##   detail and a higher power puts the darkness in the creases.
## - SSIL bounced a quarter of what a sunlit facade throws across a street.
## - With SDFGI off (MEDIUM, LOW) the sky fill is unoccluded: an underpass was lit like the open
##   street; the occlusion the sky gets from SSAO is what is left there (light_affect).

static var enabled: bool = OS.get_environment("GI_REVIEW") != "0"

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
	"bounce_feedback": [0.5],
	"energy": [1.0],
}


static func _pick(table: Dictionary, key: String, level: int) -> float:
	var row: Array = table[key]
	return float(row[clampi(level, 0, row.size() - 1)])


## Sets the environment's tuning for `level` (Quality.Level as an int). Never switches an effect
## on or off: that is Quality's.
static func apply(env: Environment, _sun: DirectionalLight3D, level: int) -> void:
	if env == null or not enabled:
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
