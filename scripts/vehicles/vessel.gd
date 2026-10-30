class_name Vessel
extends AnimatableBody3D
## A ship or boat of the ocean traffic (OceanTraffic): scripted like AirTraffic's aircraft, never
## simulated. Each tick OceanTraffic calls drive(), the vessel works out where it is in TRUE world
## coordinates (`world_pos`, the water's rest level in y) and how it sits (yaw, heel, trim) from
## its program, and apply_pose() puts the body there. The swell's heave, pitch and roll are not
## here: the hull's shader rides the sea (vessel.gdshader, BOAT_RIDE) off the water's own TIME.
##
## Programs:
##   LOOP   follow a closed world-space polyline (rounded through its corners) at a speed that
##          eases down where the route says so (harbours), banking into turns, the bow up with
##          speed (motor yachts, sport fishers, the ferry, the pilot boat, tugs);
##   SAIL   sail free under a wind: a course, tacking up to windward in legs 48 degrees off it,
##          the boom and jib sheeted by the point of sail and swung across on a tack or a gybe,
##          heeled to leeward by the breeze, speed from a polar (sloops);
##   HOLD   keep station by a point, nosing about it (a tug standing by the moored ship).
## A body on the props layer with one box shape and take_hit(), so bullets, pellets, rockets and
## blasts hit it with no weapon code knowing boats exist (mask 0; the layer is dropped past
## `hit_range`). Shot to pieces it burns, explodes and settles by the stern into the sea, and
## OceanTraffic replaces it later.

signal finished(v: Vessel)

enum Program { LOOP, SAIL, HOLD }
enum Life { UNDERWAY, BURNING, SINKING }

## Hit points by VesselMesh.Kind (a rifle round does 10, a rocket up to 120).
const HEALTH := [150.0, 260.0, 220.0, 90.0, 300.0, 900.0, 1100.0]
## Seconds from going up in flames to the explosion, and how long it takes to go under.
const BURN_SECONDS := 2.5
const SINK_SECONDS := 38.0
## Bullets and blasts see it within this range of the camera (metres).
const HIT_RANGE := 700.0
const HIT_LAYER := 4
## The water chunks' surface at rest (sea_ride.gdshaderinc SR_SEA_LEVEL).
const SEA_LEVEL := 0.15
## Range bands for the hull's three levels, in metres for a 10 m boat (scaled by its length).
const LOD_NEAR := 90.0
const LOD_MID := 420.0
## Past this the whole vessel is hidden (metres for a 10 m boat, scaled; capped by FAR_CAP).
const DRAW := 2600.0
const FAR_CAP := 11500.0

var kind: int = VesselMesh.Kind.MOTOR
var variant: int = 0
## Length over all (metres) and the scale of the reference mesh it is drawn at.
var length: float = 10.0
var scale_k: float = 1.0
var program: int = Program.LOOP
var life: int = Life.UNDERWAY
var world_pos: Vector3 = Vector3.ZERO
var yaw: float = 0.0
var heel: float = 0.0
var trim: float = 0.0
## Speed through the water (m/s) and its heading in world XZ (unit).
var speed: float = 0.0
var heading: Vector2 = Vector2(0.0, -1.0)
var health: float = 100.0
var done: bool = false
var traffic: Node = null
## A name for tests and stills ("sail_3", "ferry_0", ...).
var tag: String = ""

# LOOP
var path: PackedVector2Array = PackedVector2Array()
var path_cum: PackedFloat32Array = PackedFloat32Array()
var path_len: float = 0.0
var path_s: float = 0.0
var cruise: float = 8.0
## [[s0, s1, speed], ...]: slower stretches along the path (harbours, the dock).
var slow: Array = []
var bank_gain: float = 1.0

# SAIL
var wind: Vector2 = Vector2(0.95, 0.3).normalized()
var course: Vector2 = Vector2(-1.0, 0.0)
var tack_side: float = 1.0
var tack_left: float = 90.0
var home: Vector2 = Vector2.ZERO
var home_reach: float = 2200.0
var boom: float = 0.4
var sail_side: float = 1.0
var _course_left: float = 200.0

# HOLD
var hold_at: Vector2 = Vector2.ZERO
var hold_face: Vector2 = Vector2(0.0, -1.0)
var _hold_t: float = 0.0

var _mat: ShaderMaterial
var _visual: Node3D
var _hulls: Array[MeshInstance3D] = []
var _main_pivot: Node3D
var _jib_pivot: Node3D
var _mains: Array[MeshInstance3D] = []
var _jibs: Array[MeshInstance3D] = []
var _lights: MeshInstance3D
var _shape: CollisionShape3D
var _smoke: CPUParticles3D
var _fire: CPUParticles3D
var _sound: AudioStreamPlayer3D
var _burn_left: float = 0.0
var _sink_t: float = 0.0
var _sink_roll: float = 0.0
var _rng := RandomNumberGenerator.new()
var _prev_yaw: float = 0.0
var _turn_rate: float = 0.0
var _tier: int = -1

static var _light_shader: Shader


func _init() -> void:
	sync_to_physics = false
	collision_layer = HIT_LAYER
	collision_mask = 0


## Builds the vessel: `kind` (VesselMesh.Kind), its look `variant`, its length, the hull's paint,
## the canvas index (Marina.CANVAS) and a seed for everything else that varies.
func setup(p_kind: int, p_variant: int, p_length: float, paint: Color, canvas: int, sd: int) -> void:
	kind = p_kind
	variant = p_variant
	length = p_length
	scale_k = length / float(VesselMesh.REF_LEN[kind])
	health = HEALTH[kind]
	_rng.seed = sd
	add_to_group("vessel")
	if kind in [VesselMesh.Kind.TUG, VesselMesh.Kind.FERRY, VesselMesh.Kind.PILOT]:
		add_to_group("rail_vehicle") # WeaponFX: rounds spark and ping off steel and aluminium
	_visual = Node3D.new()
	_visual.name = "Visual"
	_visual.scale = Vector3.ONE * scale_k
	add_child(_visual)
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/vessel.gdshader")
	_mat.set_shader_parameter("solo", 1.0)
	_mat.set_shader_parameter("ride", 1.0)
	_mat.set_shader_parameter("solo_paint", Vector3(paint.r, paint.g, paint.b))
	var lit := kind in [VesselMesh.Kind.MOTOR, VesselMesh.Kind.FISHER, VesselMesh.Kind.FERRY, VesselMesh.Kind.TUG, VesselMesh.Kind.PILOT]
	_mat.set_shader_parameter("solo_flags", float(canvas % 6) + (8.0 if lit else 0.0) + 16.0)
	_mat.set_shader_parameter("solo_seed", _rng.randf())
	var rs := VesselMesh.ride_size(kind) * scale_k
	_mat.set_shader_parameter("ride_size", rs)
	_mat.set_shader_parameter("ride_follow", clampf(1.25 - length / 60.0, 0.45, 1.0))
	var near := LOD_NEAR * maxf(length / 10.0, 1.0)
	var mid := LOD_MID * maxf(length / 10.0, 1.0)
	var far := minf(DRAW * maxf(length / 10.0, 1.0), FAR_CAP)
	var bands := [[0.0, near], [near, mid], [mid, far]]
	for lv in 3:
		var mi := MeshInstance3D.new()
		mi.name = "Hull%d" % lv
		mi.mesh = VesselMesh.hull(kind, variant, lv)
		mi.material_override = _mat
		mi.visibility_range_begin = bands[lv][0]
		mi.visibility_range_end = bands[lv][1]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if lv < 2 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_visual.add_child(mi)
		_hulls.append(mi)
	if kind == VesselMesh.Kind.SAIL:
		_build_sails(bands)
	var box: Array = VesselMesh.hull_box(kind)
	_shape = CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = (box[1] as Vector3) * scale_k
	_shape.shape = bs
	_shape.position = (box[0] as Vector3) * scale_k
	add_child(_shape)
	_build_lights()


func _build_sails(bands: Array) -> void:
	var r := VesselMesh.rig(variant)
	_main_pivot = Node3D.new()
	_main_pivot.name = "Main"
	_main_pivot.position = r.gooseneck
	_visual.add_child(_main_pivot)
	_jib_pivot = Node3D.new()
	_jib_pivot.name = "Jib"
	_jib_pivot.position = r.stem
	_visual.add_child(_jib_pivot)
	for lv in 3:
		for s in 2:
			var side := 1.0 if s == 0 else -1.0
			var m := MeshInstance3D.new()
			m.mesh = VesselMesh.main_sail(variant, side, lv)
			m.material_override = _mat
			m.visibility_range_begin = bands[lv][0]
			m.visibility_range_end = bands[lv][1]
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if lv < 2 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_main_pivot.add_child(m)
			_mains.append(m)
			var j := MeshInstance3D.new()
			j.mesh = VesselMesh.jib(variant, side, lv)
			j.material_override = _mat
			j.visibility_range_begin = bands[lv][0]
			j.visibility_range_end = bands[lv][1]
			j.cast_shadow = m.cast_shadow
			_jib_pivot.add_child(j)
			_jibs.append(j)
	_set_sail_side(1.0)


func _set_sail_side(side: float) -> void:
	sail_side = side
	for i in _mains.size():
		var on := (i % 2 == 0) == (side > 0.0)
		_mains[i].visible = on
		_jibs[i].visible = on


# --- Programs -------------------------------------------------------------------------------------

## A LOOP program round the closed polyline `pts` (TRUE world XZ), starting `s` metres along it.
func follow(pts: PackedVector2Array, p_cruise: float, s: float = 0.0, p_slow: Array = []) -> void:
	program = Program.LOOP
	path = pts
	cruise = p_cruise
	slow = p_slow
	path_cum = cumulate(pts)
	path_len = path_cum[path_cum.size() - 1]
	path_s = fposmod(s, path_len)
	speed = _speed_at(path_s)
	var p := path_at(path_s)
	var d := (path_at(path_s + 5.0) - path_at(path_s - 5.0)).normalized()
	heading = d
	world_pos = Vector3(p.x, SEA_LEVEL, p.y)
	yaw = atan2(-d.x, -d.y)
	_prev_yaw = yaw


func sail(at: Vector2, p_home: Vector2, p_wind: Vector2, first_course: Vector2) -> void:
	program = Program.SAIL
	world_pos = Vector3(at.x, SEA_LEVEL, at.y)
	home = p_home
	wind = p_wind.normalized()
	course = first_course.normalized()
	tack_side = 1.0 if _rng.randf() < 0.5 else -1.0
	tack_left = _rng.randf_range(40.0, 140.0)
	_course_left = _rng.randf_range(120.0, 360.0)
	heading = _sail_heading()
	yaw = atan2(-heading.x, -heading.y)
	_prev_yaw = yaw
	speed = 3.0
	boom = _boom_target()
	_set_sail_side(signf(boom) if boom != 0.0 else 1.0)


func hold(at: Vector2, face: Vector2) -> void:
	program = Program.HOLD
	hold_at = at
	hold_face = face.normalized()
	world_pos = Vector3(at.x, SEA_LEVEL, at.y)
	heading = hold_face
	yaw = atan2(-heading.x, -heading.y)
	_prev_yaw = yaw
	_hold_t = _rng.randf() * 100.0


## The point `s` metres along the loop, rounded through its corners (Catmull-Rom by segment).
func path_at(s: float) -> Vector2:
	return loop_point(path, path_cum, s)


## Distance along a closed loop at each of its points, and the whole length last.
static func cumulate(pts: PackedVector2Array) -> PackedFloat32Array:
	var cum := PackedFloat32Array([0.0])
	var l := 0.0
	for i in pts.size():
		l += pts[i].distance_to(pts[(i + 1) % pts.size()])
		cum.append(l)
	return cum


static func loop_point(pts: PackedVector2Array, cum: PackedFloat32Array, s: float) -> Vector2:
	var n := pts.size()
	if n == 0:
		return Vector2.ZERO
	s = fposmod(s, cum[n])
	var lo := 0
	var hi := n - 1
	while lo < hi:
		var mid := (lo + hi + 1) / 2
		if cum[mid] <= s:
			lo = mid
		else:
			hi = mid - 1
	var i := lo
	var seg := maxf(cum[i + 1] - cum[i], 0.001)
	var u := (s - cum[i]) / seg
	return pts[i].cubic_interpolate(pts[(i + 1) % n], pts[(i - 1 + n) % n], pts[(i + 2) % n], u)


func _speed_at(s: float) -> float:
	var v := cruise
	for sl: Array in slow:
		var a: float = sl[0]
		var b: float = sl[1]
		var ease := 140.0
		var inside := smoothstep(a - ease, a, s) * (1.0 - smoothstep(b, b + ease, s))
		v = lerpf(v, float(sl[2]), inside)
	return v


## One tick of the vessel's life: its program, the pose, the presence tiers.
func drive(dt: float) -> void:
	if done:
		return
	match life:
		Life.UNDERWAY:
			match program:
				Program.LOOP:
					_drive_loop(dt)
				Program.SAIL:
					_drive_sail(dt)
				Program.HOLD:
					_drive_hold(dt)
		Life.BURNING:
			_burn_left -= dt
			speed = move_toward(speed, 0.0, dt * 1.5)
			_coast(dt)
			if _burn_left <= 0.0:
				_explode()
		Life.SINKING:
			_sink(dt)
			if done:
				return
	apply_pose()


func _drive_loop(dt: float) -> void:
	var target := _speed_at(path_s)
	speed = move_toward(speed, target, dt * 0.8)
	path_s = fposmod(path_s + speed * dt, path_len)
	var p := path_at(path_s)
	var ahead := path_at(path_s + maxf(length * 0.6, 5.0))
	var behind := path_at(path_s - maxf(length * 0.6, 5.0))
	var d := (ahead - behind)
	if d.length_squared() > 0.0001:
		heading = d.normalized()
	world_pos = Vector3(p.x, SEA_LEVEL, p.y)
	_turn(dt)
	# Bank into the turn (a planing hull leans in), bow up with speed.
	var plane := clampf(speed / maxf(length * 0.9, 4.0), 0.0, 1.0)
	var want_heel := clampf(_turn_rate * speed * 0.03 * bank_gain, -0.18, 0.18)
	if kind == VesselMesh.Kind.FERRY:
		want_heel *= 0.4
	heel = lerpf(heel, want_heel, minf(dt * 1.5, 1.0))
	var want_trim := 0.02 + 0.07 * plane * (0.3 if kind in [VesselMesh.Kind.TUG, VesselMesh.Kind.FERRY] else 1.0)
	trim = lerpf(trim, want_trim, minf(dt, 1.0))


func _drive_hold(dt: float) -> void:
	_hold_t += dt
	var drift := Vector2(sin(_hold_t * 0.07), cos(_hold_t * 0.053)) * 6.0
	var p := hold_at + drift
	var prev := Vector2(world_pos.x, world_pos.z)
	world_pos = Vector3(p.x, SEA_LEVEL, p.y)
	speed = prev.distance_to(p) / maxf(dt, 0.001)
	heading = hold_face.rotated(sin(_hold_t * 0.04) * 0.12)
	_turn(dt)
	heel = lerpf(heel, 0.0, minf(dt, 1.0))
	trim = lerpf(trim, 0.015, minf(dt, 1.0))


func _turn(dt: float) -> void:
	var new_yaw := atan2(-heading.x, -heading.y)
	var dy := wrapf(new_yaw - _prev_yaw, -PI, PI)
	_turn_rate = lerpf(_turn_rate, dy / maxf(dt, 0.001), minf(dt * 2.0, 1.0))
	_prev_yaw = new_yaw
	yaw = new_yaw


# --- Sailing --------------------------------------------------------------------------------------

## Upwind (where the wind comes FROM), unit.
func _upwind() -> Vector2:
	return -wind


## The heading the boat steers for its course: straight there if it can be sailed, else 48 degrees
## off the wind on the current tack.
func _sail_heading() -> Vector2:
	var up := _upwind()
	if rad_to_deg(course.angle_to(up)) * signf(course.angle_to(up)) < 45.0:
		return up.rotated(deg_to_rad(48.0) * tack_side)
	return course


## The true wind angle off the bow, degrees 0..180.
func _twa(h: Vector2) -> float:
	return absf(rad_to_deg(h.angle_to(_upwind())))


## Boat speed (m/s) at a true wind angle, a sloop's polar in a sea breeze.
func _polar(twa: float) -> float:
	if twa < 32.0:
		return lerpf(0.6, 1.4, twa / 32.0)
	if twa < 52.0:
		return lerpf(2.7, 3.1, (twa - 32.0) / 20.0)
	if twa < 110.0:
		return lerpf(3.1, 3.7, (twa - 52.0) / 58.0)
	return lerpf(3.7, 2.7, (twa - 110.0) / 70.0)


## The boom's angle off the centre line (radians), signed to the leeward side (+ starboard).
func _boom_target() -> float:
	var twa := _twa(heading)
	var a := deg_to_rad(lerpf(7.0, 78.0, clampf((twa - 40.0) / 135.0, 0.0, 1.0)))
	# The wind comes over one side; the sails go out on the other. In the hull frame starboard is
	# +X; the heading x upwind cross says which side is to windward.
	var cr := heading.x * _upwind().y - heading.y * _upwind().x
	return a * (1.0 if cr < 0.0 else -1.0)


func _drive_sail(dt: float) -> void:
	var here := Vector2(world_pos.x, world_pos.z)
	_course_left -= dt
	tack_left -= dt
	# Keep off the shore, the piers and the headland, and do not wander too far from home.
	var trouble: bool = traffic != null and traffic.has_method("sea_room") and not traffic.sea_room(here + heading * 160.0, 120.0)
	if trouble or here.distance_to(home) > home_reach or _course_left <= 0.0:
		var away := (home - here).normalized() if here.distance_to(home) > home_reach * 0.6 else Vector2.from_angle(_rng.randf() * TAU)
		if trouble and traffic.has_method("offshore_dir"):
			away = traffic.offshore_dir(here)
		course = away
		_course_left = _rng.randf_range(150.0, 420.0)
		tack_left = minf(tack_left, 2.0) if trouble else tack_left
	var up := _upwind()
	var beating := absf(rad_to_deg(course.angle_to(up))) < 45.0
	if beating and tack_left <= 0.0:
		tack_side = -tack_side
		tack_left = _rng.randf_range(50.0, 150.0)
	var want := _sail_heading()
	# Turn toward it at a sailboat's rate (about 8 degrees a second).
	var a := heading.angle_to(want)
	var step := clampf(a, -deg_to_rad(8.0) * dt, deg_to_rad(8.0) * dt)
	heading = heading.rotated(step).normalized()
	var twa := _twa(heading)
	var gust := 1.0 + 0.12 * sin(Time.get_ticks_msec() * 0.00031 + float(get_instance_id() % 97))
	var target := _polar(twa) * gust * scale_k
	speed = move_toward(speed, target, dt * 0.35)
	here += heading * speed * dt
	world_pos = Vector3(here.x, SEA_LEVEL, here.y)
	_turn(dt)
	# Sheets: the boom eases toward its angle, swinging across through the centre on a tack.
	var bt := _boom_target()
	boom = move_toward(boom, bt, dt * deg_to_rad(22.0))
	if absf(boom) > 0.02 and signf(boom) != sail_side:
		_set_sail_side(signf(boom))
	if _main_pivot:
		_main_pivot.rotation = Vector3(0.0, -boom, 0.0)
		_jib_pivot.rotation = Vector3(0.0, -boom * 0.75, 0.0)
	# Heel to leeward: hardest close-hauled, almost none running; down to nothing in a luff.
	var press := clampf(sin(deg_to_rad(clampf(twa, 0.0, 180.0))) * 1.2, 0.0, 1.0) * smoothstep(25.0, 45.0, twa)
	var want_heel := -signf(boom) * deg_to_rad(19.0) * press * gust
	heel = lerpf(heel, want_heel, minf(dt * 0.6, 1.0))
	trim = lerpf(trim, 0.012, minf(dt, 1.0))


# --- Pose -------------------------------------------------------------------------------------

func apply_pose() -> void:
	global_transform = Transform3D(Basis.from_euler(Vector3(trim, yaw, heel)), WorldState.to_local(world_pos))


## The bow's and the stern's points in TRUE world XZ and the beam, for the wake
## (OceanTraffic.push_wakes()).
func bow_xz() -> Vector2:
	return Vector2(world_pos.x, world_pos.z) + heading * length * 0.48


func stern_xz() -> Vector2:
	return Vector2(world_pos.x, world_pos.z) - heading * length * 0.48


func beam() -> float:
	if kind == VesselMesh.Kind.FERRY:
		return float(VesselMesh.REF_BEAM[kind]) * scale_k * 0.9
	return float(VesselMesh.REF_BEAM[kind]) * scale_k


## Called by OceanTraffic every so often with the camera's distance: hit layer on or off, the
## engine sound in earshot or freed.
func presence(cam_dist: float) -> void:
	var t := 0 if cam_dist < HIT_RANGE else 1
	if t != _tier:
		_tier = t
		if life == Life.UNDERWAY or life == Life.BURNING:
			collision_layer = HIT_LAYER if t == 0 else 0
	var hear := 220.0 + length * 8.0
	if kind != VesselMesh.Kind.SAIL and cam_dist < hear and _sound == null and life != Life.SINKING:
		_start_sound()
	elif _sound and cam_dist > hear * 1.2:
		_sound.queue_free()
		_sound = null
	if _sound:
		var load01 := clampf(speed / maxf(cruise, 1.0), 0.0, 1.2)
		var base := 0.55 if length > 25.0 else (0.8 if length > 14.0 else 1.05)
		_sound.pitch_scale = base * (0.85 + 0.35 * load01)


func _start_sound() -> void:
	if not is_inside_tree():
		return
	var name_s := "diesel_idle" if Sfx.has("diesel_idle") else "engine_loop"
	_sound = Sfx.loop_player(name_s, -4.0 if length > 20.0 else -9.0)
	_sound.max_distance = 260.0 + length * 9.0
	_sound.unit_size = 6.0 + length * 0.5
	_sound.attenuation_filter_cutoff_hz = 2500.0
	_sound.name = "Engine"
	_sound.position = Vector3(0.0, 1.5, length * 0.3)
	add_child(_sound)
	_sound.play()


# --- Lights ---------------------------------------------------------------------------------------

## Navigation lights by night (aircraft_lights.gdshader kind 4: lit with the lamps, dark by day):
## the masthead white forward, red to port and green to starboard aimed out, the stern light;
## tugs show two masthead whites, the pilot boat its white over red, the ferry its deck lights.
func _build_lights() -> void:
	if _light_shader == null:
		_light_shader = load("res://shaders/aircraft_lights.gdshader")
	var k := scale_k
	var l := length
	var b := beam()
	var specs: Array = []
	var white := Color(1.0, 0.95, 0.85, 1.0)
	var red := Color(1.0, 0.08, 0.05, 1.0)
	var green := Color(0.1, 1.0, 0.35, 1.0)
	var top := 3.0
	match kind:
		VesselMesh.Kind.SAIL:
			top = ((VesselMesh.rig(variant).top as Vector3).y + 0.2) * k
		VesselMesh.Kind.TUG:
			top = 12.5 * k
		VesselMesh.Kind.FERRY:
			top = 12.6 * k
		VesselMesh.Kind.PILOT:
			top = 6.7 * k
		VesselMesh.Kind.MOTOR:
			top = 6.5 * k
		VesselMesh.Kind.FISHER:
			top = 5.8 * k
		_:
			top = 2.0 * k
	var deck := clampf(top * 0.25, 1.0, 4.0)
	specs.append([Vector3(0.0, top, -l * 0.15), white, 0.6 + l * 0.01, 4, Vector3.ZERO])
	specs.append([Vector3(-b * 0.48, deck, -l * 0.25), red, 0.45 + l * 0.008, 4, Vector3(-1.0, 0.0, -0.5).normalized()])
	specs.append([Vector3(b * 0.48, deck, -l * 0.25), green, 0.45 + l * 0.008, 4, Vector3(1.0, 0.0, -0.5).normalized()])
	specs.append([Vector3(0.0, deck * 0.8, l * 0.49), white, 0.45 + l * 0.008, 4, Vector3(0.0, 0.0, 1.0)])
	if kind == VesselMesh.Kind.TUG:
		specs.append([Vector3(0.0, top - 1.2 * k, -l * 0.15), white, 0.6 + l * 0.01, 4, Vector3.ZERO])
		specs.append([Vector3(0.0, top - 2.4 * k, -l * 0.15), Color(1.0, 0.75, 0.2, 1.0), 0.6, 4, Vector3.ZERO])
	elif kind == VesselMesh.Kind.PILOT:
		specs.append([Vector3(0.0, top - 0.9 * k, -l * 0.15), red, 0.6, 4, Vector3.ZERO])
	elif kind == VesselMesh.Kind.FERRY:
		# Deck and cabin lights along the house, warm, and the wheelhouse's.
		for i in 9:
			var z := lerpf(-l * 0.3, l * 0.4, float(i) / 8.0)
			for side: float in [-1.0, 1.0]:
				specs.append([Vector3(side * b * 0.5, 6.4 * k, z), Color(1.0, 0.85, 0.6, 0.5), 0.5, 4, Vector3.ZERO])
	_lights = MeshInstance3D.new()
	_lights.name = "Lights"
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners := [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0)]
	for spec: Array in specs:
		var code := float(spec[3]) * 10.0
		if (spec[4] as Vector3) != Vector3.ZERO:
			code += 100.0
		for c in [0, 1, 2, 0, 2, 3]:
			st.set_color(spec[1])
			st.set_uv(corners[c])
			st.set_uv2(Vector2(spec[2], code))
			st.set_normal(spec[4] if (spec[4] as Vector3) != Vector3.ZERO else Vector3.UP)
			st.add_vertex(spec[0])
	var mesh := st.commit()
	var lm := ShaderMaterial.new()
	lm.shader = _light_shader
	lm.set_shader_parameter("field_day", 0.0)
	lm.set_shader_parameter("min_angle", 0.0035)
	mesh.surface_set_material(0, lm)
	_lights.mesh = mesh
	_lights.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lights.custom_aabb = AABB(Vector3.ONE * -60.0, Vector3.ONE * 120.0)
	_lights.extra_cull_margin = 16000.0
	add_child(_lights)


# --- Damage -------------------------------------------------------------------------------------

## Bullets, pellets, rockets and blasts all come through here (the props layer's contract; the
## extra arguments are a Vehicle's and are ignored).
func take_hit(_shape_idx: int, damage: float, _dir: Vector3, _at: Vector3 = Vector3.ZERO, _kind: int = 0) -> void:
	if life != Life.UNDERWAY:
		return
	health -= damage
	if health < float(HEALTH[kind]) * 0.5 and _smoke == null:
		_smoke = _particles(AmbientCraft._smoke_material(), 60, 3.4, Color(0.13, 0.12, 0.11, 0.7), 1.5 + length * 0.12, 4.0 + length * 0.3)
		_smoke.gravity = Vector3(0.0, 1.4, 0.0)
		_smoke.position = Vector3(0.0, 1.5 * scale_k, length * 0.15)
		add_child(_smoke)
	if health <= 0.0:
		life = Life.BURNING
		_burn_left = BURN_SECONDS
		_fire = _particles(AmbientCraft._fire_material(), 30, 0.5, Color(2.4, 0.9, 0.22, 0.85), 1.0 + length * 0.06, 2.0 + length * 0.12)
		_fire.position = Vector3(0.0, 1.2 * scale_k, length * 0.1)
		add_child(_fire)
		if _smoke:
			_smoke.color = Color(0.06, 0.055, 0.05, 0.85)


func _coast(dt: float) -> void:
	var here := Vector2(world_pos.x, world_pos.z) + heading * speed * dt
	world_pos = Vector3(here.x, world_pos.y, here.y)


func _explode() -> void:
	life = Life.SINKING
	_sink_t = 0.0
	_sink_roll = (1.0 if _rng.randf() < 0.5 else -1.0) * _rng.randf_range(0.15, 0.45)
	collision_layer = 0
	var at := WorldState.to_local(world_pos) + Vector3(0.0, 1.0 * scale_k, 0.0)
	Explosion.blast(self, at, 6.0 + length * 0.35, 14.0, 10.0)
	if _sound:
		_sound.queue_free()
		_sound = null
	if _lights:
		_lights.visible = false
	if traffic and traffic.has_method("on_vessel_lost"):
		traffic.on_vessel_lost(self)


## Settling by the stern and over on one side, then gone under.
func _sink(dt: float) -> void:
	_sink_t += dt
	var u := clampf(_sink_t / SINK_SECONDS, 0.0, 1.0)
	speed = move_toward(speed, 0.0, dt * 2.0)
	_coast(dt)
	var depth := pow(u, 1.6) * (length * 0.5 + 6.0)
	world_pos.y = SEA_LEVEL - depth
	trim = lerpf(trim, -0.35 * clampf(u * 1.5, 0.0, 1.0), minf(dt, 1.0))
	heel = lerpf(heel, _sink_roll, minf(dt * 0.3, 1.0))
	if _fire and u > 0.4:
		_fire.emitting = false
	if _smoke and u > 0.75:
		_smoke.emitting = false
	if u >= 1.0:
		done = true
		finished.emit(self)


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
	p.custom_aabb = AABB(Vector3.ONE * -200.0, Vector3.ONE * 400.0)
	p.emitting = true
	return p
