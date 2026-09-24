class_name Helicopter
extends AmbientCraft
## A kinematic helicopter (assets/models/helicopter.glb, tools/make_helicopter.py): police or
## news livery. It is flown, not simulated - AirTraffic gives it a mode and it steers a velocity
## toward what that mode wants, with an acceleration cap, and the attitude comes from the
## acceleration the way a real one's does: nose down to speed up, nose up to stop, banked into
## every turn (bank = atan(sideways accel / g)). Modes:
##   HOVER   hold a point
##   GOTO    fly to a point and stop there (smooth: it brakes from `brake_accel` out)
##   ORBIT   circle `orbit_centre` at `orbit_radius`, `orbit_height` over the ground there -
##           the news covering a scene, the police circling the player
##   LEAVE   fly off along `leave_dir`, climbing; AirTraffic removes it far away
## Whatever the mode, it climbs over anything AirTraffic.obstacle_top() says is ahead.
## The rotors spin; above `disc_rpm` the blades are swapped for a translucent disc
## (shaders/rotor_disc.gdshader) so they do not strobe. Police carry a gimballed searchlight
## (SpotLight3D, volumetric on Forward+ HIGH, a drawn shaft elsewhere, a pool of light where it
## lands); news carry a camera ball that follows what they are filming.

enum Role { POLICE, NEWS }
enum Mode { HOVER, GOTO, ORBIT, LEAVE }

const MODEL := "res://assets/models/helicopter.glb"
## Per-livery colours (linear-ish sRGB picks): upper body, lower body, stripe, boom lettering.
const LIVERIES := {
	Role.POLICE: [Color(0.035, 0.07, 0.19), Color(0.90, 0.91, 0.92), Color(0.30, 0.56, 0.92), Color(0.93, 0.94, 0.95)],
	Role.NEWS: [Color(0.92, 0.92, 0.93), Color(0.02, 0.33, 0.39), Color(1.00, 0.45, 0.08), Color(0.02, 0.33, 0.39)],
}

@export_group("Flight")
## Cruise speed (m/s), and the fastest it changes velocity (m/s^2).
@export var cruise_speed: float = 42.0
@export var max_accel: float = 5.0
## Deceleration it plans its stop with in GOTO (m/s^2).
@export var brake_accel: float = 3.0
## Climb and descent rates (m/s).
@export var climb_rate: float = 8.0
@export var descent_rate: float = 5.0
## How fast it turns its nose (rad/s).
@export var turn_rate: float = 0.8
## Speed round an orbit (m/s).
@export var orbit_speed: float = 17.0
## Height kept over the tallest thing ahead (m), and over plain ground.
@export var obstacle_clearance: float = 35.0
@export var min_height: float = 45.0
@export_group("Rotor")
## Main and tail rotor speeds (rpm), and the rpm above which the blades become a disc.
@export var main_rpm: float = 395.0
@export var tail_rpm: float = 2100.0
@export var disc_rpm: float = 150.0
@export_group("Searchlight")
## Beam energy at night, its cone half-angle (degrees), reach (m), and the volumetric fog energy
## it gets where volumetric fog is on (Forward+ HIGH).
@export var searchlight_energy: float = 22.0
@export var searchlight_angle: float = 6.5
@export var searchlight_range: float = 420.0
@export var searchlight_fog: float = 6.0
## How quickly the light swings onto its target (1/s).
@export var searchlight_track: float = 3.5

var role: Role = Role.NEWS
var mode: Mode = Mode.HOVER
## GOTO / HOVER target, TRUE world.
var goal: Vector3 = Vector3.ZERO
var orbit_centre: Vector3 = Vector3.ZERO
var orbit_radius: float = 150.0
var orbit_height: float = 140.0
## +1 anticlockwise seen from above, -1 clockwise.
var orbit_dir: float = 1.0
## The tallest thing anywhere on the current ring, and the ring it was measured for.
var _ring_top: float = -INF
var _ring_key: Vector4 = Vector4.INF
var leave_dir: Vector3 = Vector3.FORWARD
## What the searchlight or the camera ball points at, TRUE world (INF = forward and down).
var look_target: Vector3 = Vector3.INF
## Whether the searchlight should be lit (AirTraffic turns it on at night).
var searchlight_on: bool = false
## AirTraffic's reason for this helicopter ("patrol", "pursuit", "cruise", "cover", "leaving").
var task: String = ""

var rotor_rpm: float = 395.0
var _main_rotor: Node3D
var _tail_rotor: Node3D
var _main_blades: Node3D
var _tail_blades: Node3D
var _main_disc: MeshInstance3D
var _tail_disc: MeshInstance3D
var _disc_mat: ShaderMaterial
var _searchlight: Node3D
var _camera_ball: Node3D
var _spot: SpotLight3D
var _beam: MeshInstance3D
var _beam_mat: ShaderMaterial
var _pool: MeshInstance3D
var _lens_mat: StandardMaterial3D
var _spin: float = 0.0
var _fall_time: float = 0.0
var _hub_local: Vector3 = Vector3(0.0, 2.96, -0.22)
var _tail_local: Vector3 = Vector3(-0.235, 2.36, 7.26)
var _main_radius: float = 5.35
var _tail_radius: float = 0.78

static var _disc_shader: Shader
static var _beam_shader: Shader


func setup(r: Role, at_world: Vector3, heading: float, seed_value: int) -> void:
	role = r
	world_pos = at_world
	goal = at_world
	yaw = heading
	_rng.seed = seed_value
	health = 80.0
	crash_radius = 11.0
	crash_launch = 30.0
	sound_range = 1500.0
	sound_unit_size = 30.0
	hit_range = 700.0
	shadow_distance = 300.0


func _ready() -> void:
	super()
	_build_model()
	_build_heli_lights()
	_start_sound("rotor_loop")
	set_engine(0.0, 1.0)
	_apply_fade()
	apply_pose()


func _build_model() -> void:
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	var scene: PackedScene = load(MODEL) if ResourceLoader.exists(MODEL) else null
	var inst: Node3D = scene.instantiate() as Node3D if scene else null
	if inst == null:
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(1.8, 1.8, 9.0)
		mi.mesh = box
		mi.position = Vector3(0.0, 1.2, 2.0)
		_visual.add_child(mi)
	else:
		_visual.add_child(inst)
		_main_rotor = inst.find_child("MainRotor", true, false) as Node3D
		_tail_rotor = inst.find_child("TailRotor", true, false) as Node3D
		_main_blades = inst.find_child("MainRotorBlades", true, false) as Node3D
		_tail_blades = inst.find_child("TailRotorBlades", true, false) as Node3D
		_searchlight = inst.find_child("Searchlight", true, false) as Node3D
		_camera_ball = inst.find_child("CameraBall", true, false) as Node3D
		var police := role == Role.POLICE
		var keep := inst.find_child("LiveryPolice" if police else "LiveryNews", true, false)
		var drop := inst.find_child("LiveryNews" if police else "LiveryPolice", true, false)
		# Freed now, not queued: everything below walks the model's meshes.
		for gone: Node in [drop, _camera_ball if police else _searchlight]:
			if gone:
				gone.get_parent().remove_child(gone)
				gone.free()
		if police:
			_camera_ball = null
		else:
			_searchlight = null
		_paint(inst, keep)
		if _main_rotor:
			_hub_local = _main_rotor.position
			_main_radius = _extent(_main_blades, _main_rotor)
		if _tail_rotor:
			_tail_local = _tail_rotor.position
			_tail_radius = _extent(_tail_blades, _tail_rotor)
	_adopt_meshes(_visual)
	# After adopting: the discs are translucent, cast nothing and take no shadow twin.
	_build_discs(inst)
	# Hit boxes: the cabin, the boom, and the rotor disc (a rotor stops bullets too).
	_box_shape(Vector3(1.8, 1.7, 5.6), Vector3(0.0, 1.3, -0.4))
	_box_shape(Vector3(0.6, 0.7, 5.4), Vector3(0.0, 1.75, 4.8))
	_box_shape(Vector3(_main_radius * 1.8, 0.35, _main_radius * 1.8), _hub_local)
	if role == Role.POLICE and _searchlight:
		_build_searchlight()


## Radius a rotor's blades reach from its hub, from their mesh bounds.
func _extent(blades: Node3D, rotor: Node3D) -> float:
	var mi := blades as MeshInstance3D
	if mi == null or mi.mesh == null or rotor == null:
		return 5.35
	var box := mi.mesh.get_aabb()
	return maxf(maxf(absf(box.position.x), absf(box.end.x)), maxf(maxf(absf(box.position.z), absf(box.end.z)), maxf(absf(box.position.y), absf(box.end.y))))


## Materials bound by the generator's slot names (tools/make_helicopter.py): the livery's own
## colours on the body, clearcoat on the paint, dark mirror glass, lit lenses.
func _paint(inst: Node, livery: Node) -> void:
	var cols: Array = LIVERIES[role]
	var mats := {
		"paint": _car_paint(cols[0]),
		"paint2": _car_paint(cols[1]),
		"stripe": _car_paint(cols[2]),
		"decal_police": _flat(cols[3], 0.45),
		"decal_news": _flat(cols[3], 0.45),
		"glass": _glass(),
	}
	for n in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for si in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(si)
			var key := src.resource_name if src else ""
			if mats.has(key):
				mi.set_surface_override_material(si, mats[key])
			elif key == "lens" and role == Role.POLICE:
				if _lens_mat == null:
					_lens_mat = _lens()
				mi.set_surface_override_material(si, _lens_mat)
	if livery is MeshInstance3D:
		(livery as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _car_paint(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = 0.25
	m.roughness = 0.33
	m.clearcoat_enabled = true
	m.clearcoat = 0.7
	m.clearcoat_roughness = 0.12
	return m


func _flat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _glass() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	# Opaque dark mirror: a canopy seen from outside is the sky and the street in it, and an
	# opaque surface keeps it out of the transparent pass.
	m.albedo_color = Color(0.015, 0.02, 0.025)
	m.metallic = 0.4
	m.roughness = 0.04
	m.metallic_specular = 1.0
	return m


func _lens() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.9, 0.95, 1.0)
	m.emission_enabled = true
	m.emission = Color(0.85, 0.92, 1.0)
	m.emission_energy_multiplier = 0.0
	m.roughness = 0.1
	return m


func _build_discs(inst: Node3D) -> void:
	if _disc_shader == null:
		_disc_shader = load("res://shaders/rotor_disc.gdshader")
	_disc_mat = ShaderMaterial.new()
	_disc_mat.shader = _disc_shader
	var holder: Node3D = inst if inst else _visual
	_main_disc = _disc(_main_radius, 4.0)
	_main_disc.rotation.x = -PI * 0.5
	_main_disc.position = _hub_local + Vector3(0.0, 0.14, 0.0)
	holder.add_child(_main_disc)
	_tail_disc = _disc(_tail_radius, 2.0)
	_tail_disc.rotation.y = PI * 0.5
	_tail_disc.position = _tail_local + Vector3(-0.08, 0.0, 0.0)
	holder.add_child(_tail_disc)


func _disc(radius: float, blades: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * radius * 2.0
	mi.mesh = quad
	var mat := _disc_mat.duplicate() as ShaderMaterial
	mat.set_shader_parameter("blades", blades)
	if blades < 3.0:
		mat.set_shader_parameter("apparent_speed", 4.0)
		mat.set_shader_parameter("hub", 0.12)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _build_heli_lights() -> void:
	var red := Color(1.0, 0.10, 0.06, 1.0)
	var green := Color(0.15, 1.0, 0.35, 1.0)
	var white := Color(1.0, 0.98, 0.92, 1.0)
	var fwd := Vector3(0.0, -0.45, -1.0).normalized()
	_build_lights([
		[Vector3(-1.23, 1.80, 5.70), red, 0.45, LightKind.STEADY, Vector3.ZERO],
		[Vector3(1.23, 1.80, 5.70), green, 0.45, LightKind.STEADY, Vector3.ZERO],
		[Vector3(0.0, 1.80, 7.58), white, 0.4, LightKind.STEADY, Vector3.ZERO],
		[Vector3(-1.23, 2.02, 5.95), white, 0.8, LightKind.STROBE, Vector3.ZERO],
		[Vector3(1.23, 2.02, 5.95), white, 0.8, LightKind.STROBE, Vector3.ZERO],
		[Vector3(0.0, 2.36, 1.55), red, 0.6, LightKind.BEACON, Vector3.ZERO],
		[Vector3(0.0, 0.46, 0.2), red, 0.6, LightKind.BEACON, Vector3.ZERO],
		[Vector3(0.0, 0.62, -2.95), white, 1.1, LightKind.LANDING, fwd],
	])
	set_landing_lights(false)


func _build_searchlight() -> void:
	if _beam_shader == null:
		_beam_shader = load("res://shaders/searchlight_beam.gdshader")
	_spot = SpotLight3D.new()
	_spot.name = "Beam"
	_spot.position = Vector3(0.0, -0.14, -0.22)
	_spot.spot_range = searchlight_range
	_spot.spot_angle = searchlight_angle
	_spot.spot_angle_attenuation = 0.6
	_spot.spot_attenuation = 0.45
	_spot.light_color = Color(0.9, 0.95, 1.0)
	_spot.light_energy = 0.0
	_spot.shadow_enabled = false
	_spot.light_volumetric_fog_energy = 0.0
	_spot.visible = false
	_searchlight.add_child(_spot)
	# The shaft for renderers without volumetric fog: an open cone from the lens down the beam.
	_beam = MeshInstance3D.new()
	_beam.name = "Shaft"
	var cone := CylinderMesh.new()
	# Scaled per tick to the beam's width where it lands, so the lamp end is a near-point.
	cone.top_radius = 0.012
	cone.bottom_radius = 1.0
	cone.height = 1.0
	cone.cap_top = false
	cone.cap_bottom = false
	cone.radial_segments = 20
	cone.rings = 1
	_beam.mesh = cone
	_beam_mat = ShaderMaterial.new()
	_beam_mat.shader = _beam_shader
	_beam.material_override = _beam_mat
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.visible = false
	_searchlight.add_child(_beam)
	# Where it lands: an additive pool, so the street reads lit on every renderer.
	_pool = MeshInstance3D.new()
	_pool.name = "Pool"
	_pool.mesh = PropFactory.light_pool(Color(0.85, 0.92, 1.0), 1.6)
	_pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pool.top_level = true
	_pool.visible = false
	add_child(_pool)


# --- Flight -----------------------------------------------------------------------------------

func _fly(dt: float) -> void:
	_spin_rotors(dt)
	var flat_v := Vector3(velocity.x, 0.0, velocity.z)
	var want := Vector3.ZERO
	var want_alt := world_pos.y
	match mode:
		Mode.HOVER:
			want = (Vector3(goal.x, 0.0, goal.z) - Vector3(world_pos.x, 0.0, world_pos.z)) * 0.3
			want_alt = goal.y
		Mode.GOTO:
			var to := Vector3(goal.x - world_pos.x, 0.0, goal.z - world_pos.z)
			var dist := to.length()
			if dist > 0.5:
				want = to / dist * minf(cruise_speed, sqrt(2.0 * brake_accel * dist))
			want_alt = goal.y
			if dist < 3.0 and flat_v.length() < 2.0:
				mode = Mode.HOVER
		Mode.ORBIT:
			var r := Vector3(world_pos.x - orbit_centre.x, 0.0, world_pos.z - orbit_centre.z)
			var rl := r.length()
			var rn := r / rl if rl > 0.5 else Vector3.RIGHT
			var tangent := Vector3(rn.z, 0.0, -rn.x) * orbit_dir
			var radial := clampf((orbit_radius - rl) * 0.3, -cruise_speed, cruise_speed)
			# Far out, come straight in; near the ring, go round it.
			var round_speed := orbit_speed * clampf(1.0 - (rl - orbit_radius) / (orbit_radius * 2.0), 0.0, 1.0)
			want = tangent * round_speed + rn * radial
			if want.length() > cruise_speed:
				want = want.normalized() * cruise_speed
			# The look-ahead floor only sees 4 s of the ring, so a tower on the far side is met
			# climbing; hold the whole ring above the tallest thing on it.
			want_alt = maxf(orbit_centre.y + orbit_height, _orbit_ring_top() + obstacle_clearance)
		Mode.LEAVE:
			want = Vector3(leave_dir.x, 0.0, leave_dir.z).normalized() * cruise_speed
			want_alt = maxf(want_alt, world_pos.y + 30.0)
	want_alt = maxf(want_alt, _floor_height(flat_v))
	var dv := want - flat_v
	var step := max_accel * dt
	if dv.length() > step:
		dv = dv.normalized() * step
	flat_v += dv
	var want_vy := clampf((want_alt - world_pos.y) * 0.5, -descent_rate, climb_rate)
	var vy := move_toward(velocity.y, want_vy, 5.0 * dt)
	velocity = Vector3(flat_v.x, vy, flat_v.z)
	world_pos += velocity * dt
	_attitude(dt, dv / maxf(dt, 0.0001), flat_v)
	_aim_gear(dt)
	set_landing_lights(world_pos.y - _ground_here() < 120.0)
	set_engine(clampf(flat_v.length() / cruise_speed, 0.0, 1.0) * 1.5, 1.0 + 0.04 * clampf(vy / climb_rate, -1.0, 1.0))


## Lowest height it will fly at here: over the tallest thing a few seconds ahead and under it,
## and never lower than `min_height` over the ground.
func _floor_height(flat_v: Vector3) -> float:
	if traffic == null:
		return -INF
	var here := Vector2(world_pos.x, world_pos.z)
	var ahead := here + Vector2(flat_v.x, flat_v.z) * 4.0
	var top := maxf(traffic.obstacle_top(here), traffic.obstacle_top(ahead))
	return maxf(top + obstacle_clearance, _ground_here() + min_height)


func _orbit_ring_top() -> float:
	if traffic == null:
		return -INF
	var key := Vector4(orbit_centre.x, orbit_centre.y, orbit_centre.z, orbit_radius)
	if key != _ring_key:
		_ring_key = key
		_ring_top = -INF
		for i in 24:
			var a := TAU * float(i) / 24.0
			for f in [0.8, 1.0, 1.2]:
				var at := Vector2(orbit_centre.x + cos(a) * orbit_radius * f, orbit_centre.z + sin(a) * orbit_radius * f)
				_ring_top = maxf(_ring_top, traffic.obstacle_top(at))
	return _ring_top


func _ground_here() -> float:
	return traffic.ground_height(Vector2(world_pos.x, world_pos.z)) if traffic else 0.0


## Nose down to speed up, nose up to slow down, banked into the turn.
func _attitude(dt: float, accel: Vector3, flat_v: Vector3) -> void:
	var face := yaw
	if flat_v.length() > 6.0:
		face = yaw_of(flat_v)
	elif look_target != Vector3.INF:
		face = yaw_of(look_target - world_pos)
	var turn := wrapf(face - yaw, -PI, PI)
	yaw += clampf(turn, -turn_rate * dt, turn_rate * dt)
	var fwd := yaw_dir(yaw)
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var a_fwd := accel.dot(fwd)
	var a_side := accel.dot(right)
	var v_fwd := flat_v.dot(fwd)
	# The sideways acceleration of an orbit is the centripetal v^2 / r, which is what banks it.
	var want_pitch := clampf(-(a_fwd * 0.05 + v_fwd * 0.0055), -0.32, 0.22)
	var want_roll := clampf(-atan(a_side / 9.8), -0.55, 0.55)
	pitch = lerp_angle(pitch, want_pitch, 1.0 - exp(-2.2 * dt))
	roll = lerp_angle(roll, want_roll, 1.0 - exp(-2.2 * dt))


func _spin_rotors(dt: float) -> void:
	var main_rad := rotor_rpm / 60.0 * TAU
	if _main_rotor:
		_main_rotor.rotate_object_local(Vector3.UP, main_rad * dt)
	if _tail_rotor:
		_tail_rotor.rotate_object_local(Vector3.RIGHT, main_rad * (tail_rpm / maxf(main_rpm, 1.0)) * dt)
	var disc := clampf((rotor_rpm - disc_rpm) / (disc_rpm * 0.5), 0.0, 1.0)
	if _main_blades:
		_main_blades.visible = disc < 0.5
	if _tail_blades:
		_tail_blades.visible = disc < 0.5
	for d in [_main_disc, _tail_disc]:
		if d:
			d.visible = disc > 0.01
			((d as MeshInstance3D).material_override as ShaderMaterial).set_shader_parameter("fade", disc)


## True while the searchlight (or the camera ball) points within `cone_deg` of `target_world`
## (TRUE world) with nothing solid in between: the police unit has eyes on the player.
func has_eyes_on(target_world: Vector3, cone_deg: float = 6.0) -> bool:
	var gear: Node3D = _searchlight if _searchlight else _camera_ball
	if gear == null or life != Life.FLYING or not is_inside_tree():
		return false
	var at := WorldState.to_local(target_world)
	var from := gear.global_position
	var to := at - from
	if to.length() > searchlight_range or to.length() < 0.5:
		return false
	if (-gear.global_basis.z).angle_to(to) > deg_to_rad(cone_deg):
		return false
	return _ground_between(from, at).is_empty()


## Points the gear at its target at once (stills: a software frame is too slow to swing it).
func snap_gear() -> void:
	var keep := searchlight_track
	searchlight_track = 1000.0
	_aim_gear(1.0)
	searchlight_track = keep


## Points the searchlight or the camera ball at `look_target`, and lays the pool where the beam
## lands.
func _aim_gear(dt: float) -> void:
	var gear: Node3D = _searchlight if _searchlight else _camera_ball
	if gear == null:
		return
	var target := look_target
	if target == Vector3.INF:
		target = world_pos + yaw_dir(yaw) * 60.0 + Vector3.DOWN * 60.0
	var from := gear.global_position
	var to := WorldState.to_local(target)
	var dir := to - from
	if dir.length() > 0.5:
		var want := Basis.looking_at(dir.normalized(), Vector3.UP if absf(dir.normalized().y) < 0.98 else Vector3.FORWARD)
		var now := gear.global_basis.orthonormalized()
		gear.global_basis = Basis(now.get_rotation_quaternion().slerp(want.get_rotation_quaternion(), 1.0 - exp(-searchlight_track * dt)))
	if _spot == null:
		return
	var lamp: float = traffic.lamp_level() if traffic else 0.0
	var lit := searchlight_on and lamp > 0.05 and life == Life.FLYING
	_spot.visible = lit
	_pool.visible = lit
	if _lens_mat:
		_lens_mat.emission_energy_multiplier = 6.0 * lamp if lit else 0.0
	if not lit:
		_beam.visible = false
		return
	_spot.light_energy = searchlight_energy * lamp
	var volumetric: bool = traffic.volumetric_searchlight() if traffic else false
	_spot.light_volumetric_fog_energy = searchlight_fog if volumetric else 0.0
	# Where it lands, for the pool and the length of the drawn shaft.
	var origin := _spot.global_position
	var axis := -_spot.global_basis.z.normalized()
	var reach := searchlight_range
	var hit := _ground_between(origin, origin + axis * searchlight_range)
	if not hit.is_empty():
		reach = origin.distance_to(hit.position)
		var n: Vector3 = hit.normal
		var tangent := n.cross(Vector3.RIGHT if absf(n.x) < 0.9 else Vector3.FORWARD).normalized()
		var bitangent := n.cross(tangent).normalized()
		var dia := 2.0 * reach * tan(deg_to_rad(searchlight_angle)) * 1.25 + 2.0
		# Columns scaled directly: Basis.scaled() would scale the WORLD axes (HANDOFF 9c).
		_pool.global_transform = Transform3D(Basis(tangent * dia, bitangent * dia, n), hit.position + n * 0.25)
	else:
		_pool.visible = false
	_beam.visible = not volumetric
	if _beam.visible:
		var wide := reach * tan(deg_to_rad(searchlight_angle))
		_beam.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5).scaled_local(Vector3(wide, reach, wide)), _spot.position + Vector3(0.0, 0.0, -reach * 0.5))


# --- Falling ----------------------------------------------------------------------------------

func _begin_fall() -> void:
	_spin = 0.0
	_fall_time = 0.0
	searchlight_on = false


## Tail rotor gone: it spins up round the mast, drifts and drops, the engine screaming.
func _fall_motion(dt: float) -> void:
	_fall_time += dt
	_spin_rotors(dt)
	_spin = move_toward(_spin, 4.2, 2.2 * dt)
	yaw += _spin * dt
	var flat := Vector3(velocity.x, 0.0, velocity.z) * exp(-0.35 * dt)
	flat += yaw_dir(yaw) * 2.0 * dt
	velocity = Vector3(flat.x, move_toward(velocity.y, -22.0, 7.0 * dt), flat.z)
	world_pos += velocity * dt
	roll = sin(_fall_time * 3.1) * 0.35
	pitch = -0.15 + sin(_fall_time * 2.3) * 0.18
	set_engine(3.0, 1.15 + 0.08 * sin(_fall_time * 7.0))


func _become_wreck() -> void:
	super()
	rotor_rpm = 0.0
	for d in [_main_disc, _tail_disc]:
		if d:
			d.visible = false
	if _main_blades:
		_main_blades.visible = true
	if _tail_blades:
		_tail_blades.visible = true
	if _spot:
		_spot.visible = false
		_beam.visible = false
		_pool.visible = false


func _smoke_origin() -> Vector3:
	return Vector3(0.0, 2.35, 1.6)
