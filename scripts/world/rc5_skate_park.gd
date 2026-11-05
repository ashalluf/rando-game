class_name RcSkatePark
extends RefCounted
## The skate park refcam (wave 8, `skate_park` in tools/refcams/cameras_w8.json; docs/HANDOFF.md
## "THE PIT at 16:30 from the deck"). What the view gave away, fixed here and in
## shaders/skate_park.gdshader's `look5` blocks:
##  - the pool and the deck were spotless beige concrete that merged with the sand: a cooler grey
##    shotcrete with pour patches, a broad band of wheel rubber round the transition that reads from
##    across the park (and its fine carve lines up close), grime at the floor, sun-bleach up top,
##    skid streaks and dirt round the lip on the deck;
##  - the coping was a bright, even ribbon: weathered blocks, waxed black and ground on the nose;
##  - the pool's frontside air cleared the deck by a hand (the rider read as standing on it): it
##    now goes `POOL_AIR` over the transition, about a metre over the coping, with a grab.
## RC5_SKATE=0 is the A/B (the old look, the old air).

static var enabled: bool = OS.get_environment("RC5_SKATE") != "0"

## The pool line's frontside air: its height over the chord along the wall (SkateParkLife).
const POOL_AIR := 2.75
const POOL_AIR_OLD := 1.9


## The shader's switch for the park's material.
static func apply(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("look5", 1.0 if enabled else 0.0)


static func pool_air() -> float:
	return POOL_AIR if enabled else POOL_AIR_OLD


## The boardwalk's painted sign boards, murals, hoardings and art-wall panels (LandmarkVeniceBoardwalk):
## they were UNSHADED, flat glowing colour with no sun or shadow on them, the loudest thing behind
## the park. Lit now, as matte paint a little faded by the sun and the salt (`PAINT_FADE` toward
## an old white). Off: the old unshaded material.
const PAINT_FADE := 0.2
const PAINT_OLD_WHITE := Color(0.86, 0.84, 0.79)
static var _paints: Dictionary = {}


static func paint(c: Color) -> StandardMaterial3D:
	if not enabled:
		return PropFactory.material(c, 0.85, true)
	var key := c.to_rgba32()
	if _paints.has(key):
		return _paints[key]
	var faded := c.lerp(PAINT_OLD_WHITE, PAINT_FADE)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = faded
	mat.roughness = 0.92
	_paints[key] = mat
	return mat
