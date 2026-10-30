class_name MapData
extends RefCounted
## The whole basin's street map as plain records, for the minimap and the full-screen map
## (MapPainter): every block on land the map draws as a block (its fill and its two roads, on its
## +X and +Z sides), the district labels, and a cell index so a small view finds its blocks in a
## few lookups. Mountains and the sea are not blocks here: map_relief.gdshader paints them from the
## basin bake (MacroMap.bake()).
##
## Built a slice at a time (warm(), a budget in microseconds), because the basin is ~30k blocks
## and a block's zone costs a height lookup: the HUD warms it a couple of milliseconds a frame from
## the moment the city is up, so it is ready long before anyone opens the map. Everything in it is
## read off CityPlan (block(), road_pos(), road_open()), so it never rolls anything.

## Half the square the map covers, centred on the world origin: the basin bake's span (16 km).
const HALF_SPAN := 8000.0
## Cell size of the index (m).
const CELL := 500.0
## District labels: blocks are counted in squares this big and a square with enough of one
## district gets its name; the same name is not written twice within LABEL_APART.
const LABEL_CELL := 1600.0
const LABEL_MIN_BLOCKS := 40
const LABEL_APART := 2600.0

## Kinds of ground a block record carries (MapPainter colours them).
enum Kind { DISTRICT, PARK, PLAZA, SCHOOL, COMMERCIAL, SITE, AIRPORT, PORT, BEACH }

static var _cache: Dictionary = {}

var plan: CityPlan
## Index range covered (inclusive).
var lo := Vector2i.ZERO
var hi := Vector2i.ZERO
## {"rect": Rect2 (inside the pavement ring), "owned": Rect2, "kind": Kind, "district": int,
##  "ix", "iz", "grounds": "" | "rec" | "school"}
var blocks: Array[Dictionary] = []
## {"rect": Rect2 (the carriageway, world XZ), "avenue": bool, "axis": int, "index": int}
var roads: Array[Dictionary] = []
## {"name": String, "pos": Vector2}
var district_labels: Array[Dictionary] = []
var ready := false

var _cells: Dictionary = {}
var _done: Dictionary = {}
var _road_cells: Dictionary = {}
var _row: int = 0
var _counts: Dictionary = {}


static func of(p: CityPlan) -> MapData:
	var key := p.get_instance_id()
	if not _cache.has(key):
		_cache.clear()
		_cache[key] = MapData.new(p)
	return _cache[key]


func _init(p: CityPlan) -> void:
	plan = p
	lo = plan.block_index_at(Vector2(-HALF_SPAN, -HALF_SPAN))
	hi = plan.block_index_at(Vector2(HALF_SPAN, HALF_SPAN))
	_row = lo.y


## Builds rows of blocks for up to `budget_usec`; true once the whole basin is in.
func warm(budget_usec: int) -> bool:
	if ready:
		return true
	var t0 := Time.get_ticks_usec()
	while _row <= hi.y:
		for ix in range(lo.x, hi.x + 1):
			_add_block(ix, _row)
		_row += 1
		if Time.get_ticks_usec() - t0 > budget_usec:
			return false
	_finish_labels()
	_done.clear()
	ready = true
	return true


## Adds every block of `r` (world XZ) not added yet, at once: the minimap's own neighbourhood
## before warm() has reached it.
func ensure_rect(r: Rect2) -> void:
	if ready:
		return
	var a := plan.block_index_at(r.position)
	var b := plan.block_index_at(r.end)
	for iz in range(maxi(a.y, lo.y), mini(b.y, hi.y) + 1):
		for ix in range(maxi(a.x, lo.x), mini(b.x, hi.x) + 1):
			_add_block(ix, iz)


func _add_block(ix: int, iz: int) -> void:
	var done_key := Vector2i(ix, iz)
	if _done.has(done_key):
		return
	_done[done_key] = true
	var owned := plan.owned_rect(ix, iz)
	var c := owned.get_center()
	var zone := plan.zone_at(c)
	var kind := Kind.DISTRICT
	match zone:
		MacroMap.Zone.OCEAN, MacroMap.Zone.HILLS:
			return
		MacroMap.Zone.AIRPORT:
			kind = Kind.AIRPORT
		MacroMap.Zone.PORT:
			kind = Kind.PORT
		MacroMap.Zone.BEACH:
			kind = Kind.BEACH
	var b := plan.block(ix, iz)
	var district := int(b.district)
	if kind == Kind.DISTRICT:
		if b.has("site"):
			kind = Kind.SITE
		else:
			match int(b.kind):
				CityPlan.BlockKind.PARK:
					kind = Kind.PARK
				CityPlan.BlockKind.PLAZA:
					kind = Kind.PLAZA
				CityPlan.BlockKind.SCHOOL:
					kind = Kind.SCHOOL
				CityPlan.BlockKind.MALL, CityPlan.BlockKind.BIGBOX:
					kind = Kind.COMMERCIAL
	var rec := {"rect": b.rect, "owned": owned, "kind": kind, "district": district, "ix": ix, "iz": iz,
		"grounds": str(b.get("grounds", ""))}
	var bi := blocks.size()
	blocks.append(rec)
	_index(_cells, owned, bi)
	# Its two roads (the +X and +Z sides), where they are open; airport and port blocks have none.
	if kind != Kind.AIRPORT and kind != Kind.PORT:
		_add_road(CityPlan.AXIS_X, ix + 1, owned.position.y, owned.end.y)
		_add_road(CityPlan.AXIS_Z, iz + 1, owned.position.x, owned.end.x)
	if kind == Kind.DISTRICT or kind == Kind.BEACH:
		var name := "Beach" if kind == Kind.BEACH else CityPlan.district_name(district as CityPlan.District)
		var cell := Vector2i(floori(c.x / LABEL_CELL), floori(c.y / LABEL_CELL))
		var key := [cell, name]
		var acc: Array = _counts.get(key, [0, Vector2.ZERO])
		acc[0] += 1
		acc[1] += c
		_counts[key] = acc


func _add_road(axis: int, index: int, a0: float, a1: float) -> void:
	var mid := (a0 + a1) * 0.5
	if not plan.road_open(axis, index, mid):
		return
	var pos := plan.road_pos(axis, index)
	var w := plan.road_width(axis, index)
	var r := Rect2(pos - w * 0.5, a0, w, a1 - a0) if axis == CityPlan.AXIS_X else Rect2(a0, pos - w * 0.5, a1 - a0, w)
	var ri := roads.size()
	# An avenue on the map is a road as wide as the plan's avenues: downtown's real streets are
	# 18-22 m, wider than a seeded street, and drawn as avenues every block was yellow.
	roads.append({"rect": r, "avenue": w >= plan.avenue_width - 1.0, "axis": axis, "index": index})
	_index(_road_cells, r, ri)


func _index(cells: Dictionary, r: Rect2, i: int) -> void:
	var c0 := Vector2i(floori(r.position.x / CELL), floori(r.position.y / CELL))
	var c1 := Vector2i(floori(r.end.x / CELL), floori(r.end.y / CELL))
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			var k := Vector2i(cx, cz)
			# Packed arrays are values: take it out, add, put it back.
			var list: PackedInt32Array = cells.get(k, PackedInt32Array())
			list.append(i)
			cells[k] = list


func _finish_labels() -> void:
	var cand: Array = []
	for key: Array in _counts:
		var acc: Array = _counts[key]
		if int(acc[0]) >= LABEL_MIN_BLOCKS:
			cand.append({"name": str(key[1]), "pos": (acc[1] as Vector2) / float(acc[0]), "n": int(acc[0])})
	cand.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.n) > int(b.n))
	for c: Dictionary in cand:
		var clash := false
		for l: Dictionary in district_labels:
			if l.name == c.name and (l.pos as Vector2).distance_to(c.pos) < LABEL_APART:
				clash = true
				break
		if not clash:
			district_labels.append({"name": str(c.name).to_upper(), "pos": c.pos})
	_counts.clear()


## Indices of the blocks (`roads` false) or roads whose cells touch `r`, each once.
func indices_in(r: Rect2, want_roads: bool = false) -> PackedInt32Array:
	var cells := _road_cells if want_roads else _cells
	var out := PackedInt32Array()
	var seen := {}
	var c0 := Vector2i(floori(r.position.x / CELL), floori(r.position.y / CELL))
	var c1 := Vector2i(floori(r.end.x / CELL), floori(r.end.y / CELL))
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			var list: Variant = cells.get(Vector2i(cx, cz))
			if list == null:
				continue
			for i: int in list:
				if not seen.has(i):
					seen[i] = true
					out.append(i)
	return out
