class_name RcStorm
extends RefCounted
## The storm_downtown reference camera's review (Flower St at 20:30 in a thunderstorm, a strike
## held for the still; docs/HANDOFF.md "The thunderstorm downtown"): what read fake first in that
## frame, fixed in the systems that draw it, every number here. RC5_STORM=0 in the environment
## puts every one of them back exactly as it was (the A/B).

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

static var enabled: bool = OS.get_environment("RC5_STORM") != "0"


static func _env_f(key: String, d: float) -> float:
	var v := OS.get_environment(key)
	return v.to_float() if v != "" else d


## A night flash's LIGHT on the street (the lightning's directional light and the sun's flash
## term, which DayNight's ambient boost follows) on top of StormDrama.night_flash_gain(): a held
## strike lit the night street like an overcast noon.
static var NIGHT_LIGHT := _env_f("RC5_FL", 0.3)
## The sky's flash in its CUBEMAP pass (the radiance every mirror, the sky ambient and the
## aerial-perspective fog read) at night, against the flash drawn in the sky itself.
static var NIGHT_CUBE := _env_f("RC5_FC", 0.12)


static func light_gain(moonlight: float) -> float:
	if not enabled:
		return 1.0
	return lerpf(1.0, NIGHT_LIGHT, clampf(moonlight, 0.0, 1.0))


static func cube_gain(moonlight: float) -> float:
	if not enabled:
		return 1.0
	return lerpf(1.0, NIGHT_CUBE, clampf(moonlight, 0.0, 1.0))


## The sky's flash at night: tighter round the strike (the cloud base lit round the bolt, the rest
## of the deck darker: an even flash over the whole sky lifted the sodium deck to a beige daylight)
## and colder (lightning is blue-white; added to the orange deck it read as beige).
static var NIGHT_SPREAD := _env_f("RC5_SP", 0.35)
static var NIGHT_FLASH_COLOR := Vector3(_env_f("RC5_CR", 0.5), _env_f("RC5_CG", 0.62), 1.0)
const DAY_FLASH_COLOR := Vector3(0.8, 0.85, 1.0)


## Weather's per-frame hook, after StormDrama.on_flash() set the spread.
static func dress_sky(sky: ShaderMaterial, moonlight: float) -> void:
	var k := clampf(moonlight, 0.0, 1.0) if enabled else 0.0
	sky.set_shader_parameter("flash_cube", lerpf(1.0, NIGHT_CUBE, k))
	sky.set_shader_parameter("flash_color", DAY_FLASH_COLOR.lerp(NIGHT_FLASH_COLOR, k))
	if k > 0.0:
		var spread: float = sky.get_shader_parameter("flash_spread")
		sky.set_shader_parameter("flash_spread", spread * lerpf(1.0, NIGHT_SPREAD, k))


## The storm's rain curtains at night (Weather's shader, `night_veil`, `night_sheets`, `thin`):
## the even veil under the streaks and the sheets' gain took the curtain's warm night tint over
## every dark facade and the sky - the far towers drew as flat orange shapes - and the inner
## curtain's cell-wide streaks read as slanted bands. A storm of weight `w`.
static var NIGHT_VEIL := _env_f("RC5_VEIL", 0.3)
static var NIGHT_SHEETS := _env_f("RC5_SHEETS", 0.5)
static var INNER_THIN := _env_f("RC5_THIN", 1.0)


static func dress_curtain(mat: ShaderMaterial, w: float, inner: bool) -> void:
	var k := clampf(w, 0.0, 1.0) if enabled else 0.0
	mat.set_shader_parameter("night_veil", lerpf(1.0, NIGHT_VEIL, k))
	mat.set_shader_parameter("night_sheets", lerpf(1.0, NIGHT_SHEETS, k))
	mat.set_shader_parameter("thin", INNER_THIN * k if inner else 0.0)


## The street lamps' reflections in a storm (NightAtmos' wet streak, night_wet.gdshader `storm`):
## the rain beating the water breaks each long column into short pitted runs and dims it; at the
## rain's numbers every lamp drew a white rod down the road. Storm weight `w`; rain is untouched.
static var STREAK_GAIN := _env_f("RC5_STREAK", 0.45)


static func dress_streaks(w: float) -> void:
	var mat := NightAtmos.atmos_material("wet")
	if mat == null:
		return
	mat.set_shader_parameter("storm", clampf(w, 0.0, 1.0) if enabled else 0.0)
	mat.set_shader_parameter("storm_gain", STREAK_GAIN)


## The storm's flying litter (StormDrama): leaves and scraps skitter low along the street, small.
## Thrown up at the old 0.3 and up to 24 cm, billboarded, the ones that passed near the lens hung
## in the sky over the street as big dark discs.
const LITTER_RISE := 0.1
const LITTER_SIZE := 0.13


static func litter_rise(old: float) -> float:
	return LITTER_RISE if enabled else old


static func litter_size(old: float) -> float:
	return LITTER_SIZE if enabled else old
