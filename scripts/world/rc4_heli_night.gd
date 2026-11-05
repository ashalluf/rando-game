class_name RcHeliNight
extends RefCounted
## The helicopter view of downtown at night (refcam `heli_night`, tools/refcams/cameras_w7.json;
## docs/HANDOFF.md "Downtown from a helicopter at 22:30"): 250 m over South Park looking north-west
## across the lit towers toward the 110. What gave it away, fixed behind the `rc4_heli_night` global
## (`RC4_HELI_NIGHT=0` is the A/B: the global 0 and the unfinished towers as they were):
## - LIGHTBOX ROOFS (tower_crown.gdshader): a lit crown loft's LID glowed as brightly as its sides,
##   so from above every lit-top tower wore a flat white / ice / blue plate. A lid (world normal up)
##   now keeps `LID_GLOW` of the glow: the crown is a lit band round a dark roof.
## - NEON HELIPADS (building_lod.gdshader kind 5): the far pad's green perimeter was one continuous
##   lit line widened to a pixel, a lime neon square on every pad. It is a row of lamps now
##   (`PAD_LAMP_EVERY` m apart), averaged to their mean under a pixel, at `PAD_LAMP_GAIN`.
## - THE BLACK MONOLITH (LandmarkDowntown._unfinished): the abandoned towers' glass had a lit
##   ratio of 0, a pure black slab mid-frame; a few floors carry work lights now (`UNFINISHED_LIT`,
##   cool white) and the frame tops their red obstruction lights.

static var enabled: bool = OS.get_environment("RC4_HELI_NIGHT") != "0"

## tower_crown.gdshader: what a crown's lid keeps of its glow (shader copy `HN_LID_GLOW`).
const LID_GLOW := 0.08
## building_lod.gdshader: metres between a far helipad's perimeter lamps, and their gain over the
## old line's (shader copies `HN_PAD_EVERY`, `HN_PAD_GAIN`).
const PAD_LAMP_EVERY := 3.0
const PAD_LAMP_GAIN := 1.8
## The unfinished towers' lit ratio (main: 0) and the work lights' colour.
const UNFINISHED_LIT := 0.07
const UNFINISHED_LIT_COLOR := Color(0.86, 0.92, 1.0)


## Pushes the switch to the shaders (DayNight._ready()).
static func install() -> void:
	RenderingServer.global_shader_parameter_set("rc4_heli_night", 1.0 if enabled else 0.0)


## Turns the pass on or off at once (tests, stills); the unfinished towers' material only takes
## it on their next build.
static func set_enabled(on: bool) -> void:
	enabled = on
	install()


## The unfinished towers' glass lit ratio.
static func unfinished_lit() -> float:
	return UNFINISHED_LIT if enabled else 0.0


## A far helipad's perimeter lamps averaged along the edge at a pixel of `tm` metres: the share
## of the edge lit (the shader's mean). Pure, for the checks.
static func pad_lamp_mean(tm: float) -> float:
	var lamp := 0.35
	return clampf(lamp / maxf(PAD_LAMP_EVERY, maxf(tm, lamp)), 0.0, 1.0)
