class_name YardSales
extends RefCounted
## Weekend yard sales in the suburbs and the beach town (2026-10-30): a household puts its stuff out
## on the front lawn and the driveway - six-foot folding tables of boxes, lamps, dishes and books,
## a card table, a rolling rack of clothes, the old sofa, a bike on its stand, stacks of boxes, a
## floor lamp - with a hand-lettered poster board and balloons at the kerb, cardboard signs taped to
## the poles at the block's corners pointing the way, the seller behind a table and neighbours
## browsing along the front of the tables. After it closes a FREE box is left at the kerb.
##
## WHO and WHEN are worked out, never placed: a hash of seed + lot says whether a house holds one
## (`ODDS` per district) and on which weekend day(s) (`DAYS`: Saturday, Sunday or both), and its
## hours (`HOURS`, shifted per sale). The chunk builds what is there at the hour and day it is
## built at (FarmersMarket.hour_now() / weekday(), the city's clock; the game starts on a
## Saturday); rain calls it off. `force_day` / `force_hour` for tests and stills, YARD_SALE=all in
## the environment makes every candidate lot hold one today.
##
## WHERE is YardFill's plan of the front yard and the house (`_beach_lot()`'s lot plans: the frame,
## the house front, the drive, the front pieces): `plan_lot()` is PURE (hashes of the seed and the
## lot, never a chunk, block or yard rng) and lays the sale out as one ROW of things parallel to the
## street with an aisle in front of it (the street side) and the seller behind, keeping clear of the
## house, the front walk and its cypresses, the trees YardFill plants on a big front lawn (the
## piece's centre), a car in the drive (YardFill's own hash), decomposed granite and beds (planted),
## the street line's wall or hedge, and a dog in the front garden (DogYard's own roll: no sale).
## Hooked from YardFill._build_beach() after Backyards (one line each), FULL chunks only, as
## deferred jobs: everything is knockable (EncampmentItem: shot or hit, a table goes over as a real
## body and stays gone). Meshes: YardSaleKit. People: StreetVendor (the seller), YardSaleBrowser.
## `YARD_SALES=0` is the A/B.

## Off: no yard sales (YARD_SALES=0 in the environment).
static var enabled: bool = OS.get_environment("YARD_SALES") != "0"
## Every candidate lot holds one, today (YARD_SALE=all in the environment, or a test).
static var force_all: bool = OS.get_environment("YARD_SALE") == "all"
## Tests and stills: the hour and the weekday (0 Sunday .. 6 Saturday) to build for (-1: the clock).
static var force_hour: float = -1.0
static var force_day: int = -1

enum State { NONE, SETUP, OPEN, LEFTOVER }

## Share of house lots holding a sale on a weekend: suburbs, beach town.
const ODDS := {CityPlan.District.SUBURBS: 0.075, CityPlan.District.BEACHTOWN: 0.035}
## Cumulative odds of the sale's days: Saturday only, Sunday only, else both.
const DAYS := [0.58, 0.72]
## [setup from, open, close, leftovers gone] hours; open and close shifted by up to HOURS_JITTER.
const HOURS := [6.7, 7.5, 14.0, 18.5]
const HOURS_JITTER := 0.75
## Most sales a chunk builds, browsers a sale and a chunk spawns (each in the crowd cap).
const MAX_PER_CHUNK := 3
const MAX_BROWSERS := 4
const MAX_CHUNK_BROWSERS := 9
## Busiest early (the bargain hunters come at opening): [hour, share of MAX_BROWSERS].
const BUSY_KEYS := [[7.0, 0.3], [7.8, 1.0], [10.0, 0.9], [12.5, 0.5], [15.0, 0.2]]

## The row: how deep the yard must be (house front from the street line), the aisle's width in
## front of the row, the street line kept clear (its wall or hedge; less with nothing there), the
## gap between things. A yard too shallow for an aisle in it puts its row at the front and the
## browsers on the pavement (PAVEMENT_AISLE: v < 0 is the pavement in the lot's frame), as
## shallow LA front yards do - unless a wall or hedge stands on the street line.
const MIN_FRONT := 2.3
const AISLE := 1.1
const STREET_KEEP := 0.75
const OPEN_KEEP := 0.4
const PAVEMENT_AISLE := -1.0
const PAVEMENT_QUEUE := -0.55
const STAKE_V := -0.35
const GAP := Vector2(0.35, 0.8)
const SELLER_BACK := 0.75
## Clear of the house and its porch, the front walk (and the cypresses either side of it), a big
## front lawn's tree at its centre (YardFill._plant_front: lawns at least 3.6 m on their short side).
const HOUSE_GAP := 0.5
const PATH_GAP := 0.9
const TREE_CLEAR := 1.5
const TREE_LAWN := 3.6
## Corner signs: a pole within this of a block corner gets one; how many corners a sale signs.
const CORNER_REACH := 16.0
const MAX_CORNERS := 2
## The pole radii at sign height (utility pole, street lamp) and the sign's height on the pole.
const POLE_R := {"upole": 0.155, "lamp": 0.095}
const SIGN_Y := 1.75
## Draw distances (m from a batch's centre) and shadows.
const DRAW := 150.0
const SIGN_DRAW := 120.0
const SHADOW_REACH := 45.0

## The things in the row, their footprint (u along the row, depth across it) and how many of each a
## sale may have ([min, max]); mesh kinds in YardSaleKit.
const ITEMS := {
	"table6": {"size": Vector2(1.83, 0.76), "count": [1, 2], "goods": true, "mass": 14.0, "box": Vector3(1.83, 0.95, 0.76)},
	"card": {"size": Vector2(0.86, 0.86), "count": [0, 1], "goods": true, "mass": 6.0, "box": Vector3(0.86, 0.9, 0.86)},
	"rack": {"size": Vector2(1.5, 0.56), "count": [0, 1], "mass": 9.0, "box": Vector3(1.5, 1.6, 0.56)},
	"sofa": {"size": Vector2(2.05, 0.9), "count": [0, 1], "mass": 45.0, "box": Vector3(2.05, 0.85, 0.9)},
	"bike": {"size": Vector2(1.75, 0.55), "count": [0, 1], "mass": 14.0, "box": Vector3(1.75, 1.0, 0.45)},
	"boxes": {"size": Vector2(0.95, 0.62), "count": [1, 2], "mass": 10.0, "box": Vector3(0.95, 0.75, 0.62)},
	"floor_lamp": {"size": Vector2(0.45, 0.45), "count": [0, 1], "mass": 4.0, "box": Vector3(0.4, 1.6, 0.4)},
}
## Shares of the optional ones.
const ITEM_ODDS := {"card": 0.55, "rack": 0.62, "sofa": 0.32, "bike": 0.42, "floor_lamp": 0.45, "table6": 0.45, "boxes": 0.5}
## The headline on the signs (cumulative odds) and the days line.
const HEADLINES := ["YARD SALE", "GARAGE SALE", "MOVING SALE", "MULTI FAMILY SALE"]
const HEADLINE_ODDS := [0.55, 0.8, 0.92]


static func _h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) / 100003.0


# --- Who, when (pure) ---------------------------------------------------------------------------

## The sale a lot would hold, or {}: {"days": [weekdays], "hours": [4], "headline", "days_text",
## "ink" (0..3), "board" (0..3)}. Pure.
static func sale_info(plan: CityPlan, key: int, district: int) -> Dictionary:
	if not ODDS.has(district):
		return {}
	var s := plan.seed
	if not force_all and _h01([s, key, "ys_sale"]) >= float(ODDS[district]):
		return {}
	var dr := _h01([s, key, "ys_days"])
	var days: Array = [6] if dr < float(DAYS[0]) else ([0] if dr < float(DAYS[1]) else [6, 0])
	var jo := (_h01([s, key, "ys_open"]) - 0.5) * 2.0 * HOURS_JITTER
	var jc := (_h01([s, key, "ys_close"]) - 0.5) * 2.0 * HOURS_JITTER
	var hours := [float(HOURS[0]) + jo, float(HOURS[1]) + jo, float(HOURS[2]) + jc, float(HOURS[3])]
	var hr := _h01([s, key, "ys_head"])
	var head := 3
	for i in HEADLINE_ODDS.size():
		if hr < float(HEADLINE_ODDS[i]):
			head = i
			break
	var o := int(round(hours[1]))
	var c := int(round(hours[2]))
	var day_names := "SAT" if days == [6] else ("SUN" if days == [0] else "SAT SUN")
	var days_text := "%s %d-%d" % [day_names, o, c - 12 if c > 12 else c]
	return {"days": days, "hours": hours, "headline": HEADLINES[head], "days_text": days_text,
		"ink": absi(hash([s, key, "ys_ink"])) % 4, "board": absi(hash([s, key, "ys_board"])) % 4}


## The state of a sale at `hour` of weekday `day` (State).
static func state_at(info: Dictionary, day: int, hour: float) -> int:
	if info.is_empty():
		return State.NONE
	if not force_all and not (info.days as Array).has(day):
		return State.NONE
	var h: Array = info.hours
	if hour < float(h[0]) or hour >= float(h[3]):
		return State.NONE
	if hour < float(h[1]):
		return State.SETUP
	if hour < float(h[2]):
		return State.OPEN
	# The last day's leftovers; a two-day sale packs away on Saturday night.
	if (info.days as Array).size() > 1 and day == 6 and not force_all:
		return State.NONE
	return State.LEFTOVER


## How many browsers an open sale has at `hour` (0..MAX_BROWSERS).
static func browsers_at(hour: float, key_share: float) -> int:
	var keys: Array = BUSY_KEYS
	var b := 0.0
	if hour > float(keys[0][0]) and hour < float(keys[keys.size() - 1][0]):
		for i in range(1, keys.size()):
			if hour <= float(keys[i][0]):
				var a: Array = keys[i - 1]
				var c: Array = keys[i]
				b = lerpf(float(a[1]), float(c[1]), (hour - float(a[0])) / (float(c[0]) - float(a[0])))
				break
	return clampi(int(round(b * float(MAX_BROWSERS) * (0.6 + 0.6 * key_share))), 0, MAX_BROWSERS)


static func hour_now(node: Node) -> float:
	return force_hour if force_hour >= 0.0 else FarmersMarket.hour_now(node)


static func weekday(node: Node) -> int:
	return force_day if force_day >= 0 else FarmersMarket.weekday(node)


## Rain or a storm calls a sale off (the Weather node's state; none: dry).
static func rained_off(node: Node) -> bool:
	if force_all or force_day >= 0:
		return false
	var tree := node.get_tree() if node and node.is_inside_tree() else (Engine.get_main_loop() as SceneTree)
	var scene := tree.current_scene if tree else null
	var w := scene.get_node_or_null("Weather") if scene else null
	if w == null or w.get("state") == null:
		return false
	var st := int(w.get("state"))
	return st == 2 or st == 3


# --- Where (pure) -------------------------------------------------------------------------------

## The sale a lot plan holds at (`day`, `hour`), laid out, or {}: {"state", "info", "items":
## [{"kind", "at": frame point, "size", "variant", "paint", "seed"}], "aisle": [Vector2, Vector2]
## (frame points), "row_v", "seller": Vector2, "stake": Vector2, "free_box": Vector2, "queue":
## [frame points in front of the tables], "browsers": int}. Pure.
static func plan_lot(plan: CityPlan, lp: Dictionary, district: int, day: int, hour: float) -> Dictionary:
	if lp.get("walk_front", false):
		return {}
	var lot: Dictionary = lp.lot
	var key: int = lot.seed
	var info := sale_info(plan, key, district)
	var state := state_at(info, day, hour)
	if state == State.NONE:
		return {}
	var s := plan.seed
	var f: Dictionary = lp.frame
	var U: float = f.U
	var fd: float = lp.front
	if fd < MIN_FRONT or U < 6.0:
		return {}
	# A dog in the front garden (DogYard's own roll): no sale there.
	var odds: Dictionary = lp.get("odds", YardFill.BEACH)
	var roll := YardFill._h01([s, key, "edge"])
	var edged: bool = fd >= 1.0 and roll < float(odds.edge_picket)
	var dog := DogYard.patch_for(plan, lp, edged)
	if not dog.is_empty() and bool(dog.front):
		return {}
	# A low wall, pickets or a hedge on the street line (YardFill's own roll).
	var lined: bool = fd >= 1.0 and roll < float(odds.edge_hedge)
	var keep := STREET_KEEP if lined else OPEN_KEEP
	var allowed: Array[Rect2] = []
	var blocked: Array[Rect2] = []
	for r: Rect2 in lp.parts:
		blocked.append(YardFill._to_frame(f, r).grow(HOUSE_GAP))
	var drive: Rect2 = lp.drive
	var drive_q := Rect2()
	if drive.size.x > 0.0:
		drive_q = YardFill._to_frame(f, drive)
		allowed.append(drive_q)
		# YardFill's car in the drive (its own hash; the chunk's cap is ignored, to stay pure).
		if YardFill._h01([s, key, "drive_car"]) < YardFill.DRIVE_CAR_ODDS and drive_q.size.y >= 5.0:
			var cv := maxf(drive_q.end.y - 3.0, 2.7)
			blocked.append(Rect2(drive_q.position.x - 0.3, cv - 2.7, drive_q.size.x + 0.6, 5.4))
	for pc: Array in lp.pieces:
		var r: Rect2 = pc[0]
		var role := String(pc[3])
		var kind := int(pc[1])
		var q := YardFill._to_frame(f, r)
		if role == "path":
			blocked.append(q.grow(PATH_GAP))
		elif role == "front":
			if kind == YardFill.G_DG:
				continue
			allowed.append(q)
			if kind == YardFill.G_LAWN and minf(r.size.x, r.size.y) >= TREE_LAWN:
				blocked.append(Rect2(q.get_center() - Vector2(TREE_CLEAR, TREE_CLEAR), Vector2(TREE_CLEAR, TREE_CLEAR) * 2.0))
	if allowed.is_empty():
		return {}
	# Nothing on the street line.
	blocked.append(Rect2(-100.0, -100.0, U + 200.0, 100.0 + keep))
	# The things for sale, in the order they go along the row.
	var want: Array = []
	for kind: String in ["table6", "rack", "card", "boxes", "sofa", "bike", "floor_lamp"]:
		var c: Array = ITEMS[kind].count
		var n := int(c[0])
		if int(c[1]) > n and _h01([s, key, "ys_n", kind]) < float(ITEM_ODDS.get(kind, 0.5)):
			n += 1
		for i in n:
			want.append(kind)
	if state == State.SETUP:
		want = want.filter(func(k: String) -> bool: return k == "table6" or k == "boxes" or k == "card")
	elif state == State.LEFTOVER:
		want = want.filter(func(k: String) -> bool: return k == "sofa" or k == "boxes")
	# Interleave a little: the hash picks a rotation of the list so not every sale starts the same.
	if want.size() > 2:
		var rot := absi(hash([s, key, "ys_rot"])) % want.size()
		want = want.slice(rot) + want.slice(0, rot)
	# The row's line: the best of a few depths (the most things placed), with the aisle in the yard
	# where it fits, else at the front with the aisle on the pavement.
	var v_hi := fd - 0.25 - SELLER_BACK - 0.45
	var best := _best_row(s, key, want, keep + AISLE + 0.45, v_hi, U, allowed, blocked)
	var on_pavement := false
	if (best.items as Array).size() < 2 and not lined:
		var front := _best_row(s, key, want, keep + 0.45, minf(v_hi, keep + AISLE + 0.4), U, allowed, blocked)
		if (front.items as Array).size() > (best.items as Array).size():
			best = front
			on_pavement = true
	if (best.items as Array).is_empty():
		return {}
	var items: Array = best.items
	var u0 := INF
	var u1 := -INF
	var queue: Array = []
	var seller := Vector2(-1, -1)
	for it: Dictionary in items:
		var at: Vector2 = it.at
		var sz: Vector2 = it.size
		u0 = minf(u0, at.x - sz.x * 0.5)
		u1 = maxf(u1, at.x + sz.x * 0.5)
		if ITEMS[it.kind].get("goods", false) or it.kind == "rack":
			var n := 2 if sz.x > 1.2 else 1
			for k in n:
				var qu := at.x + (float(k) - float(n - 1) * 0.5) * 0.85
				queue.append(Vector2(qu, PAVEMENT_QUEUE if on_pavement else at.y - sz.y * 0.5 - 0.5))
		if seller.x < 0.0 and it.kind == "table6":
			seller = Vector2(at.x + 0.3, minf(at.y + sz.y * 0.5 + SELLER_BACK * 0.6, fd - 0.3))
	var row_v: float = best.v
	var aisle_v := PAVEMENT_AISLE if on_pavement else row_v - 0.45 - AISLE * 0.6
	var out := {"state": state, "info": info, "items": items, "row_v": row_v, "on_pavement": on_pavement,
		"aisle": [Vector2(u0 + 0.3, aisle_v), Vector2(u1 - 0.3, aisle_v)], "queue": queue,
		"seller": seller if state != State.LEFTOVER else Vector2(-1, -1),
		"browsers": browsers_at(hour, _h01([s, key, "ys_busy"])) if state == State.OPEN else 0}
	# The poster board on the pavement in front of the lot, by the drive or the row's end; after
	# the sale the FREE box there.
	var su := clampf(drive_q.position.x - 0.6 if drive_q.size.x > 0.0 and drive_q.position.x > 1.2 else u0 - 0.2, 0.5, U - 0.5)
	out.stake = Vector2(su, STAKE_V) if state != State.LEFTOVER else Vector2(-1, -1)
	out.free_box = Vector2(clampf(su + 0.2, 0.6, U - 0.6), STAKE_V) if state == State.LEFTOVER else Vector2(-1, -1)
	return out


## The row with the most things over depths v0..v1 (a few tries).
static func _best_row(s: int, key: int, want: Array, v0: float, v1: float, U: float, allowed: Array[Rect2], blocked: Array[Rect2]) -> Dictionary:
	var best := {"v": v0, "items": []}
	var v := v0
	var tries := 0
	while v <= v1 + 0.001 and tries < 8:
		var row := _lay_row(s, key, want, v, U, allowed, blocked)
		if (row.items as Array).size() > (best.items as Array).size():
			best = row
		v += 0.3
		tries += 1
	return best


## Lays `want` along the row at depth `v`: each thing at the first u it fits from the low end, a
## hashed gap after it. {"v", "items"}.
static func _lay_row(s: int, key: int, want: Array, v: float, U: float, allowed: Array[Rect2], blocked: Array[Rect2]) -> Dictionary:
	var items: Array = []
	var u := 0.45
	var i := 0
	for kind: String in want:
		var sz: Vector2 = ITEMS[kind].size
		var placed := false
		var uu := u
		while uu + sz.x <= U - 0.45:
			var r := Rect2(Vector2(uu, v - sz.y * 0.5), sz)
			if _fits(r, allowed, blocked):
				placed = true
				break
			uu += 0.15
		if not placed:
			continue
		var at := Vector2(uu + sz.x * 0.5, v)
		# A sofa and boxes stand back a little, a bike leans forward of the line.
		if kind == "sofa":
			at.y += 0.1
		items.append({"kind": kind, "at": at, "size": sz, "variant": absi(hash([s, key, "ys_var", i])) % 3,
			"paint": absi(hash([s, key, "ys_paint", i])) % 8, "seed": _h01([s, key, "ys_seed", i]),
			"yaw": (_h01([s, key, "ys_yaw", i]) - 0.5) * 0.08})
		u = uu + sz.x + lerpf(GAP.x, GAP.y, _h01([s, key, "ys_gap", i]))
		i += 1
	return {"v": v, "items": items}


## A rect is inside the allowed ground (sampled: corners, edge middles, centre) and off everything
## blocked.
static func _fits(r: Rect2, allowed: Array[Rect2], blocked: Array[Rect2]) -> bool:
	for b: Rect2 in blocked:
		if r.intersects(b):
			return false
	for p: Vector2 in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.get_center(),
			Vector2(r.get_center().x, r.position.y), Vector2(r.get_center().x, r.end.y), Vector2(r.position.x, r.get_center().y), Vector2(r.end.x, r.get_center().y)]:
		var inside := false
		for a: Rect2 in allowed:
			if a.grow(0.02).has_point(p):
				inside = true
				break
		if not inside:
			return false
	return true


## The block's sales at (day, hour), for checks and probes: [[lot plan, sale plan]]. Pure but for
## YardFill's block plan (itself pure).
static func block_sales(plan: CityPlan, bx: int, bz: int, day: int, hour: float) -> Array:
	var out: Array = []
	var block := plan.block(bx, bz)
	var district := int(block.district)
	if not ODDS.has(district):
		return out
	var bp := block_plans(plan, bx, bz)
	for lp: Dictionary in bp.lots:
		var p := plan_lot(plan, lp, district, day, hour)
		if not p.is_empty():
			out.append([lp, p])
	return out


## YardFill's plan of a house block, from the plan alone (the lots HouseKit would build).
static func block_plans(plan: CityPlan, bx: int, bz: int) -> Dictionary:
	var d := int(plan.block(bx, bz).district)
	var lots: Array = plan.lots(bx, bz)
	if HouseKit.enabled:
		lots.append_array(HouseKit.extra_lots(plan, bx, bz))
	var entries: Array = []
	for lot: Dictionary in lots:
		if lot.yard or YardFill.is_corridor(plan, lot):
			continue
		entries.append(HouseKit.yard_entry(lot, HouseKit.plan_house(plan, bx, bz, lot, d)))
	return YardFill.beach_block(plan, bx, bz, entries)


# --- Building -----------------------------------------------------------------------------------

## From YardFill._build_beach() (after Backyards): a FULL chunk's sales, as deferred jobs (a job a
## sale, then the corner signs and the people).
static func block(ch: CityChunk, bp: Dictionary) -> void:
	if not enabled or ch.capturing or ch.level != CityChunk.Level.FULL:
		return
	var district := int(ch.plan.block(ch.ix, ch.iz).district)
	if not ODDS.has(district):
		return
	if rained_off(ch):
		return
	var day := weekday(ch)
	var hour := hour_now(ch)
	var sales: Array = []
	for lp: Dictionary in bp.lots:
		var p := plan_lot(ch.plan, lp, district, day, hour)
		if not p.is_empty():
			sales.append([lp, p])
		if sales.size() >= MAX_PER_CHUNK:
			break
	if sales.is_empty():
		return
	var st := {"counts": {}, "browsers": 0, "sales": sales}
	var jobs: Array[Callable] = []
	for sp: Array in sales:
		jobs.append(_build_sale.bind(ch, sp[0], sp[1], district, st))
	jobs.append(_corner_signs.bind(ch, sales, st))
	for sp: Array in sales:
		jobs.append(_people.bind(ch, sp[0], sp[1], st))
	jobs.append(_finish.bind(ch, st))
	YardFill._defer(ch, jobs)


static func _y(ch: CityChunk, lp: Dictionary, district: int, at: Vector2) -> float:
	if at.y < 0.0:
		return CityChunk.SIDEWALK_TOP
	return Backyards._yard_top(ch, lp, district, at)


## The frame's direction `d` (u, v) in world XZ.
static func _dir(f: Dictionary, d: Vector2) -> Vector2:
	return ((f.u as Vector2) * d.x + (f.v as Vector2) * d.y).normalized()


## A thing's transform: its local -Z (its front, the customers' side) toward the street.
static func _xf(f: Dictionary, at: Vector2, y: float, yaw: float) -> Transform3D:
	var xf := Backyards._xf(f, at, 0.0, y, 1.0, Vector2(0, -1))
	return Transform3D(xf.basis * Basis(Vector3.UP, yaw), xf.origin)


static func _build_sale(ch: CityChunk, lp: Dictionary, sale: Dictionary, district: int, st: Dictionary) -> void:
	var f: Dictionary = lp.frame
	var key: int = lp.lot.seed
	var counts: Dictionary = st.counts
	var queue: Array = ch.get_meta("vendor_queue", [])
	var records: Array = []
	for it: Dictionary in sale.items:
		var kind := String(it.kind)
		var at: Vector2 = it.at
		var y := _y(ch, lp, district, at)
		var xf := _xf(f, at, y, float(it.yaw))
		var mk := kind
		var custom := Color(0, 0, 0, (float(it.paint) + 0.5) / 8.0)
		match kind:
			"table6", "card":
				mk = "%s_%d" % [kind, int(it.variant)] if sale.state != State.SETUP or int(it.variant) != 2 else "%s_bare" % kind
			"boxes":
				mk = "boxes_%d" % (int(it.variant) % 2)
			"bike":
				custom = YardSaleKit.bike_paint(int(it.paint))
		var mesh := YardSaleKit.get_mesh(mk) if kind != "bike" else MicroMesh.whole(MicroMesh.Kind.CRUISER)
		var bkey := "ys_" + mk if kind != "bike" else "ys_bike"
		var data: Dictionary = ITEMS[kind]
		var box: Vector3 = data.box
		var bxf := xf
		if kind == "bike":
			# Along the row on its kickstand, leaning onto it.
			bxf = Transform3D(xf.basis * Basis(Vector3.UP, PI * 0.5) * Basis(Vector3.BACK, 0.07), xf.origin)
			box = Vector3(0.45, 1.0, 1.75)
		var rec := _item(ch, bkey, mesh, bxf, custom, "%d_%d" % [key, records.size()], box, box.y * 0.5, float(data.mass))
		records.append(rec)
		counts[kind] = int(counts.get(kind, 0)) + 1
		# A price sign on the sofa ("$40", "FREE" after the sale).
		if kind == "sofa":
			var tag := "FREE" if sale.state == State.LEFTOVER else "$%d" % (20 + 10 * (absi(hash([key, "ys_price"])) % 6))
			var txf := xf * Transform3D(Basis(Vector3.RIGHT, -0.25), Vector3(0.35, 0.62, -0.18))
			ch._batch.add("ys_tag", YardSaleKit.tag_mesh(tag), txf)
	# The browse spots in front of the tables (the crowd's life layer stops people there).
	var fwd := _dir(f, Vector2(0, -1))
	for q: Vector2 in sale.queue:
		var w := YardFill._fp(f, q.x, q.y)
		queue.append({"p": w, "yaw": atan2(fwd.x, fwd.y), "taken": null, "record": records[0] if not records.is_empty() else null})
	ch.set_meta("vendor_queue", queue)
	var info: Dictionary = sale.info
	var stake: Vector2 = sale.stake
	if stake.x >= 0.0:
		var y := _y(ch, lp, district, stake)
		var sxf := _xf(f, stake, y, (_h01([key, "ys_stake_yaw"]) - 0.5) * 0.3)
		var sm := YardSaleKit.stake_sign(String(info.headline), String(info.days_text), int(info.board), int(info.ink))
		_item(ch, "ys_stake_%s" % sm.resource_name, sm, sxf, Color.BLACK, "%d_stake" % key, Vector3(0.75, 1.2, 0.1), 0.6, 2.0)
		ch._batch.add("ys_balloons", YardSaleKit.get_mesh("balloons"), sxf * Transform3D(Basis(), Vector3(0.36, 0.0, 0.03)))
		counts["stake"] = int(counts.get("stake", 0)) + 1
	var fb: Vector2 = sale.free_box
	if fb.x >= 0.0:
		var y := _y(ch, lp, district, fb)
		_item(ch, "ys_free_box", YardSaleKit.get_mesh("free_box"), _xf(f, fb, y, 0.1), Color.BLACK, "%d_free" % key, Vector3(0.6, 0.45, 0.45), 0.22, 4.0)
		counts["free_box"] = int(counts.get("free_box", 0)) + 1
	counts["sales"] = int(counts.get("sales", 0)) + 1


## Cardboard signs taped to the poles at the corners of the sale's front street, the arrow pointing
## along it to the sale; a stake in the parkway where a corner has no pole.
static func _corner_signs(ch: CityChunk, sales: Array, st: Dictionary) -> void:
	var rect: Rect2 = ch.plan.block(ch.ix, ch.iz).rect
	var poles: Array = []
	var data: Dictionary = ch._batch.data()
	if data.has("upole"):
		for xf: Transform3D in data["upole"].xforms:
			poles.append([Vector2(xf.origin.x, xf.origin.z), "upole"])
	for rec: Dictionary in ch.prop_records:
		if String(rec.kind) == "lamp" and not rec.dead:
			var p: Vector3 = rec.position
			poles.append([Vector2(p.x, p.z), "lamp"])
	var done := {}
	var n := 0
	for sp: Array in sales:
		var lp: Dictionary = sp[0]
		var sale: Dictionary = sp[1]
		var f: Dictionary = lp.frame
		var side := int(f.side)
		var info: Dictionary = sale.info
		var at := YardFill._fp(f, (sale.items[0].at as Vector2).x, 0.0)
		var out_n := -(f.v as Vector2)
		# The front edge's two corners (the block rect's corners on that side).
		var corners: Array = []
		match side:
			0:
				corners = [rect.position, Vector2(rect.end.x, rect.position.y)]
			1:
				corners = [Vector2(rect.position.x, rect.end.y), rect.end]
			2:
				corners = [rect.position, Vector2(rect.position.x, rect.end.y)]
			_:
				corners = [Vector2(rect.end.x, rect.position.y), rect.end]
		corners.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_squared_to(at) < b.distance_squared_to(at))
		for c: Vector2 in corners:
			if n >= MAX_CORNERS * sales.size() or done.has(c):
				continue
			done[c] = true
			# Facing drivers coming up the cross street toward the front street.
			var nrm := -out_n
			# up x n in XZ, as (x, z): the right hand of someone reading the sign.
			var right := Vector2(nrm.y, -nrm.x)
			var arrow := 1 if (at - c).dot(right) > 0.0 else -1
			var best := []
			var bd := CORNER_REACH
			for pl: Array in poles:
				var d := (pl[0] as Vector2).distance_to(c)
				if d < bd:
					bd = d
					best = pl
			var sm := YardSaleKit.pole_sign(String(info.headline), arrow, int(info.board), int(info.ink))
			var yaw := atan2(nrm.x, nrm.y)
			if not best.is_empty():
				var pp: Vector2 = best[0]
				var r: float = POLE_R[best[1]]
				var o := pp + nrm * (r + 0.004)
				var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(o.x, CityChunk.SIDEWALK_TOP + SIGN_Y, o.y))
				ch._batch.add("ys_pole_%s" % sm.resource_name, sm, xf)
				ch._batch.add("ys_tape_%d" % int(r * 1000.0), YardSaleKit.tape_ring(r), Transform3D(Basis(Vector3.UP, yaw), Vector3(pp.x, CityChunk.SIDEWALK_TOP + SIGN_Y, pp.y)))
				st.counts["pole_sign"] = int(st.counts.get("pole_sign", 0)) + 1
			else:
				# In the parkway by the corner, on a lath stake.
				var inward := Vector2(signf(rect.get_center().x - c.x), signf(rect.get_center().y - c.y))
				var q := c + inward * 1.1
				var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(q.x, CityChunk.SIDEWALK_TOP, q.y))
				var lm := YardSaleKit.lath_sign(String(info.headline), arrow, int(info.board), int(info.ink))
				_item(ch, "ys_lath_%s" % lm.resource_name, lm, xf, Color.BLACK, "corner_%d_%d" % [int(c.x), int(c.y)], Vector3(0.6, 1.2, 0.1), 0.6, 1.5)
				st.counts["corner_stake"] = int(st.counts.get("corner_stake", 0)) + 1
			n += 1


## The seller and the browsers of one sale (the crowd cap).
static func _people(ch: CityChunk, lp: Dictionary, sale: Dictionary, st: Dictionary) -> void:
	var f: Dictionary = lp.frame
	var key: int = lp.lot.seed
	var rect: Rect2 = ch.plan.block(ch.ix, ch.iz).rect
	var seller: Vector2 = sale.seller
	if seller.x >= 0.0 and ch._take_crowd_room():
		var w := YardFill._fp(f, seller.x, seller.y)
		var to_street := _dir(f, Vector2(0, -1))
		# The people are loaded by path: naming them here would compile the crowd (and its autoloads)
		# into every tool that loads YardFill (Backyards' rule).
		var ped: Node3D = load("res://scripts/npc/street_vendor.gd").new()
		ped.name = "YardSeller_%d" % absi(key % 100000)
		ped.call("setup_vendor", rect, hash([ch.plan.seed, key, "ys_seller"]), w, atan2(-to_street.x, -to_street.y), false, 0.0)
		ped.position = Vector3(w.x, ch.ground_y(w.x, w.y) + 0.08, w.y)
		ped.add_to_group("yard_seller")
		ch.add_child(ped)
		st.counts["seller"] = int(st.counts.get("seller", 0)) + 1
	var aisle: Array = sale.aisle
	var a := YardFill._fp(f, (aisle[0] as Vector2).x, (aisle[0] as Vector2).y)
	var b := YardFill._fp(f, (aisle[1] as Vector2).x, (aisle[1] as Vector2).y)
	for i in int(sale.browsers):
		if int(st.browsers) >= MAX_CHUNK_BROWSERS or not ch._take_crowd_room():
			return
		var ped: Node3D = load("res://scripts/npc/yard_sale_browser.gd").new()
		ped.name = "YardBrowser_%d_%d" % [absi(key % 100000), i]
		ped.call("setup_sale", a, b, rect, hash([ch.plan.seed, key, "ys_browser", i]))
		var p := a.lerp(b, _h01([key, "ys_bat", i]))
		ped.position = Vector3(p.x, ch.ground_y(p.x, p.y) + 0.1, p.y)
		ch.add_child(ped)
		st.browsers = int(st.browsers) + 1
		st.counts["browser"] = int(st.counts.get("browser", 0)) + 1


static func _finish(ch: CityChunk, st: Dictionary) -> void:
	for key: String in ch._batch.keys():
		if not key.begins_with("ys_"):
			continue
		var small := key.begins_with("ys_tag") or key.begins_with("ys_pole") or key.begins_with("ys_tape") or key == "ys_balloons"
		ch._batch.set_draw_distance(key, SIGN_DRAW if small else DRAW)
		if small or key == "ys_free_box":
			ch._batch.set_no_shadow(key)
		else:
			ch._batch.set_shadow_reach(key, SHADOW_REACH)
	ch.set_meta("yard_sales", st.counts)


## One knockable thing: drawn in the chunk's batch, an EncampmentItem for its collision; knocked, a
## real body, gone for good (WorldState).
static func _item(ch: CityChunk, key: String, mesh: Mesh, xf: Transform3D, custom: Color, item_id: String, box: Vector3, centre_y: float, mass: float) -> Node:
	var id := "ys_%s_%d_%d" % [item_id, ch.ix, ch.iz]
	if WorldState.is_destroyed(ch.key, id):
		return null
	var index := ch._batch.add(key, mesh, xf, Color.WHITE, custom)
	var item := EncampmentItem.new()
	item.name = "YardSale_" + id
	item.chunk = ch
	item.item_id = id
	item.instances = [[key, index]]
	item.mesh = mesh
	item.mass_kg = mass
	item.tint = Color.WHITE
	item.custom = custom
	item.health = 25.0
	item.setup(box, centre_y)
	item.transform = Transform3D(xf.basis, xf.origin + Vector3(0.0, ch._gy(xf.origin.x, xf.origin.z), 0.0))
	item.add_to_group("yard_sale_item")
	ch.add_child(item)
	return item
