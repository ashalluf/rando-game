class_name BoatWake
extends Node3D
## A boat's water (Boat): the wake - a churned white trail from the stern spreading behind, and
## the two arms of the Kelvin V peeling off the bow quarters at about 19.5 degrees either side -,
## the bow's spray sheets thrown out sideways at speed, the jet ski's rooster tail, the hull's
## slap and splash coming down off a wave. Flat foam and mist on SwimFX's materials (the
## swimmer's), CPUParticles3D in world space; emitters ride the water's surface under the hull.
## One node per boat; nothing runs past `fx_range` of the camera or while the boat is still.

## Beyond this distance from the camera no particles are emitted.
const FX_RANGE := 160.0
## Kelvin's wake half-angle (radians).
const KELVIN := 0.34

var boat: Boat
var _trail: CPUParticles3D
var _arms: Array[CPUParticles3D] = []
var _spray: Array[CPUParticles3D] = []
var _rooster: CPUParticles3D
var _web := OS.has_feature("web")


func _ready() -> void:
	var s: Vector2 = BoatKit.SIZE[boat.kind] if boat else Vector2(7.4, 2.5)
	var big := boat == null or boat.kind == BoatKit.Kind.SPEEDBOAT
	_trail = _foam(70 if not _web else 30, 7.0, Vector3(s.y * 0.35, 0.0, 0.25), 1.4 if big else 0.9, 5.5 if big else 3.5)
	for side: float in [-1.0, 1.0]:
		var a := _foam(40 if not _web else 16, 6.0, Vector3(0.15, 0.0, 0.3), 0.7, 3.2 if big else 2.0)
		a.set_meta("side", side)
		_arms.append(a)
		_spray.append(_drops(36 if not _web else 14, 0.9, SwimFX.drop_material(), Color(0.9, 0.95, 1.0, 0.75), 0.06, 0.16))
	if not big:
		_rooster = _drops(60 if not _web else 24, 1.1, SwimFX.mist_material(), Color(0.95, 0.97, 1.0, 0.55), 0.5, 1.4)


func _foam(n: int, life: float, box: Vector3, s0: float, s1: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = n
	p.lifetime = life
	p.local_coords = false
	p.emitting = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = box
	p.gravity = Vector3.ZERO
	p.spread = 30.0
	# Spread in the water's plane only: a cone sent half the foam down under the surface.
	p.flatness = 1.0
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.6
	p.damping_min = 0.3
	p.damping_max = 0.6
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.scale_amount_curve = SwimFX._grow(s0, s1)
	p.color_ramp = _ramp(0.85)
	p.mesh = SwimFX._flat(1.0, SwimFX.foam_material())
	p.custom_aabb = AABB(Vector3(-60, -4, -60), Vector3(120, 10, 120))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p


func _drops(n: int, life: float, mat: Material, col: Color, s0: float, s1: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = n
	p.lifetime = life
	p.local_coords = false
	p.emitting = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.2
	p.gravity = Vector3(0.0, -9.8, 0.0)
	p.spread = 14.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 6.0
	p.scale_amount_curve = SwimFX._grow(s0, s1)
	var g := Gradient.new()
	g.set_color(0, col)
	g.set_color(1, Color(col.r, col.g, col.b, 0.0))
	p.color_ramp = g
	p.mesh = SwimFX._quad(1.0, mat)
	p.custom_aabb = AABB(Vector3(-30, -4, -30), Vector3(60, 20, 60))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p


static func _ramp(a0: float) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, a0))
	g.add_point(0.15, Color(1, 1, 1, a0 * 0.85))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0.0))
	return g


## The share of the effects to emit (0 still, 1 flat out): what the checks read.
func level() -> float:
	if boat == null or boat.wet <= 0.0 or boat.water.is_empty():
		return 0.0
	return clampf((boat.linear_velocity.length() - 1.0) / (boat.boat_top_speed * 0.7), 0.0, 1.0)


func drive(_delta: float) -> void:
	if boat == null:
		return
	var lv := level()
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null and cam.global_position.distance_to(boat.global_position) > FX_RANGE:
		lv = 0.0
	var on := lv > 0.02
	var s: Vector2 = BoatKit.SIZE[boat.kind]
	var xf := boat.global_transform
	var surf := 0.0
	if not boat.water.is_empty():
		surf = WorldState.to_local(Vector3(0.0, float(boat.water.surface), 0.0)).y + 0.04
	var fwd := Vector3(-xf.basis.z.x, 0.0, -xf.basis.z.z).normalized()
	var right := Vector3(xf.basis.x.x, 0.0, xf.basis.x.z).normalized()
	var v := boat.linear_velocity.length()
	var stern := xf * Vector3(0.0, 0.0, s.x * 0.48)
	_place(_trail, Vector3(stern.x, surf, stern.z), -fwd, on)
	_trail.initial_velocity_max = 0.6 + lv * 1.5
	for i in 2:
		var side: float = _arms[i].get_meta("side")
		var bow := xf * Vector3(side * s.y * 0.35, 0.0, -s.x * 0.18)
		var out := (-fwd * cos(KELVIN) + right * side * sin(KELVIN)).normalized()
		_place(_arms[i], Vector3(bow.x, surf, bow.z), out, on and lv > 0.15)
		_arms[i].initial_velocity_min = v * 0.25
		_arms[i].initial_velocity_max = v * 0.35
		# Spray: thrown out of the chine forward of amidships, up and out.
		var chine := xf * Vector3(side * s.y * 0.45, 0.0, -s.x * 0.12)
		var sd := (right * side * 0.85 + Vector3.UP * 0.55 - fwd * 0.2).normalized()
		_place(_spray[i], Vector3(chine.x, surf + 0.05, chine.z), sd, on and lv > 0.3)
		_spray[i].initial_velocity_min = 2.0 + lv * 4.0
		_spray[i].initial_velocity_max = 3.5 + lv * 6.0
	if _rooster:
		var nz := xf * Vector3(0.0, 0.0, s.x * 0.5)
		var thr := maxf(boat.throttle, 0.0)
		_place(_rooster, Vector3(nz.x, surf + 0.1, nz.z), (Vector3.UP * 0.9 - fwd * 0.45).normalized(), on and thr > 0.5 and boat.driver != null)
		_rooster.initial_velocity_min = 4.0 + thr * 4.0
		_rooster.initial_velocity_max = 6.0 + thr * 6.0


func _place(p: CPUParticles3D, at: Vector3, dir: Vector3, on: bool) -> void:
	p.global_position = at
	p.global_basis = Basis()
	p.direction = dir
	if p.emitting != on:
		p.emitting = on


## The hull coming down off a wave: a splash each side and the slap.
func slap(strength: float) -> void:
	if boat == null or boat.water.is_empty() or not is_inside_tree():
		return
	var root := get_tree().current_scene
	var surf := WorldState.to_local(Vector3(0.0, float(boat.water.surface), 0.0)).y
	var s: Vector2 = BoatKit.SIZE[boat.kind]
	for side: float in [-1.0, 1.0]:
		var p := boat.global_transform * Vector3(side * s.y * 0.5, 0.0, -s.x * 0.1)
		SwimFX.splash(root, Vector3(p.x, surf, p.z), strength * 0.8)
	SwimFX.play(root, "splash" if strength > 0.7 else "splash_small", boat.global_position, -4.0 + strength * 4.0)


## A round's hit on the hull (the weapon draws its own impact; nothing more here).
func hit_spark(_at: Vector3, _dir: Vector3) -> void:
	pass
