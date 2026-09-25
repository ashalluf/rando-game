class_name Encampment
extends RefCounted
## Sidewalk encampments downtown (owner, 2026-09-24): rows of dome tents in faded colours against
## the building line, tarps strung over some of them, shopping carts, bags, mattresses, flattened
## boxes, a camp chair, bikes and bike parts - and the people who live there (RoughSleeper), not
## walking but sitting against the wall, lying on their bedding, or standing folded forward in a
## deep slump. Depicted the way a realistic Los Angeles game would: as the street, not as a joke.
##
## Where: DOWNTOWN blocks of ordinary buildings - never a plaza, a park, a mall, a landmark's
## ground or anywhere near a place of worship - and some streets far more than others, the way
## they cluster on real blocks. A block face either has a camp or does not (a hash of its seed,
## face and street), and a camp is a run of pieces laid along the wall, with gaps left for
## doorways and kept clear of every lamp, hydrant, meter, shelter and trash can already on that
## pavement, of the corners, and of the strip at the kerb the walkers keep to (PATH_KEEP).
##
## Denser where the real city is (owner, 2026-09-25: "downtown needs way more homeless people"):
## - Skid row (skid_row()): a band of blocks east of downtown's centre, measured in downtown radii
##   from MacroMap.downtown_center so it moves with downtown, patchy per block (a hash), running
##   out into the midtown and industrial blocks beside it. There nearly every face has a camp, the
##   runs are long, more of what is laid is people, and the chunk's caps are higher.
## - People not only in tents: sitting against the wall and in camp chairs, lying on mattresses
##   and flattened boxes, standing in twos and threes, standing by a bundle, and pushing a loaded
##   shopping cart slowly round the block (RoughSleeper's CHAIR, STAND and PUSH).
## - Under the freeway decks near downtown (_build_underpass()): rows along the pillar lines, the
##   centre under the deck left open.
## - Along the pavements facing MacArthur Park across its boundary roads (PARK_EDGE_ODDS).
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
const CAMP_STREET_SHARE := 0.42
const FACE_ODDS_CAMP_STREET := 0.8
const FACE_ODDS := 0.22
## Most camps on one block, pieces in one chunk, and people at them in one chunk (outside skid
## row; skid row's are the SKID_ ones, and a block between gets a value between).
const MAX_CAMPS := 3
const MAX_ITEMS := 44
const MAX_SLEEPERS := 9
## Skid row: east of downtown's centre, in downtown radii (MacroMap.downtown_radius), the field
## ramps in between SKID_EAST.x and .y and out again between .z and .w; north-south it is centred
## SKID_SOUTH radii south of the centre (+z), full within SKID_SPAN.x radii and gone past .y. Each
## block's value is then scaled by a hashed factor in SKID_PATCH, so the band has its worst
## blocks and its quieter ones rather than being a uniform rectangle.
const SKID_EAST := Vector4(0.1, 0.42, 1.15, 1.6)
const SKID_SOUTH := 0.2
const SKID_SPAN := Vector2(0.55, 1.0)
const SKID_PATCH := Vector2(0.55, 1.3)
## From this skid-row value a block's faces take the skid-row odds whatever its district (the
## band spills into the midtown and industrial blocks beside downtown); below it the odds blend.
const SKID_MIN := 0.35
const SKID_FACE_ODDS := 0.95
const SKID_MAX_CAMPS := 4
const SKID_MAX_ITEMS := 72
const SKID_MAX_SLEEPERS := 16
const SKID_RUN_LENGTH := Vector2(20.0, 64.0)
## At full skid-row strength, the odds that the next unit of a run is one of PEOPLE_UNITS.
const SKID_PEOPLE_BIAS := 0.35
## Somebody pushing a loaded cart round the block: the odds of one on any block with camps along
## its faces, and up to this many more at full skid-row strength.
const PUSHER_ODDS := 0.3
const SKID_PUSHERS := 2
## Build steps a chunk queues for its people (CityChunk: one person a step): the most people and
## pushers one chunk can have.
const PEOPLE_STEPS := SKID_MAX_SLEEPERS + SKID_PUSHERS + 1
## Faces across the road from MacArthur Park (its site, CityPlan.sites()): the odds of a camp.
const PARK_EDGE_ODDS := 0.7
## Freeway underpasses within this many downtown radii of the centre (or on skid row) get camps:
## per deck segment and side the odds of a row, the deck height it needs over the ground, how
## far inside the pillar line the row's back stands, and the room kept round each pillar.
const UNDERPASS_REACH := 2.2
const UNDERPASS_ODDS := 0.7
const UNDERPASS_CLEARANCE := 5.5
const UNDERPASS_INSET := 1.0
const PILLAR_CLEAR := 2.0
## No camp on a block within this many metres of a place of worship (a landmark whose id names
## one - Masjid Omar ibn Al-Khattab is `masjid_omar`), whatever its district.
const WORSHIP_CLEAR := 160.0
const WORSHIP_WORDS := ["masjid", "mosque", "church", "chapel", "cathedral", "temple", "synagogue", "shrine"]
## Share of the crowd cap the walkers of blocks near downtown (UNDERPASS_REACH) leave for the
## people at the camps (CityChunk._spawn_walker, CityStreamer.take_crowd_room()): downtown's
## walkers used to fill the whole cap, so every chunk built after the first few had nobody at
## its camps at all. Quality's crowd scaling moves the cap, and this share with it.
const CROWD_RESERVE := 0.2
## Bits of block_flags(): camps along the faces, and under a freeway deck.
const FACES := 1
const UNDERPASS := 2
## Metres of a block face kept clear at each corner (the crossing and its kerb ramps).
const CORNER_CLEAR := 9.0
## How long a camp runs along the face (metres, min and max).
const RUN_LENGTH := Vector2(9.0, 32.0)
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
	"loaded_cart": {"w": 0.7, "d": 1.05, "box": Vector3(0.6, 1.25, 1.0), "y": 0.63, "mass": 34.0, "body": true, "colors": "cloth", "far": false},
	"bundle": {"w": 0.65, "d": 0.45, "box": Vector3(0.58, 0.38, 0.42), "y": 0.19, "mass": 7.0, "body": true, "colors": "cloth", "far": false},
}
## What a camp is made of, as weighted "units" laid one after another along the wall. A unit is a
## main piece and the clutter that sits with it.
const UNITS := [
	["tent", 30], ["tent_tarp", 12], ["mound", 8], ["cart", 10], ["bed", 11], ["sit", 9],
	["bags", 8], ["bike", 6], ["parts", 3], ["slump", 6], ["chair", 5], ["group", 4], ["bundle", 4],
]
## The units with somebody in them, which skid row leans toward (SKID_PEOPLE_BIAS).
const PEOPLE_UNITS := [
	["bed", 3], ["sit", 3], ["chair", 2], ["group", 2], ["bundle", 2], ["slump", 1],
]


## True when this block will have encampments along its faces (decided from hashes alone, before
## anything is built, so the block's walkers can be given the narrower ring).
static func block_has_camps(plan: CityPlan, ix: int, iz: int) -> bool:
	return not _faces(plan, ix, iz).is_empty()


## FACES | UNDERPASS: what this block builds (CityChunk queues the camp steps when it is not 0,
## and narrows the walkers' ring only for FACES).
static func block_flags(plan: CityPlan, ix: int, iz: int) -> int:
	var flags := 0
	if not _faces(plan, ix, iz).is_empty():
		flags |= FACES
	if _underpass_ok(plan, ix, iz) and not _underpass_segments(plan, ix, iz).is_empty():
		flags |= UNDERPASS
	return flags


## The share of the crowd cap a walker on this block leaves for the camps (CROWD_RESERVE near
## downtown, 0 elsewhere, where there are none).
static func walker_reserve(plan: CityPlan, ix: int, iz: int) -> float:
	if plan.macro == null:
		return 0.0
	var c: Vector2 = (plan.block(ix, iz).rect as Rect2).get_center()
	var r := maxf(plan.macro.downtown_radius, 1.0)
	return CROWD_RESERVE if c.distance_to(plan.macro.downtown_center) < r * UNDERPASS_REACH else 0.0


## 0..1: how much of skid row this block is (see SKID_EAST). Downtown, midtown and industrial
## blocks only; a pure function of the plan, the block and the seed.
static func skid_row(plan: CityPlan, ix: int, iz: int) -> float:
	if plan.macro == null:
		return 0.0
	var block := plan.block(ix, iz)
	var d := int(block.district)
	if d != CityPlan.District.DOWNTOWN and d != CityPlan.District.MIDTOWN and d != CityPlan.District.INDUSTRIAL:
		return 0.0
	var r := maxf(plan.macro.downtown_radius, 1.0)
	var off: Vector2 = ((block.rect as Rect2).get_center() - plan.macro.downtown_center) / r
	var east := smoothstep(SKID_EAST.x, SKID_EAST.y, off.x) * (1.0 - smoothstep(SKID_EAST.z, SKID_EAST.w, off.x))
	var ns := 1.0 - smoothstep(SKID_SPAN.x, SKID_SPAN.y, absf(off.y - SKID_SOUTH))
	if east <= 0.0 or ns <= 0.0:
		return 0.0
	return clampf(east * ns * lerpf(SKID_PATCH.x, SKID_PATCH.y, _hash01([plan.seed, "skid_row", ix, iz])), 0.0, 1.0)


## True when a camp may stand on this block at all: ordinary buildings, city ground, not a
## landmark's site or block, nowhere near a place of worship.
static func _block_ok(plan: CityPlan, ix: int, iz: int) -> bool:
	if plan.macro == null:
		return false
	var block := plan.block(ix, iz)
	if int(block.kind) != CityPlan.BlockKind.BUILDINGS or block.has("site"):
		return false
	var rect: Rect2 = block.rect
	if plan.zone_at(rect.get_center()) != MacroMap.Zone.CITY:
		return false
	for lm: Dictionary in Landmarks.all():
		var anchor: Vector2 = lm.anchor
		if rect.has_point(anchor):
			return false
		if _is_worship(String(lm.id)) and rect.grow(WORSHIP_CLEAR + float(lm.get("radius", 0.0))).has_point(anchor):
			return false
	return true


static func _is_worship(id: String) -> bool:
	for w: String in WORSHIP_WORDS:
		if id.contains(w):
			return true
	return false


## The block faces (0..3, CityChunk._build_sidewalk_props's edge order) that carry a camp.
static func _faces(plan: CityPlan, ix: int, iz: int) -> Array:
	var out: Array = []
	if not _block_ok(plan, ix, iz):
		return out
	var block := plan.block(ix, iz)
	var downtown := int(block.district) == CityPlan.District.DOWNTOWN
	var skid := skid_row(plan, ix, iz)
	var skid_w := clampf(skid / SKID_MIN, 0.0, 1.0)
	var cap := SKID_MAX_CAMPS if skid >= SKID_MIN else MAX_CAMPS
	# Edge order: 0 the -Z side (faces road Z iz), 1 the +Z side (Z iz+1), 2 the -X side (X ix),
	# 3 the +X side (X ix+1); and the block across each of those roads.
	var roads := [[CityPlan.AXIS_Z, iz], [CityPlan.AXIS_Z, iz + 1], [CityPlan.AXIS_X, ix], [CityPlan.AXIS_X, ix + 1]]
	var across := [Vector2i(ix, iz - 1), Vector2i(ix, iz + 1), Vector2i(ix - 1, iz), Vector2i(ix + 1, iz)]
	for e in 4:
		var axis: int = roads[e][0]
		var index: int = roads[e][1]
		var odds := 0.0
		if downtown:
			var camp_street := _hash01([plan.seed, "camp_street", axis, index]) < CAMP_STREET_SHARE
			odds = FACE_ODDS_CAMP_STREET if camp_street else FACE_ODDS
		odds = lerpf(odds, maxf(odds, SKID_FACE_ODDS), skid_w)
		var other: Vector2i = across[e]
		if String(plan.block(other.x, other.y).get("site", "")) == LandmarkMacArthurPark.SITE.id:
			odds = maxf(odds, PARK_EDGE_ODDS)
		if odds > 0.0 and _hash01([plan.seed, "camp_face", ix, iz, e]) < odds:
			out.append(e)
		if out.size() >= cap:
			break
	return out


## The camps of one block, as one build step (FULL chunks). `edges` are [a, b, inward] like the
## chunk's sidewalk props. Runs after the furniture so it can keep clear of it, and fills
## `out_sleepers` with the people to seat at the camps (and the ones who push a cart round the
## block), which the chunk spawns a build step each (spawn_sleeper) BEFORE the block's walkers:
## the crowd cap is spent on the people who live on the pavement first.
static func build_block(chunk: CityChunk, rect: Rect2, edges: Array, out_sleepers: Array) -> void:
	var plan: CityPlan = chunk.plan
	var faces := _faces(plan, chunk.ix, chunk.iz)
	var underpass := _underpass_ok(plan, chunk.ix, chunk.iz)
	if faces.is_empty() and not underpass:
		return
	var skid := skid_row(plan, chunk.ix, chunk.iz)
	var occupied := _occupied(chunk)
	var walls := StreetDetail._footprints(chunk)
	# [pieces laid, the most this chunk may lay]
	var items := [0, roundi(lerpf(MAX_ITEMS, SKID_MAX_ITEMS, skid))]
	var sleepers: Array = []
	for e: int in faces:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([plan.seed, "camp", chunk.ix, chunk.iz, e])
		_build_run(chunk, walls, edges[e], e, rng, occupied, items, sleepers, skid)
		if items[0] >= items[1]:
			break
	if underpass:
		_build_underpass(chunk, rect, walls, occupied, items, sleepers, skid)
	for key: String in PIECES:
		var k := "camp_" + key
		chunk._batch.set_draw_distance(k, DRAW_DISTANCE if PIECES[key].far else SMALL_DRAW_DISTANCE)
	out_sleepers.append_array(_thin(sleepers, roundi(lerpf(MAX_SLEEPERS, SKID_MAX_SLEEPERS, skid))))
	# Somebody pushing their cart round the block's pavement (the walkers' strip, like a walker).
	if not faces.is_empty():
		var pushers := roundi(skid * SKID_PUSHERS)
		if _hash01([plan.seed, "pusher", chunk.ix, chunk.iz]) < PUSHER_ODDS:
			pushers += 1
		for i in pushers:
			out_sleepers.append({"pose": RoughSleeper.Pose.PUSH, "at": Vector2.ZERO, "yaw": 0.0, "n": i})


## `list` cut to `cap` entries picked evenly along it, so a chunk over its cap loses people from
## every camp rather than all of the last face's.
static func _thin(list: Array, cap: int) -> Array:
	if list.size() <= cap:
		return list
	var out: Array = []
	for k in cap:
		out.append(list[floori(float(k) * list.size() / float(cap))])
	return out


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
static func _build_run(chunk: CityChunk, walls: Array[Rect2], edge: Array, face: int, rng: RandomNumberGenerator, occupied: Array, items: Array, sleepers: Array, skid: float) -> void:
	var a: Vector2 = edge[0]
	var b: Vector2 = edge[1]
	var inward: Vector2 = edge[2]
	var length := a.distance_to(b)
	var usable := length - CORNER_CLEAR * 2.0
	if usable < RUN_LENGTH.x:
		return
	var dir := (b - a) / length
	var lengths := RUN_LENGTH.lerp(SKID_RUN_LENGTH, skid)
	var run := minf(rng.randf_range(lengths.x, lengths.y), usable)
	var t := CORNER_CLEAR + rng.randf_range(0.0, usable - run)
	var t_end := t + run
	var next_door := t + rng.randf_range(DOOR_EVERY.x, DOOR_EVERY.y)
	# The pieces face the street: local +Z toward the kerb.
	var yaw := atan2(-inward.x, -inward.y)
	var basis := Basis(Vector3.UP, yaw)
	var camp_id := [0]
	while t < t_end and items[0] < items[1]:
		if t >= next_door:
			t += rng.randf_range(DOOR_GAP.x, DOOR_GAP.y)
			next_door = t + rng.randf_range(DOOR_EVERY.x, DOOR_EVERY.y)
			continue
		var unit := _pick_unit(rng, skid)
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


## Rows under a freeway deck crossing this block: along each segment whose middle is over the
## block's own ground (inside its pavement ring, so never on a road), at each pillar line, the
## pieces' backs just inside the pillars and their fronts to the open middle under the deck -
## the "wall" is the line of pillars, and the middle is left as the walkway.
static func _build_underpass(chunk: CityChunk, rect: Rect2, walls: Array[Rect2], occupied: Array, items: Array, sleepers: Array, skid: float) -> void:
	var plan: CityPlan = chunk.plan
	var interior := rect.grow(-plan.sidewalk_width - 0.8)
	var grown: Array[Rect2] = []
	for w: Rect2 in walls:
		grown.append(w.grow(1.0))
	var every := int(round(Freeway.PILLAR_SPACING / Freeway.STEP))
	for seg: Dictionary in _underpass_segments(plan, chunk.ix, chunk.iz):
		var a: Vector2 = seg.a
		var b: Vector2 = seg.b
		var seg_len := a.distance_to(b)
		var dir := (b - a) / seg_len
		var nrm := Vector2(-dir.y, dir.x)
		# The pillar line (CityChunk._pillar: two columns at 0.26 of the deck width).
		var half := float(seg.width) * 0.26
		var pillars: Array = []
		if int(seg.index) % every == 0:
			pillars.append(a)
		if (int(seg.index) + 1) % every == 0:
			pillars.append(b)
		for side: float in [-1.0, 1.0]:
			if items[0] >= items[1]:
				return
			if _hash01([plan.seed, "underpass", int(seg.route), int(seg.index), side]) >= UNDERPASS_ODDS:
				continue
			var rng := RandomNumberGenerator.new()
			rng.seed = hash([plan.seed, "underpass_run", int(seg.route), int(seg.index), side])
			# In _lay_unit's terms the centre line is the "kerb", `inward` runs out to the pillar
			# line and the pillars are the "wall" (depth from the centre line).
			var inward := nrm * side
			var depth := half - UNDERPASS_INSET + WALL_BACK
			var yaw := atan2(-inward.x, -inward.y)
			var basis := Basis(Vector3.UP, yaw)
			var camp_id := [0]
			# A face id past the four block faces, one per segment and side, so WorldState ids
			# never collide.
			var face := 4 + int(seg.route) * 100000 + int(seg.index) * 2 + (0 if side < 0.0 else 1)
			var t := rng.randf_range(0.3, 2.5)
			while t < seg_len - 1.0 and items[0] < items[1]:
				var unit := _pick_unit(rng, skid)
				var width := _unit_width(unit)
				if t + width > seg_len:
					break
				var mid := a + dir * (t + width * 0.5)
				var back := mid + inward * (depth - WALL_BACK)
				var front := mid + inward * (depth - WALL_BACK - 2.6)
				var ok := interior.has_point(back) and interior.has_point(front) and _clear_of(occupied, mid + inward * (depth - 1.5), width * 0.5)
				for w: Rect2 in grown:
					if ok and (w.has_point(back) or w.has_point(front)):
						ok = false
				for p: Vector2 in pillars:
					if ok and (p + nrm * half * side).distance_to(mid + inward * (depth - 1.0)) < PILLAR_CLEAR + width * 0.5:
						ok = false
				if ok:
					_lay_unit(chunk, unit, a, dir, inward, t, width, depth, basis, yaw, rng, items, sleepers, face, camp_id)
				t += width + rng.randf_range(0.2, 0.9)


## True when this block is close enough to downtown for its underpasses to have camps.
static func _underpass_ok(plan: CityPlan, ix: int, iz: int) -> bool:
	if not _block_ok(plan, ix, iz) or plan.macro.freeway == null:
		return false
	var c: Vector2 = (plan.block(ix, iz).rect as Rect2).get_center()
	var r := maxf(plan.macro.downtown_radius, 1.0)
	return c.distance_to(plan.macro.downtown_center) < r * UNDERPASS_REACH or skid_row(plan, ix, iz) > 0.0


## Deck segments whose middle is over this block's own ground with room under the deck, away
## from any off-ramp.
static func _underpass_segments(plan: CityPlan, ix: int, iz: int) -> Array:
	var out: Array = []
	var fw: Freeway = plan.macro.freeway if plan.macro else null
	if fw == null:
		return out
	var rect: Rect2 = plan.block(ix, iz).rect
	var interior := rect.grow(-plan.sidewalk_width - 0.8)
	var ramps := fw.ramps_in(rect.grow(60.0))
	for seg: Dictionary in fw.segments_in(rect):
		var mid: Vector2 = ((seg.a as Vector2) + (seg.b as Vector2)) * 0.5
		if not interior.has_point(mid) or (seg.a as Vector2).distance_to(seg.b) < 6.0:
			continue
		if (float(seg.ha) + float(seg.hb)) * 0.5 - plan.height_at(mid) < UNDERPASS_CLEARANCE:
			continue
		var near_ramp := false
		for r: Dictionary in ramps:
			if (r.pos as Vector2).distance_to(mid) < 40.0:
				near_ramp = true
		if not near_ramp:
			out.append(seg)
	return out


static func _pick_unit(rng: RandomNumberGenerator, skid: float = 0.0) -> String:
	var table: Array = UNITS
	if skid > 0.0 and rng.randf() < skid * SKID_PEOPLE_BIAS:
		table = PEOPLE_UNITS
	var total := 0
	for u: Array in table:
		total += int(u[1])
	var roll := rng.randi() % total
	for u: Array in table:
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
		"chair":
			return 1.6
		"group":
			return 2.8
		"bundle":
			return 1.5
	return 2.3


## Lays one unit: `t` is where along the face it starts, `depth` how far in the wall is.
static func _lay_unit(chunk: CityChunk, unit: String, a: Vector2, dir: Vector2, inward: Vector2, t: float, width: float, depth: float, basis: Basis, yaw: float, rng: RandomNumberGenerator, items: Array, sleepers: Array, face: int, camp_id: Array) -> void:
	var back := depth - WALL_BACK
	# How far out from the wall somebody may be and stay out of the walkers' strip.
	var reach := back - PATH_KEEP - 0.3
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
			# In front of the tent, if the pavement leaves room short of the walkers' strip.
			if rng.randf() < 0.25:
				var turn := rng.randf_range(-0.6, 0.6)
				var sitter := rng.randf() < 0.55
				if d + 0.55 <= reach + 0.3:
					var spot: Vector2 = at.call(off - 1.3, d + 0.2)
					_place(chunk, "chair", spot, basis * Basis(Vector3.UP, turn), rng, items, face, camp_id)
					if sitter:
						# Somebody in it, by their tent.
						sleepers.append(_chair_sitter(spot, yaw + turn))
			elif rng.randf() < 0.14:
				# Somebody standing folded forward outside their tent.
				var turn := rng.randf_range(-1.0, 1.0)
				if d + 0.45 <= reach:
					sleepers.append({"pose": RoughSleeper.Pose.SLUMP, "at": at.call(off + 0.9, d + 0.45), "yaw": yaw + PI + turn})
		"mound":
			_place(chunk, "tarp_mound", at.call(width * 0.5, 0.95), basis * Basis(Vector3.UP, rng.randf_range(-0.2, 0.2)), rng, items, face, camp_id)
		"cart":
			# A cart stands side-on to the wall, nose along the pavement; half of them loaded.
			var cb := basis * Basis(Vector3.UP, PI * 0.5 + rng.randf_range(-0.25, 0.25))
			_place(chunk, "loaded_cart" if rng.randf() < 0.5 else "cart", at.call(width * 0.5, 0.5), cb, rng, items, face, camp_id)
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
			# Standing at the front of the camp, folded forward, facing along the pavement.
			var spot: Vector2 = at.call(width * 0.5, minf(reach, 1.6))
			sleepers.append({"pose": RoughSleeper.Pose.SLUMP, "at": spot, "yaw": yaw + PI + rng.randf_range(-1.2, 1.2)})
		"chair":
			# A camp chair against the wall with somebody sitting in it, a bag at their side.
			var turn := rng.randf_range(-0.35, 0.35)
			var spot: Vector2 = at.call(width * 0.5, minf(0.5, reach))
			_place(chunk, "chair", spot, basis * Basis(Vector3.UP, turn), rng, items, face, camp_id)
			if rng.randf() < 0.6:
				_place(chunk, "bag_duffel" if rng.randf() < 0.5 else "bundle", at.call(width * 0.5 + 0.65, 0.3), basis * Basis(Vector3.UP, rng.randf_range(0.0, TAU)), rng, items, face, camp_id)
			sleepers.append(_chair_sitter(spot, yaw + turn))
		"group":
			# Two or three people standing together talking, in the camp's band by the wall.
			var n := 3 if rng.randf() < 0.4 else 2
			var spots: Array[Vector2] = []
			var centre := Vector2.ZERO
			for i in n:
				var along := width * (float(i) + 0.5) / float(n) + rng.randf_range(-0.15, 0.15)
				var p: Vector2 = at.call(along, clampf(rng.randf_range(0.45, 1.1), 0.45, maxf(reach, 0.45)))
				spots.append(p)
				centre += p / float(n)
			# Faces turn in toward the group, a little toward the street.
			var street := -inward
			for p: Vector2 in spots:
				var look := ((centre - p).normalized() + street * rng.randf_range(0.15, 0.6)).normalized()
				sleepers.append({"pose": RoughSleeper.Pose.STAND, "at": p, "yaw": atan2(-look.x, -look.y) + rng.randf_range(-0.25, 0.25)})
			if rng.randf() < 0.45:
				_place(chunk, "bags_pile" if rng.randf() < 0.5 else "bag_trash", at.call(width * 0.5, 0.3), basis * Basis(Vector3.UP, rng.randf_range(0.0, TAU)), rng, items, face, camp_id)
		"bundle":
			# Somebody standing by what they carry: a roped blanket bundle or a duffel at their feet.
			var spot: Vector2 = at.call(width * 0.4, clampf(0.7, 0.45, maxf(reach, 0.45)))
			sleepers.append({"pose": RoughSleeper.Pose.STAND, "at": spot, "yaw": yaw + PI + rng.randf_range(-0.9, 0.9)})
			_place(chunk, "bundle" if rng.randf() < 0.65 else "bag_duffel", at.call(width * 0.4 + 0.6, 0.35), basis * Basis(Vector3.UP, rng.randf_range(0.0, TAU)), rng, items, face, camp_id)


## Somebody sitting in the camp chair at `spot` (its seat facing `chair_yaw`'s +Z, the street).
static func _chair_sitter(spot: Vector2, chair_yaw: float) -> Dictionary:
	# The hips a little behind the seat's middle; the body faces the way the chair does (the
	# visual faces -Z, so half a turn round from the chair's +Z).
	var fwd := Vector2(sin(chair_yaw), cos(chair_yaw))
	return {"pose": RoughSleeper.Pose.CHAIR, "at": spot - fwd * 0.05, "yaw": chair_yaw + PI}


## One kit piece: a batch instance with its colour and wear, and (for the knockable ones) its body.
static func _place(chunk: CityChunk, piece: String, p: Vector2, basis: Basis, rng: RandomNumberGenerator, items: Array, face: int, camp_id: Array, lift: float = 0.0) -> void:
	if items[0] >= items[1]:
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


## Somebody at the camp: a posed RoughSleeper (or one pushing a cart round the block), if the
## crowd cap has room for one more. The camps spend the whole cap; the walkers near downtown
## leave CROWD_RESERVE of it for them.
static func _spawn_sleeper(chunk: CityChunk, rect: Rect2, s: Dictionary) -> void:
	if not chunk._take_crowd_room():
		return
	var ped := RoughSleeper.new()
	if int(s.pose) == RoughSleeper.Pose.PUSH:
		var seed_value := hash([chunk.plan.seed, "pusher", chunk.ix, chunk.iz, int(s.get("n", 0))])
		ped.setup_sleeper(rect, PATH_KEEP + 1.0, seed_value, RoughSleeper.Pose.PUSH, Vector2.ZERO, 0.0)
		var start := ped._random_ring_point(PATH_KEEP + 1.0)
		ped.position = Vector3(start.x, chunk.ground_y(start.x, start.y) + 0.05, start.y)
		chunk.add_child(ped)
		return
	var at: Vector2 = s.at
	ped.setup_sleeper(rect, PATH_KEEP + 1.0, hash([chunk.plan.seed, "sleeper", int(at.x * 10.0), int(at.y * 10.0)]), int(s.pose), at, float(s.yaw))
	var lift: float = s.get("lift", 0.0)
	ped.lift = lift
	ped.position = Vector3(at.x, chunk.ground_y(at.x, at.y) + lift, at.y)
	chunk.add_child(ped)


static func _hash01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) * (1.0 / 100003.0)
