class_name AdBlimp
extends AmbientCraft
## The FIZZLY advertising blimp (SkyAds, docs/HANDOFF.md "Aerial advertising"): a 60 m airship
## that loops between the ballpark and the beach on an AirRoute at walking-pace airship speeds,
## its night sign (SkyAdMesh.K_LED) scrolling the brand's lines along both flanks. Scripted like
## AirTraffic's craft (AmbientCraft): bullets, rockets and blasts hit it through take_hit(); it
## takes a lot of them. Shot down, the envelope loses its gas: it sags, noses down, burns and
## sinks onto whatever is under it, and blows up there.

## Airspeed along the route (m/s; real advertising airships cruise at 50-60 km/h).
@export var speed: float = 14.0
## How far it rocks with the air (m) and how fast (rad/s).
@export var bob_height: float = 1.6
@export var bob_rate: float = 0.21
## The most it banks in a turn (degrees: an airship hardly does).
@export var max_bank: float = 4.0
## Seconds a deflating envelope takes to sag to `sag_scale` of its height.
@export var deflate_seconds: float = 14.0
@export var sag_scale: float = 0.55

var route: AirRoute
## Distance along the route (m).
var s: float = 0.0
var _clock: float = 0.0
var _deflate: float = 0.0
var _mesh: MeshInstance3D


func _init() -> void:
	super()
	health = 900.0
	crash_radius = 22.0
	crash_launch = 30.0
	wreck_seconds = 40.0
	hit_range = 2200.0
	shadow_distance = 700.0
	sound_range = 1100.0
	sound_unit_size = 30.0
	sound_volume_db = -8.0


func _ready() -> void:
	super()
	name = "AdBlimp"
	add_to_group("sky_ads")
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	_mesh = MeshInstance3D.new()
	_mesh.name = "Blimp"
	_mesh.mesh = SkyAdMesh.blimp()
	_visual.add_child(_mesh)
	_adopt_meshes(_visual)
	_build_lights(SkyAdMesh.blimp_light_specs())
	# The envelope (a capsule along its length), the gondola and the fins.
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = SkyAdMesh.ENV_RADIUS * 0.95
	cap.height = SkyAdMesh.ENV_LENGTH * 0.96
	cs.shape = cap
	cs.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	add_child(cs)
	_box_shape(Vector3(2.8, 2.6, SkyAdMesh.GONDOLA_LEN), Vector3(0.0, SkyAdMesh.GONDOLA_Y + 1.25, -SkyAdMesh.ENV_LENGTH * 0.5 + 17.0 + SkyAdMesh.GONDOLA_LEN * 0.5))
	_box_shape(Vector3(13.0, 13.0, 11.0), Vector3(0.0, 0.0, 22.0))
	_start_sound("rotor_loop")
	set_engine(-6.0, 0.42)


## Where it is at distance `d` along the route: world position and attitude.
func place_at(d: float) -> void:
	s = fposmod(d, maxf(route.length, 1.0))
	var smp := route.sample(s)
	world_pos = smp.pos
	world_pos.y += bob_height * sin(_clock * bob_rate)
	yaw = smp.yaw
	roll = clampf(atan(speed * speed * float(smp.turn) / 9.8), -deg_to_rad(max_bank), deg_to_rad(max_bank))
	pitch = atan(float(smp.grade)) * 0.6 + 0.012 * sin(_clock * bob_rate * 1.7)
	velocity = yaw_dir(yaw) * speed


func _fly(dt: float) -> void:
	_clock += dt
	if route == null:
		return
	place_at(s + speed * dt)
	set_engine(-6.0, 0.42 + 0.02 * sin(_clock * 0.7))
	if fading_out or fade > 0.0:
		if _step_fade(dt):
			_finish()


func _smoke_origin() -> Vector3:
	return Vector3(0.0, SkyAdMesh.ENV_RADIUS * 0.6, 4.0)


func _begin_fall() -> void:
	velocity = yaw_dir(yaw) * speed * 0.8
	_deflate = 0.0
	if _fire:
		# A burning envelope: a long sheet of flame along the top.
		_fire.amount = 60
		_fire.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		_fire.emission_box_extents = Vector3(3.0, 1.0, 18.0)
		_fire.scale_amount_min = 3.0
		_fire.scale_amount_max = 6.0
	if _smoke:
		_smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		_smoke.emission_box_extents = Vector3(3.0, 1.0, 16.0)
		_smoke.scale_amount_min = 5.0
		_smoke.scale_amount_max = 12.0


## It loses gas: sags, noses down, slows, and sinks faster as it goes.
func _fall_motion(dt: float) -> void:
	_deflate = minf(_deflate + dt / maxf(deflate_seconds, 0.1), 1.0)
	var flat := Vector3(velocity.x, 0.0, velocity.z) * exp(-0.12 * dt)
	var sink := lerpf(2.0, 11.0, _deflate)
	velocity = Vector3(flat.x, move_toward(velocity.y, -sink, 3.0 * dt), flat.z)
	world_pos += velocity * dt
	pitch = lerp_angle(pitch, -0.42 * _deflate, 1.0 - exp(-0.8 * dt))
	roll = lerp_angle(roll, 0.25 * _deflate, 1.0 - exp(-0.5 * dt))
	if _visual:
		var sag := lerpf(1.0, sag_scale, _deflate)
		_visual.scale = Vector3(lerpf(1.0, 1.12, _deflate), sag, lerpf(1.0, 0.92, _deflate))
	set_engine(-14.0, 0.3)


func _become_wreck() -> void:
	super()
	if _visual:
		_visual.scale = Vector3(1.25, 0.18, 0.9)
