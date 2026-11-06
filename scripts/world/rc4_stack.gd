class_name RcStack
extends RefCounted
## The four-level stack from the air (wave 7 refcam `stack_aerial`, tools/refcams/cameras_w7.json,
## docs/HANDOFF.md "The four-level stack from the air"). What the 150 m view at 17:30 gave away:
##
## 1. The ground inside the stack was bare dirt: YardFill paints the right of way bare in a deck's
##    shade by the distance to its edge alone, and under the stack nearly everything is near a deck
##    - but the connectors stand 25-50 m up, where the low sun and the sky reach under them. The
##    shade now falls off with the deck's clearance over the ground (`bareness()`): under the main
##    lines (8 m) it is as before, under a connector it is ivy.
## 2. Nothing grew there: trees and shrubs keep out of every deck's footprint and margin, so the
##    stack's right of way was flat squares. `spots()` (pure: hashes of seed + block + cell) plants
##    the stack's right of way like the real one - eucalyptus, sycamore and fig groves where the
##    crown clears the deck over it by `TREE_CLEAR`, oleander mounds under the lower decks, nothing
##    under a main line. FULL chunks plant real trees (`dress_corridor()`, LaTrees / YardFill's
##    shrubs); the LOD ring and the far city draw the same spots as canopies (`far_trees()`, from
##    Skyline next to MidCity's yard trees), so the groves are there from every distance.
## 3. The columns read as toothpicks: a 40 m single shaft drawn 2.3 m wide. A tall column is drawn
##    (and collides) thicker, up to `COLUMN_GAIN` x at `COLUMN_TALL` m (`column_r()`), inside the
##    0.8 m margin FreewayStack's clearance tests keep, so no plan or check moves.
## 4. The connectors were nearly empty at rush hour: StackTraffic kept four cars a connector at
##    every hour. `cars_per_link()` follows the hour - the evening and morning peaks fill them.
##
## Every part is a hash of seed + place, after every existing roll. `RC4_STACK=0` is the A/B.

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

static var enabled: bool = OS.get_environment("RC4_STACK") != "0"

## Only the stack's own right of way (metres from FreewayStack.centre to a block's centre).
const REACH := 700.0
## Under a deck whose underside clears the ground by less than SHADE_LOW the ground is in its full
## shade (YardFill's old rule); by SHADE_HIGH the sun and sky get under it and the ivy grows.
const SHADE_LOW := 10.0
const SHADE_HIGH := 22.0
## The planting grid (metres), jittered by hash, inside each right-of-way cell less a margin.
const STEP := 9.5
const CELL_MARGIN := 1.6
## Odds a grid point gets a tree (where it fits), else a shrub mound; a pocket garden's lawn
## (a yard lot under the decks) gets trees only, sparser.
const TREE_ODDS := 0.5
const YARD_TREE_ODDS := 0.3
const SHRUB_ODDS := 0.75
## A crown's top keeps this far under the deck over it; a shrub needs this much room.
const TREE_CLEAR := 3.0
const SHRUB_ROOM := 4.0
const TREE_MIN := 8.0
## Crown radius over height per species (LaTrees' meshes, measured from crown()).
const SPECIES := [LaTrees.Species.EUCALYPTUS, LaTrees.Species.SYCAMORE, LaTrees.Species.FIG]
const SPECIES_CUM := [0.15, 0.42, 1.0]
const CROWN_RATIO := [0.28, 0.42, 0.46]
## Per FULL chunk.
const MAX_TREES := 180
const MAX_SHRUBS := 140
## Canopy colours for the far tiers (LINEAR, far_canopy shades by them): eucalyptus grey-green,
## sycamore, fig; and the oleander mounds.
const FAR_GREENS := [Color(0.050, 0.060, 0.044), Color(0.058, 0.080, 0.032), Color(0.030, 0.050, 0.022)]
const FAR_SHRUB := Color(0.034, 0.055, 0.026)
## The columns: drawn this much thicker at COLUMN_TALL metres and over (1 at 18 m).
const COLUMN_GAIN := 1.4
const COLUMN_TALL := 40.0
const COLUMN_SHORT := 18.0

static var _cache := {}


static func h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) / 100003.0


static func _stack(plan: CityPlan) -> FreewayStack:
	if plan == null or plan.macro == null or plan.macro.freeway == null:
		return null
	return plan.macro.freeway.stack


# --- 1. The shade under the decks ------------------------------------------------------------------

## How bare the right of way is at `p` (0 open ivy .. 1 the deck's shade), from the decks in `segs`
## (Freeway.segments_in() entries), `ground` the ground's height there: YardFill's distance fade,
## times how low each deck is over the ground.
static func bareness(segs: Array, p: Vector2, ground: float, fade: Vector2) -> float:
	var best := 0.0
	for s in segs:
		var a: Vector2 = s.a
		var b: Vector2 = s.b
		var q := Geometry2D.get_closest_point_to_segment(p, a, b)
		var d := (q - p).length() - float(s.width) * 0.5
		var near := 1.0 - smoothstep(fade.x, fade.y, d)
		if near <= best:
			continue
		var t := 0.0 if a.distance_squared_to(b) < 0.0001 else clampf((q - a).dot(b - a) / a.distance_squared_to(b), 0.0, 1.0)
		var under := lerpf(float(s.ha), float(s.hb), t) - _thickness(s) - ground
		best = maxf(best, near * (1.0 - smoothstep(SHADE_LOW, SHADE_HIGH, under)))
	return best


static func _thickness(s: Dictionary) -> float:
	return FreewayStack.GIRDER if s.has("link") else Freeway.DECK_THICKNESS


## The least room under any deck (its underside over `ground`) within `reach` metres of `p`
## across: INF when no deck is that near.
static func clearance(fw: Freeway, p: Vector2, reach: float, ground: float) -> float:
	var best := INF
	var r := reach + 30.0
	for s in fw.segments_in(Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0)):
		var a: Vector2 = s.a
		var b: Vector2 = s.b
		var q := Geometry2D.get_closest_point_to_segment(p, a, b)
		if (q - p).length() - float(s.width) * 0.5 > reach:
			continue
		var t := 0.0 if a.distance_squared_to(b) < 0.0001 else clampf((q - a).dot(b - a) / a.distance_squared_to(b), 0.0, 1.0)
		best = minf(best, lerpf(float(s.ha), float(s.hb), t) - _thickness(s) - ground)
	return best


## True where the right of way is the stack's own (its ivy ground gets lot_yard's mixed cover:
## lighter ivy, iceplant and juniper patches, dry grass - COLOR.b of the yard ground mesh).
static func mixed_ground(plan: CityPlan, bx: int, bz: int) -> bool:
	if not enabled:
		return false
	var st := _stack(plan)
	return st != null and (plan.block(bx, bz).rect as Rect2).get_center().distance_to(st.centre) <= REACH


# --- 2. The planting -------------------------------------------------------------------------------

## The right of way's planting of block (bx, bz): [[pos: Vector2, kind 0 tree / 1 shrub, species
## index (SPECIES) or -1, height m, crown radius m], ...]. Pure (the plan and hashes), cached.
static func spots(plan: CityPlan, bx: int, bz: int) -> Array:
	if not enabled:
		return []
	var st := _stack(plan)
	if st == null:
		return []
	var key := "%d_%d_%d" % [plan.seed, bx, bz]
	if _cache.has(key):
		return _cache[key]
	var out: Array = []
	_cache[key] = out
	var b: Dictionary = plan.block(bx, bz)
	if (b.rect as Rect2).get_center().distance_to(st.centre) > REACH:
		return out
	var fw: Freeway = plan.macro.freeway
	var all := plan.lots(bx, bz)
	if all.is_empty():
		return out
	var grid := YardFill.lot_grid(plan, bx, bz, all)
	var rail := LightRail.of(plan)
	var corridor: Array = []
	var yards := {}
	for lot: Dictionary in all:
		var size: Vector2 = lot.size
		var rect := Rect2((lot.center as Vector2) - size * 0.5, size)
		var under: bool = fw.blocks(lot.center, 14.0) or fw.blocks_rect(rect, CityChunk.LOT_FREEWAY_MARGIN) \
			or (rail != null and rail.blocks_rect(rect, 2.0))
		if not under:
			continue
		if lot.yard:
			yards[YardFill.cell_index(grid, lot.center)] = true
		else:
			corridor.append(lot)
	var cells: Array = []
	if not corridor.is_empty():
		var cp := YardFill.corridor_block(plan, bx, bz, corridor)
		for r: Rect2 in cp.cells:
			if r != (cp.yard as Rect2):
				cells.append([r, false])
	for i: Vector2i in yards:
		cells.append([YardFill.cell_rect(grid, i), true])
	for c: Array in cells:
		var r: Rect2 = (c[0] as Rect2).grow(-CELL_MARGIN)
		var yard: bool = c[1]
		if r.size.x < 2.0 or r.size.y < 2.0:
			continue
		var nx := maxi(1, int(r.size.x / STEP))
		var nz := maxi(1, int(r.size.y / STEP))
		for i in nx:
			for j in nz:
				var k := [plan.seed, "rc4_row", bx, bz, int(r.position.x), int(r.position.y), i, j]
				var p := r.position + Vector2((float(i) + 0.2 + 0.6 * h01(k + ["x"])) * r.size.x / nx,
					(float(j) + 0.2 + 0.6 * h01(k + ["z"])) * r.size.y / nz)
				var ground := float(plan.height_at(p))
				var roll := h01(k + ["t"])
				var sp_roll := h01(k + ["s"])
				var si := 0
				while si < SPECIES_CUM.size() - 1 and sp_roll > float(SPECIES_CUM[si]):
					si += 1
				var h := LaTrees.height_at(SPECIES[si], h01(k + ["h"]))
				if roll < (YARD_TREE_ODDS if yard else TREE_ODDS):
					var cr := h * float(CROWN_RATIO[si])
					var room := clearance(fw, p, cr + 1.0, ground)
					if room < INF:
						h = minf(h, room - TREE_CLEAR)
						cr = h * float(CROWN_RATIO[si])
					if h >= TREE_MIN:
						out.append([p, 0, si, h, cr])
						continue
				if yard or h01(k + ["b"]) >= SHRUB_ODDS:
					continue
				if clearance(fw, p, 1.5, ground) < SHRUB_ROOM:
					continue
				out.append([p, 1, -1, 1.4 + 0.9 * h01(k + ["m"]), 1.6 + 0.8 * h01(k + ["r"])])
	return out


## FULL chunks: the spots this chunk owns as real trees (LaTrees' species; LotFill's tree with
## LA_TREES=0) and YardFill's shrubs. From YardFill._build_corridor() / the yard lots, once a chunk.
static func dress(ch: CityChunk) -> void:
	if not enabled or ch.level != CityChunk.Level.FULL or ch.capturing:
		return
	var list := spots(ch.plan, ch.ix, ch.iz)
	if list.is_empty() or ch.has_meta("rc4_stack"):
		return
	ch.set_meta("rc4_stack", true)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([ch.plan.seed, "rc4_row_rng", ch.ix, ch.iz])
	var own := ch.owned_rect()
	var trees := 0
	var shrubs := 0
	for s: Array in list:
		var p: Vector2 = s[0]
		if not own.has_point(p):
			continue
		var at := Vector3(p.x, CityChunk.SIDEWALK_TOP + YardFill.LIFT, p.y)
		if int(s[1]) == 0:
			if trees >= MAX_TREES:
				continue
			trees += 1
			var sp: int = SPECIES[int(s[2])]
			var yaw := h01([ch.plan.seed, p, "rc4_yaw"]) * TAU
			var tint := Color(0.9 + 0.2 * h01([p, "r"]), 0.92 + 0.16 * h01([p, "g"]), 0.88 + 0.14 * h01([p, "b"]))
			if LaTrees.enabled:
				var v := absi(hash([ch.plan.seed, ch.ix, ch.iz, sp, "la_v"])) % LaTrees.VARIANTS
				var sc := LaTrees.scale_for(sp, float(s[3]))
				LaTrees._add(ch, sp, v, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(sc, sc, sc)), at), tint)
			else:
				LotFill._tree(ch, at, rng)
		else:
			if shrubs >= MAX_SHRUBS:
				continue
			shrubs += 1
			YardFill._shrub(ch, p, rng, float(s[3]))
	ch.set_meta("rc4_stack_counts", [trees, shrubs])


## The LOD ring and the far city (Skyline, beside MidCity.yard_trees): the same spots as canopies.
## `gy` is the chunk's ground (a Callable(x, z)). Returns how many it planted.
static func far_trees(plan: CityPlan, k: Vector2i, gy: Callable, veg: Array, colors: Array, customs: Array) -> int:
	var n := 0
	for s: Array in spots(plan, k.x, k.y):
		var p: Vector2 = s[0]
		var h: float = s[3]
		var r: float = s[4]
		var g: float = float(gy.call(p.x, p.y)) + CityChunk.SIDEWALK_TOP
		var th: float
		var lift: float
		var col: Color
		if int(s[1]) == 0:
			th = h * 0.62
			lift = h - th
			col = FAR_GREENS[int(s[2])]
		else:
			th = h * 1.1
			lift = 0.0
			col = FAR_SHRUB
		var yaw := h01([plan.seed, p, "rc4_yaw"]) * TAU
		veg.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(r, th, r * 0.9)), Vector3(p.x, g + lift + th * 0.5, p.y)))
		colors.append(col)
		customs.append(Color(1.0, 0.0, 0.0, 0.0))
		n += 1
	return n


# --- 3. The columns --------------------------------------------------------------------------------

## A stack column's drawn (and collision) radius: FreewayStack's `r`, thicker for a tall one.
static func column_r(c: Dictionary) -> float:
	var r: float = c.r
	if not enabled:
		return r
	var tall := float(c.top) - float(c.base)
	return r * lerpf(1.0, COLUMN_GAIN, smoothstep(COLUMN_SHORT, COLUMN_TALL, tall))


# --- 4. The connectors' traffic --------------------------------------------------------------------

## Cars kept on each connector at `hour` (StackTraffic's `base` is its off-peak count).
static func cars_per_link(base: int, hour: float) -> int:
	if not enabled or is_nan(hour):
		return base
	var h := fposmod(hour, 24.0)
	var f := 0.6
	if h >= 6.0 and h < 22.0:
		f = 1.4
	# The peaks: 7-9:30 and 15:30-19 (LA's evening rush runs long).
	f = maxf(f, 2.4 * _bump(h, 6.5, 7.5, 9.0, 10.0))
	f = maxf(f, 2.6 * _bump(h, 15.0, 16.0, 18.75, 19.75))
	return maxi(base, roundi(float(base) * f)) if f >= 1.0 else maxi(1, roundi(float(base) * f))


static func _bump(h: float, a: float, b: float, c: float, d: float) -> float:
	return smoothstep(a, b, h) * (1.0 - smoothstep(c, d, h))
