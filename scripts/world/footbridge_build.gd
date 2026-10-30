class_name FootbridgeBuild
extends RefCounted
## Puts the footbridges (Footbridges plans them, FootbridgeKit builds them) into the city chunks.
## One hook in CityChunk.begin_build() (and one in its capture build):
## * FULL: each bridge whose span centre is in the chunk's owned rect is a build step of its own -
##   a pivot node at the span's centre with ONE mesh (FootbridgeKit, Detail.FULL), a StaticBody3D
##   of boxes (walkway, cage sides and crown, landings, stair ramps, tower walls) you can walk, a
##   lamp_light OmniLight3D under the crown (desktop), light pools on the walkway and at the stair
##   feet. Then, after every deferred step (CityChunk._run_last), the planting and street furniture
##   instances of THIS chunk that stand where any bridge's stairs, landings, towers or span are
##   (Footbridges' `clear` rects) are collapsed: their rolls were all made, nothing else moves.
## * LOD: the same bridges at Detail.LOD, no collision, no lights.
## * The far city (capture): plain far boxes (`lod_box`, the old path with no windows) for the span
##   and the stairs / towers.

## Batches never collapsed under a bridge: the far boxes, flat paint (tilt keys) and light pools.
const KEEP_KEYS := ["lod_box", "lamp_pool"]
## How far a bridge's mesh draws (metres; a LOD chunk's copy takes over within its own range).
const DRAW_DISTANCE := 0.0


static func attach(ch: CityChunk) -> Array[Callable]:
	var steps: Array[Callable] = []
	if not Footbridges.enabled or ch.plan == null or ch.plan.macro == null:
		return steps
	var mine := Footbridges.owned_by(ch.plan, ch.ix, ch.iz)
	if ch.capturing:
		if not mine.is_empty():
			steps.append(capture.bind(ch, mine))
		return steps
	for b in mine:
		steps.append(build_one.bind(ch, b))
	if ch.level == CityChunk.Level.FULL:
		var near := Footbridges.near(ch.plan, ch.owned_rect())
		if not near.is_empty():
			steps.append(func() -> void: ch._run_last(clear_ground.bind(ch, near)))
	return steps


static func build_one(ch: CityChunk, b: Dictionary) -> void:
	var full := ch.level == CityChunk.Level.FULL
	var c: Vector2 = b.c
	var pivot := Node3D.new()
	pivot.name = "Footbridge_" + String(b.id)
	pivot.position = Vector3(c.x, 0.0, c.y)
	ch.add_child(pivot)
	var boxes: Array = []
	var geo := FootbridgeKit.build(b, Vector3(c.x, 0.0, c.y), FootbridgeKit.Detail.FULL if full else FootbridgeKit.Detail.LOD, boxes)
	var mi := geo.commit(pivot, "Mesh", true, DRAW_DISTANCE)
	if mi != null:
		mi.add_to_group("footbridge")
	if not full:
		return
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = 1
	body.collision_mask = 0
	pivot.add_child(body)
	for bx: Array in boxes:
		var size: Vector3 = bx[1]
		if size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0:
			continue
		LandmarkGeo.shape_box(body, bx[0], size, (bx[2] as Basis).orthonormalized())
	# Night: a light under the crown and pools on the walkway and at each stair's foot.
	var y: float = b.y
	var pool_at: Array[Vector3] = []
	# Under each lamp of the crown (FootbridgeKit._lamps()' spacing).
	var span := float(b.half) * 2.0
	var nl := maxi(int(span / 9.0), 2)
	for i in nl:
		var p2: Vector2 = c + (b.dir as Vector2) * (-float(b.half) + span * (float(i) + 0.5) / float(nl))
		pool_at.append(Vector3(p2.x, y + 0.03, p2.y))
	for e: Dictionary in b.ends:
		var foot: Vector2 = (e.stair as Dictionary).foot
		pool_at.append(Vector3(foot.x, float(e.ground) + 0.09, foot.y))
	for p: Vector3 in pool_at:
		var size := 6.0
		var xf := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(size, 1.0, size)), p - Vector3(0.0, ch._gy(p.x, p.z), 0.0))
		ch._batch.add("lamp_pool", PropFactory.light_pool(), xf, Color(1.0, 0.9, 0.75, 0.5))
	if not OS.has_feature("web"):
		var light := OmniLight3D.new()
		light.position = Vector3(0.0, y + FootbridgeKit.CAGE_CROWN - 0.3, 0.0)
		light.omni_range = 9.0
		light.omni_attenuation = 1.3
		light.light_color = Color(1.0, 0.88, 0.72)
		light.light_energy = 0.0
		light.shadow_enabled = false
		light.distance_fade_enabled = true
		light.distance_fade_begin = 60.0
		light.distance_fade_length = 20.0
		light.add_to_group("lamp_light")
		pivot.add_child(light)


## Collapses this chunk's batch instances (trees, shrubs, palms, street furniture) standing in any
## nearby bridge's `clear` rects. Runs after every deferred step; every roll was already made.
static func clear_ground(ch: CityChunk, near: Array[Dictionary]) -> void:
	var rects: Array[Rect2] = []
	for b in near:
		for r: Rect2 in b.clear:
			rects.append(r)
	var batches: Dictionary = ch._batch._batches
	var zero := Basis().scaled(Vector3(0.0001, 0.0001, 0.0001))
	var hidden := 0
	for key: String in batches:
		if KEEP_KEYS.has(key) or ch._batch.tilt_keys.has(key):
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
	ch.set_meta("footbridge_cleared", hidden)


## The far city's version: a box for the span (deck and parapets) and one for each stair or tower.
static func capture(ch: CityChunk, mine: Array[Dictionary]) -> void:
	for b in mine:
		var c: Vector2 = b.c
		var dir: Vector2 = b.dir
		var along: Vector2 = b.along
		var y: float = b.y
		var depth: float = Footbridges.DEPTH[int(b.form)]
		var basis := Basis(Vector3(along.x, 0.0, along.y), Vector3.UP, Vector3(dir.x, 0.0, dir.y))
		var paint: Color = b.paint
		var span := float(b.half) * 2.0
		var h := depth + 1.2
		var at := Vector3(c.x, y - depth + h * 0.5, c.y)
		_far_box(ch, at, Vector3(Footbridges.BRIDGE_W, h, span), basis, paint)
		for e: Dictionary in b.ends:
			var g: float = e.ground
			var tw: Dictionary = e.tower
			if not tw.is_empty():
				var tc: Vector2 = tw.c
				var out: Vector2 = tw.out
				var al: Vector2 = tw.along
				var tb := Basis(Vector3(out.x, 0.0, out.y), Vector3.UP, Vector3(al.x, 0.0, al.y))
				var top := y + FootbridgeKit.CAGE_SIDE
				_far_box(ch, Vector3(tc.x, (g + top) * 0.5, tc.y), Vector3(float(tw.d) + 0.4, top - g, float(tw.len) + 0.4), tb, paint * 0.9)
			else:
				var foot: Vector2 = (e.stair as Dictionary).foot
				var lc: Vector2 = (e.landing as Dictionary).c
				var mid := (foot + lc) * 0.5
				var length := foot.distance_to(lc) + Footbridges.LANDING_W * 0.5
				var hb := Basis(Vector3(dir.x, 0.0, dir.y), Vector3.UP, Vector3(along.x, 0.0, along.y))
				_far_box(ch, Vector3(mid.x, (g + y) * 0.5, mid.y), Vector3(Footbridges.STAIR_W + 0.4, y - g, length), hb, Color(0.82, 0.81, 0.78))


static func _far_box(ch: CityChunk, at: Vector3, size: Vector3, basis: Basis, color: Color) -> void:
	var xf := Transform3D(basis.scaled_local(size), at - Vector3(0.0, ch._gy(at.x, at.z), 0.0))
	ch._batch.add("lod_box", PropFactory.unit_box(), xf, color, Color(0.0, 0.0, 0.0, 1.0))
