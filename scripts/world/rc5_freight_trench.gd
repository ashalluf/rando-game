class_name RcFreightTrench
extends RefCounted
## The freight trench refcam (wave 8, refcam `freight_trench` in tools/refcams/cameras_w8.json;
## docs/HANDOFF.md "The Alameda trench at noon"). What gave the trench away as a game from a bridged
## cross street, and what this does about it:
##
##   walls     clean pale planes with a few vertical streaks: the trench's own copy of the freeway
##             structure material (`trench_look`) draws 24 ft cast panels with recessed joints, lift
##             lines, form-tie holes, diesel soot on the upper wall, ballast dust at the foot, a
##             weep hole a panel with its lime run, graffiti pieces; the concrete weathered darker.
##   ballast   a pale flat beige field once the stones were under a couple of pixels (the mean had
##             no crevices): freight_track's `rc5` keeps the crevices' shadow in the mean, mottles
##             the bed at 0.3-2 m, fouls it brown along the mainline; the crib sits up near the
##             tie tops (`BALLAST_DROP`) instead of the ties lying on a flat bed.
##   lights    the wall lights were black boxes floating on the wall: a conduit runs along each wall
##             at their height, into a pull box behind each.
##
## RC5_FREIGHT_TRENCH=0 is the A/B (the trench exactly as before).

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

static var enabled: bool = OS.get_environment("RC5_FREIGHT_TRENCH") != "0"

## The ballast top under the rail top in the trench (FreightKit.BALLAST_DROP is 0.25: the 0.21 m
## concrete tie's top is 0.172 under the rail, so the bed lay 8 cm under the ties' tops).
const BALLAST_DROP := 0.205
## The conduit's height over the wall light (FreightKit puts the light 5.6 m over the floor).
const CONDUIT_OVER := 0.32
const CONDUIT_R := 0.045

static var _mat: ShaderMaterial


## The trench's structure material: FreewayKit's, with the trench look on (a copy: the freeway's
## own stays as it is).
static func structure_material() -> ShaderMaterial:
	if not enabled:
		return FreewayKit.structure_material()
	if _mat == null:
		_mat = FreewayKit.structure_material().duplicate() as ShaderMaterial
		_mat.set_shader_parameter("trench_look", 1.0)
		if _mat.get_shader_parameter("tag_atlas") == null:
			_mat.set_shader_parameter("tag_atlas", load("res://assets/textures/street_wear/street_wear_tags.png"))
	return _mat


## How far the ballast's top lies under the rail top in the trench.
static func ballast_drop(default_drop: float) -> float:
	return BALLAST_DROP if enabled else default_drop


## The conduit along one wall over the stretch za..zb (the wall's inside face at x xi, the floor at
## fa..fb), and a pull box where a light hangs (`light_z`, NAN for none). Into the kit's body mesh.
static func conduit(kit: FreightKit, xi: float, side: float, za: float, zb: float, fa: float, fb: float, light_z: float) -> void:
	if not enabled:
		return
	var out := Vector3(-side, 0.0, 0.0)
	var ya := fa + 5.6 + CONDUIT_OVER
	var yb := fb + 5.6 + CONDUIT_OVER
	var col := FreewayKit.kind_color(Color(0.55, 0.56, 0.57), FreewayKit.S_STEEL)
	var a := Vector3(xi, ya, za) + out * (CONDUIT_R + 0.02)
	var b := Vector3(xi, yb, zb) + out * (CONDUIT_R + 0.02)
	var m := (a + b) * 0.5
	var half_len := (b - a) * 0.5
	kit.box(kit.body, m, half_len, Vector3.UP * CONDUIT_R, out * CONDUIT_R, col, 0.0, false)
	# A strap a couple of metres.
	var zz := ceilf(za / 2.0) * 2.0
	while zz < zb:
		var t := (zz - za) / maxf(zb - za, 0.001)
		var p := a.lerp(b, t)
		kit.box(kit.body, p, Vector3(0, 0, 0.02), Vector3.UP * (CONDUIT_R + 0.012), out * (CONDUIT_R + 0.012), col, 0.0, false)
		zz += 2.0
	if not is_nan(light_z):
		var t := (light_z - za) / maxf(zb - za, 0.001)
		var y := lerpf(fa, fb, t) + 5.6
		# The pull box over the fitting, and the drop to it.
		kit.box(kit.body, Vector3(xi, y + CONDUIT_OVER, light_z) + out * 0.07, Vector3(0, 0, 0.13), Vector3.UP * 0.14, out * 0.07,
			FreewayKit.kind_color(Color(0.42, 0.43, 0.44), FreewayKit.S_STEEL), 0.0, false)
		kit.box(kit.body, Vector3(xi, y + 0.15, light_z) + out * 0.06, Vector3(0, 0, 0.025), Vector3.UP * 0.1, out * 0.025, col, 0.0, false)
