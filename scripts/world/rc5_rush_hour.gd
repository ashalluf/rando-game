class_name RcRushHour
extends RefCounted
## The rush_hour refcam's look (fleet wave 8; docs/HANDOFF.md "The freeway at rush hour"): what
## the 105 at 17:40 from a footbridge, into the low sun, showed beside the empty lanes RushHour
## fills. `RC5_RUSH_LOOK=0` in the environment is the A/B: every uniform at its old default.
##
## - The deck's asphalt patches (freeway_deck.gdshader `patch_aged`): 0.05 albedo at roughness 0.8
##   in a concrete deck that shines into a low sun drew every patch as a crisp black tile. Aged
##   binder is grey and polished by the tyres; the outline is rounded and ragged.

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

## - Heat haze over the jam (HeatHaze, Forward+ desktop at HIGH / MEDIUM only): Weather's heat is
##   the afternoon sun's (LaWeather.afternoon_heat()), all but gone by 17:40; a jammed freeway's
##   exhaust and asphalt still shimmer the tail lamps down the carriageway. While the camera looks
##   along a jammed route it is on or over (RushHour.now_view), the haze is at least TRAFFIC_HAZE x
##   the jam's level x how dry and clear it is.

static var enabled := OS.get_environment("RC5_RUSH_LOOK") != "0"

## The heat haze's strength over a full jam on a clear day (a clear afternoon's peak is 0.5).
const TRAFFIC_HAZE := 0.32


## Called by FreewayCloseup.deck_material() once the deck material is made.
static func dress_deck(mat: ShaderMaterial) -> void:
	if not enabled or mat == null:
		return
	mat.set_shader_parameter("patch_aged", 1.0)


## The floor Weather puts under the heat haze's strength: `dry` is the clear (and Santa Ana)
## weather's weight, 0..1.
static func traffic_haze(dry: float) -> float:
	if not enabled:
		return 0.0
	return TRAFFIC_HAZE * RushHour.now_level * RushHour.now_view * clampf(dry, 0.0, 1.0)
