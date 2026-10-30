class_name StuntBuild
extends RefCounted
## Puts the stunt features (StuntRamps plans them, StuntKit builds them) into the city chunks.
## One hook in CityChunk.begin_build() (attach()) and one after VacantLots.build_lot() in
## CityChunk._build_lot() (vacant_lot()):
## * FULL: each site whose foot is in the chunk's owned rect is a build step of its own - a pivot at
##   the foot (true world: a chunk's children live in true world space) with ONE mesh and a
##   StaticBody3D (world layer, mask 0) of its collision triangles, registered with StuntDirector
##   (its lips and, for a loop, its track) while it is in the tree. The freeway pieces' right of
##   way is then cleared of this chunk's planting under them (after every deferred step, the
##   rolls all made: Footbridges' way). A vacant lot's weeds in its line are collapsed at once.
## * LOD: the freeway pair and the loop only (they stand 6-14 m tall over the right of way), with
##   no collision, at half the draw distance.
## Nothing is ever built in the far city: the pieces are small next to a 7 km view.

const DRAW_DISTANCE := 420.0
const LOD_DRAW := 900.0
## Batches never collapsed under a piece (Footbridges' rule).
const KEEP_KEYS := ["lod_box", "lamp_pool"]


static func attach(ch: CityChunk) -> Array[Callable]:
	var steps: Array[Callable] = []
	if not StuntRamps.enabled or ch.plan == null or ch.plan.macro == null or ch.capturing:
		return steps
	var mine := StuntRamps.owned_by(ch.plan, ch.ix, ch.iz)
	var full := ch.level == CityChunk.Level.FULL
	for s: Dictionary in mine:
		var k := int(s.kind)
		if not full and k != StuntRamps.Kind.LAUNCH and k != StuntRamps.Kind.LAND and k != StuntRamps.Kind.LOOP:
			continue
		steps.append(func() -> void: build_site(ch, s))
	if full:
		# Any freeway piece whose cleared ground reaches this chunk (its foot may be next door).
		var r := ch.owned_rect()
		var rects: Array[Rect2] = []
		for s: Dictionary in StuntRamps.freeway_sites(ch.plan):
			if s.has("clear") and (s.clear as Rect2).intersects(r):
				rects.append(s.clear)
		if not rects.is_empty():
			steps.append(func() -> void: ch._run_last(clear_ground.bind(ch, rects)))
	return steps


## The mesh and collision of a site, in its own frame: [mesh, faces, triangles].
static func piece(s: Dictionary, ground: Callable = Callable()) -> Array:
	match int(s.kind):
		StuntRamps.Kind.KICKER, StuntRamps.Kind.PIER:
			return StuntKit.kicker(float(s.len), float(s.h), float(s.w), s.paint)
		StuntRamps.Kind.LAUNCH:
			return StuntKit.launch(float(s.len), float(s.h), float(s.w), s.paint)
		StuntRamps.Kind.LAND:
			return StuntKit.landing(float(s.len), float(s.h), float(s.w), s.paint)
		StuntRamps.Kind.QPIPE:
			return StuntKit.qpipe(float(s.len), float(s.r), float(s.angle), float(s.deck), float(s.bank_slope))
		StuntRamps.Kind.LOOP:
			return StuntKit.loop(float(s.r), float(s.w), float(s.shift), float(s.run), s.paint)
		StuntRamps.Kind.DIRT:
			var g := ground if ground.is_valid() else func(_x: float, _z: float) -> float: return 0.0
			return StuntKit.dirt(s.jumps, float(s.w), g, Color(0.95, 0.88, 0.78))
	return []


static func xform(s: Dictionary) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, float(s.yaw)), s.p)


static func build_site(ch: CityChunk, s: Dictionary, ground: Callable = Callable()) -> Node3D:
	var full := ch.level == CityChunk.Level.FULL
	var got := piece(s, ground)
	if got.is_empty() or got[0] == null:
		return null
	var pivot := Node3D.new()
	pivot.name = "Stunt_" + String(s.id)
	pivot.transform = xform(s)
	pivot.add_to_group("stunt_ramp")
	pivot.set_meta("stunt", s)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = got[0]
	var reach := DRAW_DISTANCE if full else LOD_DRAW
	if int(s.kind) == StuntRamps.Kind.LOOP or int(s.kind) == StuntRamps.Kind.LAUNCH or int(s.kind) == StuntRamps.Kind.LAND:
		reach *= 1.6
	mi.visibility_range_end = reach
	mi.visibility_range_end_margin = reach * 0.1
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	pivot.add_child(mi)
	if full and not (got[1] as PackedVector3Array).is_empty():
		var body := StaticBody3D.new()
		body.name = "Body"
		body.collision_layer = 1
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var tri := ConcavePolygonShape3D.new()
		tri.backface_collision = true
		tri.set_faces(got[1])
		cs.shape = tri
		body.add_child(cs)
		pivot.add_child(body)
	ch.add_child(pivot)
	if full:
		StuntDirector.register(pivot, s)
		StuntDirector.ensure(ch)
	ch.set_meta("stunt_sites", int(ch.get_meta("stunt_sites", 0)) + 1)
	return pivot


## Collapses this chunk's batch instances (trees, shrubs, hedges, poles) standing in `rects`. Runs
## after every deferred step; every roll was already made.
static func clear_ground(ch: CityChunk, rects: Array[Rect2]) -> void:
	var hidden := collapse(ch, rects, [])
	ch.set_meta("stunt_cleared", int(ch.get_meta("stunt_cleared", 0)) + hidden)


static func collapse(ch: CityChunk, rects: Array[Rect2], only_prefix: Array) -> int:
	var batches: Dictionary = ch._batch._batches
	var zero := Basis().scaled(Vector3(0.0001, 0.0001, 0.0001))
	var hidden := 0
	for key: String in batches:
		if KEEP_KEYS.has(key) or ch._batch.tilt_keys.has(key):
			continue
		if not only_prefix.is_empty():
			var ok := false
			for pre: String in only_prefix:
				if key.begins_with(pre):
					ok = true
			if not ok:
				continue
		var xforms: Array = batches[key].xforms
		for i in xforms.size():
			var xf: Transform3D = xforms[i]
			var p := Vector2(xf.origin.x, xf.origin.z)
			for r in rects:
				if r.has_point(p):
					xforms[i] = Transform3D(zero, xf.origin)
					hidden += 1
					break
	return hidden


## After VacantLots built `lot` (FULL): its line of dirt jumps, if it has one, with the lot's weeds
## in the line collapsed (they were all rolled).
static func vacant_lot(ch: CityChunk, lot: Dictionary) -> void:
	if not StuntRamps.enabled or ch.level != CityChunk.Level.FULL or ch.capturing:
		return
	var kind := VacantLots.kind_of(ch.plan, ch.ix, ch.iz, lot)
	if kind != VacantLots.VACANT:
		return
	var vp := VacantLots.plan_lot(ch.plan, ch.ix, ch.iz, lot, kind)
	var s := StuntRamps.vacant_site(ch.plan, lot, vp)
	if s.is_empty():
		return
	var xf := xform(s)
	var base: float = (s.p as Vector3).y
	# The lot's ground under the line, in the line's frame (VacantLots lays it at SIDEWALK_TOP + LIFT
	# over the relief).
	var ground := func(x: float, z: float) -> float:
		var w := xf * Vector3(x, 0.0, z)
		return CityChunk.SIDEWALK_TOP + VacantLots.LIFT + ch._gy(w.x, w.z) - base
	build_site(ch, s, ground)
	var f: Dictionary = vp.frame
	var u := (Vector2((s.p as Vector3).x, (s.p as Vector3).z) - (f.o as Vector2)).dot(f.a)
	var lane := Industrial.fr(f, u - float(s.w) * 0.5 - 2.6, 3.0, u + float(s.w) * 0.5 + 2.6, float(f.depth) - 0.5)
	collapse(ch, [lane], ["vac_"])
