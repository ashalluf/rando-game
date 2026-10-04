class_name LightRailSystem
extends Node3D
## The Coral Line in motion (a Node3D in city.tscn, shifted with the world like AirTraffic). Every
## physics tick it advances the line's clock (LightRail.clock) and works everything else out from
## it - nothing per train is ticked that the timetable already says:
##   * trains: LightRail.trains_at(clock); the ones within `detail_range` of the player get a
##     LightRailTrain from a small pool (at most `max_detailed`), posed from the clock; the rest
##     within `far_range` are lit boxes in one MultiMesh (lrv_far.gdshader), so the line reads
##     from the air, strings of lit windows at night. Trains in the tunnel are drawn by nobody.
##   * crossings: which junctions the line is closing (LightRail.crossing_state()), into
##     LightRail.closed for TrafficManager's stop rule, and every RailGate in the tree driven
##     from it (arms down, lamps alternating, a bell near the player);
##   * strikes: whoever stands in front of a moving detailed train - the player (launched and
##     hurt), pedestrians (knocked down; never the player's crime) - is hit by it;
##   * the horn and the gong as a train nears the player or a crossing.

## Trains within this distance (m, from the player to the train's middle) are drawn in full.
@export var detail_range: float = 520.0
## At most this many detailed trains at once (the nearest).
@export var max_detailed: int = 3
## Far boxes out to here (m).
@export var far_range: float = 7000.0
## Crossings within this distance of the player are worked out every tick (the rest stay open:
## nobody is there to stop).
@export var crossing_range: float = 1600.0
## A train hits what is up to this far ahead of its nose (m, plus a share of its speed).
@export var strike_reach: float = 1.2
## The player struck: launched by speed times this, hurt by speed times `strike_damage`.
@export var strike_launch: float = 1.25
@export var strike_damage: float = 9.0
## The bell's reach (m) and the horn's: sounded when the player is this close ahead of a train.
@export var bell_reach: float = 140.0
@export var horn_reach: float = 70.0
## Off on the plain grid, and RAIL=0 in the environment (LightRail.enabled).

## Where "the player" is when there is none (tools/light_rail/rail_shot.gd), TRUE world.
var focus := Vector3.INF
## The clock stands still (stills: RAIL_HOLD=1 with RAIL_AT / RAIL_CROSS).
var hold: bool = OS.get_environment("RAIL_HOLD") == "1"
var plan: CityPlan
var line: LightRail
var _player: Node3D
var _ready_done := false
var _pool: Dictionary = {}
var _far: MultiMeshInstance3D
var _bells: Array[AudioStreamPlayer3D] = []
var _horn_at: Dictionary = {}
var _struck_at := -10.0
## The trains this tick (for tests and the HUD): LightRail.trains_at(clock).
var trains: Array[Dictionary] = []
## Ids of the trains drawn in detail this tick.
var detailed: Array[int] = []


func _ready() -> void:
	name = "LightRail"


func _setup() -> bool:
	var city := get_parent()
	if city == null or not ("plan" in city):
		return false
	plan = city.get("plan") as CityPlan
	if plan == null:
		return false
	line = LightRail.of(plan)
	if line == null:
		set_physics_process(false)
		return false
	_player = get_tree().get_first_node_in_group("player") as Node3D
	_build_far()
	_build_far_line()
	# The horizon plane sinks under the portal's trench (macro_ground.gdshader cut_rect).
	var ground: ShaderMaterial = city.get("_ground_material") as ShaderMaterial
	if ground and not line.cut_rects().is_empty():
		var r: Rect2 = line.cut_rects()[0]
		ground.set_shader_parameter("cut_rect", Vector4(r.position.x, r.position.y, r.end.x, r.end.y))
	for i in 2:
		var b := Sfx.loop_player("rail_bell", -2.0)
		b.unit_size = 10.0
		add_child(b)
		_bells.append(b)
	# Stills: RAIL_AT=<station>[:<dir 0|1>[:<seconds from mid-dwell>]] or
	# RAIL_CROSS=<crossing>[:<dir>[:<seconds before the train>]] set the clock there.
	var at := OS.get_environment("RAIL_AT").split(":", false)
	if at.size() > 0:
		LightRail.clock = line.clock_at_station(at[0].to_int(), at[1].to_int() if at.size() > 1 else 0, at[2].to_float() if at.size() > 2 else 0.0)
	var cr := OS.get_environment("RAIL_CROSS").split(":", false)
	if cr.size() > 0:
		LightRail.clock = line.clock_at_crossing(cr[0].to_int(), cr[1].to_int() if cr.size() > 1 else 0, cr[2].to_float() if cr.size() > 2 else 6.0)
	# RAIL_S=<s>:<dir>[:<seconds before>]: a train's nose at s along the line.
	var rs := OS.get_environment("RAIL_S").split(":", false)
	if rs.size() > 0:
		LightRail.clock = line.clock_at_s(rs[0].to_float(), rs[1].to_int() if rs.size() > 1 else 0, rs[2].to_float() if rs.size() > 2 else 0.0)
	_ready_done = true
	return true


func _physics_process(delta: float) -> void:
	if not _ready_done and not _setup():
		return
	if not hold:
		LightRail.clock += delta
	step()


## One tick at the current clock (public: the smoke test calls it after setting the clock).
func step() -> void:
	if line == null:
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	var pw := WorldState.to_world(_player.global_position) if _player else Vector3.ZERO
	if focus != Vector3.INF:
		pw = focus
	trains = line.trains_at(LightRail.clock)
	_trains(pw)
	_crossings(pw)


# --- Trains ----------------------------------------------------------------------------------

func _trains(pw: Vector3) -> void:
	var lamp := DayNight.lamp_now
	# The nearest trains get the detail.
	var by_dist: Array = []
	for st in trains:
		var mid := line.sample(float(st.s) - float(st.dir) * LightRail.TRAIN_LENGTH * 0.5)
		var p: Vector2 = mid.pos
		var d := Vector2(pw.x, pw.z).distance_to(p)
		by_dist.append([d, st])
	by_dist.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var want: Dictionary = {}
	for e: Array in by_dist:
		if want.size() >= max_detailed or float(e[0]) > detail_range + LightRail.TRAIN_LENGTH * 0.5:
			break
		if _buried(e[1]):
			continue
		want[int(e[1].id)] = e[1]
	detailed.clear()
	# Retire what is no longer wanted (hidden and kept, the pool is tiny).
	for id: int in _pool.keys():
		if not want.has(id):
			var tr: LightRailTrain = _pool[id]
			tr.visible = false
			tr.process_mode = Node.PROCESS_MODE_DISABLED
			for s in tr.sections:
				s.collision_layer = 0
	for id: int in want.keys():
		var tr: LightRailTrain = _pool.get(id)
		if tr == null:
			# Reuse a hidden one before building a new train.
			for other: int in _pool.keys():
				if not want.has(other):
					tr = _pool[other]
					_pool.erase(other)
					break
			if tr == null:
				if not LightRailTrain.available():
					continue
				tr = LightRailTrain.new()
				add_child(tr)
				tr.setup(line)
			_pool[id] = tr
		tr.id = id
		tr.visible = true
		tr.process_mode = Node.PROCESS_MODE_INHERIT
		for s in tr.sections:
			s.collision_layer = 4
		var st: Dictionary = want[id]
		tr.set_destination(str(line.stations[line.stations.size() - 1 if int(st.dir) > 0 else 0].name))
		tr.pose(st, lamp)
		detailed.append(id)
		_strike(tr, st, pw)
		_sound(tr, st, pw)
		_passengers(tr, st)
	_update_far(want, pw)


func _buried(st: Dictionary) -> bool:
	var rear := float(st.s) - float(st.dir) * LightRail.TRAIN_LENGTH
	return maxf(float(st.s), rear) < line.mouth_s - 10.0


## The section boxes of every train not drawn in detail.
func _build_far() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _far_box()
	mm.instance_count = (line.fleet + 2) * LightRail.CARS * 2
	mm.visible_instance_count = 0
	_far = MultiMeshInstance3D.new()
	_far.name = "FarTrains"
	_far.multimesh = mm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/lrv_far.gdshader")
	_far.material_override = mat
	_far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_far.custom_aabb = AABB(Vector3(-9000, -200, -9000), Vector3(18000, 600, 18000))
	add_child(_far)


## The line itself past the streamed chunks (they build it out to their LOD ring): the structure,
## its columns, the trackway, the stations' canopies, as one cheap mesh in true world space that
## dithers in from `far_line_start` (light_rail_far_line.gdshader), so the line is there from the
## air and from the hills. Its pieces sit a hair inside the chunks' own where both draw.
@export var far_line_start: float = 880.0
var _far_line: MeshInstance3D


func _build_far_line() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var conc := Color(0.66, 0.65, 0.62, 0.0)
	var track := Color(0.40, 0.395, 0.38, 0.0)
	var n := line.pts.size()
	var stride := 6
	var i := 0
	while i < n - 1:
		var j := mini(i + stride, n - 1)
		var a := line.pts[i]
		var b := line.pts[j]
		var ra := Vector2(-line.dirs[i].y, line.dirs[i].x)
		var rb := Vector2(-line.dirs[j].y, line.dirs[j].x)
		var m: int = line.mode[i]
		if m == LightRail.Mode.AERIAL or line.mode[j] == LightRail.Mode.AERIAL:
			var wa: float = line.half[i] + 1.6
			var wb: float = line.half[j] + 1.6
			var ta: float = line.rail[i] - 0.5
			var tb: float = line.rail[j] - 0.5
			_far_quad(st, a - ra * wa, a + ra * wa, b + rb * wb, b - rb * wb, [ta, ta, tb, tb], Vector3.UP, conc)
			for side: float in [-1.0, 1.0]:
				var ea := a + ra * side * wa
				var eb := b + rb * side * wb
				_far_side(st, ea, eb, ta + 0.9, tb + 0.9, ta - 2.0, tb - 2.0, Vector3(ra.x, 0.0, ra.y) * side, conc)
		elif m == LightRail.Mode.GRADE:
			var wa2: float = line.half[i] + 1.3
			var wb2: float = line.half[j] + 1.3
			_far_quad(st, a - ra * wa2, a + ra * wa2, b + rb * wb2, b - rb * wb2,
				[float(line.street[i]) + 0.01, float(line.street[i]) + 0.01, float(line.street[j]) + 0.01, float(line.street[j]) + 0.01], Vector3.UP, track)
		i = j
	# Columns under the structure.
	var k := 0
	while float(k) * 30.0 < line.length:
		var smp := line.sample(float(k) * 30.0 + 5.0)
		k += 1
		if int(smp.mode) != LightRail.Mode.AERIAL:
			continue
		var p: Vector2 = smp.pos
		var top := float(smp.y) - 2.6
		var foot := float(smp.street) - 0.5
		if top - foot < 2.0:
			continue
		for e: Vector2 in [Vector2(0.8, 0.0), Vector2(0.0, 0.8), Vector2(-0.8, 0.0), Vector2(0.0, -0.8)]:
			var q := Vector2(-e.y, e.x)
			_far_side(st, p + e + q, p + e - q, top, top, foot, foot, Vector3(e.x, 0.0, e.y).normalized(), conc)
	# Station canopies: a lit roof (vertex alpha 1 glows after dark) over a platform box.
	for s2 in line.stations:
		if int(s2.mode) == LightRail.Mode.TUNNEL:
			continue
		var c := line.sample(float(s2.s))
		var d: Vector2 = c.dir
		var r := Vector2(-d.y, d.x)
		var p: Vector2 = c.pos
		var hl := LightRail.PLATFORM_LENGTH * 0.4
		var hw := float(s2.width) * 0.5 + 0.6
		var roof := float(c.y) + LightRail.PLATFORM_HEIGHT + 3.6
		_far_quad(st, p - d * hl - r * hw, p - d * hl + r * hw, p + d * hl + r * hw, p + d * hl - r * hw, [roof, roof, roof, roof], Vector3.UP, Color(0.86, 0.86, 0.84, 1.0))
		_far_side(st, p - d * hl + r * hw, p + d * hl + r * hw, roof, roof, roof - 0.3, roof - 0.3, Vector3(r.x, 0, r.y), Color(0.93, 0.40, 0.30, 0.0))
		_far_side(st, p + d * hl - r * hw, p - d * hl - r * hw, roof, roof, roof - 0.3, roof - 0.3, Vector3(-r.x, 0, -r.y), Color(0.93, 0.40, 0.30, 0.0))
	var mesh := st.commit()
	_far_line = MeshInstance3D.new()
	_far_line.name = "FarLine"
	_far_line.mesh = mesh
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/light_rail_far_line.gdshader")
	mat.set_shader_parameter("fade_start", far_line_start)
	_far_line.material_override = mat
	_far_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_far_line)
	_far_line.global_position = -WorldState.world_offset


func _far_quad(st: SurfaceTool, a: Vector2, b: Vector2, c: Vector2, d: Vector2, ys: Array, n: Vector3, col: Color) -> void:
	var pts: Array[Vector3] = [Vector3(a.x, ys[0], a.y), Vector3(b.x, ys[1], b.y), Vector3(c.x, ys[2], c.y), Vector3(d.x, ys[3], d.y)]
	var nn: Vector3 = (pts[2] - pts[0]).cross(pts[1] - pts[0])
	var order := [0, 1, 2, 0, 2, 3] if nn.dot(n) > 0.0 else [0, 2, 1, 0, 3, 2]
	for idx: int in order:
		st.set_color(col)
		st.set_normal(n)
		st.add_vertex(pts[idx])


func _far_side(st: SurfaceTool, a: Vector2, b: Vector2, ya_top: float, yb_top: float, ya_bot: float, yb_bot: float, n: Vector3, col: Color) -> void:
	var pts: Array[Vector3] = [Vector3(a.x, ya_top, a.y), Vector3(b.x, yb_top, b.y), Vector3(b.x, yb_bot, b.y), Vector3(a.x, ya_bot, a.y)]
	var nn: Vector3 = (pts[2] - pts[0]).cross(pts[1] - pts[0])
	var order := [0, 1, 2, 0, 2, 3] if nn.dot(n) > 0.0 else [0, 2, 1, 0, 3, 2]
	for idx: int in order:
		st.set_color(col)
		st.set_normal(n)
		st.add_vertex(pts[idx])


static func _far_box() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := [[Vector3.RIGHT, Vector3.BACK, Vector3.UP], [Vector3.LEFT, Vector3.FORWARD, Vector3.UP],
		[Vector3.UP, Vector3.RIGHT, Vector3.FORWARD], [Vector3.BACK, Vector3.LEFT, Vector3.UP],
		[Vector3.FORWARD, Vector3.RIGHT, Vector3.UP]]
	for f: Array in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1] * 0.5
		var v: Vector3 = f[2] * 0.5
		var c := n * 0.5 + Vector3(0.0, 0.5, 0.0)
		var p := [c - u - v, c + u - v, c + u + v, c - u + v]
		for i: int in [0, 2, 1, 0, 3, 2]:
			st.set_normal(n)
			st.add_vertex(p[i])
	return st.commit()


func _update_far(want: Dictionary, pw: Vector3) -> void:
	var mm := _far.multimesh
	var n := 0
	for st in trains:
		if want.has(int(st.id)) or _buried(st):
			continue
		var mid := line.sample(float(st.s) - float(st.dir) * LightRail.TRAIN_LENGTH * 0.5)
		if Vector2(pw.x, pw.z).distance_to(mid.pos) > far_range:
			continue
		for k in LightRail.CARS * 2:
			if n >= mm.instance_count:
				break
			var xf := LightRailTrain.section_world(line, float(st.s), int(st.dir), k)
			if xf == Transform3D():
				continue
			xf.origin = WorldState.to_local(xf.origin)
			# The unit box to the section's size (2.65 x 3.5 x 13.4).
			xf.basis = xf.basis * Basis().scaled(Vector3(2.65, 3.5, 13.4))
			mm.set_instance_transform(n, global_transform.affine_inverse() * xf)
			n += 1
	mm.visible_instance_count = n


# --- Passengers ------------------------------------------------------------------------------

## Once a dwell, with the doors open: a few of the waiting go to the doors and aboard, a few get
## off and walk away down the platform (RailRider).
var _served: Dictionary = {}


func _passengers(tr: LightRailTrain, st: Dictionary) -> void:
	if not bool(st.dwell) or float(st.doors) < 0.7:
		return
	var mid_s := float(st.s) - float(st.dir) * LightRail.TRAIN_LENGTH * 0.5
	var idx := -1
	for i in line.stations.size():
		if absf(float(line.stations[i].s) - mid_s) < 20.0:
			idx = i
	if idx < 0 or int(line.stations[idx].mode) == LightRail.Mode.TUNNEL:
		return
	var key := "%d:%d" % [int(st.id), int(floor(float(st.tau) / 30.0))]
	if _served.has(key):
		return
	_served[key] = true
	if _served.size() > 64:
		_served.clear()
		_served[key] = true
	var doors := tr.door_points()
	if doors.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([plan.seed, key])
	# Boarding: the waiting at this station, nearest door each.
	var boarded := 0
	for r in get_tree().get_nodes_in_group("rail_rider"):
		var rider := r as RailRider
		if rider == null or rider.station != idx or rider.state != 0 or not rider.is_inside_tree():
			continue
		if rng.randf() < 0.35:
			continue
		var hw := WorldState.to_world(rider.global_position)
		var best := doors[0]
		for d: Vector2 in doors:
			if d.distance_to(Vector2(hw.x, hw.z)) < best.distance_to(Vector2(hw.x, hw.z)):
				best = d
		rider.board(best)
		boarded += 1
		if boarded >= 4:
			break
	# Alighting: one to three out of the doors, off toward the platform's end.
	var st_d: Dictionary = line.stations[idx]
	var chunk := _chunk_at(st_d.pos)
	if chunk == null:
		return
	var city := get_parent()
	for k in rng.randi_range(1, 3):
		if city == null or not city.has_method("take_crowd_room") or not city.take_crowd_room(0.0):
			break
		var rider := RailRider.new()
		rider.line = line
		rider.station = idx
		rider.setup(Rect2(), 3.0, hash([plan.seed, key, "off", k]))
		var door: Vector2 = doors[rng.randi() % doors.size()]
		var end := 1.0 if rng.randf() < 0.5 else -1.0
		var exit_s := float(st_d.s) + end * (LightRail.PLATFORM_LENGTH * 0.5 + (LightRail.RAMP_RUN + 3.0 if int(st_d.mode) == LightRail.Mode.GRADE else -3.0))
		var exit: Vector2 = line.sample(exit_s).pos
		rider.position = Vector3(door.x, rider._ground_y(door.x, door.y, 0.0), door.y)
		chunk.add_child(rider)
		rider.alight(exit)


func _chunk_at(p: Vector2) -> Node:
	var city := get_parent()
	if city == null:
		return null
	var k := plan.chunk_index_at(p)
	return city.get_node_or_null("Chunk_%d,%d" % [k.x, k.y])


# --- Strikes and sound -----------------------------------------------------------------------

func _strike(tr: LightRailTrain, st: Dictionary, pw: Vector3) -> void:
	var v := float(st.v)
	if v < 1.5:
		return
	var nose := LightRailTrain.section_world(line, float(st.s), int(st.dir), 0)
	if nose == Transform3D():
		return
	var fwd := -nose.basis.z.normalized()
	var front := nose.origin + fwd * LightRailTrain.SECTION_HALF
	var reach := strike_reach + v * 0.08
	# The player.
	if _player and Time.get_ticks_msec() * 0.001 - _struck_at > 1.0:
		var rel := pw - front
		var ahead := rel.dot(fwd)
		var side := absf(rel.dot(nose.basis.x.normalized()))
		var up := rel.y
		if ahead > -1.0 and ahead < reach and side < 1.7 and up > -1.0 and up < 4.0:
			_struck_at = Time.get_ticks_msec() * 0.001
			if _player.has_method("launch"):
				_player.launch(fwd * v * strike_launch + Vector3.UP * v * 0.35)
			if _player.has_method("take_damage"):
				_player.take_damage(v * strike_damage, WorldState.to_local(front), "train")
			Sfx.play("rail_horn", WorldState.to_local(front), 2.0)
	# People on the line: a box in front of the nose on the npc layer.
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.8, 2.6, reach + 0.6)
	q.shape = box
	q.collision_mask = 8
	q.collide_with_areas = false
	q.transform = Transform3D(nose.basis, WorldState.to_local(front + fwd * (reach * 0.5) + Vector3.UP * 1.4))
	for hit in space.intersect_shape(q, 6):
		var who: Object = hit.get("collider")
		if who != null and who.has_method("knock"):
			Police.innocent = true
			who.knock(fwd * v * 1.6 + Vector3.UP * v * 0.5)
			Police.innocent = false


func _sound(tr: LightRailTrain, st: Dictionary, pw: Vector3) -> void:
	var v := float(st.v)
	if v < 2.0:
		return
	var now := Time.get_ticks_msec() * 0.001
	if now - float(_horn_at.get(int(st.id), -100.0)) < 9.0:
		return
	var nose := LightRailTrain.section_world(line, float(st.s), int(st.dir), 0)
	if nose == Transform3D():
		return
	var fwd := -nose.basis.z.normalized()
	var rel := pw - nose.origin
	var ahead := rel.dot(fwd)
	var side := absf(rel.dot(nose.basis.x.normalized()))
	# The player ahead on or by the track: the horn; a crossing coming up: the gong.
	if ahead > 0.0 and ahead < horn_reach and side < 4.0:
		Sfx.play("rail_horn", WorldState.to_local(nose.origin + fwd * 6.0), 0.0)
		_horn_at[int(st.id)] = now
		return
	if Vector2(pw.x, pw.z).distance_to(Vector2(nose.origin.x, nose.origin.z)) > 160.0:
		return
	for c in line.crossings:
		var ds := (float(c.s) - float(st.s)) * float(st.dir)
		if ds > 15.0 and ds < 45.0:
			Sfx.play("rail_gong", WorldState.to_local(nose.origin + fwd * 6.0), -2.0)
			_horn_at[int(st.id)] = now
			return


# --- Crossings -------------------------------------------------------------------------------

func _crossings(pw: Vector3) -> void:
	var closed: Dictionary = {}
	var phases: Dictionary = {}
	var p2 := Vector2(pw.x, pw.z)
	var ringing: Array = []
	for c in line.crossings:
		if p2.distance_to(c.pos) > crossing_range:
			continue
		var ph := line.crossing_phase(c, LightRail.clock)
		phases[c.node] = ph
		if ph > 0.0:
			closed[c.node] = int(c.axis)
			if bool(c.gates) and p2.distance_to(c.pos) < bell_reach:
				ringing.append([p2.distance_to(c.pos), c])
	LightRail.closed = closed
	var blink := fmod(LightRail.clock, 1.0) < 0.5
	for g in get_tree().get_nodes_in_group("rail_gate"):
		var gate := g as RailGate
		if gate == null or not gate.is_inside_tree():
			continue
		gate.pose_at(float(phases.get(gate.node_key, -120.0)), blink)
	# The bells of the nearest closed crossings.
	ringing.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for i in _bells.size():
		var b := _bells[i]
		if i < ringing.size():
			var c: Dictionary = ringing[i][1]
			var at: Vector2 = c.pos
			b.global_position = WorldState.to_local(Vector3(at.x, line.sample(float(c.s)).y + 3.5, at.y))
			if not b.playing:
				b.play()
		elif b.playing:
			b.stop()
