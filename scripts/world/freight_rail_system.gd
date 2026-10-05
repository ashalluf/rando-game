class_name FreightRailSystem
extends Node3D
## The freight line in motion (a Node3D in city.tscn, shifted with the world like LightRailSystem).
## Every physics tick it advances the line's clock (FreightRail.clock) and works everything else
## out from it - nothing per train is ticked that the timetable already says:
##   * trains: FreightRail.trains_at(clock). Every car of every train not in the covered way is
##     placed on its two trucks' points on the track (so a train snakes through the crossover and
##     tilts on the ramps); within `detail_range` of the camera a car is its FreightStock mesh
##     (one MultiMesh per type, the stack cars' boxes PortKit's), out to `far_range` a box in one
##     MultiMesh. The leading unit's headlight and ditch lights are lit.
##   * crossings: which are closed (FreightRail.crossing_phase()), into FreightRail.closed for
##     TrafficManager's stop rule, every RailGate in the "freight_gate" group posed from it, the
##     bells of the nearest closed ones ringing;
##   * sound: the horn's long-long-short-long for every crossing ahead of a train near the player
##     and for the player on the track, the rolling clatter and the engines at the nearest cars;
##   * strikes: whoever stands in front of a moving train is hit (the player launched and hurt,
##     pedestrians knocked down, cars shoved off: never the player's crime);
##   * collision: a small pool of boxes on the cars nearest the player (props layer, so bullets,
##     the player and cars hit them; the player can ride one).

@export var detail_range: float = 300.0
@export var far_range: float = 3800.0
@export var crossing_range: float = 1600.0
@export var bell_reach: float = 160.0
## The horn is sounded for crossings and the player within this distance of a train (m).
@export var horn_hear: float = 650.0
@export var strike_reach: float = 1.4
@export var strike_launch: float = 1.15
@export var strike_damage: float = 11.0
## Collision boxes on the cars within this distance of the player, at most `bodies`.
@export var body_range: float = 70.0
@export var bodies: int = 18

## Where "the player" is when there is none (stills), TRUE world.
var focus := Vector3.INF
var hold: bool = OS.get_environment("FREIGHT_HOLD") == "1"
var plan: CityPlan
var line: FreightRail
var trains: Array[Dictionary] = []
## Cars drawn in detail this tick (for the checks and the HUD).
var detailed_cars := 0
var far_cars := 0
var _player: Node3D
var _ready_done := false
var _mm: Dictionary = {}
var _boxes: MultiMeshInstance3D
var _far: MultiMeshInstance3D
var _bells: Array[AudioStreamPlayer3D] = []
var _roll: AudioStreamPlayer3D
var _engine: AudioStreamPlayer3D
var _body_pool: Array[AnimatableBody3D] = []
var _body_key: Array = []
var _horned: Dictionary = {}
var _horn: AudioStreamPlayer3D
var _horn_blast: AudioStreamPlayer3D
var _horn_n := -1
var _struck_at := -10.0
const CAP := 160
const BOX_CAP := 260
const FAR_CAP := 300


func _ready() -> void:
	name = "FreightRail"


func _setup() -> bool:
	var city := get_parent()
	if city == null or not ("plan" in city):
		return false
	plan = city.get("plan") as CityPlan
	if plan == null:
		return false
	line = FreightRail.of(plan)
	if line == null:
		set_physics_process(false)
		return false
	_player = get_tree().get_first_node_in_group("player") as Node3D
	for t in 6:
		_mm[t] = _multimesh("FreightCars_%d" % t, FreightStock.mesh(t), CAP, true)
	_boxes = _multimesh("FreightBoxes", PropFactory.container(), BOX_CAP, true)
	_far = _multimesh("FreightFar", FreightStock.far_box(), FAR_CAP, false)
	_far.material_override = FreightStock.material()
	for i in 2:
		var b := Sfx.loop_player("rail_bell", -2.0)
		b.unit_size = 12.0
		add_child(b)
		_bells.append(b)
	_roll = Sfx.loop_player("freight_roll", 0.0)
	_roll.unit_size = 22.0
	add_child(_roll)
	_horn = Sfx.loop_player("freight_horn", 6.0)
	_horn_blast = Sfx.loop_player("freight_horn_blast", 6.0)
	for hp: AudioStreamPlayer3D in [_horn, _horn_blast]:
		hp.unit_size = 45.0
		hp.max_distance = 2500.0
		add_child(hp)
	_engine = Sfx.loop_player("freight_engine", 0.0)
	_engine.unit_size = 18.0
	add_child(_engine)
	for i in bodies:
		var body := AnimatableBody3D.new()
		body.name = "FreightCarBody"
		body.sync_to_physics = false
		body.collision_layer = 0
		body.collision_mask = 0
		body.add_to_group("rail_vehicle")
		body.set_script(load("res://scripts/world/freight_car_body.gd"))
		var cs := CollisionShape3D.new()
		cs.shape = BoxShape3D.new()
		body.add_child(cs)
		add_child(body)
		_body_pool.append(body)
		_body_key.append(null)
	# Stills: FREIGHT_CROSS=<crossing>[:<dir 0 north|1 south>[:<seconds before>]],
	# FREIGHT_S=<s>[:<dir>[:<seconds before>]], FREIGHT_YARD=<seconds into the stand>.
	var cr := OS.get_environment("FREIGHT_CROSS").split(":", false)
	if cr.size() > 0:
		FreightRail.clock = line.clock_at_crossing(cr[0].to_int(), cr[1].to_int() if cr.size() > 1 else 0, cr[2].to_float() if cr.size() > 2 else 6.0)
	var fs := OS.get_environment("FREIGHT_S").split(":", false)
	if fs.size() > 0:
		FreightRail.clock = line.clock_at_s(fs[0].to_float(), fs[1].to_int() if fs.size() > 1 else 0, fs[2].to_float() if fs.size() > 2 else 0.0)
	var fy := OS.get_environment("FREIGHT_YARD")
	if fy != "":
		FreightRail.clock = line.clock_at_yard(fy.to_float())
	_ready_done = true
	return true


func _multimesh(node_name: String, mesh: Mesh, cap: int, shadows: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = cap
	mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.name = node_name
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-20000, -500, -20000), Vector3(40000, 1000, 40000))
	add_child(mi)
	return mi


func _physics_process(delta: float) -> void:
	if not _ready_done and not _setup():
		return
	if not hold:
		FreightRail.clock += delta
	step()


## One tick at the current clock (public: the checks call it after setting the clock).
func step() -> void:
	if line == null:
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	var pw := WorldState.to_world(_player.global_position) if _player else Vector3.ZERO
	if focus != Vector3.INF:
		pw = focus
	var cam := pw
	var vp := get_viewport()
	if vp and vp.get_camera_3d():
		cam = WorldState.to_world(vp.get_camera_3d().global_position)
	trains = line.trains_at(FreightRail.clock)
	_draw(cam, pw)
	_crossings(pw)


# --- Placing the cars ------------------------------------------------------------------------------

## A car's transform (true world) from its centre's s, its truck half spacing, the train's state and
## whether it faces +s: on the two truck points, its -Z toward the cab end.
func car_xform(st: Dictionary, s_c: float, th: float, faces_south: bool) -> Transform3D:
	var sf := s_c - th
	var sr := s_c + th
	var pf := line.track_point(sf, line.offset_at(st, sf))
	var pr := line.track_point(sr, line.offset_at(st, sr))
	var north := (pf - pr).normalized()
	var z := north if faces_south else -north
	var x := Vector3.UP.cross(z).normalized()
	var y := z.cross(x).normalized()
	return Transform3D(Basis(x, y, z), (pf + pr) * 0.5)


func _draw(cam: Vector3, pw: Vector3) -> void:
	var bufs: Dictionary = {}
	var counts: Dictionary = {}
	for t in 6:
		bufs[t] = PackedFloat32Array()
		counts[t] = 0
	var box_buf := PackedFloat32Array()
	var box_n := 0
	var far_buf := PackedFloat32Array()
	var far_n := 0
	var to_local := global_transform.affine_inverse()
	var near_cars: Array = []
	var lead_info: Array = []
	for st in trains:
		if line.hidden(st):
			continue
		var c: Dictionary = st.consist
		var sA: float = st.sA
		var cars: Array = c.cars
		var dir: int = st.dir
		var phase: int = st.phase
		var nose_s := sA if (phase < 2) else sA + float(c.len)
		for j in cars.size():
			var car: Dictionary = cars[j]
			var t: int = car.type
			var s_c: float = sA + float(car.c)
			if s_c > line.s_mouth + 4.0:
				continue
			var th: float = FreightRail.TRUCK_HALF[t]
			var xf := car_xform(st, s_c, th, bool(car.flip))
			var d := cam.distance_to(xf.origin)
			if d > far_range:
				continue
			var look: int = car.look
			var lamps := -1.0
			var number := -1.0
			if t == FreightRail.Car.LOCO:
				number = float(int(car.loco_no) % 1000) / 1000.0
				lamps = 0.0
				# The leading unit's cab end lit (north: the first; south: the last).
				var leading := (j == 0 and phase < 2) or (j == cars.size() - 1 and phase == 2)
				if leading:
					lamps = 1.0
					lead_info.append([xf, st])
			var custom := FreightStock.custom(t, look, lamps, number)
			var paint := Color(1, 1, 1)
			var lxf := to_local * Transform3D(xf.basis, WorldState.to_local(xf.origin))
			if d < detail_range and int(counts[t]) < CAP:
				_put(bufs[t], lxf, paint, custom)
				counts[t] = int(counts[t]) + 1
				if t == FreightRail.Car.WELL:
					for b: Array in FreightYard.well_boxes(look):
						if box_n >= BOX_CAP:
							break
						var bx: Transform3D = b[0]
						_put_raw(box_buf, Transform3D(lxf.basis * bx.basis, lxf * bx.origin), b[1], b[2])
						box_n += 1
				if d < body_range + 30.0:
					near_cars.append([pw.distance_to(xf.origin), xf, t, st, j])
			elif far_n < FAR_CAP:
				var env := FreightStock.envelope(t)
				var h := env.y
				var fcode := int(custom.r)
				if t == FreightRail.Car.WELL:
					h = 6.1
					fcode = (FreightStock.LIVERY0 + absi(look >> 2) % PortKit.LIVERY_COUNT) * 16 + 4
				var fb := Basis(lxf.basis.x * env.x, lxf.basis.y * (h - 0.8), lxf.basis.z * (env.z - 0.6))
				_put(far_buf, Transform3D(fb, lxf.origin + lxf.basis.y * 0.8), paint, Color(float(fcode), 0.5, -1.0, 0.0))
				far_n += 1
		_sound_train(st, nose_s, dir, pw)
	detailed_cars = 0
	for t in 6:
		var mi: MultiMeshInstance3D = _mm[t]
		detailed_cars += int(counts[t])
		_commit(mi.multimesh, bufs[t], int(counts[t]), CAP)
	_commit(_boxes.multimesh, box_buf, box_n, BOX_CAP)
	_commit(_far.multimesh, far_buf, far_n, FAR_CAP)
	far_cars = far_n
	_bodies(near_cars)
	_strikes(lead_info, pw)


static func _put(buf: PackedFloat32Array, xf: Transform3D, col: Color, custom: Color) -> void:
	_put_raw(buf, xf, col, custom)


static func _put_raw(buf: PackedFloat32Array, xf: Transform3D, col: Color, custom: Color) -> void:
	var b := xf.basis
	buf.append_array([b.x.x, b.y.x, b.z.x, xf.origin.x, b.x.y, b.y.y, b.z.y, xf.origin.y, b.x.z, b.y.z, b.z.z, xf.origin.z,
		col.r, col.g, col.b, col.a, custom.r, custom.g, custom.b, custom.a])


## The buffer into the MultiMesh (padded to its capacity with collapsed instances).
static func _commit(mm: MultiMesh, buf: PackedFloat32Array, n: int, cap: int) -> void:
	if n == 0 and mm.visible_instance_count == 0:
		return
	if buf.size() < cap * 20:
		var pad := cap * 20 - buf.size()
		var start := buf.size()
		buf.resize(cap * 20)
		for i in range(start, start + pad):
			buf[i] = 0.0
	mm.buffer = buf
	mm.visible_instance_count = n


# --- Collision -----------------------------------------------------------------------------------

## Boxes on the nearest cars. A body that moves to a different car is teleported (no velocity from
## it), one that stays with its car moves with sync_to_physics, so whoever stands on it rides.
func _bodies(near: Array) -> void:
	near.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var used := 0
	for i in _body_pool.size():
		var body := _body_pool[i]
		if i < near.size() and float(near[i][0]) < body_range:
			var e: Array = near[i]
			var xf: Transform3D = e[1]
			var t: int = e[2]
			var st: Dictionary = e[3]
			var key := [int(st.n), int(e[4])]
			var env := FreightStock.envelope(t)
			var h := env.y - 0.9
			if t == FreightRail.Car.WELL:
				h = 5.3
			var local := global_transform.affine_inverse() * Transform3D(xf.basis, WorldState.to_local(xf.origin + xf.basis.y * (0.9 + h * 0.5)))
			var cs: CollisionShape3D = body.get_child(0)
			(cs.shape as BoxShape3D).size = Vector3(env.x, h, env.z - 0.5)
			if _body_key[i] != key:
				body.sync_to_physics = false
				body.transform = local
				_body_key[i] = key
			else:
				body.sync_to_physics = true
				body.transform = local
			body.collision_layer = 4
			used += 1
		else:
			body.collision_layer = 0
			_body_key[i] = null


# --- Strikes and sound ---------------------------------------------------------------------------

func _strikes(leads: Array, pw: Vector3) -> void:
	for li: Array in leads:
		var xf: Transform3D = li[0]
		var st: Dictionary = li[1]
		var v := float(st.v)
		if v < 1.0:
			continue
		var fwd := -xf.basis.z.normalized()
		var front := xf.origin + fwd * 11.4
		var reach := strike_reach + v * 0.1
		if _player and Time.get_ticks_msec() * 0.001 - _struck_at > 1.0:
			var rel := pw - front
			var ahead := rel.dot(fwd)
			var side := absf(rel.dot(xf.basis.x.normalized()))
			if ahead > -1.0 and ahead < reach and side < 1.8 and rel.y > -1.0 and rel.y < 5.0:
				_struck_at = Time.get_ticks_msec() * 0.001
				if _player.has_method("launch"):
					_player.launch(fwd * v * strike_launch + Vector3.UP * v * 0.4)
				if _player.has_method("take_damage"):
					_player.take_damage(v * strike_damage, WorldState.to_local(front), "train")
				Sfx.play("freight_horn", WorldState.to_local(front), 2.0)
		var space := get_world_3d().direct_space_state
		var q := PhysicsShapeQueryParameters3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(3.0, 3.0, reach + 0.8)
		q.shape = box
		q.collision_mask = 8 | 4
		q.collide_with_areas = false
		q.transform = Transform3D(xf.basis, WorldState.to_local(front + fwd * (reach * 0.5) + Vector3.UP * 1.6))
		for hit in space.intersect_shape(q, 8):
			var who: Object = hit.get("collider")
			if who == null or (who is Node and (who as Node).is_in_group("rail_vehicle")):
				continue
			Police.innocent = true
			if who is Vehicle:
				var car := who as Vehicle
				var shove := fwd * v * 1.3 + Vector3.UP * v * 0.25
				if car.is_traffic():
					car.drop_out_of_traffic(shove)
				else:
					car.linear_velocity += shove
				car.take_hit(0, v * 3.0, fwd, WorldState.to_local(front), Vehicle.HIT_CRASH)
			elif who.has_method("knock"):
				who.knock(fwd * v * 1.6 + Vector3.UP * v * 0.5)
			Police.innocent = false


## The horn for each crossing ahead of a train (from 18 s out: long, long, short, long), and for the
## player on the track ahead of it; the clatter and the engines follow the nearest cars.
func _sound_train(st: Dictionary, nose_s: float, dir: int, pw: Vector3) -> void:
	var v := float(st.v)
	var nose := line.track_point(nose_s, line.offset_at(st, nose_s))
	var dist := pw.distance_to(nose)
	if dist > horn_hear or v < 2.0 or dir == 0:
		return
	var now := Time.get_ticks_msec() * 0.001
	var key := int(st.n) * 4 + (1 if dir > 0 else 0)
	for c in line.crossings:
		var ahead := (float(c.s) - nose_s) * float(dir)
		var eta := ahead / maxf(v, 0.5)
		if eta > 0.0 and eta < 18.0:
			var ck := "%d:%d" % [key, int(c.k)]
			if not _horned.has(ck):
				_horned[ck] = now
				_horn_pattern(st, dir)
	# The player on the track ahead.
	var rel := Vector2(pw.x - nose.x, pw.z - nose.z)
	var ahead_p := rel.y * float(dir)
	if ahead_p > 0.0 and ahead_p < 140.0 and absf(rel.x) < 5.0 and now - float(_horned.get(key, -100.0)) > 6.0:
		_horned[key] = now
		_horn_pattern(st, dir, true)
	if _horned.size() > 200:
		_horned.clear()


## The horn: the crossing pattern (one CC0 take of a five-chime horn doing long, long, short,
## long) or one blast, from a player that follows the leading unit while it sounds.
func _horn_pattern(st: Dictionary, _dir: int, short := false) -> void:
	var p := _horn_blast if short else _horn
	if p.playing and _horn_n == int(st.n):
		return
	_horn_n = int(st.n)
	p.play()
	_place_horn()


func _place_horn() -> void:
	if _horn_n < 0:
		return
	var cur := line.train_state(_horn_n, FreightRail.clock)
	if cur.is_empty():
		return
	var ns := float(cur.sA) if int(cur.phase) < 2 else float(cur.sA) + float(cur.len)
	var at := WorldState.to_local(line.track_point(ns, line.offset_at(cur, ns)) + Vector3.UP * 4.9)
	_horn.global_position = at
	_horn_blast.global_position = at


# --- Crossings -----------------------------------------------------------------------------------

func _crossings(pw: Vector3) -> void:
	var closed: Dictionary = {}
	var phases: Dictionary = {}
	var p2 := Vector2(pw.x, pw.z)
	var ringing: Array = []
	for c in line.crossings:
		if p2.distance_to(c.pos) > crossing_range:
			continue
		var ph := line.crossing_phase(c, FreightRail.clock)
		phases[c.node] = ph
		if ph > 0.0:
			closed[c.node] = int(c.axis)
			if p2.distance_to(c.pos) < bell_reach:
				ringing.append([p2.distance_to(c.pos), c])
	FreightRail.closed = closed
	if _horn.playing or _horn_blast.playing:
		_place_horn()
	var blink := fmod(FreightRail.clock, 1.0) < 0.5
	for g in get_tree().get_nodes_in_group("freight_gate"):
		var gate := g as RailGate
		if gate == null or not gate.is_inside_tree():
			continue
		gate.pose_at(float(phases.get(gate.node_key, -120.0)), blink)
	ringing.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for i in _bells.size():
		var b := _bells[i]
		if i < ringing.size():
			var c: Dictionary = ringing[i][1]
			var at: Vector2 = c.pos
			b.global_position = WorldState.to_local(Vector3(at.x, line.street_at(float(c.s)) + 4.0, at.y))
			if not b.playing:
				b.play()
		elif b.playing:
			b.stop()
	# The clatter and the engine: at the nearest moving car and the nearest locomotive.
	var best_d := INF
	var best_p := Vector3.ZERO
	var best_v := 0.0
	var loco_d := INF
	var loco_p := Vector3.ZERO
	for st in trains:
		if line.hidden(st):
			continue
		var c: Dictionary = st.consist
		var sA: float = st.sA
		# The point of the train nearest the player along the line.
		var s_p := clampf(pw.z - line.z0, sA, sA + float(c.len))
		var p := line.track_point(s_p, line.offset_at(st, s_p))
		var d := pw.distance_to(p)
		if d < best_d:
			best_d = d
			best_p = p
			best_v = float(st.v)
		for end_s: float in [sA + 11.0, sA + float(c.len) - 11.0]:
			var lp := line.track_point(end_s, line.offset_at(st, end_s))
			if pw.distance_to(lp) < loco_d:
				loco_d = pw.distance_to(lp)
				loco_p = lp
	if best_d < 400.0 and best_v > 0.5:
		_roll.global_position = WorldState.to_local(best_p + Vector3.UP * 1.0)
		_roll.volume_db = linear_to_db(clampf(best_v / 15.0, 0.05, 1.0)) + 2.0
		_roll.pitch_scale = clampf(0.75 + best_v / 40.0, 0.7, 1.25)
		if not _roll.playing:
			_roll.play()
	elif _roll.playing:
		_roll.stop()
	if loco_d < 350.0:
		_engine.global_position = WorldState.to_local(loco_p + Vector3.UP * 4.0)
		if not _engine.playing:
			_engine.play()
	elif _engine.playing:
		_engine.stop()
