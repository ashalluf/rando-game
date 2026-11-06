class_name JetFinal
extends RefCounted
## An airliner on final approach at night, seen from the street under it (refcam5 "airport_final",
## tools/refcams/cameras_w8.json: Crest Ave in midtown, 19:30 clear, the jet coming in over the
## street on its turn onto final). What that view found, kept in one place so JET_FINAL=0 is the
## old jet:
##
## - Seen from below, the gear was one black blob under each wing: airliner_livery.gdshader painted
##   everything under y -0.25 of the model "gear" (0.05 grey), and that line also cut through the
##   bottom of both nacelles. With `final_look` the nacelles keep their paint to the bottom, the
##   legs and doors are light grey, the wheels black tyres round bare hubs (axles measured off the
##   model's vertices; the shader has the numbers).
## - The belly and the nacelles were flat black against the night sky: nothing lit what faces
##   down. A real jet low over Los Angeles at night carries the city's sodium glow on its belly.
##   `under_glow` (linear) is that glow, strongest low over the city and fading with height
##   (`UNDER_FULL_BELOW` .. `UNDER_FADE_TO`, down to `UNDER_HIGH` of it), only after dark.
## - The gear legs stood dark between two landing lights: `gear_light` lights them (and a little of
##   the nacelles' undersides) while the landing and taxi lights are on.
## The jet's own copy of its livery material carries these (a flying jet is a handful of nodes;
## the parked jets and the player's airliner keep the shared one). Nothing rolls.

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

static var enabled: bool = OS.get_environment("JET_FINAL") != "0"

## The city's glow on the belly (linear, at full: low over the lit city at night).
const UNDER_GLOW := Color(0.11, 0.066, 0.034)
## Full glow below this height over the runway (m), easing to UNDER_HIGH of it by UNDER_FADE_TO.
const UNDER_FULL_BELOW := 150.0
const UNDER_FADE_TO := 1400.0
const UNDER_HIGH := 0.3
## Under this height the airfield's own lights are what lights it (no city glow on the runway).
const UNDER_GROUND := 12.0
## The landing and taxi lights' spill on the gear legs while they are on.
const GEAR_LIGHT := 0.7


## The jet's own copy of `shared` with the pass on (or `shared` itself when off).
static func material(shared: ShaderMaterial) -> ShaderMaterial:
	if not enabled or shared == null:
		return shared
	var mat := shared.duplicate() as ShaderMaterial
	mat.set_shader_parameter("final_look", 1.0)
	return mat


## How much of UNDER_GLOW reaches the belly at `above` metres over the runway (0..1).
static func under_share(above: float) -> float:
	if above < UNDER_GROUND:
		return 0.0
	return lerpf(1.0, UNDER_HIGH, smoothstep(UNDER_FULL_BELOW, UNDER_FADE_TO, above))


## Each flight tick (AmbientJet._fly()): the glow for the jet's height, the gear lamps with its
## landing lights.
static func tick(mat: ShaderMaterial, above: float, landing_on: bool) -> void:
	if not enabled or mat == null:
		return
	var k := under_share(above)
	mat.set_shader_parameter("under_glow", Vector3(UNDER_GLOW.r, UNDER_GLOW.g, UNDER_GLOW.b) * k)
	mat.set_shader_parameter("gear_light", GEAR_LIGHT if landing_on else 0.0)
