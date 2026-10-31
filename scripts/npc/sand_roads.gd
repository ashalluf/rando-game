class_name SandRoads
extends RefCounted
## The grid streets the beach covers (wave 4, rc-beach). CityPlan's grid runs the whole map, but on
## the coast nobody draws the road: a sea chunk builds water and sand and no road at all, and a
## beach chunk that holds the shore lays its sand over the street end on its +Z side
## (CityChunk._build_beach). The traffic only checked the zone where a car is PUT DOWN, so a car
## spawned in the city drove straight on down its street into the sand: sedans and buses parked
## on the beach among the sunbathers and at the waterline (the beach refcam's views along the
## shore). on_sand() says which stretches those are; TrafficManager treats them as closed - a car
## turns at the last junction before them, never spawns on them, and one found on them goes back
## to the pool.
##
## Pure and O(1) per call after the first for a chunk: the answer is kept per chunk (the owning
## chunk's zone and whether it holds the shore), the way CityChunk decides what it builds.
## `SAND_ROADS=0` in the environment turns it off (the A/B).

static var enabled: bool = OS.get_environment("SAND_ROADS") != "0"

## Per plan (instance id): chunk Vector2i -> [kind, sand_x]: kind 0 a road chunk, 1 a sea chunk (no
## road at all), 2 a beach chunk, 3 a beach chunk holding the shore (its +Z street end is under the
## sand); sand_x the sand's landward edge at the chunk's middle (a beach chunk's streets are under
## the sand west of it).
static var _cache: Dictionary = {}


## True where the street (axis, index) at `along` lies under the sand or the sea: nobody drew it.
static func on_sand(plan: CityPlan, axis: int, index: int, along: float) -> bool:
	if not enabled or plan == null or plan.macro == null:
		return false
	var p := Vector2(plan.road_pos(axis, index), along) if axis == CityPlan.AXIS_X else Vector2(along, plan.road_pos(axis, index))
	var k := plan.chunk_index_at(p)
	var c := _kind(plan, k)
	var kind: int = c[0]
	if kind == 1:
		return true
	if kind == 0:
		return false
	# A shore beach chunk's sand runs over its +Z street (the AXIS_Z road iz + 1); anywhere in a
	# beach chunk, a street inside the sand band is under it (the sand is laid over the whole
	# beach; the road slab under it is never seen).
	return (kind == 3 and axis == CityPlan.AXIS_Z and index == k.y + 1) or p.x < float(c[1])


static func _kind(plan: CityPlan, k: Vector2i) -> Array:
	var id := plan.get_instance_id()
	var per: Dictionary = _cache.get(id, {})
	if per.is_empty():
		_cache[id] = per
	if per.has(k):
		return per[k]
	var kind := 0
	var sand_x := -INF
	# Built by somebody else, whatever the zone: the marina's blocks and the replica's corridor
	# (their own roads, their own traffic rules).
	var replica: ReplicaAreas = plan.macro.replica
	if not plan.marina_block(k.x, k.y) and (replica == null or replica.block_role(plan, k.x, k.y) == 0):
		var block := plan.block(k.x, k.y)
		var zone := plan.zone_at((block.rect as Rect2).get_center())
		if zone == MacroMap.Zone.OCEAN:
			kind = 1
		elif zone == MacroMap.Zone.BEACH:
			var own := plan.owned_rect(k.x, k.y)
			var z := own.get_center().y
			var cx := plan.macro.coast_x(z)
			kind = 3 if cx >= own.position.x and cx < own.end.x else 2
			sand_x = cx + plan.macro.beach_width_at(z)
	per[k] = [kind, sand_x]
	return per[k]
