class_name ShopCrowd
## A shopping pavement is busy (rc2-hero-foot, 2026-11-01; docs/HANDOFF.md "The on-foot camera
## behind the hero"). The hero_foot refcam - the default on-foot camera behind the hero on a
## midtown shopping street at 13:30, what the player sees most of the time - had nobody within
## 12 m of him: a midtown block plans 20 walkers for a ~400 m ring, one every 20 m. A block whose
## buildings have shop fronts now carries up to `GAIN` times its planned walkers (by district)
## while it is near the camera, fading back to the plan by `FAR`:
##   * steps() (one hook after the block's walkers in CityChunk._block_steps, FULL only): once the
##     lots stand, counts the block's storefront parts, keeps the block's shop weight in its
##     BusyStreets entry, and spawns the extra walkers of a block near the camera right away -
##     the chunk is still hidden while it builds, so nobody pops in;
##   * gain() (one hook in BusyStreets.balance_crowd): the top-up target, so a shopping block near
##     the camera stays as busy as people walk off it (spawned out of view as before).
## Hash-seeded walkers (never the block rng); the crowd cap and the camps' reserve are spent as
## any walker spends them. Needs BusyStreets (its entries). SHOP_CROWD=0 is the A/B.

static var enabled: bool = OS.get_environment("SHOP_CROWD") != "0"

## How many times its planned walkers a full shopping block carries near the camera, by district
## (the downtown core already doubles its own; the beach town's walk streets are busy too).
const GAIN := {
	CityPlan.District.MIDTOWN: 2.2,
	CityPlan.District.DOWNTOWN: 1.35,
	CityPlan.District.BEACHTOWN: 1.6,
}
## Storefront parts that make a block a full shopping block (fewer weigh in proportionally).
const FULL_SHOPS := 3
## Full gain within NEAR metres of the camera (BusyStreets' block distance), none past FAR.
const NEAR := 70.0
const FAR := 150.0
## The most extra walkers one block spawns at build.
const MAX_EXTRA := 30


## The steps for a FULL block, after its walkers' (CityChunk._block_steps).
static func steps(ch: Node3D, block: Dictionary) -> Array[Callable]:
	var out: Array[Callable] = []
	if not enabled or not BusyStreets.enabled or block.kind != CityPlan.BlockKind.BUILDINGS:
		return out
	var g: float = GAIN.get(block.district, 1.0)
	if g <= 1.0:
		return out
	var state := {"extra": 0, "entry": []}
	out.append(func() -> void: _decide(ch, block, g, state))
	for i in MAX_EXTRA:
		out.append(func() -> void: _spawn(ch, state, i))
	return out


## The block's shop weight (0..1) times (gain - 1), kept as its BusyStreets entry's 4th item.
static func weight(ch: Node3D, rect: Rect2, g: float) -> float:
	var shops := 0
	for n in ch.get_children():
		var b := n as Building
		if b == null:
			continue
		var p := Vector2(b.position.x, b.position.z)
		if not rect.grow(4.0).has_point(p):
			continue
		for part in b.parts:
			if float(part.get("storefront", 0.0)) > 0.0:
				shops += 1
	return clampf(float(shops) / float(FULL_SHOPS), 0.0, 1.0) * (g - 1.0)


## The walker target multiplier of a BusyStreets entry `d` metres from the camera.
static func gain(entry: Array, d: float) -> float:
	if not enabled or entry.size() < 4:
		return 1.0
	return 1.0 + float(entry[3]) * (1.0 - smoothstep(NEAR, FAR, d))


static func _decide(ch: Node3D, block: Dictionary, g: float, state: Dictionary) -> void:
	var rect: Rect2 = block.rect
	var list: Array = ch.get_meta("busy_crowd", [])
	for entry: Array in list:
		if entry[0] != rect:
			continue
		if entry.size() < 4:
			entry.append(weight(ch, rect, g))
		state.entry = entry
		var e := BusyStreets.eye(ch.get_tree(), null)
		var at: Vector3 = e[0]
		var c := rect.get_center()
		var d := Vector2(c.x - at.x, c.y - at.z).length() - rect.size.length() * 0.35
		var factor := BusyStreets.crowd_factor(BusyStreets.hour_now(ch))
		state.extra = mini(MAX_EXTRA, roundi(int(entry[2]) * factor * (gain(entry, d) - 1.0)))
		return


static func _spawn(ch: Node3D, state: Dictionary, i: int) -> void:
	if i >= int(state.extra) or (state.entry as Array).is_empty():
		return
	var chunk := ch as CityChunk
	if chunk == null or not chunk._take_crowd_room(Encampment.walker_reserve(chunk.plan, chunk.ix, chunk.iz)):
		return
	var entry: Array = state.entry
	var rect: Rect2 = entry[0]
	var sidewalk: float = entry[1]
	var ped := Pedestrian.new()
	ped.setup(rect, sidewalk, hash([chunk.plan.seed, chunk.ix, chunk.iz, "shop_crowd", i]))
	FashionDistrict.walker(chunk, ped)
	var start := ped._random_ring_point(sidewalk)
	ped.position = Vector3(start.x, CityChunk.SIDEWALK_TOP + 0.1 + chunk._gy(start.x, start.y), start.y)
	chunk.add_child(ped)
	CrowdFlow.spawned(chunk, ped)
