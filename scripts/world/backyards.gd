class_name Backyards
extends RefCounted
## Backyard life in the suburbs and the beach town (2026-10-05): what people keep out back - a
## patio set under a market umbrella, the grill against the house (smoking at dinner time), string
## lights zig-zagging over the patio (lit after dark), loungers by the pool and floats on it, a
## trampoline on the lawn, the washing line, a citrus tree in the corner, a doghouse or a dog run,
## a toddler's slide and wagon left out (no children: the crowd has no child rigs).
##
## Laid on YardFill's back-yard plan (`_beach_lot()`'s lot plans: the frame, the house's extent, the
## pieces and their roles). `plan_lot()` is PURE: hashes of the seed and the lot, never a chunk,
## block or yard rng, and it keeps clear of what is already there without looking at the chunk -
## the house, the pool, the drive, the tree and shrubs YardFill may plant out back (`_plant_back()`:
## a tree at a back lawn's centre, shrubs along its long edge), ClimbingPlants' pergolas (worked out
## the way it works them out; a dining set goes under one) and the yard's fences. FULL chunks
## place everything (one MultiMesh batch per kind, the bigger pieces breakable props) and the
## chunk's string lights as ONE merged mesh; LOD chunks the umbrellas, the trampolines and the
## lights' glow, so the yards read from the air. Meshes: BackyardKit. `BACKYARDS=0` is the A/B.

## Off: no backyard life (BACKYARDS=0 in the environment).
static var enabled: bool = OS.get_environment("BACKYARDS") != "0"

## Shares (per lot with a back yard deep enough), suburbs / beach town.
const DINING_ODDS := [0.74, 0.62]
const TEAK_SHARE := 0.38
const UMBRELLA_ODDS := 0.62
const GRILL_ODDS := [0.62, 0.5]
const KETTLE_SHARE := 0.42
const LIGHTS_ODDS := [0.34, 0.46]
const LOUNGER_POOL_ODDS := 0.86
const LOUNGER_ODDS := 0.14
const FLOAT_ODDS := 0.78
const TRAMPOLINE_ODDS := [0.17, 0.08]
const LAUNDRY_ODDS := [0.13, 0.2]
const CITRUS_ODDS := [0.5, 0.38]
const CITRUS_TWO := 0.3
const DOG_RUN_ODDS := 0.07
const TOYS_ODDS := [0.12, 0.08]

## Kept clear of the yard's fences and the house (m).
const EDGE := 0.4
const HOUSE_GAP := 0.25
## Smallest back yard (m, house to back fence) worth furnishing.
const MIN_DEPTH := 2.4

## The house's eave, where string lights are hooked on (m over the yard), and the posts' tops.
const EAVE := 2.55
const POST_TOP := 2.86
const BULB_PITCH := 0.6
const LIGHT_SAG := 0.28

## Draw distances (m from the chunk's batch centre) and the shadows' (their stand-ins'); the kinds
## that cast one.
const NEAR_DRAW := 130.0
const BIG_DRAW := 260.0
const SHADOW_DISTANCE := 90.0
const SHADOWED := ["by_dining_metal", "by_dining_teak", "by_umbrella", "by_trampoline", "by_citrus_leaves", "by_citrus",
	"by_grill_gas", "by_grill_kettle", "by_loungers", "by_doghouse"]
const LOD_DRAW := 1400.0

## Paints (sRGB): powder coat; umbrella pads and grill enamel; floats; fruit; doghouses.
const FRAME_PAINTS := [Color(0.13, 0.12, 0.11), Color(0.9, 0.89, 0.86), Color(0.36, 0.3, 0.24), Color(0.22, 0.27, 0.24), Color(0.5, 0.5, 0.49)]
const ENAMEL := [Color(0.06, 0.06, 0.07), Color(0.6, 0.1, 0.09), Color(0.1, 0.25, 0.45), Color(0.15, 0.3, 0.2), Color(0.1, 0.1, 0.11)]
const PADS := [Color(0.1, 0.32, 0.62), Color(0.16, 0.48, 0.25), Color(0.08, 0.08, 0.09), Color(0.7, 0.14, 0.12)]
const FLOAT_PAINTS := [Color(0.95, 0.3, 0.45), Color(0.98, 0.62, 0.12), Color(0.15, 0.62, 0.86), Color(0.98, 0.85, 0.15), Color(0.3, 0.8, 0.55), Color(0.62, 0.35, 0.85)]
const FRUIT := [Color(0.97, 0.52, 0.06), Color(0.96, 0.84, 0.2), Color(0.98, 0.6, 0.1)]
const DOGHOUSE_PAINTS := [Color(0.62, 0.16, 0.12), Color(0.86, 0.85, 0.8), Color(0.3, 0.42, 0.55), Color(0.55, 0.45, 0.33)]
const GLOW_TINT := Color(1.0, 0.72, 0.42)

# Item footprints in the lot frame (u along the street, v back from it), metres.
const SIZE := {"dining_metal": Vector2(2.5, 2.5), "dining_teak": Vector2(3.3, 2.5), "grill_gas": Vector2(1.4, 0.75),
	"grill_kettle": Vector2(0.8, 0.8), "loungers": Vector2(2.3, 2.1), "trampoline": Vector2(3.95, 3.95),
	"laundry": Vector2(4.0, 1.1), "citrus": Vector2(2.1, 2.1), "doghouse": Vector2(1.6, 1.3), "dog_run": Vector2(2.5, 3.7),
	"toys": Vector2(2.7, 2.0)}


static func _h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) / 100003.0


# --- The plan (pure) ---------------------------------------------------------------------------------

## A lot plan's backyard: [{"kind", "at": Vector2 frame point, "yaw": radians turning the item's
## local +Z from the frame's +v, "size": footprint, ...}], plus for string lights {"kind": "lights",
## "runs": [[Vector3 frame point (u, height, v), Vector3]], "posts": [Vector2], "glow": Rect2}. Pure.
static func plan_lot(plan: CityPlan, lp: Dictionary, district: int) -> Array:
	var out: Array = []
	if lp.walk_front:
		return out
	var lot: Dictionary = lp.lot
	var key: int = lot.seed
	var s := plan.seed
	var f: Dictionary = lp.frame
	var U: float = f.U
	var V: float = f.V
	var bv1: float = lp.back
	var beach := 1 if district == CityPlan.District.BEACHTOWN else 0
	if V - bv1 < MIN_DEPTH or U < 4.0:
		return out
	var hu: Vector2 = lp.house_u
	var zone := Rect2(EDGE, bv1 + HOUSE_GAP, U - 2.0 * EDGE, V - bv1 - HOUSE_GAP - EDGE)
	var blocked: Array[Rect2] = []
	for r: Rect2 in lp.parts:
		blocked.append(YardFill._to_frame(f, r).grow(HOUSE_GAP))
	var drive: Rect2 = lp.drive
	if drive.size.x > 0.0:
		blocked.append(YardFill._to_frame(f, drive))
	var pool := Rect2()
	var pergola := Rect2()
	for pc: Array in lp.pieces:
		var r: Rect2 = pc[0]
		var role := String(pc[3])
		var q := YardFill._to_frame(f, r)
		if role == "pool":
			pool = q
			blocked.append(q.grow(0.35))
		elif role == "back" and int(pc[1]) == YardFill.G_LAWN and minf(r.size.x, r.size.y) >= 4.0:
			# YardFill's back-lawn tree (_plant_back: the piece's centre, a metre either way).
			var c := q.get_center()
			blocked.append(Rect2(c - Vector2(2.1, 2.1), Vector2(4.2, 4.2)))
		if role == "back" and minf(r.size.x, r.size.y) >= 2.0:
			# Its shrubs along the piece's long edge, 0.7 m in (world +z or +x end).
			var strip := Rect2(r.position.x, r.end.y - 1.5, r.size.x, 1.5) if r.size.x >= r.size.y else Rect2(r.end.x - 1.5, r.position.y, 1.5, r.size.y)
			blocked.append(YardFill._to_frame(f, strip))
		var pg := pergola_rect(plan, district, r, int(pc[1]))
		if pg.size.x > 0.0:
			var pq := YardFill._to_frame(f, pg)
			if role == "back" or role == "side" or role == "court":
				pergola = pq
			# Its four posts; under it stays free for a table.
			for corner: Vector2 in [pq.position, Vector2(pq.end.x, pq.position.y), pq.end, Vector2(pq.position.x, pq.end.y)]:
				blocked.append(Rect2(corner - Vector2(0.35, 0.35), Vector2(0.7, 0.7)))
			blocked.append(pq.grow(-0.0))
	var placed: Array[Rect2] = []
	var house_cu := clampf((hu.x + hu.y) * 0.5, zone.position.x + 1.2, zone.end.x - 1.2)
	# A dog in the back yard (DogYard's own roll) gets a doghouse, and no trampoline or toys.
	var odds: Dictionary = lp.get("odds", YardFill.BEACH)
	var roll := YardFill._h01([s, key, "edge"])
	var edged: bool = float(lp.front) >= 1.0 and roll < float(odds.edge_picket)
	var dog := DogYard.patch_for(plan, lp, edged)
	var back_dog := not dog.is_empty() and not bool(dog.front)

	# 1. The dining set, near the house (or under the pergola), maybe an umbrella through it.
	var dining := Vector2(-1, -1)
	if _h01([s, key, "by_dining"]) < float(DINING_ODDS[beach]):
		var kind := "dining_teak" if _h01([s, key, "by_teak"]) < TEAK_SHARE else "dining_metal"
		var sz: Vector2 = SIZE[kind]
		var at := Vector2(-1, -1)
		if pergola.size.x >= sz.x - 0.4 and pergola.size.y >= sz.y - 0.6 and zone.encloses(Rect2(pergola.get_center() - sz * 0.5, sz)):
			at = pergola.get_center()
		else:
			var free := blocked.duplicate()
			if pergola.size.x > 0.0:
				free.append(pergola)
			at = _find(zone, sz, free, placed, Vector2(house_cu, zone.position.y), Vector2(0.4, 1.0))
		if at.x >= 0.0:
			dining = at
			placed.append(Rect2(at - sz * 0.5, sz))
			var umb := pergola.size.x <= 0.0 or not pergola.has_point(at)
			umb = umb and _h01([s, key, "by_umbrella"]) < UMBRELLA_ODDS
			out.append({"kind": kind, "at": at, "yaw": (PI * 0.5 if kind == "dining_teak" and sz.x < sz.y else 0.0) + (_h01([s, key, "by_dyaw"]) - 0.5) * 0.12,
				"size": sz, "paint": FRAME_PAINTS[absi(hash([s, key, "by_frame"])) % FRAME_PAINTS.size()],
				"fabric": absi(hash([s, key, "by_fabric"])) % 8, "umbrella": umb,
				"canvas": float(absi(hash([s, key, "by_canvas"])) % 8) / 8.0 + (1.0 if _h01([s, key, "by_stripe"]) < 0.35 else 0.0)})
	# 2. The grill, against the house, near the table.
	if _h01([s, key, "by_grill"]) < float(GRILL_ODDS[beach]):
		var kind := "grill_kettle" if _h01([s, key, "by_kettle"]) < KETTLE_SHARE else "grill_gas"
		var sz: Vector2 = SIZE[kind]
		var near := dining if dining.x >= 0.0 else Vector2(house_cu, zone.position.y)
		var side := 1.0 if _h01([s, key, "by_gside"]) < 0.5 else -1.0
		var at := _find(zone, sz, blocked, placed, Vector2(near.x + side * 2.3, zone.position.y), Vector2(0.6, 1.5))
		if at.x >= 0.0:
			placed.append(Rect2(at - sz * 0.5, sz))
			out.append({"kind": kind, "at": at, "yaw": PI, "size": sz,
				"paint": ENAMEL[absi(hash([s, key, "by_enamel"])) % ENAMEL.size()], "seed": _h01([s, key, "by_cook"])})
	# 3. Loungers by the pool (feet toward it), floats on it.
	if pool.size.x > 0.0:
		if _h01([s, key, "by_lounge"]) < LOUNGER_POOL_ODDS:
			var sz: Vector2 = SIZE.loungers
			var pc := pool.get_center()
			# Beside the pool, on the side nearest the house first, then the others.
			var at := Vector2(-1, -1)
			var g := 0.55
			for c: Vector2 in [Vector2(pc.x, pool.position.y - g - sz.y * 0.5), Vector2(pool.position.x - g - sz.x * 0.5, pc.y),
					Vector2(pool.end.x + g + sz.x * 0.5, pc.y), Vector2(pc.x, pool.end.y + g + sz.y * 0.5)]:
				var r := Rect2(c - sz * 0.5, sz)
				if zone.encloses(r) and _free(r, blocked, placed):
					at = c
					break
			if at.x >= 0.0:
				placed.append(Rect2(at - sz * 0.5, sz))
				# Feet (local -Z) toward the pool: the nearest axis direction of the frame.
				var to := pc - at
				var face := Vector2(0.0, signf(to.y)) if absf(to.y) >= absf(to.x) else Vector2(signf(to.x), 0.0)
				out.append({"kind": "loungers", "at": at, "yaw": 0.0, "face": face, "size": sz,
					"paint": FRAME_PAINTS[absi(hash([s, key, "by_lframe"])) % FRAME_PAINTS.size()],
					"fabric": absi(hash([s, key, "by_lfabric"])) % 8})
		if _h01([s, key, "by_floats"]) < FLOAT_ODDS:
			var n := 1 + int(_h01([s, key, "by_nfloat"]) * 2.99)
			var kinds := ["float_ring", "float_mat", "float_ball"]
			for i in n:
				var k: String = kinds[absi(hash([s, key, "by_fk", i])) % 3]
				var m := 0.75 if k != "float_mat" else 1.0
				var inner := pool.grow(-m)
				if inner.size.x <= 0.0 or inner.size.y <= 0.0:
					continue
				var p := inner.position + Vector2(_h01([s, key, "by_fu", i]), _h01([s, key, "by_fv", i])) * inner.size
				out.append({"kind": k, "at": p, "yaw": _h01([s, key, "by_fy", i]) * TAU, "size": Vector2(1, 1),
					"paint": FLOAT_PAINTS[absi(hash([s, key, "by_fp", i])) % FLOAT_PAINTS.size()]})
	elif _h01([s, key, "by_lounge"]) < LOUNGER_ODDS:
		var sz: Vector2 = SIZE.loungers
		var at := _find(zone, sz, blocked, placed, zone.get_center(), Vector2(0.2, 1.0))
		if at.x >= 0.0:
			placed.append(Rect2(at - sz * 0.5, sz))
			out.append({"kind": "loungers", "at": at, "yaw": 0.0, "size": sz,
				"paint": FRAME_PAINTS[absi(hash([s, key, "by_lframe"])) % FRAME_PAINTS.size()], "fabric": absi(hash([s, key, "by_lfabric"])) % 8})
	# 4. String lights over the dining set: hooked on the house, out to two posts.
	if dining.x >= 0.0 and (pergola.size.x <= 0.0 or not pergola.has_point(dining)) and _h01([s, key, "by_lights"]) < float(LIGHTS_ODDS[beach]):
		var lt := _lights(f, lp, zone, dining, blocked)
		if not lt.is_empty():
			out.append(lt)
	# 5. A dog: its house in the patch's back corner; or a dog run.
	if back_dog:
		var sz: Vector2 = SIZE.doghouse
		var at := _find(zone, sz, blocked, placed, Vector2(zone.end.x if _h01([s, key, "by_dside"]) < 0.5 else zone.position.x, zone.end.y), Vector2(0.5, 1.0))
		if at.x >= 0.0:
			placed.append(Rect2(at - sz * 0.5, sz))
			out.append({"kind": "doghouse", "at": at, "yaw": 0.0, "size": sz,
				"paint": DOGHOUSE_PAINTS[absi(hash([s, key, "by_dh"])) % DOGHOUSE_PAINTS.size()]})
	elif _h01([s, key, "by_dogrun"]) < DOG_RUN_ODDS:
		var sz: Vector2 = SIZE.dog_run
		var at := _find(zone, sz, blocked, placed, Vector2(zone.end.x if _h01([s, key, "by_dside"]) < 0.5 else zone.position.x, zone.end.y), Vector2(0.5, 1.0))
		if at.x >= 0.0:
			placed.append(Rect2(at - sz * 0.5, sz))
			out.append({"kind": "dog_run", "at": at, "yaw": 0.0, "size": sz,
				"paint": DOGHOUSE_PAINTS[absi(hash([s, key, "by_dh"])) % DOGHOUSE_PAINTS.size()]})
	# 6. A trampoline on the lawn, toward the back.
	if not back_dog and pool.size.x <= 0.0 and _h01([s, key, "by_tramp"]) < float(TRAMPOLINE_ODDS[beach]):
		var sz: Vector2 = SIZE.trampoline
		var at := _find(zone, sz, blocked, placed, Vector2(zone.get_center().x, zone.end.y), Vector2(0.15, 1.0))
		if at.x >= 0.0:
			placed.append(Rect2(at - sz * 0.5, sz))
			out.append({"kind": "trampoline", "at": at, "yaw": _h01([s, key, "by_ty"]) * TAU, "size": sz,
				"paint": PADS[absi(hash([s, key, "by_pad"])) % PADS.size()]})
	# 7. Citrus in the back corners.
	if _h01([s, key, "by_citrus"]) < float(CITRUS_ODDS[beach]):
		var n := 2 if _h01([s, key, "by_citrus2"]) < CITRUS_TWO else 1
		var fruit: Color = FRUIT[absi(hash([s, key, "by_fruit"])) % FRUIT.size()]
		for i in n:
			var sz: Vector2 = SIZE.citrus
			var side := 1.0 if (i == 0) == (_h01([s, key, "by_cside"]) < 0.5) else -1.0
			var at := _find(zone, sz, blocked, placed, Vector2(zone.end.x if side > 0.0 else zone.position.x, zone.end.y), Vector2(1.0, 1.0))
			if at.x >= 0.0:
				placed.append(Rect2(at - sz * 0.5, sz))
				out.append({"kind": "citrus", "at": at, "yaw": _h01([s, key, "by_cy", i]) * TAU, "size": sz, "paint": fruit,
					"scale": lerpf(0.82, 1.12, _h01([s, key, "by_cs", i]))})
	# 8. The washing line, along the back fence or down a side.
	if _h01([s, key, "by_laundry"]) < float(LAUNDRY_ODDS[beach]):
		var sz: Vector2 = SIZE.laundry
		var at := _find(zone, sz, blocked, placed, Vector2(zone.get_center().x, zone.end.y), Vector2(0.1, 1.0))
		var yaw := 0.0
		if at.x < 0.0:
			sz = Vector2(sz.y, sz.x)
			yaw = PI * 0.5
			at = _find(zone, sz, blocked, placed, Vector2(zone.end.x if _h01([s, key, "by_lside"]) < 0.5 else zone.position.x, zone.end.y), Vector2(1.0, 0.2))
		if at.x >= 0.0:
			placed.append(Rect2(at - sz * 0.5, sz))
			out.append({"kind": "laundry", "at": at, "yaw": yaw, "size": sz, "seed": _h01([s, key, "by_wash"])})
	# 9. Toys left out on the lawn.
	if not back_dog and pool.size.x <= 0.0 and _h01([s, key, "by_toys"]) < float(TOYS_ODDS[beach]):
		var sz: Vector2 = SIZE.toys
		var at := _find(zone, sz, blocked, placed, zone.get_center(), Vector2(0.3, 1.0))
		if at.x >= 0.0:
			placed.append(Rect2(at - sz * 0.5, sz))
			out.append({"kind": "toys", "at": at, "yaw": _h01([s, key, "by_toyy"]) * TAU, "size": sz,
				"paint": FLOAT_PAINTS[absi(hash([s, key, "by_ball"])) % FLOAT_PAINTS.size()]})
	return out


## ClimbingPlants' pergola over a deck or patio ground piece, worked out as it works it out
## (ClimbingPlants._pergola: the same rng and the same first roll), or an empty Rect2.
static func pergola_rect(plan: CityPlan, district: int, r: Rect2, kind: int) -> Rect2:
	if not ClimbingPlants.enabled or not (kind == YardFill.G_DECK or kind == YardFill.G_TILE):
		return Rect2()
	if r.size.x < ClimbingPlants.PERGOLA_MIN.x or r.size.y < ClimbingPlants.PERGOLA_MIN.y:
		return Rect2()
	var share := float(ClimbingPlants.DISTRICT_SHARE[district])
	if share <= 0.0:
		return Rect2()
	var rng := ClimbingPlants._rng([plan.seed, "climb_pergola", roundi(r.position.x * 10.0), roundi(r.position.y * 10.0)])
	if rng.randf() >= ClimbingPlants.PERGOLA_ODDS * share:
		return Rect2()
	return Rect2(r.position + Vector2(0.4, 0.4), Vector2(minf(r.size.x - 0.8, 5.5), minf(r.size.y - 0.8, 4.5)))


## The free spot nearest `target` (distance weighted per axis by `wt`, lower is better) for a
## `size` footprint inside `zone`, on a lattice of at most 16 x 16, clear of `blocked` and
## `placed`; (-1, -1) when there is none.
static func _find(zone: Rect2, size: Vector2, blocked: Array[Rect2], placed: Array[Rect2], target: Vector2, wt: Vector2) -> Vector2:
	var half := size * 0.5
	var lo := zone.position + half
	var hi := zone.end - half
	if hi.x < lo.x or hi.y < lo.y:
		return Vector2(-1, -1)
	var nx := clampi(int((hi.x - lo.x) / 0.4) + 1, 1, 16)
	var ny := clampi(int((hi.y - lo.y) / 0.4) + 1, 1, 16)
	var best := Vector2(-1, -1)
	var best_s := INF
	for j in ny:
		var y := lo.y + (hi.y - lo.y) * (float(j) / float(maxi(ny - 1, 1)))
		for i in nx:
			var x := lo.x + (hi.x - lo.x) * (float(i) / float(maxi(nx - 1, 1)))
			var sc := wt.x * absf(x - target.x) + wt.y * absf(y - target.y)
			if sc >= best_s:
				continue
			var r := Rect2(Vector2(x, y) - half, size)
			if _free(r, blocked, placed):
				best = Vector2(x, y)
				best_s = sc
	return best


static func _free(r: Rect2, blocked: Array[Rect2], placed: Array[Rect2]) -> bool:
	for b: Rect2 in blocked:
		if r.intersects(b):
			return false
	for b: Rect2 in placed:
		if r.intersects(b):
			return false
	return true


static func _rect_distance(a: Rect2, b: Rect2) -> float:
	var dx := maxf(0.0, maxf(b.position.x - a.end.x, a.position.x - b.end.x))
	var dy := maxf(0.0, maxf(b.position.y - a.end.y, a.position.y - b.end.y))
	return sqrt(dx * dx + dy * dy)


## String lights over the dining set: three hooks on the house's back wall (where a part of the
## house stands behind them; a post where none does) and two posts beyond the table, the runs
## zig-zagging between the lines.
static func _lights(f: Dictionary, lp: Dictionary, zone: Rect2, dining: Vector2, blocked: Array[Rect2]) -> Dictionary:
	var u0 := clampf(dining.x - 2.0, zone.position.x, zone.end.x)
	var u1 := clampf(dining.x + 2.0, zone.position.x, zone.end.x)
	if u1 - u0 < 2.5:
		return {}
	var v_house := float(lp.back) + 0.05
	var v_post := minf(dining.y + 1.9, zone.end.y - 0.1)
	if v_post - v_house < 2.2:
		return {}
	for p: Vector2 in [Vector2(u0, v_post), Vector2(u1, v_post)]:
		for b: Rect2 in blocked:
			if b.grow(-0.2).has_point(p):
				return {}
	var hooks: Array = []
	var posts: Array = []
	for u: float in [u0, (u0 + u1) * 0.5, u1]:
		var on_house := false
		for r: Rect2 in lp.parts:
			var q := YardFill._to_frame(f, r)
			if u >= q.position.x + 0.1 and u <= q.end.x - 0.1 and absf(q.end.y - float(lp.back)) < 0.6:
				on_house = true
				v_house = minf(v_house, q.end.y + 0.05)
		if on_house:
			hooks.append(Vector3(u, EAVE, v_house))
		else:
			var pv := float(lp.back) + 0.35
			hooks.append(Vector3(u, POST_TOP - 0.06, pv))
			posts.append(Vector2(u, pv))
	var far := [Vector3(u0, POST_TOP - 0.06, v_post), Vector3(u1, POST_TOP - 0.06, v_post)]
	posts.append(Vector2(u0, v_post))
	posts.append(Vector2(u1, v_post))
	var runs := [[hooks[0], far[0]], [far[0], hooks[1]], [hooks[1], far[1]], [far[1], hooks[2]], [far[0], far[1]]]
	return {"kind": "lights", "runs": runs, "posts": posts, "glow": Rect2(u0, v_house, u1 - u0, v_post - v_house)}


# --- Building -----------------------------------------------------------------------------------------

## From YardFill._build_beach, once its yards are planned (FULL: after its own dressing jobs are
## queued; LOD: before it returns). The far city's capture gets nothing.
static func block(ch: CityChunk, bp: Dictionary) -> void:
	if not enabled or ch.capturing:
		return
	var district := int(ch.plan.block(ch.ix, ch.iz).district)
	if ch.level == CityChunk.Level.FULL:
		# A job a lot (time-sliced with YardFill's own dressing), then the chunk's lights mesh.
		var st := {"lights": BackyardKit.G.new(), "counts": {}}
		(st.lights as BackyardKit.G).use_custom = true
		var jobs: Array[Callable] = []
		for lp: Dictionary in bp.lots:
			jobs.append(_build_lot.bind(ch, lp, district, st))
		jobs.append(_finish_full.bind(ch, st))
		YardFill._defer(ch, jobs)
	else:
		_build_lod(ch, bp, district)


static func _yard_top(ch: CityChunk, lp: Dictionary, district: int, at: Vector2, on_water: bool = false) -> float:
	# The suburbs lay their paving a little over the block's lawn (YardFill.PATH_LIFT); the pool's
	# water is its ground piece's top.
	if district != CityPlan.District.SUBURBS:
		return CityChunk.SIDEWALK_TOP + YardFill.LIFT
	if on_water:
		return CityChunk.SIDEWALK_TOP + YardFill.PATH_LIFT
	var w := YardFill._fp(lp.frame, at.x, at.y)
	for pc: Array in lp.pieces:
		if (pc[0] as Rect2).has_point(w):
			return CityChunk.SIDEWALK_TOP + (YardFill.LIFT if int(pc[1]) == YardFill.G_LAWN else YardFill.PATH_LIFT)
	return CityChunk.SIDEWALK_TOP + YardFill.LIFT


## An item's transform: its local +Z along the frame's +v turned by `yaw`, or, given `face` (a frame
## direction), its local -Z toward that (the frames of a block's two sides are mirror images, so a
## turn by a quarter is not the same way round in both).
static func _xf(f: Dictionary, at: Vector2, yaw: float, y: float, scale: float = 1.0, face: Vector2 = Vector2.ZERO) -> Transform3D:
	var p := YardFill._fp(f, at.x, at.y)
	var v: Vector2 = f.v
	var a := atan2(v.x, v.y) + yaw
	if face != Vector2.ZERO:
		var d: Vector2 = (f.u as Vector2) * face.x + v * face.y
		a = atan2(-d.x, -d.y)
	return Transform3D(Basis(Vector3.UP, a).scaled(Vector3.ONE * scale), Vector3(p.x, y, p.y))


static func _build_lot(ch: CityChunk, lp: Dictionary, district: int, st: Dictionary) -> void:
	var lights: BackyardKit.G = st.lights
	var counts: Dictionary = st.counts
	if true:
		var f: Dictionary = lp.frame
		for it: Dictionary in plan_lot(ch.plan, lp, district):
			var kind := String(it.kind)
			counts[kind] = int(counts.get(kind, 0)) + 1
			if kind == "lights":
				_add_lights(ch, lp, district, it, lights)
				continue
			var at: Vector2 = it.at
			var water := kind.begins_with("float")
			var y := _yard_top(ch, lp, district, at, water)
			var xf := _xf(f, at, float(it.yaw), y, float(it.get("scale", 1.0)), it.get("face", Vector2.ZERO))
			var paint: Color = it.get("paint", Color.WHITE)
			var mesh := BackyardKit.get_mesh(kind)
			var bk := "by_" + kind
			match kind:
				"dining_metal", "dining_teak":
					var inst := [[bk, mesh, xf, Color.WHITE, Color(paint.r, paint.g, paint.b, float(it.fabric) / 8.0 + 0.01)]]
					if it.umbrella:
						inst.append(["by_umbrella", BackyardKit.get_mesh("umbrella"), xf, Color.WHITE, Color(0.2, 0.2, 0.2, float(it.canvas) + 0.01)])
					_prop(ch, "patio", xf, paint, inst, Vector3(1.4 if kind == "dining_metal" else 1.9, 0.78, 1.4 if kind == "dining_metal" else 1.0))
				"grill_gas", "grill_kettle":
					var cust := Color(paint.r, paint.g, paint.b, float(it.seed))
					_prop(ch, "grill", xf, paint, [[bk, mesh, xf, Color.WHITE, cust], ["by_smoke", BackyardKit.get_mesh("smoke"), xf, Color.WHITE, cust]],
						Vector3(1.2 if kind == "grill_gas" else 0.6, 1.1, 0.6))
				"loungers":
					_prop(ch, "patio", xf, paint, [[bk, mesh, xf, Color.WHITE, Color(paint.r, paint.g, paint.b, float(it.fabric) / 8.0 + 0.01)]], Vector3(2.1, 0.5, 2.0))
				"trampoline":
					_prop(ch, "trampoline", xf, paint, [[bk, mesh, xf, Color.WHITE, Color(paint.r, paint.g, paint.b, 0.0)]], Vector3(3.6, 0.92, 3.6))
				"doghouse":
					_prop(ch, "doghouse", xf, paint, [[bk, mesh, xf, Color.WHITE, Color(paint.r, paint.g, paint.b, 0.0)]], Vector3(0.9, 1.0, 1.1))
				"dog_run":
					# The pen, and the house at its back end, its door toward the gate.
					var hx := xf * Transform3D(Basis(), Vector3(0, 0, 1.05))
					ch._batch.add(bk, mesh, xf)
					_prop(ch, "doghouse", hx, paint, [["by_doghouse", BackyardKit.get_mesh("doghouse"), hx, Color.WHITE, Color(paint.r, paint.g, paint.b, 0.0)]], Vector3(0.9, 1.0, 1.1))
				"citrus":
					ch._batch.add("by_citrus", mesh, xf, Color.WHITE, Color(paint.r, paint.g, paint.b, 0.0))
					ch._batch.add("by_citrus_leaves", BackyardKit.get_mesh("citrus_leaves"), xf)
				"laundry":
					ch._batch.add(bk, mesh, xf, Color.WHITE, Color(1, 1, 1, float(it.seed)))
				"toys":
					ch._batch.add(bk, mesh, xf, Color.WHITE, Color(paint.r, paint.g, paint.b, 0.0))
				_:
					ch._batch.add(bk, mesh, xf, Color.WHITE, Color(paint.r, paint.g, paint.b, 0.0))


static func _finish_full(ch: CityChunk, st: Dictionary) -> void:
	var lights: BackyardKit.G = st.lights
	for key: String in ch._batch.keys():
		if not key.begins_with("by_"):
			continue
		var big := key in ["by_umbrella", "by_trampoline", "by_citrus_leaves", "by_citrus", "by_smoke", "by_dining_metal", "by_dining_teak", "by_glow"]
		ch._batch.set_draw_distance(key, BIG_DRAW if big else NEAR_DRAW)
		# The small things cast nothing; the rest from their stand-ins (BackyardKit), not far.
		if key in SHADOWED:
			ch._batch.set_shadow_distance(key, SHADOW_DISTANCE)
		else:
			ch._batch.set_no_shadow(key)
	if lights.tris() > 0:
		var mi := MeshInstance3D.new()
		mi.name = "BackyardLights"
		mi.mesh = lights.mesh(BackyardKit.material())
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = NEAR_DRAW + 80.0
		mi.visibility_range_end_margin = 20.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		ch.add_child(mi)
	ch.set_meta("backyards", st.counts)


## A breakable prop: the instances and one box (`size`, its foot at the item's origin).
static func _prop(ch: CityChunk, kind: String, xf: Transform3D, color: Color, inst: Array, size: Vector3) -> void:
	var at := xf.origin
	var yaw := xf.basis.get_euler().y
	ch._add_prop(kind, at, color, inst, [[size, at + Vector3(0, size.y * 0.5, 0), yaw]])


static func _add_lights(ch: CityChunk, lp: Dictionary, district: int, it: Dictionary, g: BackyardKit.G) -> void:
	var f: Dictionary = lp.frame
	var base := _yard_top(ch, lp, district, (it.glow as Rect2).get_center())
	var post := BackyardKit.get_mesh("post")
	for p: Vector2 in it.posts:
		ch._batch.add("by_post", post, _xf(f, p, 0.0, _yard_top(ch, lp, district, p)))
	for run: Array in it.runs:
		var a: Vector3 = run[0]
		var b: Vector3 = run[1]
		var wa := YardFill._fp(f, a.x, a.z)
		var wb := YardFill._fp(f, b.x, b.z)
		# Merged into a chunk mesh, so the relief is added here (the batch adds it to instances).
		var pa := Vector3(wa.x, base + a.y + ch._gy(wa.x, wa.y), wa.y)
		var pb := Vector3(wb.x, base + b.y + ch._gy(wb.x, wb.y), wb.y)
		BackyardKit.string_run(g, pa, pb, LIGHT_SAG, BULB_PITCH)
	_glow(ch, f, it.glow, base)


## The warm light the string lights throw on the patio after dark (an additive pool, lamp_factor).
static func _glow(ch: CityChunk, f: Dictionary, r: Rect2, base: float) -> void:
	var c := YardFill._fp(f, r.get_center().x, r.get_center().y)
	var size := maxf(r.size.x, r.size.y) * 1.8
	var xf := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(size, 1.0, size)), Vector3(c.x, base + 0.04, c.y))
	ch._batch.add("by_glow", PropFactory.light_pool(GLOW_TINT, 1.5), xf)


## LOD chunks: what reads from the air - umbrellas, trampolines, the lights' glow - as cheap meshes.
static func _build_lod(ch: CityChunk, bp: Dictionary, district: int) -> void:
	for lp: Dictionary in bp.lots:
		var f: Dictionary = lp.frame
		for it: Dictionary in plan_lot(ch.plan, lp, district):
			var kind := String(it.kind)
			if kind == "lights":
				_glow(ch, f, it.glow, _yard_top(ch, lp, district, (it.glow as Rect2).get_center()))
				continue
			var paint: Color = it.get("paint", Color.WHITE)
			if kind.begins_with("dining") and it.umbrella:
				var xf := _xf(f, it.at, float(it.yaw), _yard_top(ch, lp, district, it.at))
				ch._batch.add("by_umbrella_lod", BackyardKit.get_mesh("umbrella_lod"), xf, Color.WHITE, Color(0.2, 0.2, 0.2, float(it.canvas) + 0.01))
			elif kind == "trampoline":
				var xf := _xf(f, it.at, float(it.yaw), _yard_top(ch, lp, district, it.at))
				ch._batch.add("by_trampoline_lod", BackyardKit.get_mesh("trampoline_lod"), xf, Color.WHITE, Color(paint.r, paint.g, paint.b, 0.0))
	for key: String in ["by_umbrella_lod", "by_trampoline_lod", "by_glow"]:
		ch._batch.set_no_shadow(key)
		ch._batch.set_draw_distance(key, LOD_DRAW)
