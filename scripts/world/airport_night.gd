class_name AirportNight
extends RefCounted
## The airfield at night (refcam3 "airport_night", wave 6: tools/refcams/cameras_w6.json, 21:30
## clear from a stand west of the concourse). What the reference view found, kept in one place so
## AIRPORT_NIGHT=0 is the old field:
##
## - The apron's high masts lit nothing. Each mast laid one 80 m soft dot 14 m in front of it,
##   under the jets and the concourse, so from the apron the stands, the taxi lane and the jets were
##   the same moonlit blue as everything else. mast_pool() lays the floods' real pool: a point
##   source 28 m up, (1 + d^2/h^2)^-1.5 out to `REACH` (airport_flood.gdshader), less behind the
##   mast. And the same light falls on what stands there: the gate jets and the ground equipment
##   take the floods as emitted light (shaders/airport_flood.gdshaderinc), dress() hands each
##   material the masts.
## - A parked airliner at night has its LOGO LIGHTS on: lamps on the tailplane washing the fin.
##   airliner_livery.gdshader's `logo_light`: the fin lit from its foot, brightest low on the fin,
##   on every airliner after dark (parked, taxiing, on final).
## - The landing jet's lights: from beside the approach an aimed landing light showed at 6 % (its
##   cone points down the runway), so a jet on short final was a dark shape. `landing_side`
##   (aircraft_lights.gdshader) keeps a share of the glare off its axis, as a real one does.
## - A patrol helicopter's searchlight in clear air was a solid white wedge across the sky.
##   PATROL_BEAM: a helicopter on patrol (no stars) runs its shaft at a share of a pursuit's.
## - ...and its light on the runway: a jet low on final or rolling out with its landing lights on
##   throws a long pool down the runway ahead (landing_pool(), one additive quad a jet).
## Every number is a constant here; nothing rolls.

static var enabled: bool = OS.get_environment("AIRPORT_NIGHT") != "0"

## How far a mast's floods reach (metres, the pool's radius) and their strength on the concrete
## (display numbers added at the foot of the head).
const REACH := 92.0
const POOL_STRENGTH := 0.18
## Floods colour: warm LED white (linear).
const TINT := Color(1.0, 0.88, 0.70)
## The floods' emitted share on a jet's and a vehicle's paint under the head.
const JET_GAIN := 0.40
const KIT_GAIN := 0.35
## Behind a mast, this share of the light.
const BACK := 0.3
## The fin's logo lights (airliner_livery.gdshader `logo_light`).
const LOGO := 0.65
## An aimed landing light seen from off its axis keeps this much (aircraft_lights.gdshader).
const LANDING_SIDE := 0.32
## An aimed landing light's glare grows to this many times its size seen down its beam.
const LANDING_GLARE := 5.0
## The landing lights' pool on the runway: shown under this height (m), its size (across, along)
## and how far ahead of the jet its middle lies, its strength.
const LANDING_POOL_UNDER := 70.0
const LANDING_POOL_SIZE := Vector2(34.0, 150.0)
const LANDING_POOL_AHEAD := 70.0
const LANDING_POOL_STRENGTH := 0.8
## A patrol helicopter's searchlight shaft against a pursuit's.
const PATROL_BEAM := 0.2

## The masts as the shaders take them: Vector4(x, ground y, z, facing angle), TRUE world.
static var _masts: Array = []
static var _mats: Array = []


## The masts (Airport.mast_spots), noted when the airport is first built (Airport.build_chunk).
static func note_macro(macro: MacroMap) -> void:
	if not enabled or not _masts.is_empty():
		return
	for spot: Array in Airport.mast_spots(macro):
		var p: Vector2 = spot[0]
		var f: Vector2 = spot[1]
		_masts.append(Vector4(p.x, macro.tarmac_top, p.y, atan2(f.x, f.y)))
		if _masts.size() >= 16:
			break
	for m: ShaderMaterial in _mats:
		_apply(m, float(m.get_meta("af_gain", 0.0)))


static func masts() -> Array:
	return _masts


## Gives a material that includes airport_flood.gdshaderinc the masts and its gain.
static func dress(mat: ShaderMaterial, gain: float) -> void:
	if not enabled or mat == null:
		return
	mat.set_meta("af_gain", gain)
	if not _mats.has(mat):
		_mats.append(mat)
	_apply(mat, gain)


static func _apply(mat: ShaderMaterial, gain: float) -> void:
	var arr: Array[Vector4] = []
	for m: Vector4 in _masts:
		arr.append(m)
	while arr.size() < 16:
		arr.append(Vector4.ZERO)
	mat.set_shader_parameter("af_masts", arr)
	mat.set_shader_parameter("af_count", _masts.size())
	mat.set_shader_parameter("af_height", Airport.MAST_HEIGHT)
	mat.set_shader_parameter("af_reach", REACH)
	mat.set_shader_parameter("af_tint", Vector3(TINT.r, TINT.g, TINT.b))
	mat.set_shader_parameter("af_back", BACK)
	mat.set_shader_parameter("af_gain", gain if not _masts.is_empty() else 0.0)


## An airliner livery material: the floods and the logo lights.
static func dress_jet(mat: ShaderMaterial) -> void:
	if not enabled:
		return
	mat.set_shader_parameter("logo_light", LOGO)
	dress(mat, JET_GAIN)


static var _pool_mesh: QuadMesh = null


## The pool one mast's floods lay on the concrete (the batch "ap_pool"), `fwd` where they face.
static func mast_pool(ch: CityChunk, p: Vector2, fwd: Vector2, y: float) -> void:
	if _pool_mesh == null:
		_pool_mesh = QuadMesh.new()
		_pool_mesh.size = Vector2.ONE
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/airport_flood.gdshader")
		mat.set_shader_parameter("tint", TINT)
		mat.set_shader_parameter("strength", POOL_STRENGTH)
		mat.set_shader_parameter("h_over_r", Airport.MAST_HEIGHT / REACH)
		mat.set_shader_parameter("back", BACK)
		_pool_mesh.material = mat
	var yaw := atan2(-fwd.x, -fwd.y)
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -PI * 0.5).scaled_local(Vector3(REACH * 2.0, REACH * 2.0, 1.0))
	ch._batch.add("ap_pool", _pool_mesh, Transform3D(basis, Vector3(p.x, y + 0.06, p.y)))


static func pool_mesh() -> QuadMesh:
	return _pool_mesh


## The landing lights' pool on the runway ahead of a low jet (AmbientJet's tick): `above` its height
## over the runway, `fwd` its heading (unit, world). Hidden while the lights are off or it is high.
static func landing_pool(jet: Node3D, above: float, fwd: Vector3) -> void:
	var pool := jet.get_node_or_null("LandingPool") as MeshInstance3D
	var mat: ShaderMaterial = jet.get("_light_mat")
	# A parameter never set reads null (the shader's default, lights on): float(null) threw on
	# every tick of a jet that started out rolling.
	var lo = mat.get_shader_parameter("landing_on") if mat else null
	var on := mat != null and (lo == null or float(lo) > 0.5) and above < LANDING_POOL_UNDER and above > -5.0
	if not on:
		if pool:
			pool.visible = false
		return
	if pool == null:
		pool = MeshInstance3D.new()
		pool.name = "LandingPool"
		pool.mesh = FwdReviewH.display_pool(PropFactory.light_pool(Color(1.0, 0.95, 0.84), LANDING_POOL_STRENGTH, 1.4))
		pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pool.top_level = true
		jet.add_child(pool)
	pool.visible = true
	var f := Vector3(fwd.x, 0.0, fwd.z).normalized()
	var side := Vector3(-f.z, 0.0, f.x)
	# Higher up, the beams land further ahead and spread.
	var ahead := LANDING_POOL_AHEAD + clampf(above, 0.0, LANDING_POOL_UNDER) * 1.2
	var at := jet.global_position + f * ahead
	at.y = jet.global_position.y - above + 0.08
	var long_side := LANDING_POOL_SIZE.y * (1.0 + clampf(above, 0.0, LANDING_POOL_UNDER) / LANDING_POOL_UNDER)
	# The quad faces +Z: its x across the runway, its y along the heading, laid flat.
	pool.global_transform = Transform3D(Basis(side * LANDING_POOL_SIZE.x, f * long_side, Vector3.UP), at)
