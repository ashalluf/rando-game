class_name CrashBreakup
extends Node
## What a crash at speed breaks OFF a car and what it does to how the car moves (wave 4,
## car-crash-3; the third crash pass after CarDamage's dents and CrashDeform's crumple). Made under
## the car's CarDamage the first time a crash is hard enough (CarDamage.breakup()), so an undamaged
## car still has no node and its shared shaders:
##   * GLASS: a hard hit bursts the side and rear glass facing it in a spray of cubes thrown on
##     with the car's own speed (CarDamage._crash calls glass()); a very hard one bursts all the
##     tempered glass as the shell twists, and the windscreen crazes right across.
##   * BONNET: past `bonnet_fly_at` of crush at the nose (or a big hit) the catch lets go: the
##     bonnet flies up on its hinges, springs, then FLAPS in the wind as the car drives on, slammed
##     back against the windscreen at speed and dropping ajar when it stops. An engine bay (block,
##     cam cover, radiator, inner wings, battery) shows under it.
##   * BUMPER: the bumper CrashDeform tore off one corner bounces on the road and throws sparks
##     (and grinds, Sfx `scrape`) wherever its corner drags while the car moves.
##   * WHEELS: a very hard hit at a corner tears the wheel off: it rolls away as a real body
##     (PhysicsBudget debris that stays `wheel_life`), the corner drops onto its hub and drags
##     sparks too.
##   * AIRBAGS: a hard frontal hit fires both front airbags, white bags in the traced cabin
##     (car_cabin.gdshaderinc `airbag`), inflating in a twentieth of a second and deflating limp.
##   * ROLLOVER: a hard side hit trips the car: the centre of mass goes to a real car's height
##     (`roll_com_height` over the road; the handling's own is 0.28 m, which never rolls), its
##     angular damping drops and it is given the roll the trip would give it, so it goes over
##     on its side or its roof by the physics; flight stabilisation (Vehicle._fly) is off for the
##     tumble unless boost is held. It ends when the car comes to rest.
##   * DEBRIS: bumper chunks, grille slats, a mirror, trim and bits of wing (CrashDebris), which
##     stay on the road.
## `CRASH_BREAKUP=0` in the environment turns all of it off (the A/B: CrashDeform only).

static var enabled: bool = OS.get_environment("CRASH_BREAKUP") != "0"

const OPEN_PAINT := preload("res://shaders/car_paint_open.gdshader")

@export_group("Glass")
## m/s over the crash threshold past which the glass facing a hit bursts out, and past which all
## the tempered glass does.
@export var glass_burst_at: float = 4.0
@export var glass_all_at: float = 13.0

@export_group("Bonnet")
## Crush at the nose (m) past which the bonnet's catch lets go, or a crash this hard (m/s over).
@export var bonnet_fly_at: float = 0.28
@export var bonnet_fly_over: float = 11.0
## How far it opens (rad): where it settles after the hit, the most the hinges allow (the
## windscreen), and how much the wind lifts it per m/s of the car's speed.
@export var bonnet_rest: Vector2 = Vector2(0.35, 0.95)
@export var bonnet_max: float = 1.22
@export var bonnet_wind: float = 0.045
## Spring and damping of the bent hinges.
@export var bonnet_spring: float = 38.0
@export var bonnet_damp: float = 3.2

@export_group("Bumper and hub")
## Speed (m/s) past which a dragging bumper corner or a bare hub throws sparks.
@export var drag_speed: float = 2.5

@export_group("Wheels")
## A crash this hard (m/s over) within `wheel_tear_reach` of a wheel tears it off.
@export var wheel_tear_at: float = 11.0
@export var wheel_tear_reach: float = 1.1
## How long a torn wheel stays (s).
@export var wheel_life: float = 300.0

@export_group("Airbags")
## A frontal crash this hard (m/s over) fires the front airbags.
@export var airbag_at: float = 5.0

@export_group("Rollover")
## A side hit this hard (m/s over) trips the car.
@export var roll_at: float = 6.0
## Roll rate given per m/s over (rad/s), and the most.
@export var roll_gain: float = 0.32
@export var roll_max: float = 4.2
## Where the centre of mass goes while the car tumbles: metres over the road.
@export var roll_com_height: float = 0.58
## The longest a tumble lasts (s).
@export var tumble_max: float = 9.0

@export_group("Debris")
## Pieces knocked off per m/s over (and the most a hit).
@export var debris_per_dv: float = 0.9
@export var debris_max: int = 14

var dmg: CarDamage
var car: Vehicle

## The bonnet: -1 latched, else its angle (rad), angular speed and where it rests.
var bonnet_angle: float = -1.0
var _bonnet_vel: float = 0.0
var _bonnet_rest: float = 0.0
var _bay: MeshInstance3D = null
## Torn wheels: indices into car._wheel_rigs.
var torn: Array[int] = []
## Airbag: seconds since it fired (-1 never).
var airbag_t: float = -1.0
## The tumble: seconds left (0 none), and what the car had before it.
var tumble_left: float = 0.0
var _com_was: Vector3 = Vector3.ZERO
var _damp_was: float = 0.5
var _tumble_t: float = 0.0
## Sparks and the grinding voice for whatever drags (made on demand).
var _sparks: Array[CPUParticles3D] = []
var _grind: AudioStreamPlayer3D = null
var _ground_ms: int = -1000
var _ground_near: Array[bool] = []
var _t: float = 0.0
## Stills: drag as if moving at this speed (m/s; 0 = the car's own).
var stage_speed: float = 0.0
## Tests: how many things it did.
var bursts: int = 0
var rolls: int = 0


func attach(to: CarDamage) -> void:
	dmg = to
	car = to.car
	name = "Breakup"
	set_physics_process(false)


static func applies(c: Vehicle) -> bool:
	return enabled and CrashDeform.applies(c)


# --- The hit -----------------------------------------------------------------------------------

## A crash (CrashDeform.crash, after its crumple): body-space contact, push and m/s over.
func crash(body_at: Vector3, push_body: Vector3, over: float, world_at: Vector3) -> void:
	var big := BigVehicles.is_big(car.body_type)
	var cd := dmg._crumple
	# The bonnet's catch.
	if bonnet_angle < 0.0 and not big and not CarDamage.MID_ENGINE.has(car.body_type) and cd != null:
		var crush := cd.crush_at_end(-1.0)
		if crush > bonnet_fly_at or (over > bonnet_fly_over and body_at.z < -dmg._len * 0.25 and push_body.z > 0.4):
			_release_bonnet(over)
	# Airbags: a hit into the front of the car.
	if airbag_t < 0.0 and over > airbag_at and push_body.z > 0.45 and not big:
		_fire_airbags()
	# A wheel torn off.
	if over > wheel_tear_at and not big:
		_tear_wheel(body_at, push_body, over)
	# A side hit trips the car over.
	if absf(push_body.x) > 0.55 and over > roll_at and not big:
		_trip(push_body, over)
	elif over > roll_at + 4.0 and not big:
		# Any big hit lets the car tumble the way the physics throws it.
		_start_tumble(3.0)
	# Debris off the face that hit.
	var n := mini(int(over * debris_per_dv), debris_max)
	if n > 0:
		var out := (car.global_basis * -push_body).normalized()
		var end_hit := absf(push_body.z) > 0.5
		CrashDebris.throw_off(car, world_at, car.linear_velocity, out, 2.0 + over * 0.25,
				CrashDebris.Kind.BUMPER if end_hit else CrashDebris.Kind.PANEL, n, car.paint)
		if end_hit and body_at.z < 0.0:
			CrashDebris.throw_off(car, world_at, car.linear_velocity, out, 2.5 + over * 0.2, CrashDebris.Kind.GRILLE, n / 3)
		CrashDebris.throw_off(car, world_at, car.linear_velocity, out, 2.0, CrashDebris.Kind.TRIM, maxi(n / 4, 1))
		if not end_hit and over > 6.0:
			# The mirror on that side.
			var m_at := car.global_transform * Vector3(signf(body_at.x) * dmg._width * 0.5, dmg._ride + (dmg._top - dmg._ride) * 0.62, -dmg._len * 0.12)
			CrashDebris.throw_off(car, m_at, car.linear_velocity, out, 3.0, CrashDebris.Kind.MIRROR, 1, car.paint)
	set_physics_process(true)


## Which glass a crash breaks (CarDamage._crash): `toward` the mesh-space direction to the hit.
func glass(toward: Vector3, over: float) -> void:
	var throw := car.linear_velocity
	for i in dmg._panes.size():
		var pane: Array = dmg._panes[i]
		var kind: int = pane[3]
		var n: Vector3 = pane[2]
		var facing := n.dot(toward)
		if kind == CarCabin.KIND_LAMP:
			continue
		if kind == CarCabin.KIND_SCREEN:
			# Laminated: it webs right across, never falls out.
			if over > glass_burst_at and facing > -0.2:
				var pc: Vector3 = ((pane[0] as Vector3) + (pane[1] as Vector3)) * 0.5
				for k in 1 + int(over / 6.0):
					dmg._add_crack(pc + Vector3(randf_range(-0.35, 0.35), randf_range(-0.1, 0.1), 0.0), n, 0.3 + over * 0.02)
			continue
		if (over > glass_burst_at and facing > 0.15) or over > glass_all_at or (over > glass_burst_at * 2.0 and facing > -0.3):
			dmg._crash_throw = throw
			dmg._set_pane(i, 2.0)
			dmg._crash_throw = Vector3.ZERO
			bursts += 1
		elif over > glass_burst_at * 0.6 and facing > -0.4:
			dmg._set_pane(i, 1.0)


# --- Bonnet ------------------------------------------------------------------------------------

func _release_bonnet(over: float) -> void:
	var cd := dmg.crumple()
	bonnet_angle = maxf(float(cd._panel_angle[CrashDeform.Lid.BONNET]), 0.04)
	# A hit throws it up hard; it rests on its bent hinges.
	_bonnet_vel = 4.0 + over * 0.35
	_bonnet_rest = lerpf(bonnet_rest.x, bonnet_rest.y, float(absi(hash([car.get_instance_id(), "bonnet"])) % 100) / 100.0)
	cd._set_panel(CrashDeform.Lid.BONNET, bonnet_angle, 0.0)
	_fit_bonnet(cd._panel_data[CrashDeform.Lid.BONNET])
	# Its underside shows now: the paint drawn from both sides.
	dmg._ensure_paint()
	if dmg._paint != null:
		dmg._paint.shader = OPEN_PAINT
	_build_bay()
	Sfx.play("hit_metal", car.global_position, -2.0, 0.7)


## The bonnet's own region, traced off the body model (CrashDeform's is a level box from the
## screen's foot, which misses the front of a bonnet that slopes down to the nose): a slab along
## the bonnet's surface from the hinge to its leading edge, a sharp edge all round. Where the
## renderer keeps no mesh data (headless) the box stays, made sharp.
func _fit_bonnet(d: Dictionary) -> void:
	d.m = 0.025
	d.fit = true
	if d.is_empty() or dmg._mesh == null or not dmg._mesh.is_inside_tree():
		return
	var pivot: Vector3 = d.pivot
	var nose := -dmg._len * 0.5
	var inv := dmg._to_mesh.affine_inverse()
	var pts: Array[Vector3] = []
	var steps := 9
	for k in steps:
		var z := lerpf(pivot.z - 0.06, nose + 0.06, float(k) / float(steps - 1))
		var at := car.global_transform * Vector3(0.0, dmg._top + 0.6, z)
		var hit := dmg._trace(at, -car.global_basis.y)
		if not hit.has("normal") or String(hit.get("slot", "")) != "paint":
			continue
		var n: Vector3 = (inv.basis * (hit.normal as Vector3)).normalized()
		var p: Vector3 = inv * (hit.pos as Vector3)
		if n.y < 0.45 or p.y > pivot.y + 0.15:
			continue
		pts.append(p)
	if pts.size() < 3:
		return
	var front: Vector3 = pts[pts.size() - 1]
	var back := Vector3(0.0, pivot.y, pivot.z)
	var along := front - back
	var half := along.length() * 0.5 + 0.03
	var axis_w := along.normalized()
	var axis_v := Vector3.RIGHT.cross(axis_w).normalized()
	if axis_v.y < 0.0:
		axis_v = -axis_v
	var mid := (front + back) * 0.5
	var dev := 0.0
	for p in pts:
		dev = maxf(dev, absf((p - mid).dot(axis_v)))
	var thick := dev + 0.1
	d.c = mid + axis_v * 0.02
	d.w = axis_w * half
	d.v = axis_v * thick
	d.u = Vector3(dmg._width * 0.5 - 0.13, 0.0, 0.0)
	if OS.get_environment("CRASH_DEBUG") != "":
		print("BONNET FIT pts %s pivot %s c %s v %s w %s ms %f" % [str(pts), str(pivot), str(d.c), str(d.v), str(d.w), dmg._mesh_scale])


func _tick_bonnet(delta: float) -> void:
	var cd := dmg._crumple
	if cd == null:
		return
	var pd: Dictionary = cd._panel_data[CrashDeform.Lid.BONNET]
	if not pd.get("fit", false):
		# A later crash re-sprang it with CrashDeform's soft catch region: fitted again.
		_fit_bonnet(pd)
	var fwd := stage_speed if stage_speed > 0.0 else car.linear_velocity.dot(-car.global_basis.z)
	# The wind under the front edge lifts it with speed (and flutters it); a car going backwards
	# blows it shut onto its rest.
	var wind := clampf(fwd * bonnet_wind, -0.3, bonnet_max)
	var flutter := 0.0
	if absf(fwd) > 6.0:
		flutter = (sin(_t * 17.0) * 0.5 + sin(_t * 29.0 + 1.3) * 0.3) * clampf(absf(fwd) / 25.0, 0.0, 1.0) * 0.07
	var target := clampf(_bonnet_rest + maxf(wind, 0.0) + flutter, 0.04, bonnet_max)
	# Gravity closes it a little when the car stops on a slope nose down... folded into the spring.
	var acc := (target - bonnet_angle) * bonnet_spring - _bonnet_vel * bonnet_damp
	_bonnet_vel += acc * delta
	bonnet_angle += _bonnet_vel * delta
	if bonnet_angle > bonnet_max:
		# Against the windscreen.
		bonnet_angle = bonnet_max
		if _bonnet_vel > 2.0:
			Sfx.play("hit_metal", car.global_position, -8.0, 1.2)
		_bonnet_vel = -_bonnet_vel * 0.3
	elif bonnet_angle < 0.04:
		bonnet_angle = 0.04
		_bonnet_vel = absf(_bonnet_vel) * 0.25
	if absf(float(cd._panel_angle[CrashDeform.Lid.BONNET]) - bonnet_angle) > 0.003:
		cd._panel_angle[CrashDeform.Lid.BONNET] = bonnet_angle
		dmg._mark_dirty()
	if _bay != null:
		_bay.visible = bonnet_angle > 0.12


## The engine bay the open bonnet shows (body space, dark metal and plastic, one mesh).
func _build_bay() -> void:
	if _bay != null:
		return
	var cd := dmg._crumple
	var d: Dictionary = cd._panel_data[CrashDeform.Lid.BONNET]
	if d.is_empty():
		return
	var c: Vector3 = d.c
	var hw := (d.u as Vector3).length()
	var hl := (d.w as Vector3).length()
	var top := c.y + (d.v as Vector3).length()
	var floor_y := dmg._ride + 0.18
	var lid_y: float = (d.pivot as Vector3).y
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var crush := cd.crush_at_end(-1.0)
	# Behind where the crushed nose now is (the radiator went back with it).
	var z_front := maxf(c.z - hl, -dmg._len * 0.5) + crush * 1.1 + 0.3
	var z_back := (d.pivot as Vector3).z - 0.04
	var zc := (z_front + z_back) * 0.5
	var bay_top := minf(lid_y, top) - 0.06
	# The tub: inner wings, the floor, the bulkhead, the slam panel / radiator at the front.
	_box(st, Vector3(-hw, floor_y, z_front), Vector3(-hw + 0.04, bay_top, z_back), Color(0.05, 0.05, 0.052))
	_box(st, Vector3(hw - 0.04, floor_y, z_front), Vector3(hw, bay_top, z_back), Color(0.05, 0.05, 0.052))
	_box(st, Vector3(-hw, floor_y, z_front), Vector3(hw, floor_y + 0.03, z_back), Color(0.03, 0.03, 0.03))
	_box(st, Vector3(-hw, floor_y, z_back - 0.03), Vector3(hw, bay_top, z_back), Color(0.035, 0.035, 0.036))
	_box(st, Vector3(-hw * 0.85, floor_y + 0.05, z_front), Vector3(hw * 0.85, bay_top - 0.1, z_front + 0.05), Color(0.02, 0.022, 0.024))
	# The engine: block, the cam cover (lighter), the intake on top, the airbox and the battery.
	var ex := hw * 0.48
	_box(st, Vector3(-ex, floor_y + 0.1, zc - hl * 0.28), Vector3(ex, bay_top - 0.12, zc + hl * 0.32), Color(0.10, 0.10, 0.105))
	_box(st, Vector3(-ex * 0.8, bay_top - 0.12, zc - hl * 0.22), Vector3(ex * 0.8, bay_top - 0.05, zc + hl * 0.26), Color(0.26, 0.26, 0.27))
	_box(st, Vector3(-ex * 0.25, bay_top - 0.05, zc - hl * 0.12), Vector3(ex * 0.25, bay_top - 0.01, zc + hl * 0.2), Color(0.02, 0.02, 0.02))
	_box(st, Vector3(ex + 0.06, bay_top - 0.2, zc - hl * 0.1), Vector3(hw - 0.08, bay_top - 0.04, zc + hl * 0.25), Color(0.025, 0.025, 0.026))
	_box(st, Vector3(-hw + 0.08, bay_top - 0.22, zc + hl * 0.05), Vector3(-ex - 0.06, bay_top - 0.05, zc + hl * 0.32), Color(0.02, 0.02, 0.02))
	# Strut towers.
	for s: float in [-1.0, 1.0]:
		_box(st, Vector3(s * hw * 0.92 - 0.07, floor_y + 0.1, z_back - 0.25), Vector3(s * hw * 0.92 + 0.07, bay_top - 0.02, z_back - 0.1), Color(0.06, 0.06, 0.062))
	st.generate_normals()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.55
	mat.metallic = 0.4
	_bay = MeshInstance3D.new()
	_bay.name = "EngineBay"
	_bay.mesh = st.commit()
	_bay.material_override = mat
	_bay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bay.visible = false
	car.add_child(_bay)


static func _box(st: SurfaceTool, lo: Vector3, hi: Vector3, col: Color) -> void:
	st.set_color(col)
	var p := [Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(lo.x, hi.y, lo.z),
		Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z)]
	# Each face clockwise seen from outside (Godot's front faces).
	for f: Array in [[0, 3, 2, 1], [4, 5, 6, 7], [0, 1, 5, 4], [3, 7, 6, 2], [0, 4, 7, 3], [1, 2, 6, 5]]:
		st.add_vertex(p[f[0]])
		st.add_vertex(p[f[1]])
		st.add_vertex(p[f[2]])
		st.add_vertex(p[f[0]])
		st.add_vertex(p[f[2]])
		st.add_vertex(p[f[3]])


# --- Wheels ------------------------------------------------------------------------------------

func _tear_wheel(body_at: Vector3, push_body: Vector3, over: float) -> void:
	var best := -1
	var best_d := INF
	for i in car._wheel_rigs.size():
		if torn.has(i):
			continue
		var node := car._wheel_rigs[i][0] as Node3D
		if node == null or not is_instance_valid(node):
			continue
		var dd := Vector2(node.position.x - body_at.x, node.position.z - body_at.z).length()
		if dd < best_d:
			best_d = dd
			best = i
	if best < 0 or best_d > wheel_tear_reach or over < wheel_tear_at * (1.0 + best_d * 0.4):
		return
	tear_wheel(best, push_body)


## Tears wheel `i` (an index into car._wheel_rigs) off and rolls it away.
func tear_wheel(i: int, push_body: Vector3 = Vector3.ZERO) -> void:
	if torn.has(i) or i < 0 or i >= car._wheel_rigs.size():
		return
	var rig: Array = car._wheel_rigs[i]
	var node := rig[0] as Node3D
	var mi := rig[1] as MeshInstance3D
	torn.append(i)
	var xf := node.global_transform
	node.visible = false
	# The physics wheel there is down to its hub: the corner drops and drags.
	var vw := _physics_wheel(node.position)
	if vw != null:
		vw.wheel_radius = 0.1
		vw.wheel_friction_slip = 0.35
	# Beside the car (the level root or a node of it: it rides the origin shifts).
	var host := car.get_parent()
	if host == null or not (host is Node3D):
		return
	var r := float(car._wheel_pose().get("r", 0.34))
	var body := RigidBody3D.new()
	body.name = "TornWheel"
	body.mass = 22.0
	body.collision_layer = 4
	body.collision_mask = 1 | 4
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = r
	cyl.height = 0.22
	shape.shape = cyl
	# The cylinder's axis is its Y: lay it along the axle (body X).
	shape.basis = Basis(Vector3.BACK, PI * 0.5)
	body.add_child(shape)
	var vis := MeshInstance3D.new()
	vis.mesh = mi.mesh
	vis.material_override = mi.material_override
	vis.basis = mi.basis
	vis.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	body.add_child(vis)
	host.add_child(body)
	body.global_transform = Transform3D(xf.basis.orthonormalized(), xf.origin)
	var side := signf(node.position.x) if absf(node.position.x) > 0.05 else 1.0
	var out := car.global_basis.x * side
	var push := (car.global_basis * -push_body) if push_body != Vector3.ZERO else out
	body.linear_velocity = car.linear_velocity * 0.85 + out * 3.5 + push * 1.5 + Vector3.UP * 2.5
	var fwd := car.linear_velocity.dot(-car.global_basis.z)
	body.angular_velocity = car.global_basis.x * (-fwd / maxf(r, 0.2)) + car.global_basis.z * randf_range(-2.0, 2.0)
	PhysicsBudget.register_debris(body, wheel_life)
	Sfx.play("hit_metal", xf.origin, 0.0, 0.8)
	CrashDebris.throw_off(car, xf.origin, car.linear_velocity, out, 3.0, CrashDebris.Kind.HUBCAP, 1)
	set_physics_process(true)


func _physics_wheel(local_pos: Vector3) -> VehicleWheel3D:
	var best: VehicleWheel3D = null
	var bd := INF
	for w in car.wheels:
		if not is_instance_valid(w):
			continue
		var dd := Vector2(w.position.x - local_pos.x, w.position.z - local_pos.z).length()
		if dd < bd:
			bd = dd
			best = w
	return best


# --- Airbags -----------------------------------------------------------------------------------

func _fire_airbags() -> void:
	airbag_t = 0.0
	dmg._ensure_glass()
	_push_airbag()
	Sfx.play("hit_metal", car.global_position, -3.0, 0.55)
	set_physics_process(true)


## Inflation (0..1) and sag (0..1) at `t` seconds since it fired: up in 30 ms, held, then the
## gas vents through the bag and it hangs limp.
static func airbag_shape(t: float) -> Vector2:
	if t < 0.0:
		return Vector2.ZERO
	var inf := clampf(t / 0.03, 0.0, 1.0)
	var vent := clampf((t - 0.25) / 1.3, 0.0, 1.0)
	vent = vent * vent * (3.0 - 2.0 * vent)
	return Vector2(inf * (1.0 - vent * 0.62), vent)


func _push_airbag() -> void:
	var s := airbag_shape(airbag_t)
	if dmg._glass != null:
		dmg._glass.set_shader_parameter("airbag", s)


# --- Rollover ----------------------------------------------------------------------------------

func _trip(push_body: Vector3, over: float) -> void:
	_start_tumble(tumble_max)
	# The wheels on the struck side catch: the top keeps going the way it was pushed.
	var push := (car.global_basis * Vector3(push_body.x, 0.0, 0.0)).normalized()
	var axis := car.global_basis.y.cross(push).normalized()
	var w := minf(roll_gain * (over - roll_at * 0.5), roll_max)
	car.hold_crash_watch(4)
	car.sleeping = false
	car.angular_velocity += axis * w
	car.linear_velocity += Vector3.UP * (0.8 + over * 0.08)
	rolls += 1


func _start_tumble(seconds: float) -> void:
	if tumble_left <= 0.0:
		_com_was = car.center_of_mass
		_damp_was = car.angular_damp
		var road := float(car._dims().get("road", car._dims().get("ride", -0.2)))
		car.center_of_mass = Vector3(0.0, road + roll_com_height, 0.0)
		car.angular_damp = 0.05
		_tumble_t = 0.0
	tumble_left = maxf(tumble_left, seconds)
	car.tumble_until = Time.get_ticks_msec() / 1000.0 + tumble_left
	set_physics_process(true)


func _tick_tumble(delta: float) -> void:
	_tumble_t += delta
	tumble_left -= delta
	var still := car.linear_velocity.length() < 1.2 and car.angular_velocity.length() < 0.4
	var on_wheels := not car.is_airborne() and car.global_basis.y.y > 0.8
	if tumble_left <= 0.0 or (_tumble_t > 0.8 and still and (on_wheels or _tumble_t > 2.5)):
		end_tumble()
	else:
		car.tumble_until = Time.get_ticks_msec() / 1000.0 + 0.2


func end_tumble() -> void:
	if tumble_left <= 0.0 and car.tumble_until <= 0.0:
		return
	tumble_left = 0.0
	car.center_of_mass = _com_was
	car.angular_damp = _damp_was
	car.tumble_until = 0.0


# --- Dragging ----------------------------------------------------------------------------------

## The points dragging on the road (body space): a hanging bumper's torn corner, a bare hub.
func _drag_points() -> Array:
	var out: Array = []
	var cd := dmg._crumple
	var road := float(car._dims().get("road", dmg._ride - 0.12))
	if cd != null:
		for lid: int in [CrashDeform.Lid.BUMPER_FRONT, CrashDeform.Lid.BUMPER_REAR]:
			var a := float(cd._panel_angle[lid])
			if absf(a) < 1e-4:
				continue
			var end := -1.0 if lid == CrashDeform.Lid.BUMPER_FRONT else 1.0
			var side := -signf(a)
			out.append([Vector3(side * dmg._width * 0.5, road + 0.02, end * dmg._len * 0.5), lid])
	for i in torn:
		var node := car._wheel_rigs[i][0] as Node3D
		if node != null:
			out.append([Vector3(node.position.x, road + 0.04, node.position.z), -1 - i])
	return out


func _tick_drag(delta: float) -> bool:
	var pts := _drag_points()
	if pts.is_empty():
		return false
	var vel := car.linear_velocity
	if stage_speed > 0.0:
		vel = -car.global_basis.z * stage_speed
	var speed := vel.length()
	var moving := speed > drag_speed
	# Is the road there (a ray each, ten times a second)?
	var now := Time.get_ticks_msec()
	if now - _ground_ms > 100 or _ground_near.size() != pts.size():
		_ground_ms = now
		_ground_near.resize(pts.size())
		var space := car.get_world_3d().direct_space_state
		for k in pts.size():
			var p: Vector3 = car.global_transform * (pts[k][0] as Vector3)
			var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.3, p + Vector3.DOWN * 0.25, 1, [car.get_rid()])
			_ground_near[k] = not space.intersect_ray(q).is_empty()
	var level := clampf((speed - drag_speed) / 18.0, 0.0, 1.0)
	var any := false
	while _sparks.size() < pts.size():
		_sparks.append(_make_sparks())
	for k in _sparks.size():
		var p := _sparks[k]
		var on := k < pts.size() and moving and _ground_near[k]
		p.emitting = on
		if not on:
			continue
		any = true
		var at: Vector3 = car.global_transform * (pts[k][0] as Vector3)
		var throw := (-vel.normalized() + Vector3.UP * 0.35).normalized()
		var x := throw.cross(Vector3.FORWARD if absf(throw.z) < 0.9 else Vector3.RIGHT).normalized()
		p.global_transform = Transform3D(Basis(x, throw, x.cross(throw).normalized()), at)
		p.color = Color(1.0, 1.0, 1.0, 0.35 + 0.65 * level)
		p.initial_velocity_min = 2.0 + speed * 0.25
		p.initial_velocity_max = 4.0 + speed * 0.55
		# The bumper bounces on the road as it is dragged.
		var lid: int = pts[k][1]
		if lid >= 0 and dmg._crumple != null:
			var cd := dmg._crumple
			var base := float(cd._panel_data[lid].get("rest", cd._panel_angle[lid]))
			if not cd._panel_data[lid].has("rest"):
				cd._panel_data[lid]["rest"] = base
			cd._panel_angle[lid] = base * (1.0 - 0.07 * absf(sin(_t * 23.0 + float(k))) * level)
			dmg._mark_dirty()
	if any:
		if _grind == null:
			_grind = Sfx.loop_player("scrape", -4.0)
			car.add_child(_grind)
		if not _grind.playing:
			_grind.play()
		_grind.volume_db = -14.0 + 12.0 * level
		_grind.pitch_scale = 0.8 + 0.5 * level
	elif _grind != null and _grind.playing:
		_grind.stop()
	return true


func _make_sparks() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "DragSparks%d" % _sparks.size()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.025, 0.22)
	quad.material = _spark_material()
	p.mesh = quad
	p.amount = WeaponFX._count(40)
	p.lifetime = 0.45
	p.lifetime_randomness = 0.5
	p.local_coords = false
	p.particle_flag_align_y = true
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.08
	p.direction = Vector3.UP
	p.spread = 30.0
	p.gravity = Vector3(0.0, -9.8, 0.0)
	p.damping_min = 0.2
	p.damping_max = 1.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.3
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.color_ramp = WeaponFX._ramp([Color(1.0, 0.9, 0.6, 1.0), Color(1.0, 0.55, 0.15, 0.95),
		Color(0.9, 0.25, 0.05, 0.6), Color(0.5, 0.08, 0.02, 0.0)])
	p.visibility_aabb = AABB(Vector3(-8.0, -2.0, -8.0), Vector3(16.0, 6.0, 16.0))
	p.emitting = false
	add_child(p)
	return p


static var _spark_mat: ShaderMaterial


static func _spark_material() -> ShaderMaterial:
	if _spark_mat == null:
		_spark_mat = ShaderMaterial.new()
		_spark_mat.shader = preload("res://shaders/spark_streak.gdshader")
	return _spark_mat


# --- The tick ----------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if car == null or not is_instance_valid(car):
		return
	_t += delta
	var busy := false
	if bonnet_angle >= 0.0:
		_tick_bonnet(delta)
		busy = true
	if airbag_t >= 0.0 and airbag_t < 2.0:
		airbag_t += delta
		_push_airbag()
		busy = true
	if tumble_left > 0.0:
		_tick_tumble(delta)
		busy = true
	if _tick_drag(delta):
		busy = true
	if not busy:
		set_physics_process(false)


## Back to whole (a pooled cruiser, CarDamage.restore()).
func reset() -> void:
	end_tumble()
	for i in torn:
		var rig: Array = car._wheel_rigs[i]
		(rig[0] as Node3D).visible = true
		var vw := _physics_wheel((rig[0] as Node3D).position)
		if vw != null:
			vw.wheel_radius = float(car._dims().get("tyre_r", 0.34))
			vw.wheel_friction_slip = car.wheel_grip
	torn.clear()
	if bonnet_angle >= 0.0 and dmg._paint != null:
		dmg._paint.shader = CarDamage.PAINT_DAMAGE_SHADER
	bonnet_angle = -1.0
	airbag_t = -1.0
	if _bay != null:
		_bay.queue_free()
		_bay = null
	for p in _sparks:
		p.emitting = false
	if _grind != null:
		_grind.stop()
	set_physics_process(false)
