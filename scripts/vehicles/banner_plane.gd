class_name BannerPlane
extends AmbientCraft
## A banner tow plane (SkyAds, docs/HANDOFF.md "Aerial advertising"): a two-seat taildragger
## flying slow laps of a racetrack off the beach with a letter banner on 55 m of rope. Scripted
## on an AirRoute like AirTraffic's craft; the banner and the rope are top-level meshes placed
## each tick from the route BEHIND the plane (so a turn swings the banner round after it, the
## way a towed thing follows), and the cloth flutters in shaders/sky_ads.gdshader.
## Shot, the plane takes take_hit() like any AmbientCraft (it is light: a few rounds); the
## banner has its own body: shoot it enough and it tears off the rope and flutters down. A plane
## that goes down cuts its banner loose too.

## Airspeed (m/s; banner tows fly at 40-50 knots).
@export var speed: float = 23.0
## Rope from the hook to the banner's lead pole (m), and how far the banner rides below the
## plane at its pole (m).
@export var tow_length: float = 55.0
@export var tow_drop: float = 9.0
## The most it banks (degrees).
@export var max_bank: float = 28.0
@export var bank_rate: float = 1.2
## Hit points of the banner (bullets do 10).
@export var banner_health: float = 120.0
## Seconds a cut banner falls before it is cleared away.
@export var banner_fall_seconds: float = 40.0

var route: AirRoute
var s: float = 0.0
var text: String = ""
var ink: Color = Color(0.1, 0.12, 0.5)
var banner: MeshInstance3D
var banner_body: AnimatableBody3D
var rope: MeshInstance3D
var banner_length: float = 30.0
## True once the banner has come off.
var banner_cut: bool = false
var _banner_vel: Vector3 = Vector3.ZERO
var _banner_world: Transform3D
var _banner_left: float = 0.0
var _banner_hp: float = 0.0
## The physics frame the banner's body was first placed in (-1 not yet); its hit layer goes on
## in a later one (see _build_banner).
var _banner_placed_frame: int = -1
var _clock: float = 0.0


func _init() -> void:
	super()
	health = 45.0
	crash_radius = 9.0
	crash_launch = 24.0
	wreck_seconds = 25.0
	hit_range = 900.0
	shadow_distance = 320.0
	sound_range = 1400.0
	sound_unit_size = 22.0
	sound_volume_db = -4.0


func _ready() -> void:
	super()
	name = "BannerPlane"
	add_to_group("sky_ads")
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	var mi := MeshInstance3D.new()
	mi.name = "Plane"
	mi.mesh = SkyAdMesh.plane()
	_visual.add_child(mi)
	_adopt_meshes(_visual)
	_build_lights(SkyAdMesh.plane_light_specs())
	_box_shape(Vector3(0.9, 1.3, 6.8), Vector3(0.0, 0.35, 0.35))
	_box_shape(Vector3(10.7, 0.25, 1.6), Vector3(0.0, 1.06, -0.75))
	_box_shape(Vector3(3.4, 1.1, 0.9), Vector3(0.0, 0.7, 3.3))
	_build_banner()
	_start_sound("engine_loop")
	set_engine(0.0, 1.35)


func _build_banner() -> void:
	banner = MeshInstance3D.new()
	banner.name = "Banner"
	banner.mesh = SkyAdMesh.banner(text, ink)
	banner.top_level = true
	banner_length = float(banner.mesh.get_meta("length", 30.0))
	add_child(banner)
	_adopt_meshes(banner)
	rope = MeshInstance3D.new()
	rope.name = "Rope"
	rope.mesh = SkyAdMesh.rope()
	rope.top_level = true
	rope.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rope)
	_meshes.append(rope)
	# The banner's own body: bullets that hit the cloth hurt the cloth, not the plane.
	var hit := BannerHit.new()
	hit.plane = self
	banner_body = hit
	banner_body.name = "BannerBody"
	banner_body.sync_to_physics = false
	# No layer until it has been placed and a step has run there (`_banner_placed_frame`): it enters the
	# tree at the local origin - where the player stands after a re-centre - and Godot takes the
	# first move to its place as the kinematic body's velocity (km in a step: it fired a boat at
	# the origin off at 200,000 m/s).
	banner_body.collision_layer = 0
	banner_body.collision_mask = 0
	banner_body.top_level = true
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.4, SkyAdMesh.BANNER_HEIGHT, banner_length)
	cs.shape = box
	cs.position = Vector3(0.0, 0.0, banner_length * 0.5)
	banner_body.add_child(cs)
	add_child(banner_body)
	_banner_hp = banner_health


## Takes the banner's hits (BannerHit forwards them).
func banner_hit(damage: float) -> void:
	if banner_cut:
		return
	_banner_hp -= damage
	if _banner_hp <= 0.0:
		cut_banner()


## The banner comes off the rope and falls, fluttering, with most of the air's speed.
func cut_banner() -> void:
	if banner_cut or banner == null:
		return
	banner_cut = true
	_banner_left = banner_fall_seconds
	_banner_vel = yaw_dir(yaw) * speed * 0.7 + Vector3.UP * 2.0
	if rope:
		rope.visible = false
	if banner_body:
		banner_body.collision_layer = 0


func place_at(d: float, dt: float = 0.0) -> void:
	s = fposmod(d, maxf(route.length, 1.0))
	var smp := route.sample(s)
	world_pos = smp.pos
	yaw = smp.yaw
	var bank := clampf(atan(speed * speed * float(smp.turn) / 9.8), -deg_to_rad(max_bank), deg_to_rad(max_bank))
	roll = bank if dt <= 0.0 else lerp_angle(roll, bank, 1.0 - exp(-bank_rate * dt))
	# Nose a little up: slow flight with a banner behind is high drag, high angle of attack.
	pitch = 0.07 + atan(float(smp.grade))
	velocity = yaw_dir(yaw) * speed


func _fly(dt: float) -> void:
	_clock += dt
	if route == null:
		return
	place_at(s + speed * dt, dt)
	set_engine(0.0, 1.35 + 0.03 * sin(_clock * 0.9))
	if fading_out or fade > 0.0:
		if _step_fade(dt):
			_finish()


func apply_pose() -> void:
	super()
	_place_banner(get_physics_process_delta_time())


## The banner's lead pole sits on the route `tow_length` behind the hook and `tow_drop` lower;
## the cloth runs back along the chord to where the route was a banner's length before that.
func _place_banner(dt: float) -> void:
	if banner == null:
		return
	if banner_cut:
		if _banner_left <= 0.0:
			return
		_banner_left -= dt
		# Falling cloth: drag holds it near its terminal speed, it tumbles a little.
		_banner_vel.y = move_toward(_banner_vel.y, -7.0, 9.8 * dt)
		_banner_vel = Vector3(_banner_vel.x * exp(-0.6 * dt), _banner_vel.y, _banner_vel.z * exp(-0.6 * dt))
		_banner_world.origin += _banner_vel * dt
		_banner_world.basis = _banner_world.basis.rotated(Vector3.UP, 0.15 * dt).orthonormalized()
		var floor_y: float = (traffic.ground_height(Vector2(_banner_world.origin.x, _banner_world.origin.z)) if traffic and traffic.has_method("ground_height") else 0.0) + 0.6
		if _banner_world.origin.y < floor_y:
			_banner_world.origin.y = floor_y
			_banner_vel = Vector3.ZERO
		banner.global_transform = Transform3D(_banner_world.basis, WorldState.to_local(_banner_world.origin))
		if _banner_left <= 0.0:
			banner.visible = false
		return
	if route == null:
		return
	var hook := global_transform * SkyAdMesh.TOW_HOOK
	var hook_w := WorldState.to_world(hook)
	var d0 := s - 4.0 - tow_length
	var d1 := d0 - banner_length
	var p0: Vector3 = route.sample(fposmod(d0, route.length)).pos
	var p1: Vector3 = route.sample(fposmod(d1, route.length)).pos
	p0.y = hook_w.y - tow_drop
	p1.y = p0.y - 1.5
	var back := (p1 - p0)
	if back.length() < 1.0:
		back = -yaw_dir(yaw)
	var z := back.normalized()
	var x := Vector3.UP.cross(z).normalized()
	var y := z.cross(x).normalized()
	_banner_world = Transform3D(Basis(x, y, z), p0 + Vector3(0.0, 0.0, 0.0))
	var local := Transform3D(_banner_world.basis, WorldState.to_local(p0))
	banner.global_transform = local
	if banner_body:
		banner_body.global_transform = local
		var f := Engine.get_physics_frames()
		if _banner_placed_frame < 0:
			_banner_placed_frame = f
		elif f > _banner_placed_frame and banner_body.collision_layer == 0 and not banner_cut:
			banner_body.collision_layer = HIT_LAYER
	if rope:
		var top := local * Vector3(0.0, SkyAdMesh.BANNER_HEIGHT * 0.5 + 0.2, 0.15)
		var span := top - hook
		if span.length() > 0.5:
			var rz := span.normalized()
			var rx := Vector3.UP.cross(rz)
			if rx.length() < 0.01:
				rx = Vector3.RIGHT
			rx = rx.normalized()
			rope.global_transform = Transform3D(Basis(rx, rz.cross(rx), rz * span.length()), hook)


## A shot-down tow plane cuts its banner and spins in.
func _begin_fall() -> void:
	cut_banner()
	velocity = yaw_dir(yaw) * speed + Vector3.UP * velocity.y


func _fall_motion(dt: float) -> void:
	velocity.y -= 8.5 * dt
	velocity *= 1.0 - 0.08 * dt
	world_pos += velocity * dt
	var horiz := Vector2(velocity.x, velocity.z).length()
	pitch = lerp_angle(pitch, atan2(velocity.y, maxf(horiz, 1.0)) - 0.25, 1.0 - exp(-1.6 * dt))
	yaw += 1.1 * dt
	roll += deg_to_rad(70.0) * dt
	set_engine(3.0, 1.6)


func _become_wreck() -> void:
	super()
	if rope:
		rope.visible = false
	# The cloth that came off is not what burned.
	if banner:
		banner.material_override = null
		for tw in banner.get_children():
			if tw is MeshInstance3D:
				(tw as MeshInstance3D).material_override = null


func _smoke_origin() -> Vector3:
	return Vector3(0.0, 0.3, -2.4)


## The banner's body: hands bullets and blasts to its plane.
class BannerHit:
	extends AnimatableBody3D
	var plane: Node = null

	func take_hit(_shape: int, damage: float, _dir: Vector3) -> void:
		if plane and is_instance_valid(plane):
			plane.banner_hit(damage)
