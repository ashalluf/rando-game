class_name AmbientCraft
extends AnimatableBody3D
## Base for the scripted aircraft AirTraffic flies through the sky: airliners and private jets
## (AmbientJet) and helicopters (Helicopter). None of them is simulated: each tick the subclass
## decides where it is (`world_pos`, TRUE world coordinates, and yaw / pitch / roll) and
## apply_pose() puts the body there. What they share lives here:
##   - a body on the props layer with box shapes and take_hit(), so rifle bullets, rockets and
##     Explosion.blast() hit them exactly the way they hit a street prop - no weapon code knows
##     aircraft exist. Mask 0, and the layer is dropped past `hit_range` (CLAUDE.md, masks).
##   - damage: smoke under half health; at zero it goes DOWN (the subclass decides how it
##     falls), explodes where it hits the ground with WeaponFX + Explosion.blast(), and leaves a
##     burning, charred wreck for `wreck_seconds`.
##   - the night lights, one additive billboard mesh per aircraft (shaders/aircraft_lights).
##   - the engine loop as an AudioStreamPlayer3D with a long falloff and a cheap Doppler.
##   - distance tiers: mesh LOD bias, a shadow twin cast from a coarser LOD (CLAUDE.md,
##     Performance), a fade in / out for spawning and despawning in view.
## World-space positions are why these survive origin re-centering: the streamer shifts the
## parent, apply_pose() converts world_pos back through WorldState every tick.

signal finished(craft: AmbientCraft)

enum Life { FLYING, DOWN, WRECK }

@export_group("Damage")
## Hit points. A rifle bullet does 10, a rocket blast up to 120 at its centre.
@export var health: float = 80.0
## The explosion when it hits the ground.
@export var crash_radius: float = 12.0
@export var crash_launch: float = 32.0
## Seconds the burning wreck stays before it is removed.
@export var wreck_seconds: float = 22.0
@export_group("Presence")
## Bullets and blasts only see it within this range of the camera (metres); further out the
## body leaves the collision layers entirely.
@export var hit_range: float = 650.0
## Shadow twin drawn inside this range of the camera.
@export var shadow_distance: float = 380.0
## How far the engine can be heard (metres) and how quickly it falls off (bigger = louder far).
@export var sound_range: float = 1800.0
@export var sound_unit_size: float = 40.0
@export var sound_volume_db: float = 0.0
## Seconds a fade in or out takes.
@export var fade_time: float = 2.5

## Physics layer the body sits on: props, which bullets (Player.AIM_MASK) and blasts
## (Player.BLAST_MASK) both test.
const HIT_LAYER := 4
## World + terrain: what a falling aircraft can hit.
const GROUND_MASK := 1 | 16
## Mesh LOD bias by distance tier (inside shadow_distance, to 900 m, beyond).
const LOD_BIAS := [1.0, 0.45, 0.2]
const SHADOW_LOD_BIAS := 0.3
## Speed of sound for the Doppler shift (m/s).
const SOUND_SPEED := 343.0

var traffic: Node = null
var life: Life = Life.FLYING
var world_pos: Vector3 = Vector3.ZERO
var yaw: float = 0.0
var pitch: float = 0.0
var roll: float = 0.0
## World velocity, m/s (kept up to date by the subclass; drives Doppler and the fall).
var velocity: Vector3 = Vector3.ZERO
## Where it came down, TRUE world (INF until it has).
var crash_world: Vector3 = Vector3.INF
## True once it has left for good (off its route, faded out, the wreck cleared away).
var done: bool = false
## 0 = drawn, 1 = invisible.
var fade: float = 0.0
var fading_out: bool = false

var _visual: Node3D
var _meshes: Array[MeshInstance3D] = []
var _shadows: Array[MeshInstance3D] = []
var _lights: MeshInstance3D
var _light_mat: ShaderMaterial
var _sound: AudioStreamPlayer3D
var _sound_name: String = ""
var _sound_pitch: float = 1.0
var _sound_gain_db: float = 0.0
## The level Sfx.loop_player() set (the game's master trim and this take's loudness trim).
var _sound_base_db: float = 0.0
var _smoke: CPUParticles3D
var _fire: CPUParticles3D
var _tier: int = -1
var _tier_timer: float = 0.0
var _wreck_left: float = 0.0
var _burn_left: float = -1.0
var _max_health: float = 80.0
var _rng := RandomNumberGenerator.new()

static var _smoke_mat: StandardMaterial3D
static var _fire_mat: StandardMaterial3D
static var _charred: StandardMaterial3D
static var _light_shader: Shader


func _init() -> void:
	sync_to_physics = false
	collision_layer = HIT_LAYER
	collision_mask = 0


func _ready() -> void:
	_max_health = health
	add_to_group("aircraft")


func _physics_process(delta: float) -> void:
	advance(delta)


## One step of the flight. Subclasses override _fly(); falling and the wreck are handled here.
func advance(dt: float) -> void:
	if done:
		return
	match life:
		Life.FLYING:
			_fly(dt)
			if done:
				return
		Life.DOWN:
			_fall(dt)
		Life.WRECK:
			_wreck_left -= dt
			if _wreck_left <= 0.0:
				_finish()
				return
	apply_pose()
	_update_presence(dt)


## Overridden: move `world_pos`, `yaw`, `pitch`, `roll`, `velocity`.
func _fly(_dt: float) -> void:
	pass


## Overridden: how this kind falls once it has been shot down. The default drops like a stone.
func _fall_motion(dt: float) -> void:
	velocity.y -= 9.8 * dt
	world_pos += velocity * dt


func apply_pose() -> void:
	global_transform = Transform3D(Basis.from_euler(Vector3(pitch, yaw, roll)), WorldState.to_local(world_pos))


# --- Damage -----------------------------------------------------------------------------------

## Bullets, rockets and blasts all come through here (see the class comment).
func take_hit(_shape: int, damage: float, dir: Vector3) -> void:
	if life != Life.FLYING:
		return
	health -= damage
	if health < _max_health * 0.5 and _smoke == null:
		_start_smoke(false)
	if health <= 0.0:
		go_down(dir)


func go_down(_dir: Vector3 = Vector3.ZERO) -> void:
	if life != Life.FLYING:
		return
	life = Life.DOWN
	fade = 0.0
	fading_out = false
	_apply_fade()
	_start_smoke(true)
	_begin_fall()
	if traffic and traffic.has_method("on_craft_down"):
		traffic.on_craft_down(self)


## Overridden: set up the fall (a helicopter starts spinning, a jet noses over).
func _begin_fall() -> void:
	pass


## True while it is sitting on the ground (a taxiing jet), where "down" means burn, then blow.
func _on_ground() -> bool:
	return false


func _fall(dt: float) -> void:
	if _burn_left >= 0.0:
		_burn_left -= dt
		if _burn_left <= 0.0:
			_explode(WorldState.to_local(world_pos))
		return
	if _on_ground():
		_burn_left = 1.6
		return
	var from := WorldState.to_local(world_pos)
	_fall_motion(dt)
	var to := WorldState.to_local(world_pos)
	var hit := _ground_between(from, to + (to - from).normalized() * 1.5)
	if not hit.is_empty():
		_explode(hit.position)
		return
	# No collision streamed in here (or open water): the ground under it is the map's.
	var floor_y := maxf(traffic.ground_height(Vector2(world_pos.x, world_pos.z)) if traffic else 0.0, 0.15)
	if world_pos.y <= floor_y + 0.5:
		world_pos.y = floor_y + 0.5
		_explode(WorldState.to_local(world_pos))


func _ground_between(from: Vector3, to: Vector3, exclude: Array[RID] = []) -> Dictionary:
	if not is_inside_tree() or from.is_equal_approx(to):
		return {}
	var skip: Array[RID] = [get_rid()]
	skip.append_array(exclude)
	var q := PhysicsRayQueryParameters3D.create(from, to, GROUND_MASK, skip)
	return get_world_3d().direct_space_state.intersect_ray(q)


func _explode(at_local: Vector3) -> void:
	if life == Life.WRECK:
		return
	life = Life.WRECK
	crash_world = WorldState.to_world(at_local)
	world_pos = crash_world + Vector3.UP * 0.4
	velocity = Vector3.ZERO
	collision_layer = 0
	Explosion.blast(self, at_local, crash_radius, crash_launch, crash_launch * 0.6)
	_become_wreck()
	_wreck_left = wreck_seconds
	if traffic and traffic.has_method("on_craft_crashed"):
		traffic.on_craft_crashed(self)


## The model stays where it came down, charred and burning, until wreck_seconds run out.
func _become_wreck() -> void:
	if _charred == null:
		_charred = StandardMaterial3D.new()
		_charred.albedo_color = Color(0.035, 0.032, 0.03)
		_charred.roughness = 0.95
	for m in _meshes:
		if is_instance_valid(m):
			m.material_override = _charred
	for s in _shadows:
		if is_instance_valid(s):
			s.material_override = _charred
	if _lights:
		_lights.visible = false
	if _sound:
		_sound.stop()
	pitch = clampf(pitch, -0.25, 0.25)
	roll = clampf(roll, -0.6, 0.6)
	if _fire:
		_fire.amount = 40
		_fire.lifetime = 0.9
	if _smoke:
		_smoke.lifetime = 5.0
		_smoke.gravity = Vector3(0.0, 3.0, 0.0)


## Takes it out of the sky now (AirTraffic: a helicopter that has flown off, tests).
func remove() -> void:
	_finish()


func _finish() -> void:
	if done:
		return
	done = true
	finished.emit(self)
	queue_free()


# --- Smoke and fire ---------------------------------------------------------------------------

func _start_smoke(with_fire: bool) -> void:
	if _smoke == null:
		_smoke = _particles(_smoke_material(), 70, 3.2, Color(0.12, 0.115, 0.11, 0.75), 2.5, 7.0)
		_smoke.gravity = Vector3(0.0, 1.6, 0.0)
		_smoke.position = _smoke_origin()
		add_child(_smoke)
	if with_fire and _fire == null:
		_fire = _particles(_fire_material(), 28, 0.45, Color(2.4, 0.9, 0.22, 0.85), 1.4, 2.8)
		_fire.position = _smoke_origin()
		add_child(_fire)
		# Darker, thicker smoke once it is burning.
		_smoke.color = Color(0.06, 0.055, 0.05, 0.85)


## Where on the body the smoke pours from (overridden: the engine).
func _smoke_origin() -> Vector3:
	return Vector3.ZERO


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
	# Raise the cap before a growth above 1 (CLAUDE.md, effects: a Curve clamps to max_value).
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
	# The trail is in world space and can stretch hundreds of metres behind a fast jet; bounds
	# that start empty make the whole trail vanish (CLAUDE.md, effects).
	p.custom_aabb = AABB(Vector3.ONE * -400.0, Vector3.ONE * 800.0)
	p.emitting = true
	return p


static func _smoke_material() -> StandardMaterial3D:
	if _smoke_mat == null:
		_smoke_mat = _puff(false)
		# Behind the fire whatever the depth order, as WeaponFX draws its blast smoke.
		_smoke_mat.render_priority = -1
	return _smoke_mat


static func _fire_material() -> StandardMaterial3D:
	if _fire_mat == null:
		_fire_mat = _puff(true)
	return _fire_mat


static func _puff(additive: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	# Or every puff is exactly a metre whatever its scale (CLAUDE.md, effects).
	mat.billboard_keep_scale = true
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = WeaponFX.puff_texture()
	mat.disable_receive_shadows = true
	return mat


# --- Lights -----------------------------------------------------------------------------------

enum LightKind { STEADY, STROBE, BEACON, LANDING }

## One mesh for every light on the aircraft (see shaders/aircraft_lights.gdshader). Each spec is
## [local position, colour, size (m), LightKind, facing (Vector3.ZERO = all round)].
func _build_lights(specs: Array) -> void:
	if _light_shader == null:
		_light_shader = load("res://shaders/aircraft_lights.gdshader")
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# One phase per aircraft for each flashing kind: a plane's strobes flash together.
	var phase := _rng.randf()
	var corners := [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0)]
	var idx := 0
	for spec: Array in specs:
		var kind: int = spec[3]
		var code := float(kind) * 10.0 + phase * 9.0
		for k in [0, 1, 2, 0, 2, 3]:
			st.set_color(spec[1])
			st.set_uv(corners[k])
			st.set_uv2(Vector2(spec[2], code))
			st.set_normal(spec[4])
			st.add_vertex(spec[0])
		idx += 1
	var mesh := st.commit()
	_light_mat = ShaderMaterial.new()
	_light_mat.shader = _light_shader
	mesh.surface_set_material(0, _light_mat)
	_lights = MeshInstance3D.new()
	_lights.name = "Lights"
	_lights.mesh = mesh
	_lights.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Every corner of a light sits on its centre, so the mesh's own bounds are points; and the
	# lights are drawn past the far plane on purpose (the shader pulls them in).
	_lights.custom_aabb = AABB(Vector3.ONE * -60.0, Vector3.ONE * 120.0)
	_lights.extra_cull_margin = 16000.0
	add_child(_lights)


func set_landing_lights(on: bool) -> void:
	if _light_mat:
		_light_mat.set_shader_parameter("landing_on", 1.0 if on else 0.0)


# --- Model, shadow twin, fade -----------------------------------------------------------------

## Registers every mesh under `root` for LOD tiers, fades and the wreck, and gives each a
## shadow-only twin at a coarser LOD while the mesh itself casts nothing.
func _adopt_meshes(root: Node) -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var m := n as MeshInstance3D
		if m == null or m.mesh == null or m == _lights:
			continue
		_meshes.append(m)
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var twin := MeshInstance3D.new()
		twin.name = "Shadow"
		twin.mesh = m.mesh
		for si in m.mesh.get_surface_count():
			twin.set_surface_override_material(si, m.get_surface_override_material(si))
		twin.material_override = m.material_override
		twin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		twin.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		twin.lod_bias = SHADOW_LOD_BIAS
		m.add_child(twin)
		_shadows.append(twin)


func _apply_fade() -> void:
	for m in _meshes:
		if is_instance_valid(m):
			m.transparency = fade
	for s in _shadows:
		if is_instance_valid(s):
			s.visible = fade < 0.5 and _tier == 0
	if _lights:
		_lights.visible = fade < 0.95 and life != Life.WRECK
	if _light_mat:
		_light_mat.set_shader_parameter("day_level", 0.22 * (1.0 - fade))


## Steps a fade in (fading_out false) or out; true once a fade out is complete.
func _step_fade(dt: float) -> bool:
	var target := 1.0 if fading_out else 0.0
	# Exact, not approximate: an is_equal_approx() stop left a fade in at 1e-7 for good, and
	# everything waiting for "fully in" waited forever.
	if fade == target:
		return fading_out
	fade = move_toward(fade, target, dt / maxf(fade_time, 0.01))
	_apply_fade()
	return fading_out and fade >= 1.0


# --- Distance tiers, sound --------------------------------------------------------------------

func _camera() -> Camera3D:
	var vp := get_viewport()
	return vp.get_camera_3d() if vp else null


func _update_presence(dt: float) -> void:
	_tier_timer -= dt
	if _tier_timer > 0.0:
		return
	_tier_timer = 0.2
	var cam := _camera()
	var eye: Vector3 = cam.global_position if cam else Vector3.ZERO
	var here := global_position
	var dist := eye.distance_to(here)
	var tier := 0 if dist < shadow_distance else (1 if dist < 900.0 else 2)
	if tier != _tier:
		_tier = tier
		for m in _meshes:
			if is_instance_valid(m):
				m.lod_bias = LOD_BIAS[tier]
		for s in _shadows:
			if is_instance_valid(s):
				s.visible = tier == 0 and fade < 0.5
	if life != Life.WRECK:
		collision_layer = HIT_LAYER if dist < hit_range else 0
	_update_sound(dist, eye, here)


## Starts the loop `sample` (an Sfx name). Volume and pitch are then set per tick by
## set_engine(); the Doppler shift is added on top.
func _start_sound(sample: String) -> void:
	_sound_name = sample
	_sound = Sfx.loop_player(sample, sound_volume_db)
	_sound_base_db = _sound.volume_db
	_sound.max_distance = sound_range
	_sound.unit_size = sound_unit_size
	# Distant engines are a rumble, not a hiss: the far end of the falloff loses its top.
	_sound.attenuation_filter_cutoff_hz = 3500.0
	_sound.attenuation_filter_db = -30.0
	_sound.name = "Engine"
	add_child(_sound)


## The engine's own level (dB on top of sound_volume_db) and pitch, before Doppler.
func set_engine(gain_db: float, pitch_scale: float) -> void:
	_sound_gain_db = gain_db
	_sound_pitch = pitch_scale


func _update_sound(dist: float, eye: Vector3, here: Vector3) -> void:
	if _sound == null:
		return
	var audible := dist < sound_range and life != Life.WRECK
	if not audible:
		if _sound.playing:
			_sound.stop()
		return
	if not _sound.playing:
		_sound.play(_rng.randf_range(0.0, 4.0))
	var to_eye := (eye - here)
	var closing := velocity.dot(to_eye.normalized()) if to_eye.length() > 1.0 else 0.0
	var doppler := clampf(SOUND_SPEED / maxf(SOUND_SPEED - closing, 100.0), 0.7, 1.35)
	_sound.pitch_scale = clampf(_sound_pitch * doppler, 0.3, 2.5)
	_sound.volume_db = _sound_base_db + _sound_gain_db


# --- Helpers ----------------------------------------------------------------------------------

## Forward (-Z) of a yaw, flat.
static func yaw_dir(y_rad: float) -> Vector3:
	return Vector3(-sin(y_rad), 0.0, -cos(y_rad))


static func yaw_of(d: Vector3) -> float:
	return atan2(-d.x, -d.z)


func _box_shape(size: Vector3, at: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = at
	add_child(cs)
