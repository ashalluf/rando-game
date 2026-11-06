class_name CrashAftermath
extends Node3D
## What a car that has just hit something at speed looks like a minute later, at arm's length
## (wave 8, refcam `crash_closeup`: a sedan wrapped round a street lamp). Four things the
## crash code did not do, each one hook in it:
##   * A POLE WRAPS: a narrow thing (a lamp, a signal, a sign post) hit by the nose does not push
##     the whole front back like a wall; it cuts a deep narrow V into it. PropBreak.smash_ahead()
##     (and the staging) note the pole's width just before the car's take_hit(); CrashDeform's
##     crash() takes it (take_pole()) and makes that crumple zone narrow (POLE_RADIUS) and deeper
##     (POLE_DEPTH x).
##   * A BONNET POPS, it does not swing open: below CrashBreakup's fly-off speed a sprung bonnet
##     rests a few degrees up off its catch (bonnet_rest(), POP_REST), buckled by the crumple's
##     tent; only a hit past `bonnet_fly_over` throws it wide (the old rest). Wide open at rest was
##     a black hole of an engine bay over a car that had hit a lamp at 50 km/h.
##   * FLUIDS: a front crush past FLUID_AT ruptures the radiator and the sump - a pool of oil and a
##     wider sheet of green coolant that spreads for SPREAD_SECONDS and runs a tongue down the
##     ground's slope (shaders/crash_fluids.gdshader on one quad, a material each, MAX_POOLS kept,
##     the oldest reused). Children of this node, which lives under the level root (origin shifts
##     carry it, a tow takes the car and leaves the pool).
##   * STEAM from the radiator, rising out of the crushed nose for STEAM_SECONDS, thinning out.
## `CRASH_AFTERMATH=0` in the environment turns all four off (the A/B).

static var enabled: bool = OS.get_environment("CRASH_AFTERMATH") != "0"

## A pole's width for the wrap (m: a street lamp's shaft and what it crushes round it).
const POLE_WIDTH := 0.3
## The wrap's half width at the face: the pole's half width plus this, plus RADIUS_GAIN x the crush.
const POLE_RADIUS := 0.12
const POLE_RADIUS_GAIN := 0.6
## A pole concentrates the load: the crush goes this much deeper than a wall's at the same speed.
const POLE_DEPTH := 1.3
## The bonnet's rest when it only popped (rad: range by the car's hash), and the throw it gets.
const POP_REST := Vector2(0.05, 0.12)
const POP_KICK := 1.2
## A front crush (m) past which the radiator and sump go.
const FLUID_AT := 0.16
const SPREAD_SECONDS := 45.0
## How old a staged car's pool is drawn (s).
const STAGED_AGE := 40.0
const STEAM_SECONDS := 150.0
const MAX_POOLS := 6
const POOL_SIZE := 3.6
const SHADER := preload("res://shaders/crash_fluids.gdshader")

static var _pole_width: float = 0.0
static var _pole_frame: int = -1
static var _inst: CrashAftermath = null

## Pools laid so far (tests).
var pools_made: int = 0
var _pools: Array = [] # [MeshInstance3D, ShaderMaterial, born_s, steam or null]
var _clock: float = 0.0
var _next: int = 0


# --- The pole ------------------------------------------------------------------------------------

## Says the hit the car is about to take is a pole `width` metres across (this physics frame only).
static func note_pole(width: float) -> void:
	if not enabled:
		return
	_pole_width = width
	_pole_frame = Engine.get_physics_frames()


## The pole width noted for this frame's hit (0 when none), used once.
static func take_pole() -> float:
	if _pole_frame != Engine.get_physics_frames():
		return 0.0
	_pole_frame = -1
	return _pole_width


## The narrow zone's half width for a crush of `total` metres.
static func pole_radius(width: float, total: float) -> float:
	return width * 0.5 + POLE_RADIUS + POLE_RADIUS_GAIN * total


# --- The bonnet ----------------------------------------------------------------------------------

## The rest angle a sprung bonnet settles at: popped off its catch for a hit under `fly_over`.
static func bonnet_rest(over: float, fly_over: float, old_rest: float, h01: float) -> float:
	if not enabled or over >= fly_over:
		return old_rest
	return lerpf(POP_REST.x, POP_REST.y, h01)


static func bonnet_kick(over: float, fly_over: float, old_kick: float) -> float:
	if not enabled or over >= fly_over:
		return old_kick
	return POP_KICK


# --- The bumper bands ----------------------------------------------------------------------------

## CarCloseup's pushed copy of the bumper trim ("BumperBands", a child of the near body mesh in its
## mesh space) stood whole in front of a crushed nose: onto a crumple part material of its own
## once the car crumples (`on`), back to its trim material when it is repaired.
static func bands(cd: CrashDeform, on: bool) -> void:
	if cd == null or cd.dmg == null or not is_instance_valid(cd.dmg._mesh):
		return
	for c in cd.dmg._mesh.get_children():
		var mi := c as MeshInstance3D
		if mi == null or String(mi.name) != "BumperBands" or mi.mesh == null:
			continue
		if not on:
			mi.material_override = null
		elif enabled:
			mi.material_override = cd._part_material(mi.mesh.surface_get_material(0) as StandardMaterial3D, false)


# --- Fluids and steam ----------------------------------------------------------------------------

## CrashDeform.crash()'s hook, after its crumple: a front crush deep enough leaks and steams.
static func after_crash(cd: CrashDeform) -> void:
	if not enabled or cd == null or cd.car == null or not cd.car.is_inside_tree():
		return
	var car := cd.car
	if BigVehicles.is_big(car.body_type) or CarDamage.MID_ENGINE.has(car.body_type):
		return
	if car.has_meta(&"warm_rehearsal") or car.has_meta(&"aftermath_pool"):
		return
	if cd.crush_at_end(-1.0) < FLUID_AT:
		return
	var inst := _ensure(car)
	if inst == null:
		return
	car.set_meta(&"aftermath_pool", true)
	inst._leak(car, cd)


static func instance() -> CrashAftermath:
	return _inst if _inst != null and is_instance_valid(_inst) and _inst.is_inside_tree() else null


static func _ensure(from: Node) -> CrashAftermath:
	if instance() != null:
		return _inst
	var tree := from.get_tree()
	var host: Node = from
	while host.get_parent() != null and host.get_parent() != tree.root:
		host = host.get_parent()
	if not (host is Node3D):
		return null
	_inst = CrashAftermath.new()
	_inst.name = "CrashAftermath"
	host.add_child(_inst)
	return _inst


func _leak(car: Vehicle, cd: CrashDeform) -> void:
	var dmg := cd.dmg
	var xf := car.global_transform
	# Under the radiator: a little behind what is left of the nose.
	var nose := -dmg._len * 0.5 + cd.crush_at_end(-1.0) + 0.35
	var at := xf * Vector3(0.0, dmg._ride + 0.3, nose)
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.4, at + Vector3.DOWN * 3.0, 1)
	q.exclude = [car.get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return
	var ground: Vector3 = hit.position
	var gn: Vector3 = (hit.normal as Vector3).normalized()
	# Which way is down the slope (the road's camber or the pavement's fall); along the car if flat.
	var down := Vector3(0.0, -1.0, 0.0) - gn * (-gn.y)
	var fwd := -(xf.basis.z)
	if down.length() < 0.01:
		down = fwd
	down = Vector3(down.x, 0.0, down.z).normalized()
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.render_priority = -2
	var h := absi(hash([int(ground.x * 10.0), int(ground.z * 10.0), "pool"]))
	mat.set_shader_parameter("seed", float(h % 997) / 97.0)
	mat.set_shader_parameter("size", POOL_SIZE)
	mat.set_shader_parameter("spread", 0.05)
	# The quad's +x is world +x turned by the basis below; its UV.y runs along +z.
	var b := Basis(Quaternion(Vector3.UP, gn))
	var lx := b.x
	var lz := b.z
	mat.set_shader_parameter("flow", Vector2(down.dot(lx), down.dot(lz)).normalized())
	var mi: MeshInstance3D
	var steam: CPUParticles3D = null
	if _pools.size() < MAX_POOLS:
		mi = MeshInstance3D.new()
		mi.name = "Pool%d" % _pools.size()
		var quad := PlaneMesh.new()
		quad.size = Vector2(POOL_SIZE, POOL_SIZE)
		mi.mesh = quad
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_pools.append([mi, mat, 0.0, null])
	else:
		var old: Array = _pools[_next]
		mi = old[0]
		if is_instance_valid(old[3]):
			(old[3] as Node).queue_free()
		_pools[_next] = [mi, mat, 0.0, null]
		_next = (_next + 1) % MAX_POOLS
	var slot := _pools.find_custom(func(e: Array) -> bool: return e[0] == mi)
	mi.material_override = mat
	mi.global_transform = Transform3D(b, ground + gn * 0.012)
	mi.visible = true
	# A staged car (stills, refcams) shows the pool a minute on, spread.
	(_pools[slot] as Array)[2] = _clock - (STAGED_AGE if dmg._staged else 0.0)
	# Steam out of the crushed nose.
	steam = _steam()
	car.add_child(steam)
	steam.position = Vector3(0.0, dmg._ride + (dmg._top - dmg._ride) * 0.45, -dmg._len * 0.5 + cd.crush_at_end(-1.0) + 0.45)
	if dmg._staged:
		steam.preprocess = 4.0
	(_pools[slot] as Array)[3] = steam
	pools_made += 1
	set_process(true)


func _steam() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "RadiatorSteam"
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.amount = WeaponFX._count(26)
	p.lifetime = 2.6
	p.lifetime_randomness = 0.3
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.45, 0.05, 0.12)
	p.direction = Vector3.UP
	p.spread = 22.0
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 1.2
	p.gravity = Vector3(0.25, 0.55, 0.0)
	p.damping_min = 0.2
	p.damping_max = 0.5
	p.scale_amount_min = 0.35
	p.scale_amount_max = 0.6
	var curve := Curve.new()
	curve.max_value = 4.0
	curve.add_point(Vector2(0.0, 0.4))
	curve.add_point(Vector2(0.5, 1.4))
	curve.add_point(Vector2(1.0, 2.6))
	p.scale_amount_curve = curve
	p.color_ramp = WeaponFX._ramp([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0.22), Color(1, 1, 1, 0.0)])
	p.color = Color(0.92, 0.93, 0.95, 0.75)
	p.angle_min = -180.0
	p.angle_max = 180.0
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = WeaponFX.smoke_material()
	p.mesh = quad
	p.custom_aabb = AABB(Vector3(-6.0, -1.0, -6.0), Vector3(12.0, 10.0, 12.0))
	return p


func _process(delta: float) -> void:
	_clock += delta
	var busy := false
	for e: Array in _pools:
		var age := _clock - float(e[2])
		var s := clampf(age / SPREAD_SECONDS, 0.0, 1.0)
		(e[1] as ShaderMaterial).set_shader_parameter("spread", 0.08 + 0.92 * sqrt(s))
		if s < 1.0:
			busy = true
		var st: Variant = e[3]
		if st != null and is_instance_valid(st):
			var k := clampf(1.0 - age / STEAM_SECONDS, 0.0, 1.0)
			if k <= 0.0:
				(st as CPUParticles3D).emitting = false
			else:
				(st as CPUParticles3D).color.a = 0.75 * k
				busy = true
	if not busy:
		set_process(false)


## The pools let the staged clock run on: a still shows a pool `seconds` old.
func age_all(seconds: float) -> void:
	_clock += seconds
	set_process(true)
	_process(0.0)


## Frees every pool (a test cleaning up after itself).
func clear() -> void:
	for e: Array in _pools:
		if is_instance_valid(e[3]):
			(e[3] as Node).queue_free()
		if is_instance_valid(e[0]):
			(e[0] as Node).queue_free()
	_pools.clear()
	_next = 0
