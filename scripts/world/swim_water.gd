class_name SwimWater
extends RefCounted
## Where the player can swim, and where the water's surface and floor are there (Swim,
## scripts/player/swim.gd). Two sources:
##  - worked out, never registered: the OCEAN (and the bay) by MacroMap's coast and the drawn
##    swell (SeaSurface), the floor the sand's profile under the water and then a shelf down to
##    the floor box; and the MARINA's basin and channel (Marina.in_water()), flat water at its 0.15.
##  - registered by the builders that lay water, one line each (`add_rect()` / `add_poly()`, in
##    the builder's chunk-local space, which is true world space): MacArthur Park's lake and the
##    canals (real floors under the city's ground box, which their own volumes already let bodies
##    through), and swimming pools (`solid`: the water is painted on the ground, so the swimmer
##    passes through it - Swim drops the player's world mask - and is held in the tank's rect).
## Entries live in a 64 m grid of true world cells and go when their node leaves the tree.
## `SWIMMING=0` in the environment: no water anywhere (the A/B).

enum Kind { NONE, SEA, MARINA, LAKE, CANAL, POOL }

const CELL := 64.0
## How deep a pool is drawn to be (its painted tank), metres under its surface.
const POOL_DEPTH := 1.7

static var enabled: bool = OS.get_environment("SWIMMING") != "0"
## Vector2i cell -> Array of entries {node_id, poly (true world), rect, surface, floor, kind}.
static var _cells: Dictionary = {}
static var _count: int = 0


## A rectangle of water (chunk-local = true world XZ) with its surface and floor heights.
static func add_rect(node: Node, r: Rect2, surface: float, floor_y: float, kind: Kind) -> void:
	add_poly(node, PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]), surface, floor_y, kind)


## A polygon of water (true world XZ).
static func add_poly(node: Node, poly: PackedVector2Array, surface: float, floor_y: float, kind: Kind) -> void:
	if not enabled or node == null or poly.size() < 3:
		return
	if node is CityChunk and ((node as CityChunk).capturing or (node as CityChunk).level != CityChunk.Level.FULL):
		return
	var lo := poly[0]
	var hi := poly[0]
	for q in poly:
		lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
		hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
	var e := {"node": node.get_instance_id(), "poly": poly, "rect": Rect2(lo, hi - lo), "surface": surface,
		"floor": floor_y, "kind": kind}
	for cz in range(floori(lo.y / CELL), floori(hi.y / CELL) + 1):
		for cx in range(floori(lo.x / CELL), floori(hi.x / CELL) + 1):
			var key := Vector2i(cx, cz)
			if not _cells.has(key):
				_cells[key] = []
			(_cells[key] as Array).append(e)
	_count += 1
	if not node.has_meta("swim_water"):
		node.set_meta("swim_water", true)
		node.tree_exiting.connect(_forget.bind(node.get_instance_id()))


static func _forget(id: int) -> void:
	for key: Vector2i in _cells.keys():
		var list: Array = _cells[key]
		for i in range(list.size() - 1, -1, -1):
			if int(list[i].node) == id:
				list.remove_at(i)
				_count -= 1
		if list.is_empty():
			_cells.erase(key)


static func count() -> int:
	return _count


static func clear() -> void:
	_cells.clear()
	_count = 0


## The water over TRUE world `p` (a point; its y says nothing about which water): {} when none,
## else {"kind", "surface" (true world y), "floor", "solid" (pass through the ground: pools),
## "rect" (a pool's tank, to hold the swimmer in), "s" (metres offshore at sea)}. `t` and
## `sea` (SeaSurface.state()) are only read at sea.
static func at(m: MacroMap, p: Vector3, t: float, sea: Array) -> Dictionary:
	if not enabled:
		return {}
	var xz := Vector2(p.x, p.z)
	var list: Array = _cells.get(Vector2i(floori(xz.x / CELL), floori(xz.y / CELL)), [])
	for e: Dictionary in list:
		if (e.rect as Rect2).grow(0.01).has_point(xz) and Geometry2D.is_point_in_polygon(xz, e.poly):
			if not is_instance_valid(instance_from_id(int(e.node))):
				continue
			var kind: int = e.kind
			return {"kind": kind, "surface": e.surface, "floor": e.floor, "solid": kind == Kind.POOL,
				"rect": e.rect, "s": 0.0}
	if m == null:
		return {}
	if m.marina and m.marina.in_water(xz):
		return {"kind": Kind.MARINA, "surface": Marina.WATER_Y, "floor": -4.5, "solid": true, "rect": Rect2(), "s": 0.0}
	if m.zone_at(xz) != MacroMap.Zone.OCEAN:
		return {}
	var sd := SeaSurface.shore_distance(m, xz)
	if sd.x <= 0.0:
		return {}
	return {"kind": Kind.SEA, "surface": SeaSurface.height(m, xz, t, sea), "floor": SeaSurface.seabed(sd.x),
		"solid": true, "rect": Rect2(), "s": sd.x}
