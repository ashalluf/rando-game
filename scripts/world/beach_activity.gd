class_name BeachActivity
extends Node3D
## What moves on a FULL beach chunk (BeachLife): swimmers treading water inside the break, surfers
## sitting on their boards out past it, now and then one paddling for a wave and riding it in;
## cyclists and skaters on the bike path (BeachRider); a volleyball game (four live BeachGoers and
## the ball); the lifeguard; walkers on the sand (BeachWalker). And the scatter: gunfire or a blast
## near this beach wakes the nearest sunbathers (BeachFigure) a few a tick and sends them running,
## riders pedal off faster.
##
## Everything is rolled from hashes of the seed and the stretch (never the block's rng), and none of
## it is ticked when nobody is near: past `active_range` from the player only the riders move (they
## are cheap) and the water people bob.

## Beyond this (m) from the player nothing here is updated but the cheapest.
@export var active_range: float = 260.0
## Most sunbathers one burst of gunfire wakes, in all, and per physics tick.
@export var scatter_max: int = 16
@export var scatter_per_tick: int = 3
## How far from the shot or blast sunbathers hear it (m).
@export var scatter_reach: float = 85.0

## Stills: BEACH_STAGE=z in the environment gathers the chunk's riders on the path round that z
## and its surfers in the water off it, one of them riding a wave in.
static var stage_z: float = float(OS.get_environment("BEACH_STAGE")) if OS.get_environment("BEACH_STAGE") != "" else INF

var chunk: CityChunk
var z0: float = 0.0
var z1: float = 0.0
var plan_ref: CityPlan
var _counts: Dictionary = {}
var _court: Dictionary = {}
var _tower: Dictionary = {}
var _dens: float = 0.0
var _hour: float = 15.0

## Water people: {node, kind ("swim" / "surf"), s (m offshore), z, yaw, phase, state, t, meshes}.
var _water: Array = []
var _riders: Array[BeachRider] = []
var _players: Array = []
var _ball: MeshInstance3D
var _rally: Dictionary = {}
var _last_alarm_ms: int = -1
var _to_wake: int = 0
var _alarm_at := Vector3.INF
var _clock: float = 0.0
var _shape := Vector4(0.9, 24.0, 8.0, 38.0)
var _extra := Vector4(12.0, 0.6, 116.0, 1.3)


func setup(ch: CityChunk, from_z: float, to_z: float, counts: Dictionary, court: Dictionary, tower: Dictionary, dens: float, hour: float) -> void:
	chunk = ch
	plan_ref = ch.plan
	z0 = from_z
	z1 = to_z
	_counts = counts
	_court = court
	_tower = tower
	_dens = dens
	_hour = hour


func _ready() -> void:
	_last_alarm_ms = Pedestrian._last_alarm_ms
	var p := Surf.params(1.0)
	_shape = p[0]
	_extra = p[1]
	if plan_ref == null or plan_ref.macro == null:
		return
	_build_water()
	_build_riders()
	_build_volleyball()
	_build_walkers()


func _h(parts: Array) -> float:
	return BeachLife._h([plan_ref.seed, z0] + parts)


func _hi(parts: Array) -> int:
	return BeachLife._hi([plan_ref.seed, z0] + parts)


## The models this chunk's people use (BeachLife's) and their suits.
func _person(i: int, salt: String) -> Array:
	var model: int = BeachGoer.BEACH_MODELS[_hi([salt, i, "model"]) % BeachGoer.BEACH_MODELS.size()]
	return [model, BeachLife.suit_of(plan_ref, chunk.ix, chunk.iz, model), BeachGoer.seed_for(model, 0)]


# --- The water ----------------------------------------------------------------------------------

func _build_water() -> void:
	var macro: MacroMap = plan_ref.macro
	var brk := Surf.break_distance(_shape)
	for i in int(_counts.get("swimmers", 0)):
		var who := _person(i, "swimmer")
		var mesh := BeachFigure.beach_mesh(who[2], RoughSleeper.Pose.STAND, "", who[1], who[0])
		if mesh == null:
			continue
		var z := lerpf(z0 + 4.0, z1 - 4.0, _h(["swim_z", i]))
		var s := lerpf(5.0, brk * 0.7, _h(["swim_s", i]))
		var mi := _figure(mesh, null)
		_water.append({"node": mi, "kind": "swim", "s": s, "z": z, "yaw": _h(["swim_yaw", i]) * TAU,
			"phase": _h(["swim_ph", i]) * TAU, "sink": 1.28})
	for i in int(_counts.get("surfers", 0)):
		var who := _person(i, "surfer")
		var sit := BeachFigure.beach_mesh(who[2], RoughSleeper.Pose.SIT, "surf_sit", who[1], who[0])
		if sit == null:
			continue
		var paddle := BeachFigure.beach_mesh(who[2], RoughSleeper.Pose.LIE, "paddle", who[1], who[0])
		var ride := BeachFigure.beach_mesh(who[2], RoughSleeper.Pose.STAND, "surf_ride", who[1], who[0])
		var z := lerpf(z0 + 6.0, z1 - 6.0, _h(["surf_z", i]))
		var lineup := brk + lerpf(8.0, 22.0, _h(["surf_s", i]))
		var board := _board_node(_hi(["surf_board", i]) % BeachLife.BOARDS.size())
		var mi := _figure(sit, board)
		var rides := _h(["surf_rides", i]) < 0.45
		_water.append({"node": mi, "board": board, "kind": "surf", "s": lineup, "lineup": lineup, "z": z,
			"z_home": z, "yaw": PI * 0.5, "phase": _h(["surf_ph", i]) * TAU, "state": "sit",
			"t": lerpf(4.0, 30.0, _h(["surf_wait", i])), "rides": rides, "meshes": {"sit": sit, "paddle": paddle, "ride": ride},
			"dir_z": 1.0 if _h(["surf_dir", i]) < 0.5 else -1.0})
	if stage_z >= z0 and stage_z < z1:
		var k := 0
		for w: Dictionary in _water:
			if String(w.kind) != "surf":
				continue
			w.z = stage_z - 6.0 + float(k) * 9.0
			w.z_home = w.z
			if k == 0 and (w.meshes as Dictionary).ride != null:
				w.state = "ride"
				w.s = brk * 0.75
				w.yaw = atan2(-float(w.dir_z) * 0.7, 0.85)
				((w.node as Node3D).get_child(0) as MeshInstance3D).mesh = (w.meshes as Dictionary).ride
			k += 1
	for w: Dictionary in _water:
		_place_water(w)


func _figure(mesh: Mesh, board: Node3D) -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = mesh
	mi.visibility_range_end = 220.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	if board:
		root.add_child(board)
	add_child(root)
	return root


## A surfboard under a surfer: a one-instance MultiMesh so it wears the props' paint like the batch.
func _board_node(paint: int) -> Node3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = BeachLife.prop_mesh("surfboard")
	mm.instance_count = 1
	mm.set_instance_transform(0, Transform3D.IDENTITY)
	var c: Color = BeachLife.BOARDS[paint]
	mm.set_instance_custom_data(0, Color(c.r, c.g, c.b, 0.0))
	var mi := MultiMeshInstance3D.new()
	mi.name = "Board"
	mi.multimesh = mm
	mi.visibility_range_end = 220.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## The sea's surface at s metres offshore at `t`: a swell's bob, and on the face of a breaking
## wave the crest's height (Surf's model, with the wave train's phase).
func _sea_y(s: float, phase: float) -> float:
	var bob := 0.22 * sin(TAU * _clock / _shape.z + phase + s * TAU / _shape.y)
	return 0.15 + bob


func _place_water(w: Dictionary) -> void:
	var node: Node3D = w.node
	var macro: MacroMap = plan_ref.macro
	var z: float = w.z
	var x := macro.coast_x(z) - float(w.s)
	var y := _sea_y(float(w.s), float(w.phase))
	var yaw: float = w.yaw
	if String(w.kind) == "swim":
		y -= float(w.sink)
		yaw += sin(_clock * 0.3 + float(w.phase)) * 0.6
		node.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(x, y, z))
		return
	var state := String(w.get("state", "sit"))
	var board: Node3D = w.board
	match state:
		"sit":
			# Facing out to sea, rocking on the swell.
			node.transform = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, 0.08 * sin(_clock * 0.8 + float(w.phase))), Vector3(x, y - 0.02, z))
			board.transform = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0.0, -0.06, 0.0))
		"out", "in":
			node.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(x, y - 0.03, z))
			board.transform = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0.0, -0.08, -0.1))
		"ride":
			# On the wave's face, up with the crest: the board runs along the rider's x.
			var face := Surf.crest_height(_shape, _extra, float(w.s), 1.0)
			node.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(x, 0.15 + maxf(face, 0.0) * 0.75, z))
			board.transform = Transform3D(Basis(Vector3.UP, 0.0), Vector3(0.0, -0.05, 0.0))


## A surfer's day: sitting in the lineup, paddling for a wave ("in"), riding it, paddling back out.
func _surf_tick(w: Dictionary, dt: float) -> void:
	w.t = float(w.t) - dt
	var brk := Surf.break_distance(_shape)
	var meshes: Dictionary = w.meshes
	var body := (w.node as Node3D).get_child(0) as MeshInstance3D
	match String(w.state):
		"sit":
			if float(w.t) <= 0.0 and bool(w.rides) and meshes.paddle != null and meshes.ride != null:
				w.state = "in"
				w.yaw = -PI * 0.5
				body.mesh = meshes.paddle
		"in":
			w.s = maxf(float(w.s) - 1.3 * dt, brk + 1.0)
			if float(w.s) <= brk + 1.05:
				w.state = "ride"
				# Down the line along the shore and in toward the beach, side-on to the way the board
				# runs (its x, the rider's x).
				w.yaw = atan2(-float(w.dir_z) * 0.7, 0.85)
				body.mesh = meshes.ride
		"ride":
			var speed := _shape.y / _shape.z
			w.s = float(w.s) - speed * 0.85 * dt
			w.z = float(w.z) + float(w.dir_z) * speed * 0.7 * dt
			if float(w.s) < 12.0 or absf(float(w.z) - float(w.z_home)) > 45.0:
				w.state = "out"
				w.yaw = PI * 0.5
				body.mesh = meshes.paddle
		"out":
			w.s = float(w.s) + 1.1 * dt
			w.z = move_toward(float(w.z), float(w.z_home), 0.4 * dt)
			if float(w.s) >= float(w.lineup):
				w.state = "sit"
				w.yaw = PI * 0.5
				w.t = lerpf(20.0, 70.0, fposmod(float(w.phase) * 3.7 + _clock * 0.01, 1.0))
				body.mesh = meshes.sit


# --- The bike path ------------------------------------------------------------------------------

func _build_riders() -> void:
	var n := int(_counts.get("riders", 0))
	var k := int(_counts.get("skaters", 0))
	var lo := z0 - 30.0
	var hi := z1 + 30.0
	for i in n + k:
		var skater := i >= n
		var who := _person(i, "rider")
		var model: int = BeachGoer.RIDER_MODELS[_hi(["rider_model", i]) % BeachGoer.RIDER_MODELS.size()]
		who = [model, BeachLife.suit_of(plan_ref, chunk.ix, chunk.iz, model), BeachGoer.seed_for(model, 0)]
		var frames: Array = []
		var paint := BeachGoer.rider_paint(model, _hi(["bike", i]) % BeachGoer.RIDER_PAINTS)
		if skater:
			var m := BeachFigure.skate_mesh(who[2], who[1], who[0])
			if m:
				frames = [m]
		else:
			frames = BeachFigure.ride_meshes(who[2], who[1], paint, who[0])
		if frames.is_empty():
			continue
		var r := BeachRider.new()
		r.name = "Rider_%d" % i
		r.frames = frames
		r.seed_value = who[2]
		r.model = who[0]
		r.suit = who[1]
		r.paint = paint
		r.skater = skater
		r.chunk = chunk
		r.dir = 1.0 if _h(["ride_dir", i]) < 0.5 else -1.0
		r.speed = lerpf(3.2, 4.2, _h(["ride_v", i])) if skater else lerpf(4.0, 6.5, _h(["ride_v", i]))
		r.z_lo = lo
		r.z_hi = hi
		r.z = lerpf(lo, hi, _h(["ride_z", i]))
		if stage_z >= z0 and stage_z < z1:
			r.z = stage_z + 10.0 + float(i) * 7.0
		chunk.add_child(r)
		_riders.append(r)


# --- Volleyball ---------------------------------------------------------------------------------

func _build_volleyball() -> void:
	if _court.is_empty():
		return
	var c: Vector2 = _court.centre
	var cy := float(_court.yaw)
	var y := BeachLife.sand_y(chunk, c.x, c.y)
	_ball = MeshInstance3D.new()
	_ball.name = "Ball"
	_ball.mesh = BeachLife.prop_mesh("ball")
	_ball.visibility_range_end = 150.0
	add_child(_ball)
	_ball.position = Vector3(c.x, y + 0.11, c.y)
	var h := fposmod(_hour, 24.0)
	if _dens < 0.25 or h < 8.5 or h > 19.0:
		return
	# Two on two: the team on -z of the court and the team on +z, each player's spot and the way
	# they face (the net).
	var spots := [Vector2(-1.9, -4.2), Vector2(1.9, -3.4), Vector2(-1.8, 3.6), Vector2(2.0, 4.3)]
	for i in 4:
		if not chunk._take_crowd_room():
			break
		var local: Vector2 = spots[i]
		var at := c + Vector2(local.x * cos(cy) + local.y * sin(cy), -local.x * sin(cy) + local.y * cos(cy))
		var facing_net := Vector2(-local.x * 0.15, -signf(local.y))
		var world_dir := Vector2(facing_net.x * cos(cy) + facing_net.y * sin(cy), -facing_net.x * sin(cy) + facing_net.y * cos(cy))
		var yaw := atan2(-world_dir.x, -world_dir.y)
		var who := _person(i, "volley")
		var p := BeachGoer.new()
		p.setup_sleeper(BeachLife.sand_ring(chunk, z0, z1), 4.0, BeachGoer.seed_for(who[0], 7 + i), RoughSleeper.Pose.STAND, at, yaw)
		p.suit = who[1]
		p.volley_home = at
		p.volley_face = yaw
		p.position = Vector3(at.x, BeachLife.sand_y(chunk, at.x, at.y), at.y)
		chunk.add_child(p)
		_players.append(p)
	_rally = {"t": 0.0, "dur": 0.0, "wait": 2.0, "hitter": 0, "touch": 0}


func _court_point(local: Vector2) -> Vector2:
	var c: Vector2 = _court.centre
	var cy := float(_court.yaw)
	return c + Vector2(local.x * cos(cy) + local.y * sin(cy), -local.x * sin(cy) + local.y * cos(cy))


func _court_local(p: Vector2) -> Vector2:
	var d := p - (_court.centre as Vector2)
	var cy := float(_court.yaw)
	return Vector2(d.x * cos(cy) - d.y * sin(cy), d.x * sin(cy) + d.y * cos(cy))


## The rally: the ball on parabolas from hand to hand - a pass to the partner, a set back, the
## attack over the net, the other side digs it - until somebody misses and it is served again.
func _volley_tick(dt: float) -> void:
	if _players.size() < 4 or _ball == null:
		return
	for p in _players:
		if not is_instance_valid(p) or (p as BeachGoer)._down or not (p as BeachGoer).is_posed():
			# Somebody ran or fell: the game is off until they are all back.
			if _rally.get("dur", 0.0) > 0.0:
				_rally.dur = 0.0
				_rally.wait = 4.0
				var bp := _ball.position
				_ball.position = Vector3(bp.x, BeachLife.sand_y(chunk, bp.x, bp.z) + 0.11, bp.z)
			if not is_instance_valid(p) or (p as BeachGoer)._down:
				_players.clear()
			return
	if float(_rally.dur) <= 0.0:
		_rally.wait = float(_rally.wait) - dt
		if float(_rally.wait) <= 0.0:
			# A serve from the back line.
			var server := _hi(["serve", int(_clock)]) % 4
			var sp: BeachGoer = _players[server]
			var back := _court_local(Vector2(sp.position.x, sp.position.z))
			sp.volley_goal = _court_point(Vector2(back.x, signf(back.y) * 7.6))
			_launch(server, _receiver_for(server), 1.6, 5.5)
		return
	_rally.t = float(_rally.t) + dt
	var f := clampf(float(_rally.t) / float(_rally.dur), 0.0, 1.0)
	var a: Vector3 = _rally.from
	var b: Vector3 = _rally.to
	var p := a.lerp(b, f)
	p.y += 4.0 * float(_rally.apex) * f * (1.0 - f)
	_ball.position = p
	_ball.rotation.x += dt * 9.0
	if f >= 1.0:
		var hitter: int = _rally.receiver
		if _h(["miss", int(_clock * 10.0)]) < 0.08:
			# Into the sand.
			_rally.dur = 0.0
			_rally.wait = 3.5
			_ball.position = Vector3(p.x, BeachLife.sand_y(chunk, p.x, p.z) + 0.11, p.z)
			for q in _players:
				(q as BeachGoer).volley_goal = (q as BeachGoer).volley_home
			return
		var touch := int(_rally.touch) + 1
		var partner := hitter ^ 1
		if touch >= 3:
			# The attack: over the net to one of the other two.
			_launch(hitter, _receiver_for(hitter), 1.0, 3.2, "reach", true)
			_rally.touch = 0
		else:
			_launch(hitter, partner, 1.25 if touch == 1 else 1.1, 3.0 if touch == 1 else 2.2, "bump" if touch == 1 else "reach", false)
			_rally.touch = touch


func _receiver_for(hitter: int) -> int:
	var other := 2 if hitter < 2 else 0
	return other + (_hi(["recv", int(_clock * 10.0)]) % 2)


## The ball off `hitter`'s hands toward `receiver`, `dur` seconds, `apex` metres over the straight
## line; the receiver runs to where it will come down.
func _launch(hitter: int, receiver: int, dur: float, apex: float, kind: String = "bump", hop: bool = false) -> void:
	var hp: BeachGoer = _players[hitter]
	var rp: BeachGoer = _players[receiver]
	hp.hit(kind, hop)
	var from := hp.position + Vector3(0.0, 2.35 if kind == "reach" else 0.95, 0.0)
	var home := rp.volley_home
	var local := _court_local(home)
	var jitter := Vector2(_h(["jx", int(_clock * 10.0)]) - 0.5, _h(["jz", int(_clock * 10.0)]) - 0.5) * 2.6
	var land := _court_point(Vector2(clampf(local.x + jitter.x, -3.6, 3.6), clampf(local.y + jitter.y, -7.5, 7.5) if signf(local.y + jitter.y) == signf(local.y) else local.y))
	rp.volley_goal = land
	var y := BeachLife.sand_y(chunk, land.x, land.y)
	_rally.from = from
	_rally.to = Vector3(land.x, y + 0.95, land.y)
	_rally.t = 0.0
	_rally.dur = dur
	_rally.apex = apex
	_rally.receiver = receiver
	# The others drift back toward their spots.
	for i in 4:
		if i != receiver:
			var q: BeachGoer = _players[i]
			q.volley_goal = q.volley_home.lerp(q.volley_goal, 0.3)


# --- Walkers ------------------------------------------------------------------------------------

func _build_walkers() -> void:
	for i in int(_counts.get("walkers", 0)):
		if not chunk._take_crowd_room():
			break
		var who := _person(i, "walker")
		var w := BeachWalker.new()
		w.plan_ref = plan_ref
		w.z_lo = z0 + 2.0
		w.z_hi = z1 - 2.0
		w.suit = who[1]
		w.board = (_hi(["walk_board", i]) % BeachLife.BOARDS.size()) if _h(["walk_has_board", i]) < 0.45 else -1
		w.setup(BeachLife.sand_ring(chunk, z0, z1), 4.0, BeachGoer.seed_for(who[0], 20 + i))
		var start := w._random_ring_point(4.0)
		w.position = Vector3(start.x, BeachLife.sand_y(chunk, start.x, start.y) + 0.1, start.y)
		chunk.add_child(w)


# --- Every tick ---------------------------------------------------------------------------------

func _physics_process(dt: float) -> void:
	_clock += dt
	var player := Pedestrian._player
	var near := true
	if player and is_instance_valid(player) and chunk and chunk.is_inside_tree():
		var zc := (z0 + z1) * 0.5
		var pc := chunk.to_local(player.global_position)
		near = Vector2(pc.x - plan_ref.macro.coast_x(zc), pc.z - zc).length() < active_range
	# A staged still (BEACH_STAGE) holds the riders and the surfers where they were put.
	var staged := stage_z >= z0 and stage_z < z1
	for r in _riders:
		if is_instance_valid(r):
			r.advance(0.0 if staged else dt)
	if near:
		for w: Dictionary in _water:
			if String(w.kind) == "surf" and not staged:
				_surf_tick(w, dt)
			_place_water(w)
		_volley_tick(dt)
	_scatter()


## Gunfire or a blast near this beach: the nearest sunbathers get up and run (a few a tick), and the
## riders pedal off.
func _scatter() -> void:
	if Pedestrian._last_alarm_ms != _last_alarm_ms:
		_last_alarm_ms = Pedestrian._last_alarm_ms
		var at: Vector3 = Pedestrian._last_alarm_at
		# The alarm's point is a scene position; the figures are the chunk's children.
		var local := chunk.to_local(at) if chunk and chunk.is_inside_tree() else at
		if absf(local.z - (z0 + z1) * 0.5) < (z1 - z0) * 0.5 + scatter_reach:
			_alarm_at = at
			_to_wake = scatter_max
			for r in _riders:
				if is_instance_valid(r) and r.global_position.distance_to(at) < scatter_reach:
					r.scare()
	if _to_wake <= 0 or chunk == null:
		return
	var local_at := chunk.to_local(_alarm_at)
	var near: Array = []
	for c in chunk.get_children():
		var f := c as BeachFigure
		if f == null or f._awake or f.collision_layer == 0:
			continue
		var d := Vector2(f.position.x - local_at.x, f.position.z - local_at.z).length()
		if d < scatter_reach:
			near.append([d, f])
	if near.is_empty():
		_to_wake = 0
		return
	near.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for i in mini(scatter_per_tick, near.size()):
		var p := (near[i][1] as BeachFigure).wake()
		_to_wake -= 1
		if p:
			p._scare(_alarm_at)
