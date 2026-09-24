class_name Encampment
extends RefCounted
## Sidewalk encampments downtown (owner, 2026-09-24): rows of dome tents in faded colours against
## the building line, tarps strung over some of them, shopping carts, bags, mattresses, flattened
## boxes, a camp chair, bikes and bike parts - and the people who live there (RoughSleeper), not
## walking but sitting against the wall, lying on their bedding, or standing folded forward in a
## deep slump. Depicted the way a realistic Los Angeles game would: as the street, not as a joke.
##
## Where: DOWNTOWN blocks of ordinary buildings only - never a plaza, a park, a mall or a landmark's
## ground - and some streets far more than others, the way they cluster on real blocks. A block
## face either has a camp or does not (a hash of its seed, face and street), and a camp is a run
## of pieces laid along the wall, with gaps left for doorways and kept clear of every lamp,
## hydrant, meter, shelter and trash can already on that pavement, and of the corners.
##
## Seeding: nothing here draws on the block's RandomNumberGenerator - the parked cars and the crowd
## roll after this and the far skyline replays the block's sequence (CLAUDE.md: the order is
## load-bearing). Every roll comes from a generator hashed from the seed, the block and the face,
## like StreetDetail's. Same seed, same camps.
##
## Cost: FULL chunks only. Pieces go through the chunk's MultiMesh batch (one draw call per piece
## kind per chunk, shadows from PropFactory.shadow_proxy() twins, faded out past DRAW_DISTANCE);
## each knockable piece has a small static body (EncampmentItem); at most MAX_ITEMS pieces and
## MAX_SLEEPERS people a chunk, and the people come out of the same crowd cap as the walkers.
## Static builder, so the knobs are consts here (like StreetDetail).

# --- Tunables --------------------------------------------------------------------------------

## Share of downtown streets that carry the big camps (hashed per road), and the odds that a block
## face on one of them, or on any other downtown street, has a camp at all.
const CAMP_STREET_SHARE := 0.34
const FACE_ODDS_CAMP_STREET := 0.72
const FACE_ODDS := 0.12
## Most camps on one block, pieces in one chunk, and people at them in one chunk.
const MAX_CAMPS := 3
const MAX_ITEMS := 34
const MAX_SLEEPERS := 6
## Metres of a block face kept clear at each corner (the crossing and its kerb ramps).
const CORNER_CLEAR := 9.0
## How long a camp runs along the face (metres, min and max).
const RUN_LENGTH := Vector2(9.0, 30.0)
## Clear pavement kept round anything already on the pavement (lamps, hydrants, meters, signs,
## shelters, trash cans), metres.
const PROP_CLEAR := 1.3
## Metres of pavement kept open at the kerb side for people walking by. Walkers on a block with
## camps keep to this strip too (CityChunk._pedestrian_steps narrows their ring).
const PATH_KEEP := 2.3
## Gap between a piece's back and the wall, and where the wall is taken to be when no building
## stands behind (an empty lot, a yard): this many metres in from the kerb.
const WALL_BACK := 0.25
const NO_WALL_DEPTH := 5.4
## A doorway gap every so often along a run (metres of wall between them, and the gap's width).
const DOOR_EVERY := Vector2(7.0, 12.0)
const DOOR_GAP := Vector2(1.6, 2.6)
## Draw distances (m): tents and tarps, and the small things.
const DRAW_DISTANCE := 190.0
const SMALL_DRAW_DISTANCE := 120.0

## Faded tent colours (a tent sold bright and left out for a year), tarp colours, trash-bag
## colours, bike paints, blanket and duffel colours. The shader bleaches them further per instance.
const TENT_COLORS := [
	Color(0.22, 0.38, 0.55), Color(0.30, 0.42, 0.28), Color(0.52, 0.50, 0.46), Color(0.62, 0.36, 0.18),
	Color(0.55, 0.20, 0.17), Color(0.24, 0.26, 0.30), Color(0.40, 0.46, 0.52), Color(0.60, 0.55, 0.32),
	Color(0.18, 0.30, 0.42), Color(0.45, 0.30, 0.40),
]
const TARP_COLORS := [
	Color(0.14, 0.30, 0.62), Color(0.14, 0.30, 0.62), Color(0.18, 0.36, 0.58), Color(0.62, 0.62, 0.60),
	Color(0.36, 0.30, 0.18), Color(0.22, 0.34, 0.20),
]
const BAG_COLORS := [
	Color(0.05, 0.05, 0.055), Color(0.05, 0.05, 0.055), Color(0.06, 0.07, 0.06), Color(0.82, 0.82, 0.80),
	Color(0.10, 0.20, 0.42),
]
const CLOTH_COLORS := [
	Color(0.30, 0.22, 0.35), Color(0.18, 0.24, 0.38), Color(0.45, 0.36, 0.24), Color(0.24, 0.30, 0.22),
	Color(0.52, 0.16, 0.14), Color(0.40, 0.40, 0.42), Color(0.60, 0.52, 0.40),
]
const BIKE_COLORS := [
	Color(0.62, 0.10, 0.08), Color(0.08, 0.22, 0.48), Color(0.10, 0.10, 0.11), Color(0.80, 0.78, 0.74),
	Color(0.18, 0.40, 0.22), Color(0.70, 0.45, 0.08),
]

## Each kit piece: its footprint along the wall (w) and out from it (d), its collision box and
## the box's centre height, its mass, whether it gets a body at all, its palette and draw distance.
const PIECES := {
	"tent_dome": {"w": 2.2, "d": 1.6, "box": Vector3(2.0, 1.0, 1.45), "y": 0.5, "mass": 9.0, "body": true, "colors": "tent", "far": true},
	"tent_pop": {"w": 2.0, "d": 1.35, "box": Vector3(1.8, 0.85, 1.2), "y": 0.42, "mass": 6.0, "body": true, "colors": "tent", "far": true},
	"tarp_canopy": {"w": 3.5, "d": 2.6, "box": Vector3(3.2, 0.15, 2.4), "y": 1.62, "mass": 5.0, "body": true, "colors": "tarp", "far": true},
	"tarp_mound": {"w": 2.4, "d": 1.9, "box": Vector3(2.0, 0.95, 1.6), "y": 0.48, "mass": 22.0, "body": true, "colors": "tarp", "far": true},
	"cart": {"w": 0.7, "d": 1.05, "box": Vector3(0.6, 1.0, 1.0), "y": 0.55, "mass": 16.0, "body": true, "colors": "none", "far": false},
	"bags_pile": {"w": 1.1, "d": 0.95, "box": Vector3(0.9, 0.6, 0.85), "y": 0.3, "mass": 12.0, "body": true, "colors": "bag", "far": false},
	"bag_trash": {"w": 0.6, "d": 0.55, "box": Vector3(0.5, 0.55, 0.5), "y": 0.28, "mass": 5.0, "body": true, "colors": "bag", "far": false},
	"bag_duffel": {"w": 0.7, "d": 0.4, "box": Vector3(0.62, 0.3, 0.34), "y": 0.15, "mass": 6.0, "body": true, "colors": "cloth", "far": false},
	"mattress": {"w": 2.0, "d": 1.0, "box": Vector3(1.9, 0.22, 0.96), "y": 0.11, "mass": 14.0, "body": true, "colors": "mattress", "far": false},
	"bedding": {"w": 2.0, "d": 0.9, "box": Vector3.ZERO, "y": 0.0, "mass": 0.0, "body": false, "colors": "cloth", "far": false},
	"cardboard": {"w": 1.5, "d": 1.0, "box": Vector3.ZERO, "y": 0.0, "mass": 0.0, "body": false, "colors": "none", "far": false},
	"box": {"w": 0.6, "d": 0.5, "box": Vector3(0.52, 0.36, 0.4), "y": 0.18, "mass": 2.0, "body": true, "colors": "none", "far": false},
	"chair": {"w": 0.7, "d": 0.7, "box": Vector3(0.56, 0.9, 0.56), "y": 0.45, "mass": 3.0, "body": true, "colors": "tent", "far": false},
	"bicycle": {"w": 1.9, "d": 0.6, "box": Vector3(0.5, 1.0, 1.7), "y": 0.5, "mass": 13.0, "body": true, "colors": "bike", "far": false},
	"bike_wheel": {"w": 0.8, "d": 0.7, "box": Vector3.ZERO, "y": 0.0, "mass": 0.0, "body": false, "colors": "none", "far": false},
	"bike_frame": {"w": 1.3, "d": 0.8, "box": Vector3(1.1, 0.3, 0.6), "y": 0.15, "mass": 7.0, "body": true, "colors": "bike", "far": false},
}
## What a camp is made of, as weighted "units" laid one after another along the wall. A unit is a
## main piece and the clutter that sits with it.
const UNITS := [
	["tent", 30], ["tent_tarp", 12], ["mound", 8], ["cart", 10], ["bed", 11], ["sit", 9],
	["bags", 8], ["bike", 6], ["parts", 3], ["slump", 7],
]


## True when this block will have encampments (decided from hashes alone, before anything is
## built, so the block's walkers can be given the narrower ring).
static func block_has_camps(plan: CityPlan, ix: int, iz: int) -> bool:
	return not _faces(plan, ix, iz).is_empty()


## The block faces (0..3, CityChunk._build_sidewalk_props's edge order) that carry a camp.
static func _faces(plan: CityPlan, ix: int, iz: int) -> Array:
	var out: Array = []
	if plan.macro == null:
		return out
	var block := plan.block(ix, iz)
	if int(block.district) != CityPlan.District.DOWNTOWN or int(block.kind) != CityPlan.BlockKind.BUILDINGS:
		return out
	if block.has("site"):
		return out
	var rect: Rect2 = block.rect
	if plan.zone_at(rect.get_center()) != MacroMap.Zone.CITY:
		return out
	# Edge order: 0 the -Z side (faces road Z iz), 1 the +Z side (Z iz+1), 2 the -X side (X ix),
	# 3 the +X side (X ix+1).
	var roads := [[CityPlan.AXIS_Z, iz], [CityPlan.AXIS_Z, iz + 1], [CityPlan.AXIS_X, ix], [CityPlan.AXIS_X, ix + 1]]
	for e in 4:
		var axis: int = roads[e][0]
		var index: int = roads[e][1]
		var camp_street := _hash01([plan.seed, "camp_street", axis, index]) < CAMP_STREET_SHARE
		var odds := FACE_ODDS_CAMP_STREET if camp_street else FACE_ODDS
		if _hash01([plan.seed, "camp_face", ix, iz, e]) < odds:
			out.append(e)
		if out.size() >= MAX_CAMPS:
			break
	return out


## The camps of one block, as one build step (FULL chunks). `edges` are [a, b, inward] like the
## chunk's sidewalk props. Runs after the furniture so it can keep clear of it, and fills
## `out_sleepers` with the people to seat at the camps, which the chunk spawns a build step each
## (spawn_sleeper) BEFORE the block's walkers: the crowd cap is spent on the people who live on
## the pavement first - behind the walkers, downtown's crowd had used it all up.
static func build_block(chunk: CityChunk, rect: Rect2, edges: Array, out_sleepers: Array) -> void:
	var plan: CityPlan = chunk.plan
	var faces := _faces(plan, chunk.ix, chunk.iz)
	if faces.is_empty():
		return
	var occupied := _occupied(chunk)
	var walls := StreetDetail._footprints(chunk)
	var items := [0]
	var sleepers: Array = []
	for e: int in faces:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([plan.seed, "camp", chunk.ix, chunk.iz, e])
		_build_run(chunk, walls, edges[e], e, rng, occupied, items, sleepers)
		if items[0] >= MAX_ITEMS:
			break
	for key: String in PIECES:
		var k := "camp_" + key
		chunk._batch.set_draw_distance(k, DRAW_DISTANCE if PIECES[key].far else SMALL_DRAW_DISTANCE)
	out_sleepers.append_array(sleepers.slice(0, MAX_SLEEPERS))


## The chunk's build step for the `index`th person build_block queued (nothing when there is none).
static func spawn_sleeper(chunk: CityChunk, rect: Rect2, sleepers: Array, index: int) -> void:
	if index < sleepers.size():
		_spawn_sleeper(chunk, rect, sleepers[index])


## Everything already standing on this chunk's pavements that a camp must keep clear of.
static func _occupied(chunk: CityChunk) -> Array:
	var out: Array = []
	for r: Dictionary in chunk.prop_records:
		var p: Vector3 = r.position
		var reach := 2.4 if String(r.kind) == "bus_stop" else PROP_CLEAR
		out.append([Vector2(p.x, p.z), reach])
	for c in chunk.get_children():
		if c is TrashCan or c is PhysicsProp:
			out.append([Vector2((c as Node3D).position.x, (c as Node3D).position.z), PROP_CLEAR])
	return out


## How far in from the kerb the wall is at `kerb_point` (walking inward), from the ground-storey
## walls the chunk's buildings actually stand on (StreetDetail._footprints()).
static func _wall_depth(walls: Array[Rect2], kerb_point: Vector2, inward: Vector2) -> float:
	var best := NO_WALL_DEPTH
	for r: Rect2 in walls:
		for k in 16:
			var d := 2.5 + k * 0.25
			if r.has_point(kerb_point + inward * d):
				best = minf(best, d)
				break
	return best


static func _clear_of(occupied: Array, p: Vector2, half: float) -> bool:
	for o: Array in occupied:
		if (o[0] as Vector2).distance_to(p) < float(o[1]) + half:
			return false
	return true


## One camp along one block face.
static func _build_run(chunk: CityChunk, walls: Array[Rect2], edge: Array, face: int, rng: RandomNumberGenerator, occupied: Array, items: Array, sleepers: Array) -> void:
	var a: Vector2 = edge[0]
	var b: Vector2 = edge[1]
	var inward: Vector2 = edge[2]
	var length := a.distance_to(b)
	var usable := length - CORNER_CLEAR * 2.0
	if usable < RUN_LENGTH.x:
		return
	var dir := (b - a) / length
	var run := minf(rng.randf_range(RUN_LENGTH.x, RUN_LENGTH.y), usable)
	var t := CORNER_CLEAR + rng.randf_range(0.0, usable - run)
	var t_end := t + run
	var next_door := t + rng.randf_range(DOOR_EVERY.x, DOOR_EVERY.y)
	# The pieces face the street: local +Z toward the kerb.
	var yaw := atan2(-inward.x, -inward.y)
	var basis := Basis(Vector3.UP, yaw)
	var camp_id := [0]
	while t < t_end and items[0] < MAX_ITEMS:
		if t >= next_door:
			t += rng.randf_range(DOOR_GAP.x, DOOR_GAP.y)
			next_door = t + rng.randf_range(DOOR_EVERY.x, DOOR_EVERY.y)
			continue
		var unit := _pick_unit(rng)
		var width := _unit_width(unit)
		if t + width > t_end:
			break
		var mid := a + dir * (t + width * 0.5)
		var depth := _wall_depth(walls, mid, inward)
		if not _clear_of(occupied, mid, width * 0.5) or depth - WALL_BACK - PATH_KEEP < 0.8:
			t += width
			continue
		_lay_unit(chunk, unit, a, dir, inward, t, width, depth, basis, yaw, rng, items, sleepers, face, camp_id)
		t += width + rng.randf_range(0.15, 0.6)


static func _pick_unit(rng: RandomNumberGenerator) -> String:
	var total := 0
	for u: Array in UNITS:
		total += int(u[1])
	var roll := rng.randi() % total
	for u: Array in UNITS:
		roll -= int(u[1])
		if roll < 0:
			return u[0]
	return "tent"


static func _unit_width(unit: String) -> float:
	match unit:
		"tent_tarp":
			return 3.6
		"mound":
			return 2.5
		"cart":
			return 1.9
		"bed":
			return 2.3
		"sit":
			return 1.7
		"bags":
			return 1.4
		"bike":
			return 2.1
		"parts":
			return 1.6
		"slump":
			return 1.2
	return 2.3


## Lays one unit: `t` is where along the face it starts, `depth` how far in the wall is.
static func _lay_unit(chunk: CityChunk, unit: String, a: Vector2, dir: Vector2, inward: Vector2, t: float, width: float, depth: float, basis: Basis, yaw: float, rng: RandomNumberGenerator, items: Array, sleepers: Array, face: int, camp_id: Array) -> void:
	var back := depth - WALL_BACK
	var at := func(along: float, from_wall: float) -> Vector2:
		return a + dir * (t + along) + inward * (back - from_wall)
	match unit:
		"tent", "tent_tarp":
			var kind := "tent_dome" if rng.randf() < 0.62 else "tent_pop"
			var d: float = PIECES[kind].d
			var off := width * 0.5
			if unit == "tent_tarp":
				_place(chunk, "tarp_canopy", at.call(width * 0.5, 1.3), basis, rng, items, face, camp_id)
			_place(chunk, kind, at.call(off, d * 0.5), basis * Basis(Vector3.UP, rng.randf_range(-0.12, 0.12)), rng, items, face, camp_id)
			if rng.randf() < 0.5:
				_place(chunk, "bag_trash", at.call(off + 1.25, 0.35), basis, rng, items, face, camp_id)
			if rng.randf() < 0.25:
				_place(chunk, "chair", at.call(off - 1.3, d + 0.2), basis * Basis(Vector3.UP, rng.randf_range(-0.6, 0.6)), rng, items, face, camp_id)
			elif rng.randf() < 0.14:
				# Somebody standing folded forward outside their tent.
				sleepers.append({"pose": RoughSleeper.Pose.SLUMP, "at": at.call(off + 0.9, minf(d + 0.45, back - PATH_KEEP * 0.5)), "yaw": yaw + PI + rng.randf_range(-1.0, 1.0)})
		"mound":
			_place(chunk, "tarp_mound", at.call(width * 0.5, 0.95), basis * Basis(Vector3.UP, rng.randf_range(-0.2, 0.2)), rng, items, face, camp_id)
		"cart":
			# A cart stands side-on to the wall, nose along the pavement.
			var cb := basis * Basis(Vector3.UP, PI * 0.5 + rng.randf_range(-0.25, 0.25))
			_place(chunk, "cart", at.call(width * 0.5, 0.5), cb, rng, items, face, camp_id)
			if rng.randf() < 0.6:
				_place(chunk, "bags_pile", at.call(width * 0.5 + 0.95, 0.5), basis * Basis(Vector3.UP, rng.randf_range(0.0, TAU)), rng, items, face, camp_id)
		"bed":
			# A mattress or boxes along the wall, bedding on it, and somebody asleep on it.
			var on_mattress := rng.randf() < 0.6
			var bb := basis * Basis(Vector3.UP, rng.randf_range(-0.08, 0.08))
			var spot: Vector2 = at.call(width * 0.5, 0.55)
			var lift := 0.0
			if on_mattress:
				_place(chunk, "mattress", spot, bb, rng, items, face, camp_id)
				lift = 0.19
			else:
				_place(chunk, "cardboard", spot, bb, rng, items, face, camp_id)
				lift = 0.02
			_place(chunk, "bedding", spot, bb, rng, items, face, camp_id, lift)
			if rng.randf() < 0.75:
				# Head on the pillow (the bedding's -x end), back to the wall (RoughSleeper's LIE).
				sleepers.append({"pose": RoughSleeper.Pose.LIE, "at": spot, "yaw": yaw + PI, "lift": lift + 0.02})
		"sit":
			var spot: Vector2 = at.call(width * 0.5, 0.42)
			_place(chunk, "cardboard", at.call(width * 0.5, 0.5), basis * Basis(Vector3.UP, rng.randf_range(-0.3, 0.3)), rng, items, face, camp_id)
			if rng.randf() < 0.5:
				_place(chunk, "bag_duffel", at.call(width * 0.5 + 0.7, 0.3), basis * Basis(Vector3.UP, rng.randf_range(0.0, TAU)), rng, items, face, camp_id)
			# Sitting with their back to the wall, looking out at the street.
			sleepers.append({"pose": RoughSleeper.Pose.SIT, "at": spot, "yaw": yaw + PI, "lift": 0.02})
		"bags":
			_place(chunk, "bags_pile", at.call(width * 0.5, 0.5), basis * Basis(Vector3.UP, rng.randf_range(0.0, TAU)), rng, items, face, camp_id)
			if rng.randf() < 0.5:
				_place(chunk, "box", at.call(width * 0.5 + 0.55, 0.3), basis * Basis(Vector3.UP, rng.randf_range(0.0, TAU)), rng, items, face, camp_id)
		"bike":
			# Leaning on the wall, side-on, a quarter tipped.
			var lean := basis * Basis(Vector3.UP, PI * 0.5) * Basis(Vector3.BACK, -deg_to_rad(rng.randf_range(8.0, 14.0)))
			_place(chunk, "bicycle", at.call(width * 0.5, 0.3), lean, rng, items, face, camp_id)
		"parts":
			_place(chunk, "bike_frame", at.call(width * 0.4, 0.45), basis * Basis(Vector3.UP, rng.randf_range(0.0, TAU)), rng, items, face, camp_id)
			_place(chunk, "bike_wheel", at.call(width * 0.8, 0.45), basis * Basis(Vector3.UP, rng.randf_range(0.0, TAU)), rng, items, face, camp_id)
		"slump":
			# Standing at the kerb side of the camp, folded forward, facing along the pavement.
			var spot: Vector2 = at.call(width * 0.5, minf(back - PATH_KEEP * 0.5, 1.6))
			sleepers.append({"pose": RoughSleeper.Pose.SLUMP, "at": spot, "yaw": yaw + PI + rng.randf_range(-1.2, 1.2)})


## One kit piece: a batch instance with its colour and wear, and (for the knockable ones) its body.
static func _place(chunk: CityChunk, piece: String, p: Vector2, basis: Basis, rng: RandomNumberGenerator, items: Array, face: int, camp_id: Array, lift: float = 0.0) -> void:
	if items[0] >= MAX_ITEMS:
		return
	var spec: Dictionary = PIECES[piece]
	var id := "camp_%d_%d" % [face, camp_id[0]]
	camp_id[0] += 1
	# Rolled whether or not the piece is still there, so a knocked-over tent does not shift what
	# the rest of the camp rolls.
	var tint := _color_for(String(spec.colors), rng)
	var custom := Color(rng.randf_range(0.2, 1.0), rng.randf(), 0.0, 0.0)
	if WorldState.is_destroyed(chunk.key, id):
		return
	var y := CityChunk.SIDEWALK_TOP + lift
	var key := "camp_" + piece
	var index := chunk._batch.add(key, PropFactory.encampment(piece), Transform3D(basis, Vector3(p.x, y, p.y)), tint, custom)
	items[0] += 1
	if not spec.body:
		return
	var item := EncampmentItem.new()
	item.name = "Camp_" + id
	item.chunk = chunk
	item.item_id = id
	item.instances = [[key, index]]
	item.mesh = PropFactory.encampment(piece)
	item.mass_kg = spec.mass
	item.tint = tint
	item.custom = custom
	item.setup(spec.box, spec.y)
	item.transform = Transform3D(basis, Vector3(p.x, y + chunk._gy(p.x, p.y), p.y))
	chunk.add_child(item)


static func _color_for(kind: String, rng: RandomNumberGenerator) -> Color:
	var pal: Array = []
	match kind:
		"tent":
			pal = TENT_COLORS
		"tarp":
			pal = TARP_COLORS
		"bag":
			pal = BAG_COLORS
		"cloth":
			pal = CLOTH_COLORS
		"bike":
			pal = BIKE_COLORS
		"mattress":
			return Color(0.80, 0.77, 0.70).lerp(Color(0.62, 0.56, 0.46), rng.randf())
		_:
			return Color(1.0, 1.0, 1.0)
	var c: Color = pal[rng.randi() % pal.size()]
	return c.lightened(rng.randf_range(-0.08, 0.1))


## Somebody at the camp: a posed RoughSleeper, if the crowd cap has room for one more.
static func _spawn_sleeper(chunk: CityChunk, rect: Rect2, s: Dictionary) -> void:
	if not chunk._take_crowd_room():
		return
	var at: Vector2 = s.at
	var ped := RoughSleeper.new()
	ped.setup_sleeper(rect, PATH_KEEP + 1.0, hash([chunk.plan.seed, "sleeper", int(at.x * 10.0), int(at.y * 10.0)]), int(s.pose), at, float(s.yaw))
	var lift: float = s.get("lift", 0.0)
	ped.lift = lift
	ped.position = Vector3(at.x, chunk.ground_y(at.x, at.y) + lift, at.y)
	chunk.add_child(ped)


static func _hash01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) * (1.0 / 100003.0)
