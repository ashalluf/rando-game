class_name ChaseFlatTyres
extends Node3D
## A car's punctured tyres (a police spike strip, PoliceChase). A child of the Vehicle, made by
## the first puncture. Each flat wheel:
##   * sinks on its rim: the VehicleWheel3D's radius drops by `rim_drop` (the hub rides lower, so
##     the drawn tyre squats into the road by that much - the look of a flat - and the corner of the
##     car goes down with it);
##   * loses most of its grip (`grip`, a share of what it had), so the car wanders and slides;
##   * drags (a flat tyre's rolling resistance, `drag` per flat at speed), and shakes the car;
##   * throws sparks off the rim on the road and grinds (Sfx `scrape`) past `spark_speed`.
## Nothing is restored: a car with flats keeps them (it is a wreck in the making).

## How far the wheel radius drops (m), the share of grip a flat keeps, the drag deceleration per
## flat wheel (m/s squared at speed) and the wobble (rad/s of yaw kick, a few times a second).
@export var rim_drop: float = 0.075
@export var grip: float = 0.32
@export var drag: float = 1.6
@export var wobble: float = 0.32
@export var spark_speed: float = 6.0

var car: Vehicle
## Bits: which of car.wheels are flat.
var flat_mask: int = 0
var _sparks: Dictionary = {}
var _scrape: AudioStreamPlayer3D
var _t: float = 0.0


## Punctures wheel `i` of `car` (true if it was not flat already).
static func puncture(car: Vehicle, i: int) -> bool:
	if car == null or i < 0 or i >= car.wheels.size():
		return false
	var ft := car.get_node_or_null("FlatTyres") as ChaseFlatTyres
	if ft == null:
		ft = ChaseFlatTyres.new()
		ft.name = "FlatTyres"
		ft.car = car
		car.add_child(ft)
	if ft.flat_mask & (1 << i):
		return false
	ft.flat_mask |= 1 << i
	var w := car.wheels[i]
	w.set_meta("flat", true)
	w.wheel_radius = maxf(w.wheel_radius - ft.rim_drop, 0.12)
	w.wheel_friction_slip *= ft.grip
	ft._add_sparks(i)
	Sfx.play("hit_metal", w.global_position, 3.0, 0.5)
	Sfx.play("casing", w.global_position, 0.0, 0.4)
	car.hold_crash_watch(2)
	return true


## The share of grip a wheel keeps for its flat (1 when it has none): whoever restores a wheel's
## grip after changing it (the PIT's slide) multiplies by this.
static func grip_of(w: VehicleWheel3D) -> float:
	if w == null or not w.has_meta("flat"):
		return 1.0
	var ft := w.get_parent().get_node_or_null("FlatTyres") as ChaseFlatTyres if w.get_parent() else null
	return ft.grip if ft else 1.0


## How many of `car`'s tyres are flat.
static func flats(car: Vehicle) -> int:
	var ft := car.get_node_or_null("FlatTyres") as ChaseFlatTyres if car else null
	if ft == null:
		return 0
	var n := 0
	for i in 8:
		if ft.flat_mask & (1 << i):
			n += 1
	return n


func _add_sparks(i: int) -> void:
	if OS.has_feature("web") and _sparks.size() >= 2:
		return
	var p := CPUParticles3D.new()
	p.name = "RimSparks%d" % i
	p.amount = 24
	p.lifetime = 0.35
	p.emitting = false
	p.local_coords = false
	p.direction = Vector3(0.0, 0.6, 1.0)
	p.spread = 35.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 8.0
	p.gravity = Vector3(0.0, -9.8, 0.0)
	p.scale_amount_min = 0.02
	p.scale_amount_max = 0.05
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(3.0, 1.6, 0.5)
	quad.material = mat
	p.mesh = quad
	p.custom_aabb = AABB(Vector3(-6, -3, -6), Vector3(12, 6, 12))
	add_child(p)
	_sparks[i] = p


func _physics_process(delta: float) -> void:
	if car == null or not is_instance_valid(car) or car.freeze:
		return
	var n := flats(car)
	if n == 0:
		return
	var v := car.linear_velocity
	var flat_v := Vector2(v.x, v.z).length()
	_t += delta
	var grounded := false
	for i in car.wheels.size():
		var w := car.wheels[i]
		if not is_instance_valid(w) or not (flat_mask & (1 << i)):
			continue
		var on := w.is_in_contact()
		grounded = grounded or on
		var sp: CPUParticles3D = _sparks.get(i)
		if sp:
			sp.global_position = w.global_position - Vector3.UP * maxf(w.wheel_radius - 0.03, 0.1)
			var back := -v.normalized() if flat_v > 0.5 else Vector3.BACK
			sp.direction = (back + Vector3.UP * 0.5).normalized()
			sp.emitting = on and flat_v > spark_speed
	if grounded and flat_v > 2.0:
		# Rolling drag, capped so it never reverses the car.
		var dv := minf(drag * float(n) * delta * clampf(flat_v / 15.0, 0.3, 1.0), flat_v)
		car.apply_central_impulse(-Vector3(v.x, 0.0, v.z).normalized() * dv * car.mass)
		# The flapping tyre: small yaw kicks, faster with speed.
		var k := sin(_t * (6.0 + flat_v * 0.35)) * wobble * clampf(flat_v / 20.0, 0.0, 1.0) * delta * 8.0
		car.apply_torque_impulse(Vector3.UP * k * car.mass)
	var grind := grounded and flat_v > spark_speed
	if grind and _scrape == null and Sfx.has("scrape"):
		_scrape = Sfx.loop_player("scrape", -8.0)
		add_child(_scrape)
	if _scrape:
		if grind and not _scrape.playing:
			_scrape.play()
		elif not grind and _scrape.playing:
			_scrape.stop()
		if grind:
			_scrape.pitch_scale = clampf(0.7 + flat_v / 40.0, 0.7, 1.4)
