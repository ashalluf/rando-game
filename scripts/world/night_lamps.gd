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
	var c := NightCity.pool_color(at2)
	var g: float = GAIN[t]
	var custom := Color(h / r, aspect, ARM_BACK if is_arm(t) else 0.0, 1.0)
	return [Transform3D(flat, Vector3(head.x, at.y + lift, head.z)), Color(c.r * g, c.g * g, c.b * g, c.a), custom]
