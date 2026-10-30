class_name RockBuild
## A hill chunk's part of the real rock (RockOutcrops plans it, RockKit is the kit): one hook line
## in CityChunk.begin_build(). FULL and LOD chunks claim the tors standing in them (RockFar draws
## them on the chunk's real terrain from then on); a FULL chunk also gives every tor its collision
## and adds the smaller rock RockFar does not draw - outcrops on the painted rock and boulders
## bedded in the hill roads' cut banks - into its batch, with collision. Every roll a hash of the
## seed and the place; the chunk's own random streams are never touched.

## How many outcrop grid rows a build step, and the most outcrops and bank boulders a chunk.
const ROWS_PER_STEP := 6
const MAX_OUTCROPS := 40
const MAX_BANK := 60
## The most scree a chunk lays round its outcrops and tors.
const MAX_SCREE := 60
## Metres from the camera inside which a chunk's rock batch casts (MultiMeshBatch.set_shadow_reach):
## past it a boulder's shadow is a few texels of the cascade.
const SHADOW_REACH := 70.0
## The LOD of the welded mesh a tor's collision is cut from (0: its ~1,800 triangles, closed).
const COLLISION_LOD := 0


static func attach(ch: CityChunk) -> Array[Callable]:
	var out: Array[Callable] = []
	if not RockOutcrops.enabled or ch.capturing or ch.plan == null or ch.plan.macro == null:
		return out
	if ch.zone != MacroMap.Zone.HILLS:
		return out
	var rect := ch.owned_rect()
	var mine := RockOutcrops.tors_in(ch.plan, rect)
	if not mine.is_empty():
		var ids: Array = []
		for t: Dictionary in mine:
			ids.append(int(t.id))
		out.append(func() -> void: _claim(ch, ids))
	if ch.level != CityChunk.Level.FULL:
		return out
	if not mine.is_empty():
		out.append(func() -> void: _tor_bodies(ch, mine))
	var state := {"row": 0, "outcrops": 0, "scree": 0, "bank": 0, "tors": mine.size()}
	# What was laid, for the checks and the probe.
	ch.set_meta("rocks", state)
	out.append(ch._on_map_ground(func() -> bool: return _outcrops(ch, rect, mine, state)))
	out.append(ch._on_map_ground(func() -> void: state.bank = _bank_boulders(ch, rect)))
	return out


static func _claim(ch: CityChunk, ids: Array) -> void:
	var seed := ch.plan.seed
	RockFar.claim(seed, ids)
	ch.set_meta("rock_claims", ids)
	ch.tree_exiting.connect(func() -> void: RockFar.release(seed, ids), CONNECT_ONE_SHOT)


## Every tor's collision: a trimesh of its welded mesh (RockKit.mid_mesh), in the tor's own transform, on
## one static body (the world layer, mask 0). Built from the CPU's placement, which is the real
## terrain the chunk draws.
static func _tor_bodies(ch: CityChunk, mine: Array) -> void:
	var body := StaticBody3D.new()
	body.name = "RockBody"
	body.collision_layer = 1
	body.collision_mask = 0
	for t: Dictionary in mine:
		var faces := _faces(int(t.kind))
		var xf := Transform3D(t.basis, Vector3(t.pos.x, t.y, t.pos.y))
		var moved := PackedVector3Array()
		moved.resize(faces.size())
		for i in faces.size():
			moved[i] = xf * faces[i]
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(moved)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
	ch.add_child(body)


static var _face_cache: Dictionary = {}


static func _faces(kind: int) -> PackedVector3Array:
	if _face_cache.has(kind):
		return _face_cache[kind]
	var m := RockKit.lod_of(RockKit.mid_mesh(kind), COLLISION_LOD)
	var f := m.get_faces()
	_face_cache[kind] = f
	return f


static func _h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) / 100003.0


static func _grad(ch: CityChunk, p: Vector2) -> Vector2:
	return Vector2(ch._terrain_height(p + Vector2(2.0, 0.0)) - ch._terrain_height(p - Vector2(2.0, 0.0)),
		ch._terrain_height(p + Vector2(0.0, 2.0)) - ch._terrain_height(p - Vector2(0.0, 2.0))) * 0.25


## Rock on the painted rock: a jittered grid, each point asked HillPlanting.ground() off the tile's
## own heights and drainage (the terrain shader's very field), a few rows a step.
static func _outcrops(ch: CityChunk, rect: Rect2, tors: Array, state: Dictionary) -> bool:
	var step := RockOutcrops.OUTCROP_STEP
	var nx := maxi(1, int(rect.size.x / step))
	var nz := maxi(1, int(rect.size.y / step))
	var segs := ch._hill_segments()
	var pads := ch.plan.macro.hill_roads.mansions_in(rect.grow(HillRoads.PAD_RADIUS + 8.0)) if ch.plan.macro.hill_roads else ([] as Array[Dictionary])
	var stop := mini(nz, int(state.row) + ROWS_PER_STEP)
	var seed := ch.plan.seed
	for j in range(int(state.row), stop):
		for i in nx:
			if int(state.outcrops) >= MAX_OUTCROPS:
				break
			var hs := [seed, "outcrop", ch.ix, ch.iz, i, j]
			var p := rect.position + Vector2((i + 0.1 + 0.8 * _h01(hs + ["x"])) * rect.size.x / nx, (j + 0.1 + 0.8 * _h01(hs + ["z"])) * rect.size.y / nz)
			if ch._near_hill_road(p, segs, 4.0) or ch._near_pad(p, pads, 6.0):
				continue
			var h := ch._terrain_height(p)
			if h < 1.5:
				continue
			if ch.plan.macro.reservoir and ch.plan.macro.reservoir.keep_clear(p, h):
				continue
			if Ballpark.covers(p, 8.0) or _near_tor(p, tors, 2.0):
				continue
			if ch.plan.macro.get("coast_highway") != null and ch.plan.macro.coast_highway.covers(p, 6.0):
				continue
			var grad := _grad(ch, p)
			var g := HillPlanting.ground(p, grad, true, ch._terrain_height(p, "drains"))
			var rocky := float(g.rocky)
			if rocky < RockOutcrops.OUTCROP_ROCKY or _h01(hs + ["odds"]) > 0.25 + 0.6 * rocky:
				continue
			var slope := float(g.slope)
			var size := _h01(hs + ["size"])
			var kind: int
			var s: float
			var roll := _h01(hs + ["kind"])
			if roll < 0.35:
				kind = RockKit.TOR_B
				s = lerpf(0.35, 1.1, size * size)
			elif roll < 0.55 and slope > 0.35:
				kind = RockKit.FACE_A
				s = lerpf(0.3, 0.8, size)
			elif roll < 0.8:
				kind = RockKit.BOULDER_B
				s = lerpf(0.8, 2.6, size)
			else:
				kind = RockKit.BOULDER_A
				s = lerpf(1.0, 3.0, size)
			var down := -grad.normalized() if grad.length() > 1e-4 else Vector2(0.0, 1.0)
			var yaw := atan2(down.x, down.y) if kind == RockKit.FACE_A else _h01(hs + ["yaw"]) * TAU
			_place(ch, kind, p, h, yaw, s, slope, hs, true)
			state.outcrops = int(state.outcrops) + 1
			# Scree: a few boulders tumbled down the slope below it.
			var n := int(_h01(hs + ["scree"]) * 4.0) if slope > 0.2 else 0
			for k in n:
				if int(state.scree) >= MAX_SCREE:
					break
				var q: Vector2 = p + down * lerpf(3.0, 9.0 + s * 3.0, _h01(hs + ["sd", k])) + down.orthogonal() * lerpf(-4.0, 4.0, _h01(hs + ["so", k]))
				if not rect.has_point(q) or ch._near_hill_road(q, segs, 2.0) or ch._near_pad(q, pads, 3.0):
					continue
				var qk := RockKit.BOULDER_C if _h01(hs + ["sk", k]) < 0.6 else RockKit.BOULDER_A
				var qs := lerpf(0.6, 1.8, _h01(hs + ["ss", k])) * (1.6 if qk == RockKit.BOULDER_C else 0.6)
				_place(ch, qk, q, ch._terrain_height(q), _h01(hs + ["sy", k]) * TAU, qs, slope, hs + ["s", k], qk != RockKit.BOULDER_C)
				state.scree = int(state.scree) + 1
	state.row = stop
	return int(state.row) >= nz


static func _near_tor(p: Vector2, tors: Array, margin: float) -> bool:
	for t: Dictionary in tors:
		if p.distance_to(t.pos) < float(t.radius) * 0.8 + margin:
			return true
	return false


## One rock into the chunk's batch at ground height `h`, sunk by the slope and a hash, and its
## collision box (`solid`).
static func _place(ch: CityChunk, kind: int, p: Vector2, h: float, yaw: float, s: float, slope: float, hs: Array, solid: bool) -> void:
	var b := RockKit.bounds(kind)
	var tilt := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, (_h01(hs + ["tx"]) - 0.5) * 0.4) * Basis(Vector3.FORWARD, (_h01(hs + ["tz"]) - 0.5) * 0.3)
	var sc := Vector3(s, s * lerpf(0.8, 1.2, _h01(hs + ["sy"])), s)
	var radius := 0.5 * Vector2(b.size.x * sc.x, b.size.z * sc.z).length()
	var tall := b.size.y * sc.y
	var sink := minf(tan(acos(clampf(1.0 - slope, 0.05, 1.0))) * radius * 0.6 + tall * 0.15, tall * 0.55)
	var at := Vector3(p.x, h - sink, p.y)
	# The tor scans are 7-9k triangles a piece: an outcrop is their welded copy (with LODs).
	var m := RockKit.mid_mesh(kind) if RockKit.MID_FILES.has(kind) else RockKit.mesh(kind)
	var key := "rock_k%d" % kind
	ch._batch.add(key, m, Transform3D(tilt.scaled(sc), at), Color.WHITE, Color(1.0, _h01(hs + ["tone"]), sink / 100.0, 1.0))
	ch._batch.set_shadow_reach(key, SHADOW_REACH)
	if solid:
		var size := Vector3(b.size.x * sc.x, tall, b.size.z * sc.z) * 0.8
		ch._add_shape(size, at + Vector3(0.0, size.y * 0.5, 0.0), yaw)


## Boulders bedded in a hill road's cut bank (where the ground beside the road stands BANK_MIN_CUT
## over the bed) and, now and then, one fallen to the shoulder at its toe.
static func _bank_boulders(ch: CityChunk, rect: Rect2) -> int:
	var placed := 0
	var seed := ch.plan.seed
	for seg: Dictionary in ch._hill_segments():
		if not bool(seg.get("draw", true)):
			continue
		var a: Vector2 = seg.a
		var b: Vector2 = seg.b
		var len := a.distance_to(b)
		if len < 1.0:
			continue
		var d := (b - a) / len
		var nrm := Vector2(-d.y, d.x)
		var w := float(seg.width)
		var n := int(len / RockOutcrops.BANK_STEP)
		for k in n:
			if placed >= MAX_BANK:
				return placed
			var f := (float(k) + 0.5) / float(n)
			var c := a.lerp(b, f)
			if not rect.has_point(c):
				continue
			var bed := lerpf(float(seg.ha), float(seg.hb), f)
			for side: float in [-1.0, 1.0]:
				var hs := [seed, "bank", int(c.x * 4.0), int(c.y * 4.0), int(side)]
				if _h01(hs) > 0.42:
					continue
				var off := w * 0.5 + lerpf(2.0, 5.0, _h01(hs + ["o"]))
				var q: Vector2 = c + nrm * side * off
				var gh := ch._terrain_height(q)
				if gh - bed < RockOutcrops.BANK_MIN_CUT:
					continue
				var kind: int = [RockKit.BOULDER_A, RockKit.BOULDER_B, RockKit.BOULDER_C][int(_h01(hs + ["k"]) * 3.0) % 3]
				var s := lerpf(0.5, 1.3, _h01(hs + ["s"])) * (1.8 if kind == RockKit.BOULDER_C else 1.0)
				_place(ch, kind, q, gh, _h01(hs + ["y"]) * TAU, s, 0.5, hs, true)
				placed += 1
				if _h01(hs + ["fall"]) < 0.12:
					# A fallen one on the shoulder, clear of the lane.
					var t: Vector2 = c + nrm * side * (w * 0.5 + 0.9) + d * lerpf(-2.0, 2.0, _h01(hs + ["fa"]))
					_place(ch, RockKit.BOULDER_C, t, bed, _h01(hs + ["fy"]) * TAU, lerpf(0.8, 1.4, _h01(hs + ["fs"])), 0.0, hs + ["f"], true)
					placed += 1
	return placed
