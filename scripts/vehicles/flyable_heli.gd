class_name FlyableHeli
extends Vehicle
## A helicopter the player flies (owner, 2026-10-05: "take a helicopter from the helipads and fly
## it"). The air traffic's model (assets/models/helicopter.glb, tools/make_helicopter.py) on a
## real rigid body: it is a Vehicle with no wheels, so the player gets in and out of it like any
## car (interact), and it sits on its skids (two boxes) until the rotor lifts it.
##
## Controls while somebody is at the stick:
##   jump (Space / pad A) held   collective up: climb at up to `climb_rate`
##   boost (Shift / pad B) held  collective down: descend at up to `descent_rate`
##   neither                     the collective holds the height (an arcade altitude hold)
##   move axes (WASD / stick)    cyclic: W tilts the nose down and it flies forward, S back,
##                               A / D roll it sideways
##   the camera (mouse / stick)  yaw: the nose turns toward where the camera looks, at the
##                               pedals' rate (`yaw_rate`) - fly where you look
## With the stick centred it levels itself and tilts against its own drift to stop (a stability
## assist), so a hover is hands off. The thrust is the rotor's, along the body's up: a tilted
## helicopter accelerates the way it leans, exactly like the real thing; it scales with the rotor
## speed, which spools up `spool_time` after somebody gets in and down after they leave.
##
## Crashes: a hard knock (the change in velocity over one step past `crash_dv`) costs health; the
## rotor disc touching anything solid (a shape query round the hub) is a ROTOR STRIKE: the blades
## shatter, the engine dies and the torque spins it round as it drops. Bullets, rockets and blasts
## come through take_hit(). At half health it smokes, at zero the engine dies, it catches fire and
## falls spinning; hitting the ground dead, or `burn_seconds` after landing on fire, it explodes
## (Explosion.blast, the player thrown out) and leaves a charred wreck, PhysicsBudget debris.
##
## The rotor wash: a ray under the hub finds the ground, `HeliDownwash` kicks a ring of dust (or
## spray over water) there, and the `heli_downwash` shader global (hub position, strength) makes
## palms, trees and grass under it bend away and flutter (foliage.gdshader, foliage_tex,
## la_tree, grass).
##
## HeliSpot puts one on a pad when the player comes near (rooftops, the hospital, the police HQ,
## the airport's heliport); HELI_FLYABLE=0 in the environment turns all of it off (HeliPads.enabled).


enum HeliLivery { PRIVATE, POLICE, NEWS, MEDICAL }

const MODEL := "res://assets/models/helicopter.glb"
## Medical (an invented air ambulance operator: white over navy with an orange band; never a
## cross, which is a protected emblem) and the police / news colours Helicopter uses.
const LIVERY_COLORS := {
	HeliLivery.POLICE: [Color(0.035, 0.07, 0.19), Color(0.90, 0.91, 0.92), Color(0.30, 0.56, 0.92), Color(0.93, 0.94, 0.95)],
	HeliLivery.NEWS: [Color(0.92, 0.92, 0.93), Color(0.02, 0.33, 0.39), Color(1.00, 0.45, 0.08), Color(0.02, 0.33, 0.39)],
	HeliLivery.MEDICAL: [Color(0.93, 0.93, 0.94), Color(0.05, 0.10, 0.22), Color(0.98, 0.40, 0.10), Color(0.05, 0.10, 0.22)],
}
const NAMES := ["Helicopter", "Police Helicopter", "News Helicopter", "Air Ambulance"]

@export_group("Flight")
## Climb and descent rates the collective asks for (m/s).
@export var climb_rate: float = 13.0
@export var descent_rate: float = 10.0
## How hard it chases the vertical speed asked for (1/s).
@export var vertical_response: float = 2.6
## Most thrust the rotor gives at full speed, as an acceleration (m/s^2; 9.8 hovers).
@export var max_thrust: float = 24.0
## Largest tilt the cyclic asks for (degrees): forward / back and sideways.
@export var max_pitch_deg: float = 30.0
@export var max_roll_deg: float = 26.0
## How quickly it reaches the attitude asked for (1/s), and the fastest it rotates (rad/s).
@export var attitude_response: float = 3.2
@export var max_rate: float = 2.2
## Yaw rate toward the camera's heading (rad/s), and the dead band (degrees).
@export var yaw_rate: float = 1.5
@export var yaw_deadband_deg: float = 2.0
## Stability assist: with the cyclic centred it tilts against its drift (rad per m/s, capped).
@export var brake_tilt: float = 0.02
## Extra push the way it leans at full tilt (m/s^2) on top of the thrust's own lean (g tan tilt):
## an arcade helicopter gets going and stops quicker than a real one.
@export var tilt_accel: float = 6.0
## Quadratic air drag (per m) on the horizontal speed: sets the top speed (~70 m/s at full tilt).
@export var drag: float = 0.0024
## Within this many metres of the ground, descending, it eases the sink to `flare_rate` (m/s): an
## auto-flare, so holding the collective down sets it on its skids instead of slamming them.
@export var flare_height: float = 7.0
@export var flare_rate: float = 2.5
## Sideslip damping (1/s): above `coordinate_speed` it flies where its nose points.
@export var slip_damp: float = 0.9
@export var coordinate_speed: float = 14.0
## Seconds the rotor takes to spool up or down.
@export var spool_time: float = 3.2
@export_group("Rotor")
## Main and tail rotor speeds at full spool (rpm), and the rpm above which the blades become a disc.
@export var main_rpm: float = 395.0
@export var tail_rpm: float = 2100.0
@export var disc_rpm: float = 150.0
@export_group("Damage")
## Hit points (a rifle round does about 10, a rocket blast up to 120).
@export var max_hp: float = 160.0
## Velocity change in one step (m/s) that counts as a crash, and hp per m/s past it.
@export var crash_dv: float = 9.0
@export var crash_damage: float = 9.0
## Seconds a downed helicopter burns on the ground before it blows; the wreck's lifetime.
@export var burn_seconds: float = 5.0
@export var wreck_lifetime: float = 90.0
## The explosion.
@export var blast_radius: float = 12.0
@export var blast_launch: float = 30.0
@export_group("Camera")
## How far the chase camera sits while flying (m); the player's own distance comes back after.
@export var camera_distance: float = 15.0

var heli_livery: int = HeliLivery.PRIVATE
var private_colors: Array = []
## 0..1 rotor speed.
var spool: float = 0.0
var hp: float = 160.0
## The engine is dead (shot down or a rotor strike): no more thrust.
var engine_dead: bool = false
var rotor_lost: bool = false
var exploded: bool = false
## The heading the pedals hold (rad), chased toward the camera's.
var yaw_cmd: float = 0.0
## What the controls asked for last tick (tests read it): collective -1..1, cyclic.
var collective: float = 0.0
var cyclic: Vector2 = Vector2.ZERO
## Seconds the skids have been off the ground.
var air_seconds: float = 0.0
## The downwash the shader global was last given (hub, local; strength): tests read it.
var wash_strength: float = 0.0
## Where it was taken from (HeliSpot), TRUE world.
var home_world: Vector3 = Vector3.INF
## Rotor kept turning with nobody aboard (stills: a helicopter held hovering for the camera).
var hold_running: bool = false
## Strikes are ignored until it has moved this far from where it started (a parked one may
## start with a windsock inside its disc).
var _strike_clear_world: Vector3 = Vector3.INF

var _main_rotor: Node3D
var _tail_rotor: Node3D
var _main_blades: Node3D
var _tail_blades: Node3D
var _main_disc: MeshInstance3D
var _tail_disc: MeshInstance3D
var _hub_local: Vector3 = Vector3(0.0, 2.96, -0.22)
var _tail_local: Vector3 = Vector3(-0.235, 2.36, 7.26)
var _main_radius: float = 5.35
var _tail_radius: float = 0.78
var _model: Node3D
var _meshes: Array[MeshInstance3D] = []
var _sound: AudioStreamPlayer3D
var _lights_mat: ShaderMaterial
var _wash: HeliDownwash
var _smoke: CPUParticles3D
var _fire: CPUParticles3D
var _crash_prev: Vector3 = Vector3.ZERO
var _crash_quiet: int = 3
var _strike_tick: int = 0
var _burn_left: float = -1.0
var _spin_dir: float = 1.0
var _cam_driver: Node = null
var _cam_keep: float = -1.0

static var _disc_shader: Shader
static var _light_shader: Shader
static var _charred: StandardMaterial3D
static var _cyl: CylinderShape3D


## Before add_child(): which livery (and for PRIVATE, the Rooftops.HELI_LIVERIES colours).
func setup_heli(kind: int, colors: Array = []) -> void:
	heli_livery = kind
	private_colors = colors
	body_type = BodyType.SEDAN
	enter_radius = 7.5
	paint = Color(0.9, 0.9, 0.9)


func display_name() -> String:
	return NAMES[heli_livery]


## CarDamage is for cars: the helicopter keeps its own hit points (take_hit below).
func can_take_damage() -> bool:
	return false


func _ready() -> void:
	super()
	add_to_group("flyable_heli")
	mass = 1500.0
	gravity_scale = 1.0
	linear_damp = 0.0
	angular_damp = 1.2
	center_of_mass = Vector3(0.0, 1.25, -0.3)
	hp = max_hp
	physics_material_override = _skid_material()
	yaw_cmd = global_rotation.y
	_crash_prev = linear_velocity


static func _skid_material() -> PhysicsMaterial:
	var m := PhysicsMaterial.new()
	m.friction = 0.9
	m.bounce = 0.05
	return m


# --- Build ------------------------------------------------------------------------------------

func _build() -> void:
	_model = _load_model()
	if _model:
		add_child(_model)
		_has_model = true
	# Collision: the cabin, the boom and fin, the two skids (what it stands on).
	_shape(Vector3(1.8, 1.55, 5.0), Vector3(0.0, 1.35, -0.5))
	_shape(Vector3(0.6, 0.8, 5.4), Vector3(0.0, 1.8, 4.8))
	_shape(Vector3(0.25, 1.4, 1.2), Vector3(0.0, 2.6, 7.3))
	for side: float in [-1.0, 1.0]:
		_shape(Vector3(0.14, 0.14, 3.6), Vector3(side * 1.12, 0.07, -0.55))
	_seat = Node3D.new()
	_seat.name = "Seat"
	_seat.position = Vector3(0.45, 1.25, -1.6)
	add_child(_seat)
	_build_lights()
	_wash = HeliDownwash.new()
	_wash.name = "Downwash"
	add_child(_wash)


func _shape(size: Vector3, at: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = at
	add_child(cs)


func _load_model() -> Node3D:
	if not ResourceLoader.exists(MODEL):
		return null
	var scene: PackedScene = load(MODEL)
	var inst: Node3D = scene.instantiate() as Node3D if scene else null
	if inst == null:
		return null
	inst.name = "Model"
	_main_rotor = inst.find_child("MainRotor", true, false) as Node3D
	_tail_rotor = inst.find_child("TailRotor", true, false) as Node3D
	_main_blades = inst.find_child("MainRotorBlades", true, false) as Node3D
	_tail_blades = inst.find_child("TailRotorBlades", true, false) as Node3D
	var police := heli_livery == HeliLivery.POLICE
	var news := heli_livery == HeliLivery.NEWS
	var gone: Array[String] = []
	if not police:
		gone.append_array(["LiveryPolice", "Searchlight"])
	if not news:
		gone.append_array(["LiveryNews", "CameraBall"])
	for nm in gone:
		var n := inst.find_child(nm, true, false)
		if n:
			n.get_parent().remove_child(n)
			n.free()
	_paint(inst)
	if _main_rotor:
		_hub_local = _main_rotor.position
		_main_radius = _extent(_main_blades)
	if _tail_rotor:
		_tail_local = _tail_rotor.position
		_tail_radius = _extent(_tail_blades)
	for n in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi and mi.mesh:
			_meshes.append(mi)
	_build_discs(inst)
	return inst


func _extent(blades: Node3D) -> float:
	var mi := blades as MeshInstance3D
	if mi == null or mi.mesh == null:
		return 5.35 if blades == _main_blades else 0.78
	var box := mi.mesh.get_aabb()
	return maxf(maxf(absf(box.position.x), absf(box.end.x)), maxf(maxf(absf(box.position.z), absf(box.end.z)), maxf(absf(box.position.y), absf(box.end.y))))


## The livery on the generator's material slots (Helicopter._paint()'s recipe).
func _paint(inst: Node) -> void:
	var cols: Array
	if heli_livery == HeliLivery.PRIVATE:
		cols = private_colors if private_colors.size() >= 3 else Rooftops.HELI_LIVERIES[0]
		cols = [cols[0], cols[1], cols[2], cols[1]]
	else:
		cols = LIVERY_COLORS[heli_livery]
	var mats := {
		"paint": _lacquer(cols[0]),
		"paint2": _lacquer(cols[1]),
		"stripe": _lacquer(cols[2]),
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


static func _lacquer(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = 0.25
	m.roughness = 0.33
	m.clearcoat_enabled = true
	m.clearcoat = 0.7
	m.clearcoat_roughness = 0.12
	return m


static func _flat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


static func _glass() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.015, 0.02, 0.025)
	m.metallic = 0.4
	m.roughness = 0.04
	m.metallic_specular = 1.0
	return m


## The rotor discs (shaders/rotor_disc.gdshader, the air traffic's): drawn over the blades above
## `disc_rpm`, faded in with the rotor speed.
func _build_discs(inst: Node3D) -> void:
	if _disc_shader == null:
		_disc_shader = load("res://shaders/rotor_disc.gdshader")
	_main_disc = _disc(_main_radius, 4.0)
	_main_disc.name = "MainDisc"
	_main_disc.rotation.x = -PI * 0.5
	_main_disc.position = _hub_local + Vector3(0.0, 0.14, 0.0)
	inst.add_child(_main_disc)
	_tail_disc = _disc(_tail_radius, 2.0)
	_tail_disc.name = "TailDisc"
	_tail_disc.rotation.y = PI * 0.5
	_tail_disc.position = _tail_local + Vector3(-0.08, 0.0, 0.0)
	inst.add_child(_tail_disc)


func _disc(radius: float, blades: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * radius * 2.0
	mi.mesh = quad
	var mat := ShaderMaterial.new()
	mat.shader = _disc_shader
	mat.set_shader_parameter("blades", blades)
	mat.set_shader_parameter("fade", 0.0)
	if blades < 3.0:
		mat.set_shader_parameter("apparent_speed", 4.0)
		mat.set_shader_parameter("hub", 0.12)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	return mi


## Nav lights, strobes, beacons and the landing light: one billboard mesh on
## shaders/aircraft_lights.gdshader (the air traffic's; spec format as AmbientCraft's).
func _build_lights() -> void:
	if _light_shader == null:
		_light_shader = load("res://shaders/aircraft_lights.gdshader")
	var red := Color(1.0, 0.10, 0.06, 1.0)
	var green := Color(0.15, 1.0, 0.35, 1.0)
	var white := Color(1.0, 0.98, 0.92, 1.0)
	var fwd := Vector3(0.0, -0.45, -1.0).normalized()
	var specs := [
		[Vector3(-1.23, 1.80, 5.70), red, 0.45, 0, Vector3.ZERO],
		[Vector3(1.23, 1.80, 5.70), green, 0.45, 0, Vector3.ZERO],
		[Vector3(0.0, 1.80, 7.58), white, 0.4, 0, Vector3.ZERO],
		[Vector3(-1.23, 2.02, 5.95), white, 0.8, 1, Vector3.ZERO],
		[Vector3(1.23, 2.02, 5.95), white, 0.8, 1, Vector3.ZERO],
		[Vector3(0.0, 2.36, 1.55), red, 0.6, 2, Vector3.ZERO],
		[Vector3(0.0, 0.46, 0.2), red, 0.6, 2, Vector3.ZERO],
		[Vector3(0.0, 0.62, -2.95), white, 1.1, 3, fwd],
	]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var phase := float(hash(get_instance_id()) % 1000) / 1000.0
	var corners := [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0)]
	for spec: Array in specs:
		var code := float(int(spec[3])) * 10.0 + phase * 9.0
		if (spec[4] as Vector3) != Vector3.ZERO:
			code += 100.0
		for k in [0, 1, 2, 0, 2, 3]:
			st.set_color(spec[1])
			st.set_uv(corners[k])
			st.set_uv2(Vector2(spec[2], code))
			st.set_normal(spec[4])
			st.add_vertex(spec[0])
	var mesh := st.commit()
	_lights_mat = ShaderMaterial.new()
	_lights_mat.shader = _light_shader
	_lights_mat.set_shader_parameter("landing_on", 0.0)
	_lights_mat.set_shader_parameter("day_level", 0.22)
	mesh.surface_set_material(0, _lights_mat)
	var mi := MeshInstance3D.new()
	mi.name = "Lights"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3.ONE * -60.0, Vector3.ONE * 120.0)
	mi.extra_cull_margin = 16000.0
	mi.visible = false
	add_child(mi)


func exit_candidates() -> Array[Vector3]:
	var side := Vector3(global_basis.x.x, 0.0, global_basis.x.z)
	side = side.normalized() if side.length() > 0.2 else Vector3.RIGHT
	var fwd := Vector3(-global_basis.z.x, 0.0, -global_basis.z.z)
	fwd = fwd.normalized() if fwd.length() > 0.2 else Vector3.FORWARD
	var base := global_position + Vector3.UP * 0.9
	return [base + side * 2.4, base - side * 2.4, base + fwd * 4.5, base - fwd * 9.5, global_position + Vector3.UP * 4.2]


func is_airborne() -> bool:
	return air_seconds > 0.25


func is_wreck() -> bool:
	return exploded


## Seats the right-hand pilot's seat for CarCabin: nobody is drawn (the canopy is a dark mirror).
func _cabin_seats() -> int:
	return 0


# --- Flight -----------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if exploded:
		return
	_camera_hook()
	var flying := (driver != null or hold_running) and not engine_dead
	spool = move_toward(spool, 1.0 if flying else 0.0, delta / maxf(spool_time, 0.1))
	var grounded := _skids_down()
	air_seconds = 0.0 if grounded else air_seconds + delta
	_spin_rotors(delta)
	if driver != null and not engine_dead:
		_controls(delta, grounded)
	elif engine_dead and not grounded:
		_dead_fall(delta)
	else:
		collective = 0.0
		cyclic = Vector2.ZERO
	_crash_watch_heli()
	_rotor_strike_check()
	_burn(delta)
	_sound_tick()
	_wash_tick(delta)
	if _lights_mat:
		_lights_mat.set_shader_parameter("landing_on", 1.0 if spool > 0.5 and air_seconds > 0.0 else 0.0)
	var lights := get_node_or_null("Lights") as MeshInstance3D
	if lights:
		lights.visible = spool > 0.05 and not engine_dead


## Skids on something: a short ray down from each skid's ends.
func _skids_down() -> bool:
	if not is_inside_tree():
		return true
	var space := get_world_3d().direct_space_state
	var down := -global_basis.y
	for p: Vector3 in [Vector3(1.12, 0.3, -1.9), Vector3(-1.12, 0.3, -1.9), Vector3(1.12, 0.3, 0.9), Vector3(-1.12, 0.3, 0.9)]:
		var from := global_transform * p
		var q := PhysicsRayQueryParameters3D.create(from, from + down * 0.55, 1 | 4 | 16, [get_rid()])
		if not space.intersect_ray(q).is_empty():
			return true
	return false


func _controls(delta: float, grounded: bool) -> void:
	var up_held := Input.is_action_pressed("jump")
	var down_held := Input.is_action_pressed("boost")
	collective = (1.0 if up_held else 0.0) - (1.0 if down_held else 0.0)
	cyclic = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var v := linear_velocity
	var g := 9.8
	var power := spool * spool
	var up := global_basis.y
	# --- Collective: chase the vertical speed asked for; on the ground with the collective down
	# it idles on its skids.
	var thrust := 0.0
	if grounded and collective <= 0.0 and air_seconds <= 0.0:
		thrust = g * 0.55 * power
	else:
		var want_vy := collective * (climb_rate if collective > 0.0 else descent_rate)
		var gap := _wash.ground_gap - _hub_local.y if _wash else INF
		if want_vy < 0.0 and gap < flare_height:
			want_vy = maxf(want_vy, -lerpf(flare_rate, descent_rate, clampf(gap / flare_height, 0.0, 1.0)))
		var a_v := g + (want_vy - v.y) * vertical_response
		thrust = clampf(a_v / maxf(up.y, 0.4), 0.0, max_thrust * power)
	apply_central_impulse(up * thrust * mass * delta)
	# --- Air: quadratic drag on the horizontal speed, sideslip damped once it is moving.
	var flat := Vector3(v.x, 0.0, v.z)
	var speed := flat.length()
	if speed > 0.01:
		apply_central_impulse(-flat * speed * drag * mass * delta)
	# The extra push the way it leans (tilt_accel), in proportion to the lean.
	var lean := Vector3(up.x, 0.0, up.z)
	var max_lean := sin(deg_to_rad(max_pitch_deg))
	if lean.length() > 0.01 and not grounded:
		apply_central_impulse(lean.normalized() * minf(lean.length() / max_lean, 1.2) * tilt_accel * power * mass * delta)
	var right := Vector3(global_basis.x.x, 0.0, global_basis.x.z).normalized()
	if speed > coordinate_speed:
		apply_central_impulse(-right * flat.dot(right) * slip_damp * minf((speed - coordinate_speed) / coordinate_speed, 1.0) * mass * delta)
	# --- Attitude: the cyclic tilts it (or, centred, it tilts against its drift), the nose
	# follows the camera.
	var fwd := Vector3(-sin(yaw_cmd), 0.0, -cos(yaw_cmd))
	var side := Vector3(cos(yaw_cmd), 0.0, -sin(yaw_cmd))
	var pitch_t := cyclic.y * deg_to_rad(max_pitch_deg)
	var roll_t := -cyclic.x * deg_to_rad(max_roll_deg)
	if cyclic.length() < 0.1 and not grounded:
		var lim := deg_to_rad(max_pitch_deg) * 0.6
		pitch_t = clampf(flat.dot(fwd) * brake_tilt, -lim, lim)
		roll_t = clampf(flat.dot(side) * brake_tilt, -lim, lim)
	if grounded and air_seconds <= 0.0 and collective <= 0.0:
		pitch_t = 0.0
		roll_t = 0.0
	var cam_yaw := _camera_yaw()
	if not grounded or collective > 0.0:
		var turn := wrapf(cam_yaw - yaw_cmd, -PI, PI)
		if absf(turn) > deg_to_rad(yaw_deadband_deg):
			yaw_cmd = wrapf(yaw_cmd + clampf(turn, -yaw_rate * delta, yaw_rate * delta), -PI, PI)
	else:
		yaw_cmd = global_rotation.y
	var target := Basis.from_euler(Vector3(pitch_t, yaw_cmd, roll_t))
	var err := (target * global_basis.orthonormalized().inverse()).get_rotation_quaternion()
	var angle := err.get_angle()
	if angle > PI:
		angle -= TAU
	var axis := err.get_axis() if absf(angle) > 1e-4 else Vector3.UP
	var want_w := axis * angle * attitude_response
	if want_w.length() > max_rate:
		want_w = want_w.normalized() * max_rate
	var authority := clampf(power * 1.2, 0.0, 1.0)
	if grounded and air_seconds <= 0.0 and collective <= 0.0:
		authority *= 0.15
	angular_velocity = angular_velocity.lerp(want_w, (1.0 - exp(-6.0 * delta)) * authority)
	if grounded and collective <= 0.0 and speed < 1.0:
		linear_velocity = Vector3(v.x * 0.9, v.y, v.z * 0.9)


## The camera's heading: the nose turns toward it.
func _camera_yaw() -> float:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return yaw_cmd
	var f := -cam.global_basis.z
	if Vector2(f.x, f.z).length() < 0.05:
		return yaw_cmd
	return atan2(-f.x, -f.z)


## Engine dead in the air: the tail rotor's torque is gone and it spins up round the mast as it
## drops; the rotor still slows the fall a little while it winds down (an autorotation of sorts).
func _dead_fall(delta: float) -> void:
	collective = 0.0
	cyclic = Vector2.ZERO
	var spin := 4.0 * _spin_dir
	angular_velocity = angular_velocity.lerp(Vector3(angular_velocity.x, spin, angular_velocity.z), 1.0 - exp(-1.5 * delta))
	apply_central_impulse(global_basis.y * 9.8 * 0.35 * spool * mass * delta)


func _spin_rotors(delta: float) -> void:
	var rpm := main_rpm * spool
	var rad := rpm / 60.0 * TAU
	if _main_rotor:
		_main_rotor.rotate_object_local(Vector3.UP, rad * delta)
	if _tail_rotor:
		_tail_rotor.rotate_object_local(Vector3.RIGHT, rad * (tail_rpm / maxf(main_rpm, 1.0)) * delta)
	var disc := clampf((rpm - disc_rpm) / (disc_rpm * 0.5), 0.0, 1.0)
	if rotor_lost:
		disc = 0.0
	if _main_blades:
		_main_blades.visible = disc < 0.5 and not rotor_lost
	if _tail_blades:
		_tail_blades.visible = disc < 0.5 and not rotor_lost
	for d: MeshInstance3D in [_main_disc, _tail_disc]:
		if d:
			d.visible = disc > 0.01
			(d.material_override as ShaderMaterial).set_shader_parameter("fade", disc)


## The chase camera pulls back while somebody flies it, and comes back when they get out.
func _camera_hook() -> void:
	if driver == _cam_driver:
		return
	if _cam_driver != null and is_instance_valid(_cam_driver) and _cam_keep >= 0.0:
		var rig := _cam_driver.get_node_or_null("CameraRig")
		if rig and "camera_distance" in rig:
			rig.camera_distance = _cam_keep
	_cam_driver = driver
	_cam_keep = -1.0
	if driver != null:
		var rig := driver.get_node_or_null("CameraRig")
		if rig and "camera_distance" in rig:
			_cam_keep = rig.camera_distance
			rig.camera_distance = camera_distance
		yaw_cmd = global_rotation.y
		_strike_clear_world = WorldState.to_world(global_position)


func _exit_tree() -> void:
	if _cam_driver != null and is_instance_valid(_cam_driver) and _cam_keep >= 0.0:
		var rig := _cam_driver.get_node_or_null("CameraRig")
		if rig and "camera_distance" in rig:
			rig.camera_distance = _cam_keep
	_cam_driver = null
	if _wash:
		_wash.clear()


# --- Sound and wash ---------------------------------------------------------------------------

func _sound_tick() -> void:
	if spool < 0.02 or engine_dead and spool < 0.1:
		if _sound and _sound.playing:
			_sound.stop()
		return
	if _sound == null:
		_sound = Sfx.loop_player("rotor_loop", 0.0)
		_sound.name = "Rotor"
		_sound.max_distance = 1500.0
		_sound.unit_size = 30.0
		_sound.attenuation_filter_cutoff_hz = 3500.0
		_sound.attenuation_filter_db = -30.0
		_sound.position = _hub_local
		add_child(_sound)
		set_meta("rotor_base_db", _sound.volume_db)
	if not _sound.playing:
		_sound.play()
	var load_share := clampf(absf(collective) * 0.5 + cyclic.length() * 0.3, 0.0, 1.0)
	_sound.pitch_scale = clampf(0.45 + 0.55 * spool + 0.05 * load_share, 0.3, 1.3)
	_sound.volume_db = float(get_meta("rotor_base_db", 0.0)) + linear_to_db(maxf(spool, 0.02)) + 3.0 * load_share


func _wash_tick(delta: float) -> void:
	if _wash == null:
		return
	var strength := spool * spool * (0.0 if rotor_lost else 1.0)
	wash_strength = strength
	_wash.drive(global_transform * _hub_local, strength, delta)


# --- Damage -----------------------------------------------------------------------------------

func take_hit(_shape_index: int, damage: float, dir: Vector3, at: Vector3 = Vector3.INF, kind: int = HIT_PROP) -> void:
	if exploded:
		return
	if kind == HIT_BLAST and dir.length() > 0.01:
		apply_central_impulse(dir.normalized() * damage * 40.0)
	hurt(damage)


## Takes `amount` of its hit points: smoke at half, the engine gone (and fire) at none.
func hurt(amount: float) -> void:
	if exploded or amount <= 0.0:
		return
	hp -= amount
	if hp < max_hp * 0.5:
		_start_smoke(false)
	if hp <= 0.0 and not engine_dead:
		kill_engine()


func kill_engine() -> void:
	if engine_dead:
		return
	engine_dead = true
	# A parked one hit where it stands, or one held for a still: it falls now.
	freeze = false
	hold_running = false
	sleeping = false
	_start_smoke(true)
	_spin_dir = -1.0 if hash(get_instance_id()) % 2 == 0 else 1.0
	if _skids_down():
		_burn_left = burn_seconds


## The rotor disc swept into something solid: the blades shatter, the engine quits, the torque
## spins it round.
func rotor_strike() -> void:
	if rotor_lost:
		return
	rotor_lost = true
	Sfx.play("hit_metal", global_transform * _hub_local, 6.0)
	var cam := driver.get_node_or_null("CameraRig") if driver else null
	if cam and cam.has_method("shake"):
		cam.shake(0.7)
	_throw_blades()
	hurt(max_hp * 0.45)
	kill_engine()
	spool = minf(spool, 0.35)


func _throw_blades() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var hub := global_transform * _hub_local
	var mat := _flat(Color(0.08, 0.08, 0.09), 0.6)
	for i in 4:
		var a := TAU * float(i) / 4.0 + global_rotation.y
		var piece := RigidBody3D.new()
		piece.collision_layer = 4
		piece.collision_mask = 1 | 4 | 16
		piece.mass = 25.0
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.32, 0.05, _main_radius * 0.55)
		bm.material = mat
		mi.mesh = bm
		piece.add_child(mi)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = bm.size
		cs.shape = bs
		piece.add_child(cs)
		parent.add_child(piece)
		var out := Vector3(sin(a), 0.0, cos(a))
		piece.global_transform = Transform3D(Basis(Vector3.UP, a), hub + out * _main_radius * 0.5)
		piece.linear_velocity = linear_velocity + out * 28.0 + Vector3.UP * 6.0
		piece.angular_velocity = Vector3(randf_range(-9, 9), randf_range(-20, 20), randf_range(-9, 9))
		PhysicsBudget.register_debris(piece, 20.0)


## A hard knock from the change of velocity over one step (Vehicle's crash watch, for a body with
## no wheels): a fall onto the skids, a wall, the ground.
func _crash_watch_heli() -> void:
	var v := linear_velocity
	var dv := v - _crash_prev
	_crash_prev = v
	if _crash_quiet > 0:
		_crash_quiet -= 1
		return
	if freeze:
		return
	var hard := dv.length() - crash_dv
	if hard <= 0.0:
		return
	if engine_dead and dv.length() > crash_dv * 1.5:
		explode()
		return
	Sfx.play("hit_metal", global_position, clampf(hard, 0.0, 10.0) - 4.0)
	hurt(hard * crash_damage)
	if engine_dead and _burn_left < 0.0:
		_burn_left = burn_seconds


## Skips the crash watch for a few steps (tests, a respawn, putting it on its pad).
func hold_crash_watch(ticks: int = 2) -> void:
	_crash_quiet = maxi(_crash_quiet, ticks)
	_crash_prev = linear_velocity


## Every third step: is anything solid inside the main rotor's disc while it turns?
func _rotor_strike_check() -> void:
	if rotor_lost or spool < 0.3 or not is_inside_tree():
		return
	_strike_tick += 1
	if _strike_tick % 3 != 0:
		return
	if _strike_clear_world != Vector3.INF:
		if WorldState.to_world(global_position).distance_to(_strike_clear_world) < 3.0:
			return
		_strike_clear_world = Vector3.INF
	if rotor_hits_something():
		rotor_strike()


## A thin cylinder round the hub at the blades' sweep, against the world, terrain and props.
func rotor_hits_something() -> bool:
	if not is_inside_tree():
		return false
	if _cyl == null:
		_cyl = CylinderShape3D.new()
		_cyl.height = 0.5
	_cyl.radius = _main_radius * 0.96
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _cyl
	q.transform = Transform3D(global_basis.orthonormalized(), global_transform * (_hub_local + Vector3(0.0, 0.14, 0.0)))
	q.collision_mask = 1 | 16
	q.exclude = [get_rid()]
	return not get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


func _burn(delta: float) -> void:
	if _burn_left < 0.0:
		return
	_burn_left -= delta
	if _burn_left <= 0.0:
		explode()


## Blows up: the blast, the player thrown out, a charred, burning wreck left as debris.
func explode() -> void:
	if exploded:
		return
	exploded = true
	_burn_left = -1.0
	var who := driver
	if who != null and who.has_method("exit_vehicle"):
		who.exit_vehicle()
	Explosion.blast(self, global_position + global_basis.y * 1.2, blast_radius, blast_launch, blast_launch * 0.6, self)
	if _charred == null:
		_charred = StandardMaterial3D.new()
		_charred.albedo_color = Color(0.035, 0.032, 0.03)
		_charred.roughness = 0.95
	for m in _meshes:
		if is_instance_valid(m):
			m.material_override = _charred
	for d: MeshInstance3D in [_main_disc, _tail_disc]:
		if d:
			d.visible = false
	var lights := get_node_or_null("Lights") as Node3D
	if lights:
		lights.visible = false
	if _sound:
		_sound.stop()
	spool = 0.0
	_start_smoke(true)
	if _fire:
		_fire.amount = 40
	if _wash:
		_wash.clear()
	apply_central_impulse(Vector3(randf_range(-1, 1), 3.0, randf_range(-1, 1)) * mass * 3.0)
	angular_velocity += Vector3(randf_range(-2, 2), randf_range(-3, 3), randf_range(-2, 2))
	set_meta("wreck", true)
	remove_from_group("vehicle")
	PhysicsBudget.register_debris(self, wreck_lifetime)


func _start_smoke(with_fire: bool) -> void:
	if _smoke == null:
		_smoke = _particles(AmbientCraft._smoke_material(), 60, 3.0, Color(0.12, 0.115, 0.11, 0.75), 1.8, 6.0)
		_smoke.gravity = Vector3(0.0, 1.6, 0.0)
		_smoke.position = Vector3(0.0, 2.35, 1.6)
		add_child(_smoke)
	if with_fire and _fire == null:
		_fire = _particles(AmbientCraft._fire_material(), 28, 0.45, Color(2.4, 0.95, 0.2, 0.85), 1.2, 2.6)
		_fire.position = Vector3(0.0, 2.35, 1.6)
		add_child(_fire)
		_smoke.color = Color(0.06, 0.055, 0.05, 0.85)


func _particles(mat: Material, amount: int, life_s: float, color: Color, size_min: float, size_max: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life_s
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 25.0
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 2.0
	p.scale_amount_min = size_min
	p.scale_amount_max = size_max
	var curve := Curve.new()
	curve.max_value = 2.5
	curve.add_point(Vector2(0.0, 0.6))
	curve.add_point(Vector2(1.0, 2.5))
	p.scale_amount_curve = curve
	p.color = color
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1))
	ramp.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = ramp
	p.angle_min = -180.0
	p.angle_max = 180.0
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = mat
	p.mesh = quad
	p.custom_aabb = AABB(Vector3.ONE * -300.0, Vector3.ONE * 600.0)
	p.emitting = true
	return p


# --- Stills -----------------------------------------------------------------------------------

## For tools/glshot/still_shot.gd (HELI=...): `hover` holds a running helicopter HELI_DIST metres
## ahead of the camera, HELI_AGL over the ground there (HELI_SIDE to the right, HELI_YAW its
## heading off the camera's, HELI_LIVERY 0-3); `pad` returns an EYE framing the HeliSpot nearest
## the camera (HELI_SPOT=n the n-th nearest) and wakes its helicopter. Returns an EYE string or "".
static func stage_for_shot(kind: String, cam: Camera3D) -> String:
	var tree := cam.get_tree()
	var ws := tree.root.get_node("/root/WorldState")
	var envf := func(k: String, d: float) -> float:
		return float(OS.get_environment(k)) if OS.get_environment(k) != "" else d
	var fwd := -cam.global_basis.z
	fwd = Vector3(fwd.x, 0.0, fwd.z).normalized()
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	if kind == "pad":
		var spots := tree.get_nodes_in_group("heli_spot")
		spots.sort_custom(func(a: Node, b: Node) -> bool:
			return (a as Node3D).global_position.distance_to(cam.global_position) < (b as Node3D).global_position.distance_to(cam.global_position))
		for s: Node in spots:
			print("HELI spot %s at %s eager %s" % [s.get_path(), ws.call("to_world", (s as Node3D).global_position), s.get("eager")])
		var i := int(envf.call("HELI_SPOT", 0.0))
		if spots.is_empty() or i >= spots.size():
			print("HELI pad: no spot")
			return ""
		var spot := spots[i] as Node3D
		var t: Vector3 = ws.call("to_world", spot.global_position)
		var turn := deg_to_rad(float(envf.call("HELI_TURN", 35.0)))
		var back := float(envf.call("HELI_BACK", 19.0))
		var look := Vector3(sin(turn), 0.0, cos(turn))
		var eye: Vector3 = t + look * back + Vector3.UP * float(envf.call("HELI_UP", 7.0))
		var d: Vector3 = t + Vector3.UP * 1.5 - eye
		var yaw := rad_to_deg(atan2(-d.x, -d.z))
		var pitch := rad_to_deg(asin(d.normalized().y))
		# Held for the shot whatever the player's distance (the pose moves him about).
		spot.set("eager", true)
		spot.call("make")
		return "%.2f,%.2f,%.2f,%.1f,%.1f" % [eye.x, eye.y, eye.z, yaw, pitch]
	var dist := float(envf.call("HELI_DIST", 30.0))
	var at: Vector3 = cam.global_position + fwd * dist + right * float(envf.call("HELI_SIDE", 0.0))
	var space := cam.get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 300.0, at + Vector3.DOWN * 600.0, 1 | 16))
	var ground := float(hit.position.y) if not hit.is_empty() else at.y - 20.0
	at.y = ground + float(envf.call("HELI_AGL", 10.0))
	var root := tree.get_first_node_in_group("city") as Node3D
	if root == null:
		root = tree.current_scene as Node3D
	var h := FlyableHeli.new()
	h.name = "StagedHeli"
	h.setup_heli(int(envf.call("HELI_LIVERY", 0.0)), Rooftops.HELI_LIVERIES[1])
	var yaw := atan2(-fwd.x, -fwd.z) + deg_to_rad(float(envf.call("HELI_YAW", 90.0)))
	h.transform = root.global_transform.affine_inverse() * Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, deg_to_rad(float(envf.call("HELI_PITCH", -4.0)))), at)
	h.freeze = true
	h.hold_running = true
	h.spool = 1.0
	root.add_child(h)
	print("HELI hover at %s, %.1f m over the ground" % [ws.call("to_world", at), at.y - ground])
	return ""

