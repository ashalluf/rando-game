class_name FarmersMarket
extends RefCounted
## The weekly certified farmers' market (VISUAL_ROADMAP, the farmers-market row): one ordinary
## street a few kilometres apart, closed to cars by a row of bollards at each end, where on its day
## the growers put up rows of white pop-up canopies over folding tables of produce in crates,
## flowers in buckets, bread on racks, honey and eggs, their vans parked behind the stalls, string
## lights hung across the aisle, and shoppers browse from stall to stall. Before and after the
## market the canopies are folded and the crates stacked by the vans; every other day the street
## is empty but for the painted stall numbers and the sign saying when the market is on.
##
## WHERE is worked out, never placed: the map is cut into CELL squares, a hash of seed + cell says
## whether one has a market and where in it (up to TRIES points); the street segment beside the
## block under that point (its +X road or its +Z road, by hash) is the market's if it is a plain
## local street of a residential or midtown block no one else claims (`_eligible()`). The street is
## closed between its two crossings (CityPlan.road_open() asks `road_closed()`), from CLOSE_INSET
## past each crossing road's edge, so the junctions at its ends keep their signals and crosswalks.
## The chunk that owns the road (the block on its -X / -Z side) builds the market.
##
## WHEN: each market has its day of the week (DAY_ODDS: mostly Saturday and Sunday) and every stall
## its own hours round HOURS (a hash); the chunk builds what is there at the hour and day it is
## built at (DayNight's hour and day_count; `force_hour` / `force_day` for tests and stills, and
## MARKET_DAY=1 in the environment makes today every market's day). States per stall: GONE (not
## there), FOLDED (setting up or packing: canopy folded, tables folded, crates stacked, van open)
## and UP. The kit (FarmersMarketKit) builds the meshes; everything is a hash of seed + market +
## stall, never a chunk, block or Building rng, so nothing a seed built before moves.
##
## `FARMERS_MARKET=0` in the environment turns it off (the A/B): no market, the street is open.

enum Kind { PRODUCE, FLOWERS, BREAD, PANTRY }
enum State { GONE, FOLDED, UP }

# --- Tunables --------------------------------------------------------------------------------

## Map cell (m) holding at most one market, and the odds a cell has one.
const CELL := 1700.0
const ODDS := 0.85
const TRIES := 5
const DISTRICTS := [CityPlan.District.MIDTOWN, CityPlan.District.SUBURBS, CityPlan.District.BEACHTOWN]
## Street widths (kerb to kerb) a market fits on: two rows of canopies and an aisle.
const MIN_WIDTH := 12.8
const MAX_WIDTH := 18.5
## Shortest block span (crossing edge to crossing edge).
const MIN_LEN := 72.0
## Steepest the street may run (rise over length).
const MAX_GRADE := 0.045
## The closure starts this far past each crossing road's edge (CityPlan.junction_closed() looks at
## 2 m, the traffic's turn test at 3 m: the junction stays a junction, the arm is closed).
const CLOSE_INSET := 2.5
## Metres kept clear at each end (bollards, the sign, room to walk in).
const END_CLEAR := 7.5
## Longest run of stalls.
const MAX_LEN := 104.0
## A canopy's side (10 ft), and the pitch of the stalls along a row.
const CANOPY := 3.05
const PITCH := 3.2
## After this many stalls a row leaves a gap (a way through to the pavement).
const GAP_EVERY := 7
const GAP := 3.2
## Across: the back of a canopy from the kerb, the van's from the kerb, the van's width and the
## room between a van and the canopy in front of it.
const KERB_GAP := 0.45
const VAN_KERB := 0.3
const VAN_W := 2.25
const VAN_GAP := 0.3
## Narrowest street with vans parked behind one row (the aisle left must be at least 4 m).
const VANS_MIN_WIDTH := 13.9
## Chance per day of the week (0 Sunday .. 6 Saturday) that it is a market's day.
const DAY_ODDS := [0.33, 0.03, 0.06, 0.13, 0.07, 0.03, 0.35]
## The weekday the game starts on (DayNight.day_count 0): a Saturday.
const START_WEEKDAY := 6
## A stall's day: [arrive, canopy up, canopy down, gone] hours, each shifted by up to HOURS_JITTER.
const HOURS := [6.3, 7.4, 13.1, 14.3]
const HOURS_JITTER := 0.45
## Kinds of stall: produce, flowers, bread, pantry (honey, jam, eggs).
const KIND_ODDS := [0.58, 0.15, 0.15, 0.12]
## Most shoppers a market has at its busiest (in the crowd cap), and by the hour (peak 9-11).
const MAX_SHOPPERS := 34
const SHOPPER_KEYS := [[6.5, 0.0], [7.5, 0.25], [8.5, 0.75], [9.5, 1.0], [11.0, 1.0], [12.5, 0.7], [13.3, 0.25], [14.0, 0.0]]
## Shoppers stop at a stall for this long (seconds), and the share who stop at a free one.
const BROWSE_SECONDS := Vector2(10.0, 32.0)

## Growers' and bakers' names on the valance banners. All invented.
const PRODUCE_NAMES := ["TRES ROBLES FARM", "SUNWARD ORCHARDS", "MESA LINDA GROWERS", "BLUE OAK RANCH",
	"LA PALOMA FARMS", "HIGH DESERT ORGANICS", "OJO DE AGUA FARM", "CAÑADA VERDE", "TWO CREEKS FARM",
	"FOXTAIL ACRES", "EL SAUCE FAMILY FARM", "KETTLE RIDGE ORCHARD", "SAN ISIDRO GROWERS", "WILLOW BEND FARM",
	"COPPER HILL CITRUS", "MARISCAL FARMS"]
const FLOWER_NAMES := ["PETAL & STEM", "LAS FLORES DE ROSA", "WILDMEADOW BLOOMS", "SUNDROP FLOWER FARM", "GARDEN ROW"]
const BREAD_NAMES := ["HEARTH & CRUMB", "PANADERÍA LUNA", "STONEMILL BREAD CO", "MORNING RISE BAKERY", "THE RYE HOUSE"]
const PANTRY_NAMES := ["GOLDEN HIVE HONEY", "RANCHO DULCE JAMS", "HAPPY HEN EGGS", "OLD GROVE OLIVE OIL", "CANYON NUT CO"]

static var enabled: bool = OS.get_environment("FARMERS_MARKET") != "0"
## Tests and stills: the hour and day of the week to build for (-1: the city's clock).
static var force_hour: float = -1.0
static var force_day: int = -1
## Every market's day is today (MARKET_DAY=1 in the environment, or set by a test).
static var force_market_day: bool = OS.get_environment("MARKET_DAY") == "1"

static var _cells: Dictionary = {}
static var _closed: Dictionary = {}
static var _layouts: Dictionary = {}
static var _deciding: bool = false


static func _h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) / 100003.0


static func _cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.y / CELL))


## Drops every cached decision (a test that changes `enabled` or the seed's plan).
static func reset() -> void:
	_cells.clear()
	_closed.clear()
	_layouts.clear()


# --- Where -----------------------------------------------------------------------------------

## The block (ix, iz) rect between the kerbs from the roads alone (CityPlan.block()'s rect).
static func _block_rect(plan: CityPlan, k: Vector2i) -> Rect2:
	var x0 := plan.road_pos(CityPlan.AXIS_X, k.x) + plan.road_width(CityPlan.AXIS_X, k.x) * 0.5
	var x1 := plan.road_pos(CityPlan.AXIS_X, k.x + 1) - plan.road_width(CityPlan.AXIS_X, k.x + 1) * 0.5
	var z0 := plan.road_pos(CityPlan.AXIS_Z, k.y) + plan.road_width(CityPlan.AXIS_Z, k.y) * 0.5
	var z1 := plan.road_pos(CityPlan.AXIS_Z, k.y + 1) - plan.road_width(CityPlan.AXIS_Z, k.y + 1) * 0.5
	return Rect2(x0, z0, x1 - x0, z1 - z0)


## The market of map cell `cell`, or {}: {"cell", "axis" (of the road: AXIS_X runs along z),
## "index" (the road), "k" (the crossing span: between crossing roads k and k + 1), "owner" (the
## chunk that builds it), "lo"/"hi" (along the road, the crossing roads' edges), "centre" (the
## road's centre line across), "width", "rect" (kerb to kerb, lo..hi), "day", "name", "seed"}.
## Cached per seed.
static func decide(plan: CityPlan, cell: Vector2i) -> Dictionary:
	var key := Vector3i(plan.seed, cell.x, cell.y)
	if _cells.has(key):
		return _cells[key]
	var out := {}
	_cells[key] = out
	if not enabled or plan.macro == null:
		return out
	if _h01([plan.seed, cell.x, cell.y, "fmarket"]) > ODDS:
		return out
	_deciding = true
	for attempt in TRIES:
		_try(plan, cell, attempt, out)
		if not out.is_empty():
			break
	_deciding = false
	return out


static func _try(plan: CityPlan, cell: Vector2i, attempt: int, out: Dictionary) -> void:
	var target := Vector2((float(cell.x) + lerpf(0.1, 0.9, _h01([plan.seed, cell.x, cell.y, attempt, "fm_x"]))) * CELL,
			(float(cell.y) + lerpf(0.1, 0.9, _h01([plan.seed, cell.x, cell.y, attempt, "fm_z"]))) * CELL)
	if plan.zone_at(target) != MacroMap.Zone.CITY:
		return
	var a := plan.block_index_at(target)
	if _cell_of(_block_rect(plan, a).get_center()) != cell:
		return
	var axes := [CityPlan.AXIS_X, CityPlan.AXIS_Z]
	if _h01([plan.seed, cell.x, cell.y, attempt, "fm_axis"]) < 0.5:
		axes.reverse()
	for axis: int in axes:
		var site := _segment(plan, a, axis)
		if not site.is_empty():
			site.cell = cell
			site.day = _pick_day(plan.seed, cell)
			site.seed = hash([plan.seed, cell.x, cell.y, "fm_site"])
			site.name = "%s FARMERS MARKET" % plan.road_name(axis, int(site.index)).to_upper()
			out.merge(site)
			return


## The street on block `a`'s +X side (axis X) or +Z side (axis Z), between its two crossings, if a
## market fits there and nobody else has a claim on it or the blocks either side.
static func _segment(plan: CityPlan, a: Vector2i, axis: int) -> Dictionary:
	var index := a.x + 1 if axis == CityPlan.AXIS_X else a.y + 1
	var k := a.y if axis == CityPlan.AXIS_X else a.x
	var o := 1 - axis
	var width := plan.road_width(axis, index)
	if width < MIN_WIDTH or width > MAX_WIDTH or width >= plan.avenue_width - 0.1:
		return {}
	if not DowntownReal.pin_at(axis, plan.road_pos(axis, index)).is_empty():
		return {}
	var lo := plan.road_pos(o, k) + plan.road_width(o, k) * 0.5
	var hi := plan.road_pos(o, k + 1) - plan.road_width(o, k + 1) * 0.5
	if hi - lo < MIN_LEN:
		return {}
	# Neither crossing road may be an avenue's roundabout or itself a real (pinned) road's end.
	var centre := plan.road_pos(axis, index)
	var rect := Rect2(centre - width * 0.5, lo, width, hi - lo) if axis == CityPlan.AXIS_X else Rect2(lo, centre - width * 0.5, hi - lo, width)
	var other := a + (Vector2i(1, 0) if axis == CityPlan.AXIS_X else Vector2i(0, 1))
	for b: Vector2i in [a, other]:
		if not _eligible(plan, b):
			return {}
	if not _street_clear(plan, axis, index, rect):
		return {}
	# Flat enough to stand tables on.
	var p0 := _point(axis, centre, lo + 4.0, 0.0)
	var p1 := _point(axis, centre, hi - 4.0, 0.0)
	var rise := absf(plan.macro.relief_at(p0) - plan.macro.relief_at(p1))
	if rise > MAX_GRADE * (hi - lo):
		return {}
	return {"axis": axis, "index": index, "k": k, "lo": lo, "hi": hi, "centre": centre, "width": width, "rect": rect,
		"owner": Vector2i(index - 1, k) if axis == CityPlan.AXIS_X else Vector2i(k, index - 1)}


## A plain residential / midtown block no one else has a claim on.
static func _eligible(plan: CityPlan, k: Vector2i) -> bool:
	var macro: MacroMap = plan.macro
	var b := plan.block(k.x, k.y)
	var rect: Rect2 = b.rect
	if not (int(b.district) in DISTRICTS):
		return false
	if b.has("site") or b.has("grounds") or b.has("school") or b.has("hospital") or b.get("was_plaza", false):
		return false
	if int(b.kind) != CityPlan.BlockKind.BUILDINGS and int(b.kind) != CityPlan.BlockKind.PARK:
		return false
	for p: Vector2 in [rect.position, rect.end, Vector2(rect.end.x, rect.position.y), Vector2(rect.position.x, rect.end.y), rect.get_center()]:
		if macro.zone_at(p) != MacroMap.Zone.CITY:
			return false
	if DowntownReal.in_extent(rect.get_center()) or Landmarks.claims(rect):
		return false
	if not plan.site_at_block(k.x, k.y).is_empty() or plan._beside_site(k.x, k.y):
		return false
	if plan.river_block(k.x, k.y) or plan.marina_block(k.x, k.y):
		return false
	if macro.replica and macro.replica._bounds.intersects(rect.grow(40.0)):
		return false
	return true


## The street itself: no freeway over it or through it, no light rail on it, out of the airport's
## approach, not a road anything else closes, no landmark standing in it.
static func _street_clear(plan: CityPlan, axis: int, index: int, rect: Rect2) -> bool:
	var macro: MacroMap = plan.macro
	if macro.freeway and macro.freeway.blocks_rect(rect, 6.0):
		return false
	var rail := LightRail.of(plan)
	if rail != null and (rail.street_rail(axis, index) or rail.blocks_rect(rect, 6.0) or not rail.cuts_in(rect).is_empty()):
		return false
	if macro.runway_clear_zone().grow(60.0).intersects(rect):
		return false
	if Landmarks.covers(plan, rect.get_center(), maxf(rect.size.x, rect.size.y) * 0.5):
		return false
	var along := rect.get_center().y if axis == CityPlan.AXIS_X else rect.get_center().x
	if not plan.road_open(axis, index, along):
		return false
	return true


static func _pick_day(plan_seed: int, cell: Vector2i) -> int:
	var r := _h01([plan_seed, cell.x, cell.y, "fm_day"])
	var acc := 0.0
	for d in 7:
		acc += float(DAY_ODDS[d])
		if r < acc:
			return d
	return 6


## World XZ of (along `t`, across `o`) on a road of `axis` whose centre line is at `centre`
## (across is +x for an AXIS_X road, +z for an AXIS_Z one).
static func _point(axis: int, centre: float, t: float, o: float) -> Vector2:
	return Vector2(centre + o, t) if axis == CityPlan.AXIS_X else Vector2(t, centre + o)


static func point(site: Dictionary, t: float, o: float) -> Vector2:
	return _point(int(site.axis), float(site.centre), t, o)


## The along direction and the across direction of a market's street (world XZ).
static func dirs(site: Dictionary) -> Array[Vector2]:
	if int(site.axis) == CityPlan.AXIS_X:
		return [Vector2(0, 1), Vector2(1, 0)]
	return [Vector2(1, 0), Vector2(0, 1)]


## The market whose street is road (axis, index) between crossings `other` and `other + 1`, or {}.
static func market_on(plan: CityPlan, axis: int, index: int, other: int) -> Dictionary:
	if not enabled or plan.macro == null:
		return {}
	var owner := Vector2i(index - 1, other) if axis == CityPlan.AXIS_X else Vector2i(other, index - 1)
	var m := decide(plan, _cell_of(_block_rect(plan, owner).get_center()))
	if m.is_empty() or int(m.axis) != axis or int(m.index) != index or int(m.k) != other:
		return {}
	return m


## The market chunk (ix, iz) builds (it owns the road), or {}.
static func market_of_chunk(plan: CityPlan, ix: int, iz: int) -> Dictionary:
	if not enabled or plan == null or plan.macro == null:
		return {}
	var m := decide(plan, _cell_of(_block_rect(plan, Vector2i(ix, iz)).get_center()))
	if m.is_empty() or m.owner != Vector2i(ix, iz):
		return {}
	return m


## CityPlan.road_open()'s hook: true along a market street, between CLOSE_INSET past each
## crossing road's edge.
static func road_closed(plan: CityPlan, axis: int, index: int, along: float) -> bool:
	if _deciding or not enabled or plan.macro == null:
		return false
	var other := plan._index_at(1 - axis, along)
	var key := Vector4i(plan.seed, axis, index, other)
	var m: Variant = _closed.get(key)
	if m == null:
		var found := market_on(plan, axis, index, other)
		m = found if not found.is_empty() else false
		_closed[key] = m
	if m is bool:
		return false
	var d: Dictionary = m
	return along > float(d.lo) + CLOSE_INSET and along < float(d.hi) - CLOSE_INSET


## Whether chunk (ix, iz)'s road on `axis` (+X: AXIS_X, +Z: AXIS_Z) is its market's street: the
## chunk lays its asphalt itself (CityChunk._build_roads() skips a closed road's slab).
static func paves(plan: CityPlan, ix: int, iz: int, axis: int) -> bool:
	var m := market_of_chunk(plan, ix, iz)
	return not m.is_empty() and int(m.axis) == axis


## True where a parked car may not stand (CityChunk._park_car, after its rolls): on a market street.
static func blocks_parking(plan: CityPlan, spot: Vector3) -> bool:
	if not enabled or plan == null or plan.macro == null:
		return false
	var p := Vector2(spot.x, spot.z)
	var bi := plan.block_index_at(p)
	for axis: int in [CityPlan.AXIS_X, CityPlan.AXIS_Z]:
		var index := plan._index_at(axis, p.x if axis == CityPlan.AXIS_X else p.y)
		# The road whose carriageway the spot is on: the nearest of the two either side.
		for idx: int in [index, index + 1]:
			if absf(plan.road_pos(axis, idx) - (p.x if axis == CityPlan.AXIS_X else p.y)) > plan.road_width(axis, idx) * 0.5:
				continue
			var other := bi.y if axis == CityPlan.AXIS_X else bi.x
			var along := p.y if axis == CityPlan.AXIS_X else p.x
			if not market_on(plan, axis, idx, other).is_empty() and road_closed(plan, axis, idx, along):
				return true
	return false


# --- When ------------------------------------------------------------------------------------

## The hour the market is built for: `force_hour`, else the city's clock, else 9:30.
static func hour_now(node: Node) -> float:
	if force_hour >= 0.0:
		return force_hour
	var env := OS.get_environment("MARKET_HOUR")
	if env != "":
		return env.to_float()
	var dn := _day_night(node)
	if dn != null:
		return float(dn.get("hour"))
	return 9.5


## The day of the week (0 Sunday .. 6 Saturday): `force_day`, else DayNight's day count from a
## Saturday start.
static func weekday(node: Node) -> int:
	if force_day >= 0:
		return force_day
	var dn := _day_night(node)
	var days := int(dn.get("day_count")) if dn != null else 0
	return posmod(START_WEEKDAY + days, 7)


static func _day_night(node: Node) -> Node:
	if node == null or not node.is_inside_tree():
		return null
	var scene := node.get_tree().current_scene
	return scene.get_node_or_null("DayNight") if scene else null


static func is_market_day(site: Dictionary, day: int) -> bool:
	return force_market_day or int(site.day) == day


## A stall's state at `hour` on a market day (State).
static func stall_state(stall: Dictionary, hour: float) -> int:
	var hrs: Array = stall.hours
	if hour < float(hrs[0]) or hour >= float(hrs[3]):
		return State.GONE
	if hour < float(hrs[1]) or hour >= float(hrs[2]):
		return State.FOLDED
	return State.UP


## How busy the market is at `hour` (0..1, SHOPPER_KEYS).
static func busyness(hour: float) -> float:
	var keys: Array = SHOPPER_KEYS
	if hour <= float(keys[0][0]) or hour >= float(keys[keys.size() - 1][0]):
		return 0.0
	for i in range(1, keys.size()):
		if hour <= float(keys[i][0]):
			var a: Array = keys[i - 1]
			var b: Array = keys[i]
			return lerpf(float(a[1]), float(b[1]), (hour - float(a[0])) / (float(b[0]) - float(a[0])))
	return 0.0


## Day names for the sign.
const DAY_NAMES := ["SUNDAYS", "MONDAYS", "TUESDAYS", "WEDNESDAYS", "THURSDAYS", "FRIDAYS", "SATURDAYS"]


# --- The layout ------------------------------------------------------------------------------

## The market's stalls and vans (pure, cached): {"stalls": [{i, side, t, o, kind, variant,
## canvas, name, van, hours}], "vans": [{t, o, side, paint, hours, dir}], "len0", "len1" (the run
## along the street), "van_side"}. `t` along the road (world coordinate), `o` across from the
## centre line, `side` the row (+1 / -1 across), a canopy's front faces the aisle (-side).
static func layout(site: Dictionary) -> Dictionary:
	var key: int = site.seed
	if _layouts.has(key):
		return _layouts[key]
	var lo: float = site.lo
	var hi: float = site.hi
	var width: float = site.width
	var half := width * 0.5
	var run := minf(hi - lo - END_CLEAR * 2.0, MAX_LEN)
	var t0 := (lo + hi) * 0.5 - run * 0.5
	var van_side := 1 if _h01([site.seed, "van_side"]) < 0.5 else -1
	var vans_ok := width >= VANS_MIN_WIDTH
	var stalls: Array = []
	var vans: Array = []
	var n := 0
	for side: int in [-1, 1]:
		var behind := vans_ok and side == van_side
		var back := half - (VAN_KERB + VAN_W + VAN_GAP if behind else KERB_GAP)
		var o := float(side) * (back - CANOPY * 0.5)
		var t := t0 + CANOPY * 0.5
		var in_row := 0
		var row_index := 0
		var row: Array = []
		while t + CANOPY * 0.5 <= t0 + run + 0.01:
			var id := [site.seed, side, row_index]
			# Now and then a stall's space stands empty (a grower who did not come).
			if _h01(id + ["empty"]) > 0.08:
				var kind := _pick_kind(_h01(id + ["kind"]))
				var variant := int(_h01(id + ["var"]) * 997.0)
				var shift := (_h01(id + ["early"]) * 2.0 - 1.0) * HOURS_JITTER
				var shift2 := (_h01(id + ["late"]) * 2.0 - 1.0) * HOURS_JITTER
				var hours := [float(HOURS[0]) + shift, float(HOURS[1]) + shift, float(HOURS[2]) + shift2, float(HOURS[3]) + shift2]
				var canvas := 0
				var cr := _h01(id + ["canvas"])
				if cr > 0.72:
					canvas = 1 + int((cr - 0.72) / 0.28 * 4.99)
				var s := {"i": n, "side": side, "t": t, "o": o, "kind": kind, "variant": variant, "canvas": canvas,
					"name": _name_for(kind, _h01(id + ["name"])), "van": behind, "hours": hours, "row": row_index}
				stalls.append(s)
				row.append(s)
				n += 1
			else:
				row.append({})
			in_row += 1
			row_index += 1
			t += PITCH
			if in_row % GAP_EVERY == 0:
				t += GAP
		# The vans behind the row: one per two spaces, centred on them, there while either is.
		if behind:
			for j in range(0, row.size() - 1, 2):
				var a: Dictionary = row[j]
				var b: Dictionary = row[j + 1]
				if a.is_empty() and b.is_empty():
					continue
				var ta: float = a.t if not a.is_empty() else float(b.t) - PITCH
				var tb: float = b.t if not b.is_empty() else float(a.t) + PITCH
				var hours := _union_hours(a, b)
				vans.append({"t": (ta + tb) * 0.5, "o": float(side) * (half - VAN_KERB - VAN_W * 0.5), "side": side,
					"paint": int(_h01([site.seed, side, j, "van_paint"]) * 997.0), "hours": hours,
					"dir": 1 if _h01([site.seed, side, j, "van_dir"]) < 0.5 else -1})
	var out := {"stalls": stalls, "vans": vans, "len0": t0, "len1": t0 + run, "van_side": van_side}
	_layouts[key] = out
	return out


static func _union_hours(a: Dictionary, b: Dictionary) -> Array:
	if a.is_empty():
		return (b.hours as Array).duplicate()
	if b.is_empty():
		return (a.hours as Array).duplicate()
	var ha: Array = a.hours
	var hb: Array = b.hours
	# A van comes a little before its stall's canopy goes up and leaves when the last is packed.
	return [minf(float(ha[0]), float(hb[0])) - 0.15, minf(float(ha[1]), float(hb[1])), maxf(float(ha[2]), float(hb[2])), maxf(float(ha[3]), float(hb[3]))]


static func _pick_kind(r: float) -> int:
	var acc := 0.0
	for k in KIND_ODDS.size():
		acc += float(KIND_ODDS[k])
		if r < acc:
			return k
	return Kind.PRODUCE


static func _name_for(kind: int, r: float) -> String:
	var pool: Array = [PRODUCE_NAMES, FLOWER_NAMES, BREAD_NAMES, PANTRY_NAMES][kind]
	return String(pool[int(r * pool.size()) % pool.size()])


## What the market is at (`hour`, `day`): {"open" (a market day at all), "states" (per stall),
## "vans" (per van: present), "up" (canopies up), "shoppers" (how many)}.
static func status(site: Dictionary, hour: float, day: int) -> Dictionary:
	var lay := layout(site)
	var states: Array[int] = []
	var vans: Array[bool] = []
	var on := is_market_day(site, day)
	var up := 0
	for s: Dictionary in lay.stalls:
		var st := stall_state(s, hour) if on else State.GONE
		states.append(st)
		if st == State.UP:
			up += 1
	for v: Dictionary in lay.vans:
		var hrs: Array = v.hours
		vans.append(on and hour >= float(hrs[0]) and hour < float(hrs[3]))
	var share := float(up) / maxf(float((lay.stalls as Array).size()), 1.0)
	var shoppers := roundi(float(MAX_SHOPPERS) * busyness(hour) * share) if on else 0
	return {"open": on, "states": states, "vans": vans, "up": up, "shoppers": shoppers}
