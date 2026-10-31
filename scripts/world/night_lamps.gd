class_name NightLamps
extends RefCounted
## The street lamps at eye level (night-lamps-review, fleet wave 4; docs/HANDOFF.md "The street
## lamps at eye level"): the pool each lamp throws on the street, its colour, and the switch.
## Read by CityChunk._add_street_lamp(), LotFill's car-park poles and the lamp test street
## (tools/night_lamps/lamp_street.tscn); LampShadows is the real shadows. NIGHT_LAMPS=0 in the
## environment puts the old pool (a soft dot centred under the head) back, and LampShadows off.

static var enabled: bool = OS.get_environment("NIGHT_LAMPS") != "0"

## The pool's across radius as a share of the lamp's pool diameter (StreetLamps.TYPES pool x
## NightStreetReview's scale): the physical profile is broad, so the quad must be big enough that
## the rim cut never shows as an edge.
const ACROSS := 0.62
## The arm heads (cobra, mast) throw along the street: the quad's along / across aspect, and how
## much of the light the house-side shield cuts behind the pole line.
const ARM_ASPECT := 1.55
const ARM_BACK := 0.55
## The pool's strength per type (rgb of its instance colour, replacing StreetLamps' `gain` in the
## new profile): the profile adds far more light over its area than the old dot, so every type
## sits lower, the tall heads lowest (their pool is wide and the omni already lights the road).
const GAIN := [0.24, 0.42, 0.42, 0.4, 0.24]


static func is_arm(t: int) -> bool:
	return t == StreetLamps.Type.COBRA or t == StreetLamps.Type.MAST


## The pool instance for a lamp placed by StreetLamps.place() (`lp`), its head (the lights' mean,
## chunk frame) and its foot `at`: [transform, colour, custom] for the "lamp_pool" batch. `size_k`
## scales it (LotFill's car-park poles: 1.15). Old (off): the dot of `size` diameter under the head.
static func pool_instance(lp: Dictionary, head: Vector3, at: Vector3, lift: float = 0.09, size_k: float = 1.0) -> Array:
	var t: int = lp.type
	var size: float = float(lp.pool) * size_k
	var at2 := Vector2(at.x, at.z)
	if not enabled:
		return [Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(size, 1.0, size)), Vector3(head.x, at.y + lift, head.z)),
			StreetLamps.pool_color(t, at2), Color.BLACK]
	var r := size * ACROSS
	var aspect := ARM_ASPECT if is_arm(t) else 1.0
	var h := maxf(head.y - at.y, 2.5)
	# Laid in the lamp's frame: the quad's x toward the street (the model's +x), its y along it.
	var b: Basis = (lp.xform as Transform3D).basis.orthonormalized()
	var flat := b * Basis(Vector3.RIGHT, -PI * 0.5) * Basis.from_scale(Vector3(r * 2.0, r * 2.0 * aspect, 1.0))
	var c := pool_ratio(NightCity.lamp_led(at2))
	var g: float = GAIN[t]
	var custom := Color(h / r, aspect, ARM_BACK if is_arm(t) else 0.0, 1.0)
	return [Transform3D(flat, Vector3(head.x, at.y + lift, head.z)), Color(c.r * g, c.g * g, c.b * g, c.a), custom]


## The wet road's lamp streaks (night_wet.gdshader): wider toward the eye and broken into glints
## (the old rods were a few pixels wide end to end, which read as sticks stood in the road).
const WET := {"width_share": 0.014, "flare": 2.2, "sparkle": 0.6, "near_fall": 2.6}


## NightAtmos' materials, tuned by the review (with NIGHT_LAMPS=0 their shaders' own defaults).
static func dress_material(kind: String, mat: ShaderMaterial) -> void:
	if not enabled:
		return
	if kind == "wet":
		for k: String in WET:
			mat.set_shader_parameter(k, WET[k])


## The real light (the OmniLight3D in the head). At the kit's numbers a cobra 8.6 m up lit the road
## under it at a quarter of what a 3.5 m post gave and nothing two lanes out: on Forward+ the street
## between lamps was black and the pools were all there was. The light's share of DayNight's level
## (meta lamp_gain, which DayNight already reads) undoes the height's falloff - h^attenuation over the
## old post's 3.5^1.4 - times LIGHT_GAIN, and its reach is at least REACH_PER_HEIGHT x the head's
## height, so the light lands where the pool is.
const LIGHT_GAIN := 1.5
const REACH_PER_HEIGHT := 2.4
const POST_FALLOFF := 5.79 # 3.5^1.4
const FALLOFF := 1.5
## The two lamps' light. NightCity's sodium (1.0, 0.86, 0.62) read as a warm-white bulb, not the
## deep amber of high-pressure sodium, and its LED (0.86, 0.92, 1.0) as a cold blue-white that the
## night grade turned grey-green on the asphalt; LA's LED heads are ~3000-4000 K.
const SODIUM := Color(1.0, 0.72, 0.42)
const LED := Color(1.0, 0.95, 0.88)


## The review's colour for a light NightCity made (`c`: its sodium or LED colour).
static func light_color(c: Color) -> Color:
	if not enabled:
		return c
	return LED if c.is_equal_approx(NightCity.LED_LIGHT) else (SODIUM if c.is_equal_approx(NightCity.SODIUM_LIGHT) else c)


## The pool's colour ratio (x light_pool's tint 1, 0.84, 0.58) for the place's lamp.
static func pool_ratio(led: bool) -> Color:
	return Color(0.98, 1.1, 1.48) if led else Color(1.0, 0.88, 0.74)


## Sets `light` (a street lamp's omni, head `h` m over its foot) up for the review; old: untouched.
static func tune_light(light: OmniLight3D, h: float) -> void:
	if not enabled:
		return
	var hh := maxf(h, 2.5)
	light.omni_range = maxf(light.omni_range, REACH_PER_HEIGHT * hh)
	# Steeper than the kit's eased decay: a pool under each lamp and dimmer road between them,
	# never one even wash (the gain below puts the light under the head back where it was).
	light.omni_attenuation = maxf(light.omni_attenuation, FALLOFF)
	light.light_color = light_color(light.light_color)
	var gain := LIGHT_GAIN * pow(hh, light.omni_attenuation) / POST_FALLOFF
	light.set_meta("lamp_gain", float(light.get_meta("lamp_gain", 1.0)) * gain)
