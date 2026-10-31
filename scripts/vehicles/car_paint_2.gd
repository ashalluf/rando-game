class_name CarPaint2
## Car paint, second pass (docs/HANDOFF.md "Car paint that reads as photographed"; owner: "make it
## look like GTA 6"). The shader side is the `paint2` block of shaders/car_paint.gdshaderinc: the
## street's skyline cut into the lacquer's mirror, orange peel, flake glints per pixel-sized cell,
## candy, satin wraps, contrast roofs, oxidised single-stage paint and dust / pollen films.
##
## This file is the GDScript side, two hooks in Vehicle:
## * `roll()` from Vehicle.random_car(), after every roll it makes: a share of private cars takes
##   one of the new paints (PAINTS_2: candies, tri-coat pearls, colour-shift pearls, satin wraps)
##   and a share of the bodies that suit one a contrast roof. Every decision is a hash of the car's
##   look seed: the caller's rng is never touched, so nothing else in the city moves, and every
##   car not picked keeps exactly its old colour, finish and livery.
## * `apply()` from Vehicle._paint_material(): the per-finish shader numbers, the contrast roof's
##   line, and a car's condition (dust or pollen, an old car's oxidised paint) off the same hashes.
## Materials stay per car, as they were (CarDetail's grime already lives on them); no instance
## uniforms.
##
## CAR_PAINT_2=0 in the environment (or `enabled` false) is the A/B: no roll changes, `paint2` 0,
## the old shader path bit for bit.

static var enabled: bool = OS.get_environment("CAR_PAINT_2") != "0"

## Shader numbers per finish (Vehicle.Finish by index). peel: orange peel in the lacquer;
## sparkle: the flake glints; wrap: the satin vinyl sheen; candy: the tinted lacquer's depth.
## The new finishes (CANDY, TRICOAT, SATIN) also carry their whole base set here, since
## Vehicle.FINISHES does not know them.
const FINISH_2 := {
	0: {"peel": 0.85, "sparkle": 0.0, "wrap": 0.0, "candy": 0.0},            # GLOSS
	1: {"peel": 1.0, "sparkle": 0.85, "wrap": 0.0, "candy": 0.0},            # METALLIC
	2: {"peel": 0.75, "sparkle": 0.9, "wrap": 0.0, "candy": 0.0},            # PEARL
	3: {"peel": 0.6, "sparkle": 1.0, "wrap": 0.0, "candy": 0.0},             # DEEP
	4: {"peel": 0.0, "sparkle": 0.0, "wrap": 0.35, "candy": 0.0},            # MATTE
	5: {"peel": 0.5, "sparkle": 1.1, "wrap": 0.0, "candy": 0.85,             # CANDY
		"metallic": 0.5, "roughness": 0.22, "clearcoat": 1.0, "cc_rough": 0.012,
		"flake": 0.09, "flake_scale": 150.0, "flake_fade": 13.0, "pearl": 0.0},
	6: {"peel": 0.6, "sparkle": 0.75, "wrap": 0.0, "candy": 0.0,             # TRICOAT
		"metallic": 0.22, "roughness": 0.26, "clearcoat": 1.0, "cc_rough": 0.014,
		"flake": 0.06, "flake_scale": 320.0, "flake_fade": 11.0, "pearl": 0.5},
	7: {"peel": 0.0, "sparkle": 0.0, "wrap": 1.0, "candy": 0.0,              # SATIN
		"metallic": 0.05, "roughness": 0.5, "clearcoat": 0.0, "cc_rough": 0.36,
		"flake": 0.0, "flake_scale": 190.0, "flake_fade": 9.0, "pearl": 0.0},
}

## The new paints: [colour, Vehicle.Finish index, flip / candy colour (alpha 0: none)]. A flip
## colour is the pearl's grazing colour (TRICOAT) or the candy's deep colour (CANDY). Weighted by
## repetition like Vehicle.PAINTS. All private taste, so never on a fleet or a job vehicle.
const PAINTS_2 := [
	# Candies: a bright base under a tinted lacquer.
	[Color(0.70, 0.03, 0.04), 5, Color(0.16, 0.0, 0.015, 1.0)],
	[Color(0.70, 0.03, 0.04), 5, Color(0.16, 0.0, 0.015, 1.0)],
	[Color(0.06, 0.20, 0.72), 5, Color(0.01, 0.02, 0.14, 1.0)],
	[Color(0.04, 0.50, 0.46), 5, Color(0.0, 0.08, 0.07, 1.0)],
	[Color(0.62, 0.05, 0.40), 5, Color(0.12, 0.0, 0.08, 1.0)],
	[Color(0.80, 0.42, 0.04), 5, Color(0.20, 0.05, 0.0, 1.0)],
	# Tri-coat pearls: white over a pearl mid-coat, the grazing glow warm or cool.
	[Color(0.93, 0.92, 0.88), 6, Color(0.98, 0.90, 0.78, 1.0)],
	[Color(0.93, 0.92, 0.88), 6, Color(0.98, 0.90, 0.78, 1.0)],
	[Color(0.90, 0.91, 0.93), 6, Color(0.80, 0.88, 1.0, 1.0)],
	[Color(0.58, 0.05, 0.07), 6, Color(0.95, 0.38, 0.10, 1.0)],
	# Colour-shift pearls: the flank turns another colour away from the eye.
	[Color(0.14, 0.06, 0.26), 6, Color(0.10, 0.55, 0.50, 1.0)],
	[Color(0.06, 0.24, 0.20), 6, Color(0.55, 0.30, 0.65, 1.0)],
	# Satin wraps: grey, black, olive, sand, white, a deep blue.
	[Color(0.40, 0.41, 0.41), 7, Color(0, 0, 0, 0)],
	[Color(0.40, 0.41, 0.41), 7, Color(0, 0, 0, 0)],
	[Color(0.050, 0.050, 0.055), 7, Color(0, 0, 0, 0)],
	[Color(0.050, 0.050, 0.055), 7, Color(0, 0, 0, 0)],
	[Color(0.25, 0.28, 0.19), 7, Color(0, 0, 0, 0)],
	[Color(0.58, 0.52, 0.42), 7, Color(0, 0, 0, 0)],
	[Color(0.82, 0.82, 0.80), 7, Color(0, 0, 0, 0)],
	[Color(0.10, 0.17, 0.32), 7, Color(0, 0, 0, 0)],
]
## Share of private cars that take one of PAINTS_2 (sports and exotics far more often).
const NEW_PAINT_SHARE := 0.10
const NEW_PAINT_SHARE_SPORTS := 0.34

## Contrast roofs: the share per body type (Vehicle.BodyType by index) and the line in body space
## (body_uv.y, 0..1 over the body mesh's height) above which the pillars and roof take it - just
## over the belt line, measured on car_shot.gd stills.
const ROOF_SHARE := {
	8: 0.20,   # CROSSOVER
	14: 0.14,  # HATCHBACK
	15: 0.08,  # SUV
	16: 0.05,  # MINIVAN
	30: 0.30,  # EV_HATCH
	31: 0.06,  # LUX_SEDAN
	32: 0.24,  # COMPACT_SUV
	34: 0.12,  # COUPE
}
const ROOF_LINE := {
	8: 0.66, 14: 0.64, 15: 0.67, 16: 0.66, 30: 0.64, 31: 0.67, 32: 0.66, 34: 0.66,
}
## Gloss black, or (on a dark body) a pale silver-white.
const ROOF_DARK := Color(0.035, 0.035, 0.04)
const ROOF_LIGHT := Color(0.86, 0.86, 0.87)

## Condition: share of cars with a dust film, of those a share in pollen, and their amounts.
const DUST_SHARE := 0.34
const POLLEN_SHARE := 0.12
const DUST_TINT := Color(0.62, 0.58, 0.50)
const POLLEN_TINT := Color(0.74, 0.68, 0.36)
## Oxidised single-stage paint: share of private solid-gloss cars on the older bodies, and the
## beater (always).
const OXIDE_SHARE := 0.10
const OXIDE_BODIES := [0, 1, 2, 14, 16]  # SEDAN, PICKUP, VAN, HATCHBACK, MINIVAN
const BEATER := 18


## A 0..1 roll off a look seed (Vehicle._roll's formula, salts 60-79 are this file's).
static func _r(look: int, salt: int) -> float:
	return float(absi(hash([look, salt])) % 100000) / 100000.0


## Called by Vehicle.random_car() after its last roll, with what it decided; returns
## [colour, finish, livery, trim, flip]. Unchanged (flip alpha 0) when off, for a job vehicle, or
## when the hashes do not pick the car.
static func roll(look: int, type: int, livery: int, color: Color, fin: int, trim: Color) -> Array:
	var flip := Color(0, 0, 0, 0)
	var out := [color, fin, livery, trim, flip]
	if not enabled or not Vehicle.PAINTS.has(color) or type == BEATER:
		return out
	# Private paint only: no graphic beyond racing stripes or two-tone.
	if livery != Vehicle.Livery.NONE and livery != Vehicle.Livery.RACING and livery != Vehicle.Livery.TWO_TONE:
		return out
	var sporty := type == Vehicle.BodyType.SPORTS or type == Vehicle.BodyType.SUPER or type == Vehicle.BodyType.SPIDER \
		or type == Vehicle.BodyType.HYPER or type == Vehicle.BodyType.TRACK or type == Vehicle.BodyType.COUPE
	if _r(look, 61) < (NEW_PAINT_SHARE_SPORTS if sporty else NEW_PAINT_SHARE):
		var e: Array = PAINTS_2[absi(hash([look, 62])) % PAINTS_2.size()]
		out[0] = e[0]
		out[1] = e[1]
		out[4] = e[2]
		if livery != Vehicle.Livery.NONE:
			out[3] = Vehicle._contrast_trim(e[0])
	if livery == Vehicle.Livery.NONE and _r(look, 63) < float(ROOF_SHARE.get(type, 0.0)):
		out[2] = Vehicle.Livery.CONTRAST_ROOF
		var c: Color = out[0]
		out[3] = ROOF_LIGHT if c.get_luminance() < 0.12 else ROOF_DARK
	return out


## The paint2 uniforms on a car's paint material (Vehicle._paint_material(), after its own).
static func apply(car: Vehicle, mat: ShaderMaterial) -> void:
	if not enabled or Lowrider.is_lowrider(car.body_type):
		return
	var fi := int(car.finish)
	var f: Dictionary = FINISH_2.get(fi, FINISH_2[1])
	mat.set_shader_parameter("paint2", 1.0)
	mat.set_shader_parameter("skyline", 1.0)
	mat.set_shader_parameter("peel", f.peel)
	mat.set_shader_parameter("sparkle", f.sparkle)
	mat.set_shader_parameter("wrap", f.wrap)
	if f.has("metallic"):
		# A new finish: its whole base set (Vehicle.FINISHES gave it METALLIC's).
		mat.set_shader_parameter("paint_metallic", f.metallic)
		mat.set_shader_parameter("paint_roughness", f.roughness)
		mat.set_shader_parameter("clearcoat_amount", f.clearcoat)
		mat.set_shader_parameter("clearcoat_roughness_value", f.cc_rough)
		mat.set_shader_parameter("flake_strength", f.flake)
		mat.set_shader_parameter("flake_scale", f.flake_scale)
		mat.set_shader_parameter("flake_fade_distance", f.flake_fade)
		mat.set_shader_parameter("pearl_amount", f.pearl)
		if float(f.pearl) > 0.0:
			mat.set_shader_parameter("pearl_power", 3.2)
			mat.set_shader_parameter("pearl_color", car.paint_flip if car.paint_flip.a > 0.0 else Vehicle._pearl_tint(car.paint))
	if float(f.candy) > 0.0:
		mat.set_shader_parameter("candy_amount", f.candy)
		mat.set_shader_parameter("candy_deep", car.paint_flip if car.paint_flip.a > 0.0 else car.paint.darkened(0.8))
	if car.livery == Vehicle.Livery.CONTRAST_ROOF:
		mat.set_shader_parameter("stripe_mode", 6)
		mat.set_shader_parameter("stripe_color", car.trim_color)
		mat.set_shader_parameter("stripe_height", float(ROOF_LINE.get(int(car.body_type), 0.66)))
		mat.set_shader_parameter("stripe_roughness_mul", 1.0)
	# Condition, plain Vehicles only (no police, emergency or show cars), off the look seed.
	if car.get_script() != Vehicle:
		return
	var c := condition(car.look_seed, int(car.body_type), car.paint, fi, int(car.livery))
	if c[0] > 0.0:
		mat.set_shader_parameter("dust_film", c[0])
		mat.set_shader_parameter("dust_tint", c[1])
	if c[2] > 0.0:
		mat.set_shader_parameter("oxidize", c[2])


## Stills: CAR_COND=dust,oxide[,pollen] forces every plain car's condition (tools/glshot/car_shot.gd).
static var force_condition: String = OS.get_environment("CAR_COND")


## [dust, dust tint, oxidation] for a car. Pure (the checks call it).
static func condition(look: int, type: int, color: Color, fin: int, livery: int) -> Array:
	if force_condition != "":
		var fc := force_condition.split(",")
		return [float(fc[0]), POLLEN_TINT if fc.size() > 2 and fc[2] == "1" else DUST_TINT, float(fc[1]) if fc.size() > 1 else 0.0]
	var key := hash([look, color, type])
	var dust := 0.0
	var tint := DUST_TINT
	if _r(key, 71) < DUST_SHARE:
		dust = 0.15 + 0.30 * _r(key, 72)
		if _r(key, 73) < POLLEN_SHARE:
			tint = POLLEN_TINT
	var ox := 0.0
	if type == BEATER:
		ox = 0.55 + 0.4 * _r(key, 74)
	elif fin == Vehicle.Finish.GLOSS and livery == Vehicle.Livery.NONE and OXIDE_BODIES.has(type) \
			and Vehicle.PAINTS.has(color) and _r(key, 75) < OXIDE_SHARE:
		ox = 0.25 + 0.35 * _r(key, 76)
	return [dust, tint, ox]
