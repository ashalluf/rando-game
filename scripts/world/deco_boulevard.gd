class_name DecoBoulevard
extends RefCounted
## Wilshire's 1920s-30s character on midtown's boulevards (VISUAL_ROADMAP #59): among the newer
## buildings on a lot that fronts a boulevard (a road 24 m wide or more - Wilshire is one, pinned
## through MacArthur Park by DowntownReal, and the seeded midtown's avenues carry it on west),
## a share of lots build a deco building instead of their Building:
##
##   TOWER       zigzag moderne: a three-storey base, a shaft set back twice, vertical piers on
##               every bay line ending in stepped finials over the parapet, chevron spandrels, a
##               zigzag frieze round each setback, a stepped crown with a spire (floodlit at night).
##   CORNER      streamline moderne on a block corner: the corner rounded in glass block, ribbon
##               windows, speed lines wrapping it, a canopy with downlights and a neon strip, a
##               pylon fin at the corner carrying the building's name in neon.
##   THEATRE     a deco movie palace (one a block at most): fluted pilasters, a stepped central
##               tower, a vertical blade sign with its name in neon and a chase of bulbs, a
##               marquee with readerboards and bulbs. Downtown's theatres are Broadway's; this is
##               the boulevard's one.
##   APARTMENTS  four to seven storeys, a stepped centre bay rising over the parapet, a portal
##               with the building's name over the door (gilt by day, neon at night).
##   COURTYARD   Spanish courtyard apartments: three two-storey stucco wings round a garden open
##               to the street, clay gable roofs, a tiled fountain, an arched gate with the name.
##
## Every roll is a hash of the plan's seed and the lot (`_h01`), never a chunk, block or Building
## rng: the planned Building is never made, the pad roll is already spent when the chunk asks
## (CityChunk._build_lot()), so nothing else on the block moves. `lot_plan()` is pure - the LOD
## chunks, the far city's capture and the checks ask the same question the FULL chunk does.
## Names are invented. Far: LOD chunks and the far city draw each massing box as a plain
## `lod_box` (building_lod.gdshader's old, uncoded path: the facade colour and a window style),
## not FarBuilding's coded copy - the deco facade has no code there.
## `DECO=0` in the environment turns it off (the A/B).

static var enabled: bool = OS.get_environment("DECO") != "0"

enum Kind { NONE, TOWER, CORNER, THEATRE, APARTMENTS, COURTYARD }

## Of the lots that front a boulevard, the share that are deco: Wilshire itself (pinned real
## street, the one LA's deco lines), and any other boulevard.
const WILSHIRE_ODDS := 0.75
const ODDS := 0.3
const WILSHIRE := "WILSHIRE BLVD"
## Of those on a corner, the share that are streamline moderne.
const CORNER_ODDS := 0.45
## Streamline corners are low buildings: a lot planned taller than this stays a tower or flats.
const CORNER_MAX_HEIGHT := 30.0
## The share of blocks that may hold a theatre, and of their big lots the share that is one (one
## a block at most).
const THEATRE_BLOCKS := 0.12
const THEATRE_ODDS := 0.5
## Of the deep, low lots, the share that are courtyard apartments.
const COURTYARD_ODDS := 0.5
## A road this wide is a boulevard (CityPlan.avenue_width, Wilshire's 24 m).
const BOULEVARD_WIDTH := 23.9
## Margin to a neighbouring lot (the back of the pavement is the property line: no margin).
const SIDE_MARGIN := 0.6
## Palms along a deco frontage: one every PALM_STEP metres, PALM_KERB in from the kerb, mature
## (PALM_SCALE times the street palm's size), kept PALM_CLEAR off anything already on the kerb.
const PALM_STEP := 11.5
const PALM_KERB := 0.7
const PALM_SCALE := Vector2(1.35, 1.7)
const PALM_CLEAR := 3.2

## Palettes, display (sRGB) numbers. `wall` is the windowed walls' facade colour, `pier` /
## `major` the piers (kind in `pier_k` / `major_k`), `crown` the crown, `span` the spandrels,
## `trim` metalwork, `tint` the glass, `frame` the window frames.
const PALETTES := {
	"jade": {"key": "deco_jade", "wall": Color(0.86, 0.81, 0.68), "pier": Color(0.88, 0.84, 0.72), "pier_k": 0,
		"major": Color(0.22, 0.48, 0.39), "major_k": 1, "crown": Color(0.22, 0.48, 0.39), "crown_k": 1,
		"span": Color(0.23, 0.44, 0.37), "trim": Color(0.80, 0.63, 0.30), "tint": Color(0.20, 0.27, 0.26),
		"frame": Color(0.26, 0.21, 0.15), "base": Color(0.08, 0.09, 0.09)},
	"turquoise": {"key": "deco_turq", "wall": Color(0.36, 0.62, 0.60), "pier": Color(0.33, 0.62, 0.60), "pier_k": 1,
		"major": Color(0.83, 0.66, 0.30), "major_k": 1, "crown": Color(0.83, 0.66, 0.30), "crown_k": 1,
		"span": Color(0.15, 0.25, 0.40), "trim": Color(0.84, 0.66, 0.30), "tint": Color(0.18, 0.24, 0.30),
		"frame": Color(0.62, 0.50, 0.24), "base": Color(0.07, 0.10, 0.12)},
	"buff": {"key": "deco_buff", "wall": Color(0.80, 0.71, 0.57), "pier": Color(0.82, 0.74, 0.60), "pier_k": 0,
		"major": Color(0.82, 0.74, 0.60), "major_k": 0, "crown": Color(0.36, 0.53, 0.45), "crown_k": 1,
		"span": Color(0.58, 0.34, 0.25), "trim": Color(0.55, 0.40, 0.24), "tint": Color(0.24, 0.26, 0.27),
		"frame": Color(0.30, 0.22, 0.15), "base": Color(0.33, 0.20, 0.15)},
	"ivory": {"key": "deco_ivory", "wall": Color(0.90, 0.88, 0.82), "pier": Color(0.92, 0.90, 0.85), "pier_k": 0,
		"major": Color(0.92, 0.90, 0.85), "major_k": 0, "crown": Color(0.80, 0.82, 0.84), "crown_k": 6,
		"span": Color(0.20, 0.21, 0.22), "trim": Color(0.78, 0.80, 0.82), "tint": Color(0.21, 0.24, 0.28),
		"frame": Color(0.62, 0.64, 0.66), "base": Color(0.05, 0.05, 0.06)},
	# Streamline moderne: white or pastel render, the speed lines in `span`.
	"sl_white": {"key": "deco_sl_white", "wall": Color(0.92, 0.91, 0.87), "span": Color(0.20, 0.45, 0.42), "trim": Color(0.78, 0.80, 0.82),
		"neon": Color(0.25, 0.95, 0.85), "sign": Color(0.20, 0.45, 0.42), "tint": Color(0.24, 0.30, 0.33), "frame": Color(0.70, 0.72, 0.74),
		"base": Color(0.12, 0.30, 0.28), "windows": Building.WindowStyle.RIBBON},
	"sl_peach": {"key": "deco_sl_peach", "wall": Color(0.93, 0.80, 0.68), "span": Color(0.40, 0.24, 0.16), "trim": Color(0.78, 0.80, 0.82),
		"neon": Color(1.0, 0.35, 0.55), "sign": Color(0.40, 0.24, 0.16), "tint": Color(0.26, 0.28, 0.30), "frame": Color(0.68, 0.70, 0.72),
		"base": Color(0.30, 0.18, 0.13), "windows": Building.WindowStyle.RIBBON},
	"sl_mint": {"key": "deco_sl_mint", "wall": Color(0.80, 0.89, 0.82), "span": Color(0.13, 0.30, 0.22), "trim": Color(0.78, 0.80, 0.82),
		"neon": Color(1.0, 0.62, 0.22), "sign": Color(0.85, 0.20, 0.16), "tint": Color(0.22, 0.28, 0.27), "frame": Color(0.68, 0.70, 0.72),
		"base": Color(0.10, 0.22, 0.16), "windows": Building.WindowStyle.RIBBON},
	# Apartments.
	"ap_cream": {"key": "deco_ap_cream", "wall": Color(0.90, 0.85, 0.72), "pier": Color(0.92, 0.87, 0.75), "span": Color(0.45, 0.58, 0.52),
		"trim": Color(0.82, 0.64, 0.30), "neon": Color(1.0, 0.72, 0.35), "tint": Color(0.24, 0.26, 0.26), "frame": Color(0.28, 0.32, 0.30), "base": Color(0.45, 0.42, 0.38)},
	"ap_peach": {"key": "deco_ap_peach", "wall": Color(0.92, 0.77, 0.66), "pier": Color(0.94, 0.82, 0.72), "span": Color(0.55, 0.36, 0.30),
		"trim": Color(0.82, 0.64, 0.30), "neon": Color(1.0, 0.36, 0.48), "tint": Color(0.24, 0.26, 0.26), "frame": Color(0.25, 0.30, 0.30), "base": Color(0.42, 0.33, 0.28)},
	"ap_yellow": {"key": "deco_ap_yellow", "wall": Color(0.93, 0.87, 0.64), "pier": Color(0.95, 0.90, 0.70), "span": Color(0.30, 0.45, 0.52),
		"trim": Color(0.80, 0.62, 0.28), "neon": Color(0.35, 0.80, 1.0), "tint": Color(0.24, 0.26, 0.27), "frame": Color(0.22, 0.30, 0.34), "base": Color(0.40, 0.38, 0.32)},
	"ap_mint": {"key": "deco_ap_mint", "wall": Color(0.78, 0.87, 0.80), "pier": Color(0.83, 0.91, 0.85), "span": Color(0.20, 0.36, 0.30),
		"trim": Color(0.82, 0.64, 0.30), "neon": Color(1.0, 0.52, 0.30), "tint": Color(0.23, 0.26, 0.26), "frame": Color(0.24, 0.30, 0.28), "base": Color(0.36, 0.40, 0.36)},
	# Spanish courtyard apartments: lime-white or pale render, wood trim.
	"sp_white": {"key": "deco_sp_white", "wall": Color(0.93, 0.91, 0.86), "trim": Color(0.20, 0.27, 0.20), "tint": Color(0.22, 0.24, 0.24),
		"frame": Color(0.24, 0.30, 0.22), "base": Color(0.60, 0.42, 0.30), "wall_set": ["plaster_painted", 3.0]},
	"sp_pink": {"key": "deco_sp_pink", "wall": Color(0.93, 0.80, 0.75), "trim": Color(0.32, 0.20, 0.14), "tint": Color(0.22, 0.24, 0.24),
		"frame": Color(0.34, 0.22, 0.16), "base": Color(0.60, 0.42, 0.30), "wall_set": ["plaster_painted", 3.0]},
	"sp_cream": {"key": "deco_sp_cream", "wall": Color(0.93, 0.87, 0.73), "trim": Color(0.16, 0.24, 0.36), "tint": Color(0.22, 0.24, 0.24),
		"frame": Color(0.18, 0.26, 0.36), "base": Color(0.60, 0.42, 0.30), "wall_set": ["plaster_painted", 3.0]},
	# The theatre: a cream front, the blade sign's enamel and neon.
	"th_cream": {"key": "deco_th_cream", "wall": Color(0.86, 0.80, 0.66), "pier": Color(0.88, 0.83, 0.70), "crown": Color(0.80, 0.62, 0.28),
		"span": Color(0.50, 0.12, 0.12), "trim": Color(0.82, 0.64, 0.30), "neon": Color(1.0, 0.30, 0.20), "sign": Color(0.50, 0.10, 0.10),
		"tint": Color(0.20, 0.20, 0.22), "frame": Color(0.40, 0.30, 0.15), "base": Color(0.10, 0.08, 0.08), "wall_set": ["plaster_painted", 3.0]},
	"th_blue": {"key": "deco_th_blue", "wall": Color(0.82, 0.80, 0.74), "pier": Color(0.84, 0.82, 0.77), "crown": Color(0.25, 0.42, 0.62),
		"span": Color(0.14, 0.22, 0.42), "trim": Color(0.80, 0.80, 0.82), "neon": Color(0.30, 0.65, 1.0), "sign": Color(0.12, 0.20, 0.42),
		"tint": Color(0.20, 0.20, 0.22), "frame": Color(0.60, 0.62, 0.64), "base": Color(0.06, 0.07, 0.10), "wall_set": ["plaster_painted", 3.0]},
}
const TOWER_PALETTES := ["jade", "jade", "turquoise", "buff", "ivory", "buff"]
const CORNER_PALETTES := ["sl_white", "sl_white", "sl_peach", "sl_mint"]
const APARTMENT_PALETTES := ["ap_cream", "ap_peach", "ap_yellow", "ap_mint", "ap_cream"]
const COURTYARD_PALETTES := ["sp_white", "sp_white", "sp_pink", "sp_cream"]
const THEATRE_PALETTES := ["th_cream", "th_blue"]

## Invented names: none is a real building, theatre or business.
const THEATRE_NAMES := ["VESPERA", "ORIOLE", "SOLANDO", "BELMIRA", "CORALUX", "STARLA", "LUMIERA", "AVALINE",
	"MOONGATE", "SERAFINO"]
const APARTMENT_NAMES := ["THE ALDERMERE", "THE CORVALLE", "THE LINDENHURST", "THE BELLAVISTE", "THE MARQUELLE",
	"THE ORLANDA", "THE VALEMONT", "THE SERENDALE", "THE HALCYRA", "THE WYNDMOOR", "THE CASSIVALE", "THE ROWENA ARMS",
	"THE DELMORA", "THE FENWICK ARMS", "THE IVORLEA", "THE GRAYMONT", "THE SOLVIENNE", "THE ARDENLY", "THE BRISTELLE",
	"THE MONTCLAIRE ARMS"]
const COURTYARD_NAMES := ["CASA LUNARA", "EL PATIO DORADO", "CASA MIRASOL", "LOS NARANJOS", "VILLA ALEGRA", "CASA PALOMAR",
	"LAS GLICINIAS", "CASA ESTRELLITA", "EL JARDIN AZUL", "VILLA DE LOS ROBLES"]
const CORNER_NAMES := ["ZEPHYR", "AEROLUX", "STRATA", "NOVALINE", "CRESTA", "HALO", "SKYVUE", "ORBITA", "VELOX",
	"MERIDIAN", "PACIFICA", "COMETA"]

static var _cache: Dictionary = {}


static func wanted(ch: CityChunk, district: int) -> bool:
	return enabled and ch.zone == MacroMap.Zone.CITY and district == CityPlan.District.MIDTOWN


static func _h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) / 100003.0


static func _pick(list: Array, parts: Array) -> Variant:
	return list[absi(hash(parts)) % list.size()]


# --- The pure plan ------------------------------------------------------------------------------

## The road on each side of a block: [axis, index] for 0 -Z, 1 +Z, 2 -X, 3 +X.
static func _side_road(bx: int, bz: int, side: int) -> Array:
	match side:
		0:
			return [CityPlan.AXIS_Z, bz]
		1:
			return [CityPlan.AXIS_Z, bz + 1]
		2:
			return [CityPlan.AXIS_X, bx]
		_:
			return [CityPlan.AXIS_X, bx + 1]


## Every lot's plan on a block (the deco ones; a theatre at most once), cached by block.
static func block_plans(plan: CityPlan, bx: int, bz: int) -> Dictionary:
	if not enabled:
		return {}
	var key := [plan.seed, bx, bz]
	if _cache.has(key):
		return _cache[key]
	if _cache.size() > 4096:
		_cache.clear()
	var out := {}
	var b := plan.block(bx, bz)
	if b.district == CityPlan.District.MIDTOWN and b.kind == CityPlan.BlockKind.BUILDINGS and not b.has("site") \
			and not b.has("grounds") and not plan.river_block(bx, bz):
		var theatre := false
		for lot: Dictionary in plan.lots(bx, bz):
			var lp := _plan_lot(plan, bx, bz, b, lot, theatre)
			if not lp.is_empty():
				theatre = theatre or lp.kind == Kind.THEATRE
				out[lot.seed] = lp
	_cache[key] = out
	return out


## The deco plan of one lot, or {} (an ordinary Building stands there).
static func lot_plan(plan: CityPlan, bx: int, bz: int, lot: Dictionary) -> Dictionary:
	return block_plans(plan, bx, bz).get(lot.seed, {})


static func _plan_lot(plan: CityPlan, bx: int, bz: int, b: Dictionary, lot: Dictionary, theatre_taken: bool) -> Dictionary:
	if lot.yard or lot.get("parking", false) or not lot.edge:
		return {}
	# A lot another feature already builds on (CityChunk._build_lot() asks them first): the plan
	# leaves it, so a theatre is not spent on a lot that a station or a palace stands on.
	if FireStation.claims(plan, bx, bz, lot) or PoliceStation.claims(plan, bx, bz, lot) \
			or Broadway.claims(plan, bx, bz, lot):
		return {}
	var inner: Rect2 = (b.rect as Rect2).grow(-plan.sidewalk_width)
	var cell: Rect2 = lot.cell
	var on := [absf(cell.position.y - inner.position.y) < 0.6, absf(cell.end.y - inner.end.y) < 0.6,
		absf(cell.position.x - inner.position.x) < 0.6, absf(cell.end.x - inner.end.x) < 0.6]
	var side := -1
	var best := 0.0
	for s in 4:
		if not on[s]:
			continue
		var r := _side_road(bx, bz, s)
		var wid := plan.road_width(r[0], r[1])
		if wid >= BOULEVARD_WIDTH and wid > best + 0.01:
			best = wid
			side = s
	if side < 0:
		return {}
	var sr := _side_road(bx, bz, side)
	var odds := WILSHIRE_ODDS if plan.road_name(sr[0], sr[1]) == WILSHIRE else ODDS
	if _h01([plan.seed, lot.seed, "deco"]) >= odds:
		return {}
	var f := Industrial.frame(cell, side)
	var flen: float = f.len
	var fdepth: float = f.depth
	# Which ends of the frontage are on a street (no margin there), and the corner, if any.
	var m0 := SIDE_MARGIN
	var m1 := SIDE_MARGIN
	var corner := 0
	var back := SIDE_MARGIN
	for s in 4:
		if not on[s] or s == side:
			continue
		if (s < 2) == (side < 2):
			back = 0.0
			continue
		var edge := inner.position.y if s == 0 else (inner.end.y if s == 1 else (inner.position.x if s == 2 else inner.end.x))
		var p0 := Industrial.fp(f, 0.0, 0.0)
		var p1 := Industrial.fp(f, flen, 0.0)
		var c0 := p0.y if s < 2 else p0.x
		var c1 := p1.y if s < 2 else p1.x
		if absf(c0 - edge) < absf(c1 - edge):
			m0 = 0.0
			corner = 1
		else:
			m1 = 0.0
			corner = -1
	var w := flen - m0 - m1
	var d := fdepth - back
	if w < 11.0 or d < 10.0:
		return {}
	var boost := plan.macro.skyline_boost(lot.center) if plan.macro else 0.0
	var h := plan.lot_height(lot.seed, CityPlan.District.MIDTOWN, boost)
	var kind := Kind.NONE
	var hk := _h01([plan.seed, lot.seed, "deco_kind"])
	if corner != 0 and w >= 13.0 and d >= 12.0 and h < CORNER_MAX_HEIGHT and hk < CORNER_ODDS:
		kind = Kind.CORNER
	elif not theatre_taken and _h01([plan.seed, bx, bz, "deco_theatre_block"]) < THEATRE_BLOCKS and w >= 22.0 and d >= 26.0 and h >= 14.0 and _h01([plan.seed, lot.seed, "deco_theatre"]) < THEATRE_ODDS:
		kind = Kind.THEATRE
	elif h >= 26.0 and w >= 17.0 and d >= 17.0:
		kind = Kind.TOWER
	elif d >= 24.0 and w >= 21.0 and h < 22.0 and _h01([plan.seed, lot.seed, "deco_court"]) < COURTYARD_ODDS:
		kind = Kind.COURTYARD
	else:
		kind = Kind.APARTMENTS
	var pal_list: Array = TOWER_PALETTES
	var names: Array = []
	match kind:
		Kind.CORNER:
			pal_list = CORNER_PALETTES
			names = CORNER_NAMES
		Kind.THEATRE:
			pal_list = THEATRE_PALETTES
			names = THEATRE_NAMES
		Kind.APARTMENTS:
			pal_list = APARTMENT_PALETTES
			names = APARTMENT_NAMES
		Kind.COURTYARD:
			pal_list = COURTYARD_PALETTES
			names = COURTYARD_NAMES
	var u_mid := (m0 + flen - m1) * 0.5
	var lp := {
		"kind": kind, "frame": f, "side": side, "corner": corner, "w": w, "d": d, "h": h,
		"u_mid": u_mid, "seed": lot.seed, "cell": cell, "center": lot.center,
		"palette": _pick(pal_list, [plan.seed, lot.seed, "deco_palette"]),
		"name": _pick(names, [plan.seed, lot.seed, "deco_name"]) if not names.is_empty() else "",
		"foot": Industrial.fr(f, m0, 0.0, flen - m1, d),
		"road": _side_road(bx, bz, side),
	}
	lp.boxes = massing(lp)
	return lp


## The building frame's transform into the chunk (y the building's foot): local +x along the
## street (against the frame's u), +z toward the street, the front face on z 0.
static func frame_xform(lp: Dictionary, y: float) -> Transform3D:
	var f: Dictionary = lp.frame
	var a: Vector2 = f.a
	var nn: Vector2 = f.n
	var o := Industrial.fp(f, float(lp.u_mid), 0.0)
	return Transform3D(Basis(Vector3(-a.x, 0.0, -a.y), Vector3.UP, Vector3(-nn.x, 0.0, -nn.y)), Vector3(o.x, y, o.y))


# --- Massing (pure: what the LOD boxes, the collision and the occluder are) ---------------------

static func _snap_floor(y: float, ground: float, floor_h: float) -> float:
	return ground + maxf(1.0, roundf((y - ground) / floor_h)) * floor_h


## The tower's tiers: {base, t1..t3 [x0, x1, z0, z1, y0, y1], crown}, all building space.
static func tower_tiers(lp: Dictionary) -> Dictionary:
	var w: float = lp.w
	var d: float = lp.d
	var h: float = lp.h
	var g := DecoBuild.GROUND_H
	var fl := DecoBuild.FLOOR_H
	var hb := g + 2.0 * fl
	var crown_h := clampf(h * 0.24, 7.0, 15.0)
	var floors := maxi(4, floori((h - crown_h - g) / fl))
	var hs := g + float(floors) * fl
	var w1 := w if w < 26.0 else w - 4.0
	var d1 := minf(d, maxf(15.0, d * 0.72))
	var y1 := _snap_floor(lerpf(hb, hs, 0.62), g, fl)
	var y2 := _snap_floor(lerpf(hb, hs, 0.84), g, fl)
	y1 = clampf(y1, hb + fl, hs - 2.0 * fl)
	y2 = clampf(y2, y1 + fl, hs - fl)
	var i2 := minf(2.2, w1 * 0.08)
	var i3 := minf(2.0, w1 * 0.08)
	var t1 := [-w1 * 0.5, w1 * 0.5, -d1, 0.0, hb, y1]
	var t2 := [-w1 * 0.5 + i2, w1 * 0.5 - i2, -d1 + i2, -i2, y1, y2]
	var t3 := [-w1 * 0.5 + i2 + i3, w1 * 0.5 - i2 - i3, -d1 + i2 + i3, -i2 - i3, y2, hs]
	var w3: float = float(t3[1]) - float(t3[0])
	var d3: float = float(t3[3]) - float(t3[2])
	var wc := clampf(w3 * 0.44, 5.0, 12.0)
	var dc := clampf(d3 * 0.44, 4.5, 12.0)
	var cz := (float(t3[2]) + float(t3[3])) * 0.5
	var ct := crown_h * 0.5
	return {"base": [-w * 0.5, w * 0.5, -d, 0.0, 0.0, hb], "t1": t1, "t2": t2, "t3": t3,
		"crown": [-wc * 0.5, wc * 0.5, cz - dc * 0.5, cz + dc * 0.5, hs + 1.2, hs + 1.2 + ct],
		"top": h, "hs": hs, "crown_h": crown_h, "cz": cz}


static func corner_dims(lp: Dictionary) -> Dictionary:
	var storeys := 2 if float(lp.h) < 11.0 or _h01([lp.seed, "sl_storeys"]) < 0.35 else 3
	var top := DecoBuild.GROUND_H + float(storeys - 1) * 3.6
	var d := minf(float(lp.d), 24.0)
	var r := clampf(minf(float(lp.w), d) * 0.28, 3.5, 6.0)
	return {"storeys": storeys, "top": top, "d": d, "r": r, "parapet": 1.3}


static func theatre_dims(lp: Dictionary) -> Dictionary:
	var hf := clampf(float(lp.h), 14.0, 18.0)
	return {"hf": hf, "front_d": 9.0, "hall_h": hf - 2.5, "tower_w": 8.4, "tower_h": hf + 5.0}


static func apartment_dims(lp: Dictionary) -> Dictionary:
	var storeys := clampi(roundi((float(lp.h) - 1.0) / 3.2), 3, 7)
	return {"storeys": storeys, "top": 1.0 + float(storeys) * 3.2, "d": minf(float(lp.d), 22.0), "floor": 3.2, "ground": 1.0}


static func courtyard_dims(lp: Dictionary) -> Dictionary:
	var wing := clampf(float(lp.w) * 0.3, 7.0, 9.0)
	return {"wing": wing, "front": 1.6, "eave": 6.4, "pitch": 0.42, "rear": minf(9.0, float(lp.d) * 0.32)}


## The massing boxes [centre, size, display colour, window style] in building space.
static func massing(lp: Dictionary) -> Array:
	var pal: Dictionary = PALETTES[lp.palette]
	var wall: Color = pal.wall
	var out := []
	match int(lp.kind):
		Kind.TOWER:
			var t := tower_tiers(lp)
			for k: String in ["base", "t1", "t2", "t3", "crown"]:
				var r: Array = t[k]
				out.append([Vector3((r[0] + r[1]) * 0.5, (r[4] + r[5]) * 0.5, (r[2] + r[3]) * 0.5),
					Vector3(r[1] - r[0], r[5] - r[4], r[3] - r[2]), (pal.crown as Color) if k == "crown" else wall, 0])
		Kind.CORNER:
			var c := corner_dims(lp)
			var top: float = c.top + float(c.parapet)
			out.append([Vector3(0.0, top * 0.5, -float(c.d) * 0.5), Vector3(float(lp.w), top, float(c.d)), wall, 1])
		Kind.THEATRE:
			var t := theatre_dims(lp)
			var fd: float = t.front_d
			var dd: float = lp.d
			out.append([Vector3(0.0, float(t.hf) * 0.5, -fd * 0.5), Vector3(float(lp.w), float(t.hf), fd), wall, 0])
			out.append([Vector3(0.0, float(t.hall_h) * 0.5, -fd - (dd - fd) * 0.5), Vector3(float(lp.w) - 1.0, float(t.hall_h), dd - fd), wall * 0.92, 0])
			out.append([Vector3(0.0, float(t.tower_h) * 0.5, -1.6), Vector3(float(t.tower_w), float(t.tower_h), 3.2), pal.crown, 0])
		Kind.APARTMENTS:
			var a := apartment_dims(lp)
			out.append([Vector3(0.0, float(a.top) * 0.5, -float(a.d) * 0.5), Vector3(float(lp.w), float(a.top), float(a.d)), wall, 0])
		Kind.COURTYARD:
			var c := courtyard_dims(lp)
			var wg: float = c.wing
			var w: float = lp.w
			var d: float = lp.d
			var e: float = c.eave + 1.0
			var f0: float = c.front
			out.append([Vector3(-w * 0.5 + wg * 0.5, e * 0.5, -f0 - (d - f0) * 0.5), Vector3(wg, e, d - f0), wall, 0])
			out.append([Vector3(w * 0.5 - wg * 0.5, e * 0.5, -f0 - (d - f0) * 0.5), Vector3(wg, e, d - f0), wall, 0])
			out.append([Vector3(0.0, e * 0.5, -d + float(c.rear) * 0.5), Vector3(w - 2.0 * wg, e, float(c.rear)), wall, 0])
	return out


# --- The chunk ----------------------------------------------------------------------------------

static func _state(ch: CityChunk) -> Dictionary:
	if not ch.has_meta("deco"):
		ch.set_meta("deco", {"orn": null, "walls": {}, "lots": [], "body": null, "lights": []})
	return ch.get_meta("deco")


static func _orn(ch: CityChunk) -> DecoBuild.Orn:
	var st := _state(ch)
	if st.orn == null:
		st.orn = DecoBuild.Orn.new()
	return st.orn


static func _walls(ch: CityChunk, pal: Dictionary) -> DecoBuild.Walls:
	var st := _state(ch)
	var key: String = pal.key
	if not (st.walls as Dictionary).has(key):
		st.walls[key] = DecoBuild.Walls.new()
	return st.walls[key]


## CityChunk._build_lot(), on a lot whose pad roll is made: builds the deco building when the plan
## says so and returns true (the chunk then builds no Building there).
static func build_lot(ch: CityChunk, lot: Dictionary) -> bool:
	if not wanted(ch, ch.plan.block(ch.ix, ch.iz).district):
		return false
	var lp := lot_plan(ch.plan, ch.ix, ch.iz, lot)
	if lp.is_empty():
		return false
	var foot: Rect2 = lp.foot
	var c := foot.get_center()
	var g := ch._gy(c.x, c.y)
	var gmin := g
	for k in 4:
		var q := foot.position + foot.size * Vector2(float(k & 1), float((k >> 1) & 1))
		gmin = minf(gmin, ch._gy(q.x, q.y))
	var plinth := g - gmin + 0.5
	var pal: Dictionary = PALETTES[lp.palette]
	var cell: Rect2 = lp.cell
	# The ground round it: the block's forecourt paving out to the cell (LotFill's).
	if LotFill.wanted(ch, CityPlan.District.MIDTOWN):
		LotFill._ground(ch, cell, "paving%d" % LotFill._paving_for(ch))
	if ch.level == CityChunk.Level.FULL and not ch.capturing:
		var xf := frame_xform(lp, CityChunk.SIDEWALK_TOP + g)
		var o := _orn(ch)
		o.xf = xf
		var walls := _walls(ch, pal)
		walls.xf = xf
		walls.base_y = CityChunk.SIDEWALK_TOP + g
		match int(lp.kind):
			Kind.TOWER:
				_build_tower(o, walls, lp, pal, plinth)
			Kind.CORNER:
				_build_corner(o, walls, lp, pal, plinth)
			Kind.THEATRE:
				_build_theatre(ch, o, walls, lp, pal, plinth, xf)
			Kind.APARTMENTS:
				_build_apartments(o, walls, lp, pal, plinth)
			Kind.COURTYARD:
				_build_courtyard(ch, o, walls, lp, pal, plinth, xf)
		var st := _state(ch)
		if st.body == null:
			var body := StaticBody3D.new()
			body.name = "DecoBody"
			body.collision_layer = 1
			body.collision_mask = 0
			ch.add_child(body)
			st.body = body
		for mb: Array in lp.boxes:
			var cs := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = mb[1]
			cs.shape = shape
			cs.transform = xf * Transform3D(Basis(), mb[0])
			(st.body as StaticBody3D).add_child(cs)
			ch._occluder_boxes.append([xf, mb[0], mb[1]])
		(st.lots as Array).append(lp)
		# The forecourt round the building (its private rng: LotFill's own, by lot).
		var keep: Array[Rect2] = [foot]
		if int(lp.kind) == Kind.COURTYARD:
			keep = []
		if not keep.is_empty():
			var rng := LotFill._rng(ch, "deco_forecourt", lot.seed)
			for r: Rect2 in LotFill._minus(cell.grow(-0.4), keep, 0.3):
				LotFill.forecourt(ch, r, rng)
	else:
		var xf := frame_xform(lp, CityChunk.SIDEWALK_TOP)
		var custom_seed := float(int(lp.seed) % 997) / 997.0
		for mb: Array in lp.boxes:
			var at: Vector3 = xf * (mb[0] as Vector3)
			var size: Vector3 = mb[1]
			_lod_box(ch, Transform3D(xf.basis.scaled(Vector3.ONE) * Basis().scaled(size), at), mb[2],
				Color(float(mb[3]) / 4.0, 0.3, custom_seed, 0.0))
			var wsize := (xf.basis * size).abs()
			ch._add_lod_shape(wsize, at + Vector3(0.0, g, 0.0))
			ch._occluder_boxes.append([Transform3D(xf.basis, Vector3(xf.origin.x, xf.origin.y + g, xf.origin.z)), mb[0], mb[1]])
	ch.building_count += 1
	return true


static func _lod_box(ch: CityChunk, xf: Transform3D, colr: Color, custom: Color) -> void:
	ch._batch.add("lod_box", PropFactory.unit_box(), xf, colr, custom)


## The chunk's finish (CityChunk._finish_build()): the ornament mesh and each palette's walls,
## a node each, and the night lights.
static func commit(ch: CityChunk) -> void:
	if not ch.has_meta("deco"):
		return
	var st: Dictionary = ch.get_meta("deco")
	if st.orn != null and (st.orn as DecoBuild.Orn).triangles() > 0:
		var mi := MeshInstance3D.new()
		mi.name = "DecoOrnament"
		mi.mesh = (st.orn as DecoBuild.Orn).commit()
		mi.material_override = DecoBuild.ornament_material()
		ch.add_child(mi)
	for key: String in st.walls:
		var w: DecoBuild.Walls = st.walls[key]
		if w.triangles() == 0:
			continue
		var mi := MeshInstance3D.new()
		mi.name = "DecoWalls_" + key
		mi.mesh = w.commit()
		var pal := _palette_by_key(key)
		mi.material_override = DecoBuild.wall_material(pal)
		ch.add_child(mi)
	st.orn = null
	st.walls = {}


static func _palette_by_key(key: String) -> Dictionary:
	for k: String in PALETTES:
		if (PALETTES[k] as Dictionary).key == key:
			return PALETTES[k]
	return PALETTES.jade


## A block step after the lots (FULL): mature palms along each deco building's boulevard kerb,
## clear of whatever already stands there, and the night pools under the canopies and marquees.
static func block_step(ch: CityChunk, block: Dictionary) -> void:
	if not ch.has_meta("deco") or ch.level != CityChunk.Level.FULL or ch.capturing:
		return
	var st: Dictionary = ch.get_meta("deco")
	if (st.lots as Array).is_empty():
		return
	var rect: Rect2 = block.rect
	# Everything already on the pavement near the kerbs (lamps, trees, signals, benches, stops).
	var taken := PackedVector2Array()
	var data: Dictionary = ch._batch.data()
	for key: String in data:
		if key in CityChunk.PAINT_KEYS or key.begins_with("text_") or key == "lod_box" or key == "shop_spill" or key == "deco_spill" or key == "patch":
			continue
		for xf: Transform3D in data[key].xforms:
			var p := Vector2(xf.origin.x, xf.origin.z)
			if rect.grow(1.0).has_point(p) and not rect.grow(-3.5).has_point(p):
				taken.append(p)
	for lp: Dictionary in st.lots:
		var f: Dictionary = lp.frame
		var nn: Vector2 = f.n
		var sw: float = ch.plan.sidewalk_width
		var u0: float = float(lp.u_mid) - float(lp.w) * 0.5
		var u1: float = float(lp.u_mid) + float(lp.w) * 0.5
		# The street trees on this frontage's pavement become mature palms where they stood (a tree
		# is no prop - nothing holds its instance index - so its pending instance can go).
		var strip := Industrial.fr(f, u0, -sw, u1, 0.0)
		var spots := PackedVector2Array()
		for key: String in data.keys():
			if not key.begins_with("tree_") or key == "tree_grate":
				continue
			var b: Dictionary = data[key]
			var xforms: Array = b.xforms
			for i in range(xforms.size() - 1, -1, -1):
				var o3: Vector3 = (xforms[i] as Transform3D).origin
				var p := Vector2(o3.x, o3.z)
				if strip.has_point(p):
					spots.append(p)
					xforms.remove_at(i)
					(b.colors as Array).remove_at(i)
					(b.custom as Array).remove_at(i)
					for t in range(taken.size() - 1, -1, -1):
						if taken[t].distance_squared_to(p) < 0.01:
							taken.remove_at(t)
		# And a palm every PALM_STEP where the pavement is clear.
		var u := u0 + 3.0
		while u < u1 - 2.0:
			var at := Industrial.fp(f, u, -(sw - PALM_KERB))
			var clear := true
			for q in taken:
				if q.distance_squared_to(at) < PALM_CLEAR * PALM_CLEAR:
					clear = false
					break
			for q in spots:
				if q.distance_squared_to(at) < PALM_STEP * PALM_STEP * 0.36:
					clear = false
					break
			if clear and not ch._under_freeway(at, CityChunk.PALM_FREEWAY_MARGIN):
				spots.append(at)
				taken.append(at)
			u += PALM_STEP
		for i in spots.size():
			var at := spots[i]
			var hp := _h01([ch.plan.seed, lp.seed, "deco_palm", i])
			var variant := absi(hash([ch.plan.seed, lp.seed, "deco_palm_v", i])) % PropFactory.PALM_VARIANTS
			var sc := lerpf(PALM_SCALE.x, PALM_SCALE.y, _h01([ch.plan.seed, lp.seed, "deco_palm_s", i]))
			var lean := -nn
			var yaw := atan2(lean.x, lean.y) - PropFactory.palm_lean(variant) + (hp - 0.5) * 0.8
			ch._batch.add("palm_%d" % variant, PropFactory.palm(variant), Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(sc, sc, sc)),
				Vector3(at.x, CityChunk.SIDEWALK_TOP, at.y)), Color(0.95 + 0.1 * hp, 1.0, 0.95))
		# The night pools under a canopy, a marquee or an apartment's door.
		for pool: Array in lp.get("pools", []):
			var xf: Transform3D = pool[0]
			ch._batch.add("deco_spill", PropFactory.shop_spill(), xf, pool[1])
	ch._batch.set_no_shadow("deco_spill")
	ch._batch.set_draw_distance("deco_spill", CityChunk.SHOP_SPILL_DISTANCE)


# --- The builders -------------------------------------------------------------------------------

static func _c(paint: Color, kind: int, flood: bool = false) -> Color:
	return DecoBuild.Orn.col(paint, kind, flood)


## A deco entrance portal on the front (z 0) centred at x: three nested stepped frames round a
## w x h opening, a bronze door screen, a sunburst over it. Returns the top of the surround.
static func _portal(o: DecoBuild.Orn, x: float, w: float, h: float, frame_c: Color, frame_k: int, trim: Color, burst: Color) -> float:
	var y := 0.0
	for s in 3:
		var k := float(s)
		var fw := 0.34 - 0.06 * k
		var out := 0.36 - 0.11 * k
		var hw := w * 0.5 + fw * (3.0 - k) * 0.9
		var top := h + 0.5 + (2.0 - k) * 0.42
		var col := _c(frame_c, frame_k)
		o.aabb(Vector3(x - hw, y, 0.0), Vector3(x - hw + fw, top, out), col)
		o.aabb(Vector3(x + hw - fw, y, 0.0), Vector3(x + hw, top, out), col)
		o.aabb(Vector3(x - hw, top - fw, 0.0), Vector3(x + hw, top, out), col)
	# The door screen: bronze, set back, with the dark lobby behind its glass.
	o.panel(Vector3(x - w * 0.5, 0.0, 0.03), Vector3.RIGHT, Vector3.UP, w, h, _c(Color(0.06, 0.06, 0.07), DecoBuild.DARK))
	for k in 5:
		var bx := x - w * 0.5 + w * float(k) / 4.0
		o.aabb(Vector3(bx - 0.04, 0.0, 0.03), Vector3(bx + 0.04, h, 0.09), _c(trim, DecoBuild.METAL))
	o.aabb(Vector3(x - w * 0.5, h * 0.62, 0.03), Vector3(x + w * 0.5, h * 0.62 + 0.08, 0.09), _c(trim, DecoBuild.METAL))
	# A sunburst transom panel over the door.
	o.panel(Vector3(x - w * 0.5, h + 0.04, 0.05), Vector3.RIGHT, Vector3.UP, w, minf(1.2, w * 0.38), _c(burst, DecoBuild.SUNBURST))
	return h + 0.5 + 2.0 * 0.42


static func _build_tower(o: DecoBuild.Orn, walls: DecoBuild.Walls, lp: Dictionary, pal: Dictionary, plinth: float) -> void:
	var t := tower_tiers(lp)
	var g := DecoBuild.GROUND_H
	var fl := DecoBuild.FLOOR_H
	var pier := _c(pal.pier, int(pal.pier_k))
	var major := _c(pal.major, int(pal.major_k))
	var crown := pal.crown as Color
	var crown_k: int = pal.crown_k
	var trim := pal.trim as Color
	var span := pal.span as Color
	var hs: float = t.hs
	var base: Array = t.base
	# The base: storefronts in the shader, a granite base course, a cornice band over them.
	var p := {"shop": true, "ground": g, "floor": fl, "base_h": 0.8, "bay": 3.0}
	DecoBuild.tier(walls, base[0], base[1], base[2], base[3], -plinth, base[5], p)
	# Its two office floors' faces have bays too (the base's upper storeys).
	var cor := DecoBuild.run_of([[Vector2(base[1], base[3]), Vector2(base[0], base[3])]])
	o.band(cor[0], cor[1], g - 0.15, g + 0.35, 0.28, _c(pal.pier, 0), 0.0, 0.0, true, true)
	o.band(cor[0], cor[1], float(base[5]) - 0.9, float(base[5]), 0.1, _c(span, DecoBuild.ZIGZAG), 0.0, 0.9)
	o.band(cor[0], cor[1], float(base[5]), float(base[5]) + 1.1, 0.0, _c(pal.pier, 0), 0.0, 0.0, true)
	o.band(cor[0], cor[1], float(base[5]) + 1.1, float(base[5]) + 1.3, 0.18, _c(pal.pier, 0), 0.0, 0.0, true, true)
	# The base's own roof edge on the sides and back: a plain parapet.
	for f: Array in DecoBuild.rect_faces(base[0], base[1], base[2], base[3]).slice(1):
		var rr := DecoBuild.run_of([f])
		o.band(rr[0], rr[1], float(base[5]), float(base[5]) + 1.1, 0.0, _c(pal.pier, 0), 0.0, 0.0, true)
	# A portal in the middle of the front.
	_portal(o, 0.0, 3.0, 3.6, pal.pier, int(pal.pier_k), trim, crown)
	# The shaft's three tiers: windowed walls, piers on the bay lines of the front and both sides,
	# chevron spandrels, and at each tier's top a zigzag frieze and a parapet the piers rise through.
	var tiers := [t.t1, t.t2, t.t3]
	for ti in 3:
		var r: Array = tiers[ti]
		var x0: float = r[0]
		var x1: float = r[1]
		var z0: float = r[2]
		var z1: float = r[3]
		var y0: float = r[4]
		var y1: float = r[5]
		var q := {"shop": false, "ground": g, "floor": fl, "bay": DecoBuild.BAY}
		DecoBuild.tier(walls, x0, x1, z0, z1, y0, y1, q)
		var rows := int(roundf((y1 - y0) / fl))
		var top_tier := ti == 2
		var flood := ti >= 1
		var vb := hs - 14.0 if flood else 0.0
		for f: Array in DecoBuild.rect_faces(x0, x1, z0, z1):
			var a: Vector2 = f[0]
			var b: Vector2 = f[1]
			var fid: int = f[2]
			var on_back := fid == 2
			# Spandrels in the bays (not on the back: it faces the neighbours).
			if not on_back:
				var first_row := int(roundf((y0 - g) / fl))
				var rows_here := maxi(0, rows - 1)
				var gy := g + float(first_row) * fl
				DecoBuild.spandrels(o, a, b, gy, fl, rows_here, _c(span, DecoBuild.CHEVRON), DecoBuild.PIER_W)
			# Piers to the parapet and finials over it.
			var fin := 1.0 if not top_tier else 1.8
			DecoBuild.piers(o, a, b, y0, y1 + 1.2, _c(pal.pier, int(pal.pier_k), flood) if not on_back else pier,
				_c(pal.major, int(pal.major_k), flood) if not on_back else major, 4, fin if not on_back else 0.0, vb)
			var rr := DecoBuild.run_of([f])
			# The frieze under the parapet and the parapet itself.
			o.band(rr[0], rr[1], y1 - 0.85, y1, 0.06, _c(span, DecoBuild.ZIGZAG, flood), vb, 0.85)
			o.band(rr[0], rr[1], y1, y1 + 1.2, 0.0, _c(pal.pier, 0, flood), vb, 0.0, true)
			o.band(rr[0], rr[1], y1 + 1.2, y1 + 1.36, 0.14, _c(pal.pier, 0, flood), vb, 0.0, true, true)
	# The crown: a fluted lantern tower on the top tier, three ziggurat steps, a spire.
	var cr: Array = t.crown
	var cx0: float = cr[0]
	var cx1: float = cr[1]
	var cz0: float = cr[2]
	var cz1: float = cr[3]
	var cy0: float = hs
	var cy1: float = cr[5]
	var fb := hs - 1.0
	o.aabb(Vector3(cx0, cy0, cz0), Vector3(cx1, cy1, cz1), _c(crown, crown_k, true), fb)
	# Fluted strips and slit windows on each face of the lantern.
	for f: Array in DecoBuild.rect_faces(cx0, cx1, cz0, cz1):
		var a: Vector2 = f[0]
		var b: Vector2 = f[1]
		var dlen := a.distance_to(b)
		var dn := (b - a) / dlen
		var out := Vector2(dn.y, -dn.x)
		var right := Vector3(dn.x, 0.0, dn.y)
		var slits := maxi(2, int(dlen / 1.6))
		for k in slits:
			var sx := a + dn * (dlen * (float(k) + 0.5) / float(slits)) + out * 0.02
			o.panel(Vector3(sx.x, cy0 + 1.2, sx.y) - right * 0.22, right, Vector3.UP, 0.44, (cy1 - cy0) - 2.6, _c(Color(0.05, 0.06, 0.07), DecoBuild.DARK))
			o.panel(Vector3(sx.x, cy0 + 0.3, sx.y) - right * 0.5 + Vector3(out.x, 0, out.y) * 0.01, right, Vector3.UP, 1.0, 0.8, _c(trim, DecoBuild.SUNBURST, true), fb)
		var rr := DecoBuild.run_of([f])
		o.band(rr[0], rr[1], cy1 - 0.7, cy1, 0.08, _c(trim, DecoBuild.ZIGZAG, true), fb, 0.7)
	# Corner piers of the lantern, stepped.
	for sx: float in [cx0, cx1]:
		for sz: float in [cz0, cz1]:
			var pw := 0.9
			o.aabb(Vector3(sx - pw * 0.5, cy0, sz - pw * 0.5), Vector3(sx + pw * 0.5, cy1 + 1.0, sz + pw * 0.5), _c(crown, crown_k, true), fb)
			DecoBuild.finial(o, sx, sz, pw, pw, cy1 + 1.0, 3, 0.6, _c(crown, crown_k, true), fb)
	var zy := cy1
	var zx0 := cx0
	var zx1 := cx1
	var zz0 := cz0
	var zz1 := cz1
	var step_h := float(t.crown_h) * 0.09
	for s in 3:
		zx0 += 0.9
		zx1 -= 0.9
		zz0 += 0.9
		zz1 -= 0.9
		if zx1 - zx0 < 1.2 or zz1 - zz0 < 1.2:
			break
		o.aabb(Vector3(zx0, zy, zz0), Vector3(zx1, zy + step_h, zz1), _c(crown if s % 2 == 0 else trim, crown_k if s % 2 == 0 else DecoBuild.METAL, true), fb)
		zy += step_h
	var top: float = t.top
	if top > zy + 1.0:
		o.spire(Vector2((cx0 + cx1) * 0.5, (cz0 + cz1) * 0.5), 0.45, 0.05, zy, top, _c(trim, DecoBuild.METAL, true), fb)


## The streamline corner. The corner (lp.corner: +1 the street corner is at +x, -1 at -x) is
## rounded at radius r; upper floors wrap it in glass block between bands of speed lines. Built in
## a canonical frame with the corner at +x and mirrored (`_mx`) when it is at -x.
static func _build_corner(o: DecoBuild.Orn, walls: DecoBuild.Walls, lp: Dictionary, pal: Dictionary, plinth: float) -> void:
	var c := corner_dims(lp)
	var w: float = lp.w
	var d: float = c.d
	var r: float = c.r
	var top: float = c.top
	var par: float = c.parapet
	var side: int = lp.corner
	var sx := float(side)
	var g := DecoBuild.GROUND_H
	var fl := 3.6
	var wall := pal.wall as Color
	var line_c := pal.span as Color
	var trim := pal.trim as Color
	var x0 := -w * 0.5
	var x1 := w * 0.5
	var ccx := x1 - r
	var ccz := -r
	# The straight faces in the walls' order (outward normal (d.z, -d.x)), canonical.
	var faces := [[Vector2(ccx, 0.0), Vector2(x0, 0.0), 0], [Vector2(x0, 0.0), Vector2(x0, -d), 1],
		[Vector2(x0, -d), Vector2(x1, -d), 2], [Vector2(x1, -d), Vector2(x1, ccz), 3]]
	var p_shop := {"shop": true, "ground": g, "floor": fl, "base_h": 0.6, "bay": 2.6, "size": Vector3(w, top, d)}
	var p_up := {"shop": false, "ground": g, "floor": fl, "bay": 2.2, "size": Vector3(w, top, d)}
	for f: Array in faces:
		var a: Vector2 = _mx(f[0], side)
		var b: Vector2 = _mx(f[1], side)
		if side < 0:
			var tmp := a
			a = b
			b = tmp
		var q := p_shop.duplicate()
		q.face = f[2]
		# The back and the inner side are blank party walls at the shop floor too.
		q.shop = f[2] == 0 or f[2] == 3
		q.blank = not q.shop
		walls.face(a, b, -plinth, g, q)
		var q2 := p_up.duplicate()
		q2.face = f[2]
		q2.blank = f[2] == 1 or f[2] == 2
		walls.face(a, b, g, top, q2)
	# The ground floor round the corner: shop glass on the curve too (u runs with the angle).
	var cxm := Vector2(ccx * sx, ccz)
	var arc_a0 := 0.0 if side > 0 else PI * 0.5
	var arc_a1 := PI * 0.5 if side > 0 else PI
	var qa := p_shop.duplicate()
	qa.face = 0
	walls.arc(cxm, r, arc_a0, arc_a1, -plinth, g, 8, qa)
	# The roof over the rounded outline.
	var outline := PackedVector2Array([_mx(Vector2(x0, -d), side), _mx(Vector2(x0, 0.0), side)])
	for k in 9:
		var ang := lerpf(PI * 0.5, 0.0, float(k) / 8.0)
		outline.append(_mx(Vector2(ccx + cos(ang) * r, ccz + sin(ang) * r), side))
	outline.append(_mx(Vector2(x1, -d), side))
	if _signed_area(outline) < 0.0:
		outline.reverse()
	walls.roof(outline, top, p_up)
	# The glass block on the curve, from the canopy to the roof.
	o.arc_wall(cxm, r - 0.02, arc_a0, arc_a1, g, top, 10, _c(Color(0.7, 0.75, 0.74), DecoBuild.GLASS_BLOCK))
	# Vertical mullions of render between the glass block, every quarter of the curve.
	for k in 3:
		var ang := lerpf(arc_a0, arc_a1, float(k + 1) / 4.0)
		var nd := Vector2(cos(ang), sin(ang))
		var pc := cxm + nd * (r + 0.06)
		o.box(Vector3(pc.x, (g + top) * 0.5, pc.y), Vector3(0.22, top - g, 0.16), _c(wall, DecoBuild.STUCCO),
			Basis(Vector3(-nd.y, 0, nd.x), Vector3.UP, Vector3(nd.x, 0, nd.y)))
	# The parapet all round, three speed lines along the street faces and the curve.
	var run := _street_run(w, d, r, side, 0.0)
	o.band(run[0], run[1], top, top + par, 0.0, _c(wall, DecoBuild.STUCCO), 0.0, 0.0, true)
	o.band(run[0], run[1], top + par, top + par + 0.12, 0.12, _c(wall, DecoBuild.STUCCO), 0.0, 0.0, true, true)
	var back := DecoBuild.run_of([[Vector2(x0, 0.0), Vector2(x0, -d)], [Vector2(x0, -d), Vector2(x1, -d)]])
	if side < 0:
		back = _flip_run(back)
	o.band(back[0], back[1], top, top + par, 0.0, _c(wall, DecoBuild.STUCCO), 0.0, 0.0, true)
	for k in 3:
		var ly := top + 0.3 + float(k) * 0.28
		o.band(run[0], run[1], ly, ly + 0.09, 0.13, _c(line_c, DecoBuild.ENAMEL), 0.0, 0.0, true, true)
	# Speed lines under the ribbon windows of every upper floor.
	for fi in range(1, int(c.storeys)):
		var sy := g + float(fi - 1) * fl + 0.45
		for k in 2:
			var ly := sy + float(k) * 0.22
			o.band(run[0], run[1], ly, ly + 0.08, 0.1, _c(line_c, DecoBuild.ENAMEL), 0.0, 0.0, true, true)
	# The canopy: a slab round the street faces and the curve, its soffit lit, a neon strip.
	_canopy(o, _street_run(w, d, r, side, 0.0), _street_run(w, d, r, side, 1.8), g - 0.75, 0.3, wall, trim, pal.neon)
	# The pylon fin on the corner's bisector with the name up both faces in neon.
	var bis := Vector2(sx, 1.0).normalized()
	var at := cxm + bis * (r + 0.05)
	var fin_out := 2.2
	var fin_c := at + bis * (fin_out * 0.5)
	var fy0 := g - 0.4
	var fy1 := top + par + 3.4
	var perp := Vector3(-bis.y, 0.0, bis.x)
	var fb := Basis(Vector3(bis.x, 0.0, bis.y), Vector3.UP, perp)
	o.box(Vector3(fin_c.x, (fy0 + fy1) * 0.5, fin_c.y), Vector3(fin_out, fy1 - fy0, 0.5), _c(pal.sign, DecoBuild.ENAMEL), fb)
	var ft := fy1
	for s in 3:
		var kk := 1.0 - 0.25 * float(s + 1)
		o.box(Vector3(at.x, ft + 0.25, at.y) + Vector3(bis.x, 0, bis.y) * (fin_out * kk * 0.5), Vector3(fin_out * kk, 0.5, 0.6), _c(wall, DecoBuild.STUCCO), fb)
		ft += 0.5
	var lead := at + bis * (fin_out + 0.02)
	o.box(Vector3(lead.x, (fy0 + fy1) * 0.5, lead.y), Vector3(0.08, fy1 - fy0 - 0.3, 0.12), _c(pal.neon, DecoBuild.NEON), fb)
	var name: String = lp.name
	var nlen := name.length()
	var room := fy1 - fy0 - 1.0
	var cap := minf(0.95, room / maxf(float(nlen), 1.0) * 0.82)
	var stepy := room / maxf(float(nlen), 1.0)
	for s: float in [1.0, -1.0]:
		var face_n := perp * s
		var right := Vector3.UP.cross(face_n)
		for i in nlen:
			var y := fy1 - 0.5 - stepy * (float(i) + 0.5)
			o.text(name[i], Vector3(fin_c.x, y - cap * 0.5, fin_c.y) + face_n * 0.26, right, Vector3.UP, cap, _c(pal.neon, DecoBuild.NEON))
	lp.pools = [_pool(lp, Vector2(0.0, 1.0), Vector3(1, 0, 0), w * 0.9, 3.0, Color(1.0, 0.86, 0.66, 0.55))]


static func _mx(p: Vector2, side: int) -> Vector2:
	return Vector2(p.x * float(side), p.y)


static func _signed_area(pts: PackedVector2Array) -> float:
	var s := 0.0
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		s += a.x * b.y - b.x * a.y
	return s * 0.5


## A polyline round the street faces of a corner building, `out` metres outside them, with its
## outward normals: along the front from the far end, round the curve, down the side street face
## to the back. Canonical (corner at +x), mirrored for a corner at -x.
static func _street_run(w: float, d: float, r: float, side: int, out: float) -> Array:
	var x0 := -w * 0.5
	var x1 := w * 0.5
	var ccx := x1 - r
	var ccz := -r
	var pts := PackedVector2Array([Vector2(x0, out)])
	var nrm := PackedVector2Array([Vector2(0.0, 1.0)])
	for k in 11:
		var ang := lerpf(PI * 0.5, 0.0, float(k) / 10.0)
		var nd := Vector2(cos(ang), sin(ang))
		pts.append(Vector2(ccx, ccz) + nd * (r + out))
		nrm.append(nd)
	pts.append(Vector2(x1 + out, -d))
	nrm.append(Vector2(1.0, 0.0))
	var run := [pts, nrm]
	return _flip_run(run) if side < 0 else run


## A run mirrored in x (its order reversed, so it still runs the same way round).
static func _flip_run(run: Array) -> Array:
	var pts: PackedVector2Array = run[0]
	var nrm: PackedVector2Array = run[1]
	var mp := PackedVector2Array()
	var mn := PackedVector2Array()
	for i in range(pts.size() - 1, -1, -1):
		mp.append(Vector2(-pts[i].x, pts[i].y))
		mn.append(Vector2(-nrm[i].x, nrm[i].y))
	return [mp, mn]


## A canopy between an inner and outer run at height y (slab `t` thick): soffit with downlights,
## an aluminium fascia with three grooves, a neon strip under its edge.
static func _canopy(o: DecoBuild.Orn, inner: Array, outer: Array, y: float, t: float, wall: Color, trim: Color, neon: Color) -> void:
	var ip: PackedVector2Array = inner[0]
	var op: PackedVector2Array = outer[0]
	var on: PackedVector2Array = outer[1]
	for i in ip.size() - 1:
		var a := ip[i]
		var b := ip[i + 1]
		var c := op[i + 1]
		var d := op[i]
		o.quad(Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), Vector3(c.x, y, c.y), Vector3(d.x, y, d.y), Vector3.DOWN, _c(wall, DecoBuild.SOFFIT),
			a, b, c, d, Vector2.ZERO, Vector3(b.x - a.x, 0, b.y - a.y).normalized())
		o.quad(Vector3(a.x, y + t, a.y), Vector3(b.x, y + t, b.y), Vector3(c.x, y + t, c.y), Vector3(d.x, y + t, d.y), Vector3.UP, _c(wall * 0.8, DecoBuild.ROOF),
			a, b, c, d, Vector2.ZERO, Vector3(b.x - a.x, 0, b.y - a.y).normalized())
	o.band(op, on, y, y + t, 0.0, _c(trim, DecoBuild.METAL), 0.0, 0.0, false, false)
	for k in 2:
		var gy := y + 0.08 + float(k) * 0.12
		o.band(op, on, gy, gy + 0.03, 0.02, _c(trim * 0.6, DecoBuild.METAL), 0.0, 0.0, false, false)
	o.band(op, on, y - 0.06, y, -0.1, _c(neon, DecoBuild.NEON), 0.0, 0.0, false, true)


## A light pool on the pavement in front (building space point and direction): [xf, colour].
static func _pool(lp: Dictionary, at: Vector2, along: Vector3, wide: float, reach: float, colr: Color) -> Array:
	var xf := frame_xform(lp, 0.0)
	var a3 := (xf.basis * along).normalized()
	var n3 := (xf.basis * Vector3(0, 0, 1)).normalized()
	var p := xf * Vector3(at.x, 0.0, at.y)
	p.y = CityChunk.SIDEWALK_TOP + 0.06
	return [Transform3D(Basis(a3 * wide, n3 * (2.0 * reach), a3.cross(n3)), p), colr]


static func _build_theatre(ch: CityChunk, o: DecoBuild.Orn, walls: DecoBuild.Walls, lp: Dictionary, pal: Dictionary, plinth: float, xf: Transform3D) -> void:
	var t := theatre_dims(lp)
	var w: float = lp.w
	var d: float = lp.d
	var hf: float = t.hf
	var fd: float = t.front_d
	var hh: float = t.hall_h
	var g := DecoBuild.GROUND_H
	var trim := pal.trim as Color
	var wall := pal.wall as Color
	var stone := _c(pal.pier, 0)
	# The front block: shops either side at the pavement, blank upper wall (pilasters carry it).
	var pf := {"shop": true, "ground": g, "floor": 3.6, "base_h": 0.9, "bay": 3.0}
	DecoBuild.tier(walls, -w * 0.5, w * 0.5, -fd, 0.0, -plinth, g, pf, false)
	var pu := {"shop": false, "ground": g, "floor": 3.6, "bay": 3.0, "blank": true}
	DecoBuild.tier(walls, -w * 0.5, w * 0.5, -fd, 0.0, g, hf, pu)
	# The auditorium: a plain box behind, a little narrower and lower.
	var pa := {"shop": false, "ground": 0.0, "floor": 4.0, "bay": 4.0, "blank": true}
	DecoBuild.tier(walls, -w * 0.5 + 0.5, w * 0.5 - 0.5, -d, -fd, -plinth, hh, pa, true, [0])
	# Fluted pilasters across the front, with stepped tops over the parapet.
	var n := maxi(4, int(w / 3.2))
	for k in n + 1:
		var px := -w * 0.5 + 0.35 + (w - 0.7) * float(k) / float(n)
		if absf(px) < float(t.tower_w) * 0.5 + 0.2:
			continue
		o.aabb(Vector3(px - 0.35, g, 0.0), Vector3(px + 0.35, hf + 0.8, 0.3), _c(pal.pier, DecoBuild.FLUTE, true), g)
		DecoBuild.finial(o, px, 0.15, 0.7, 0.3, hf + 0.8, 3, 0.45, _c(pal.pier, 0, true), g)
	# Between the pilasters: tall chevron panels (the facade's ornament band) and a frieze.
	var run := DecoBuild.run_of([[Vector2(w * 0.5, 0.0), Vector2(-w * 0.5, 0.0)]])
	o.band(run[0], run[1], hf - 1.1, hf, 0.08, _c(pal.span, DecoBuild.ZIGZAG, true), g, 1.1)
	o.band(run[0], run[1], hf, hf + 0.5, 0.0, _c(pal.pier, 0, true), g, 0.0, true)
	for k in n:
		var xa := -w * 0.5 + 0.35 + (w - 0.7) * float(k) / float(n) + 0.4
		var xb := -w * 0.5 + 0.35 + (w - 0.7) * float(k + 1) / float(n) - 0.4
		if absf((xa + xb) * 0.5) < float(t.tower_w) * 0.5 + 0.2:
			continue
		o.panel(Vector3(xa, g + 3.2, 0.02), Vector3.RIGHT, Vector3.UP, xb - xa, hf - g - 4.6, _c(pal.span, DecoBuild.CHEVRON, true), g)
	# The central tower: stepped glazed terracotta, with the sign standing out of it.
	var tw: float = t.tower_w
	var th: float = t.tower_h
	o.aabb(Vector3(-tw * 0.5, g, -3.2), Vector3(tw * 0.5, th, 0.35), _c(pal.crown, DecoBuild.GLAZE, true), g)
	var sy := th
	var sw := tw
	for s in 3:
		sw -= 1.6
		o.aabb(Vector3(-sw * 0.5, sy, -2.6), Vector3(sw * 0.5, sy + 1.1, 0.1), _c(pal.crown if s % 2 == 1 else trim, DecoBuild.GLAZE if s % 2 == 1 else DecoBuild.METAL, true), g)
		sy += 1.1
	for s: float in [-1.0, 1.0]:
		o.aabb(Vector3(s * tw * 0.5 - 0.5, g, -0.2), Vector3(s * tw * 0.5 + 0.5, th + 1.6, 0.55), _c(pal.pier, DecoBuild.FLUTE, true), g)
		DecoBuild.finial(o, s * tw * 0.5, 0.18, 1.0, 0.75, th + 1.6, 3, 0.7, _c(trim, DecoBuild.METAL, true), g)
	o.panel(Vector3(-tw * 0.5 + 0.6, g + 2.4, 0.37), Vector3.RIGHT, Vector3.UP, tw - 1.2, 2.2, _c(trim, DecoBuild.SUNBURST, true), g)
	# The vertical blade sign: out of the tower's face, perpendicular to the street.
	var by0 := g + 2.0
	var by1 := th + 1.0
	var bout := 2.1
	var bb := Basis(Vector3(0, 0, 1), Vector3.UP, Vector3(-1, 0, 0))
	o.box(Vector3(0.0, (by0 + by1) * 0.5, 0.35 + bout * 0.5), Vector3(bout, by1 - by0, 0.6), _c(pal.sign, DecoBuild.ENAMEL), bb)
	# Its stepped crown and a bulb border down the outer edge.
	var bt := by1
	for s in 3:
		var kk := 1.0 - 0.22 * float(s + 1)
		o.box(Vector3(0.0, bt + 0.3, 0.35 + bout * 0.5 * kk), Vector3(bout * kk, 0.6, 0.6), _c(trim, DecoBuild.METAL), bb)
		bt += 0.6
	for s: float in [-1.0, 1.0]:
		var zs := 0.35 + bout - 0.05 - (0.28 if s < 0.0 else 0.0)
		o.panel(Vector3(s * 0.305, by0 + 0.2, zs), Vector3(0.0, 0.0, -s), Vector3.UP, 0.28, by1 - by0 - 0.4, _c(Color(0.1, 0.08, 0.06), DecoBuild.BULBS))
	o.aabb(Vector3(-0.08, by0 + 0.1, 0.35 + bout - 0.02), Vector3(0.08, by1 - 0.1, 0.35 + bout + 0.06), _c(Color(0.1, 0.08, 0.06), DecoBuild.BULBS))
	var name: String = lp.name
	var nlen := name.length()
	var room := by1 - by0 - 0.8
	var cap := minf(1.15, room / maxf(float(nlen), 1.0) * 0.8)
	var stepy := room / maxf(float(nlen), 1.0)
	for s: float in [1.0, -1.0]:
		var face_n := Vector3(s, 0.0, 0.0)
		var right := Vector3(0.0, 0.0, -s)
		for i in nlen:
			var y := by1 - 0.4 - stepy * (float(i) + 0.5)
			o.text(name[i], Vector3(0.302 * s, y - cap * 0.5, 0.35 + bout * 0.48), right, Vector3.UP, cap, _c(pal.neon, DecoBuild.NEON))
	# The marquee: a trapezoid canopy over the entrance, readerboards on its three faces, bulbs on
	# its edges and soffit, its name in neon on top.
	var my0 := g - 0.35
	var mh := 1.5
	var mback := minf(w - 2.0, 12.0)
	var mfront := mback - 3.0
	var mdeep := 3.4
	var corners := [Vector2(mback * 0.5, 0.0), Vector2(-mback * 0.5, 0.0), Vector2(-mfront * 0.5, mdeep), Vector2(mfront * 0.5, mdeep)]
	var faces := [[corners[1], corners[2]], [corners[2], corners[3]], [corners[3], corners[0]]]
	for f: Array in faces:
		var a: Vector2 = f[0]
		var b: Vector2 = f[1]
		var len := a.distance_to(b)
		var dn := (b - a) / len
		var nrm := Vector3(-dn.y, 0.0, dn.x)
		var right := Vector3(dn.x, 0.0, dn.y)
		# The board (its outer face; the walls' rule turned: these faces look outward).
		o.panel(Vector3(a.x, my0 + 0.25, a.y) + nrm * 0.01, right, Vector3.UP, len, mh - 0.5, _c(Color.WHITE, DecoBuild.READER))
		o.panel(Vector3(a.x, my0, a.y) + nrm * 0.01, right, Vector3.UP, len, 0.25, _c(Color(0.1, 0.08, 0.06), DecoBuild.BULBS))
		o.panel(Vector3(a.x, my0 + mh - 0.25, a.y) + nrm * 0.01, right, Vector3.UP, len, 0.25, _c(Color(0.1, 0.08, 0.06), DecoBuild.BULBS))
	# Soffit with bulbs, and the top deck.
	o.quad(Vector3(corners[0].x, my0, corners[0].y), Vector3(corners[1].x, my0, corners[1].y), Vector3(corners[2].x, my0, corners[2].y),
		Vector3(corners[3].x, my0, corners[3].y), Vector3.DOWN, _c(Color(0.25, 0.2, 0.15), DecoBuild.BULBS),
		corners[0], corners[1], corners[2], corners[3], Vector2.ZERO, Vector3.RIGHT)
	o.quad(Vector3(corners[0].x, my0 + mh, corners[0].y), Vector3(corners[1].x, my0 + mh, corners[1].y), Vector3(corners[2].x, my0 + mh, corners[2].y),
		Vector3(corners[3].x, my0 + mh, corners[3].y), Vector3.UP, _c(trim * 0.7, DecoBuild.METAL),
		corners[0], corners[1], corners[2], corners[3], Vector2.ZERO, Vector3.RIGHT)
	# The name on top of the marquee, in neon on a short enamel crest.
	var crest_w := minf(mfront - 0.6, DecoBuild.text_width(name, 0.9) + 1.2)
	o.aabb(Vector3(-crest_w * 0.5, my0 + mh, mdeep - 0.25), Vector3(crest_w * 0.5, my0 + mh + 1.15, mdeep - 0.1), _c(pal.sign, DecoBuild.ENAMEL))
	o.text(name, Vector3(0.0, my0 + mh + 0.1, mdeep - 0.08), Vector3.RIGHT, Vector3.UP, 0.9, _c(pal.neon, DecoBuild.NEON))
	o.aabb(Vector3(-crest_w * 0.5, my0 + mh + 1.15, mdeep - 0.27), Vector3(crest_w * 0.5, my0 + mh + 1.25, mdeep - 0.08), _c(Color(0.1, 0.08, 0.06), DecoBuild.BULBS))
	# The lobby doors under it: dark glass with bronze frames, poster cases either side.
	o.panel(Vector3(-mfront * 0.5 + 0.5, 0.0, 0.03), Vector3.RIGHT, Vector3.UP, mfront - 1.0, g - 0.6, _c(Color(0.06, 0.05, 0.05), DecoBuild.DARK))
	for k in 7:
		var dx := -mfront * 0.5 + 0.5 + (mfront - 1.0) * float(k) / 6.0
		o.aabb(Vector3(dx - 0.05, 0.0, 0.03), Vector3(dx + 0.05, g - 0.6, 0.1), _c(trim, DecoBuild.METAL))
	for s: float in [-1.0, 1.0]:
		var px := s * (mback * 0.5 + 0.9)
		o.aabb(Vector3(px - 0.7, 0.6, 0.0), Vector3(px + 0.7, 2.9, 0.12), _c(trim, DecoBuild.METAL))
		o.panel(Vector3(px - 0.6, 0.7, 0.125), Vector3.RIGHT, Vector3.UP, 1.2, 2.1, _c(Color(0.95, 0.9, 0.8), DecoBuild.READER))
	lp.pools = [_pool(lp, Vector2(0.0, 2.0), Vector3(1, 0, 0), mback, 3.2, Color(1.0, 0.82, 0.55, 0.9))]
	# A real light under the marquee after dark (desktop; DayNight drives the lamp_light group).
	if not OS.has_feature("web"):
		var light := OmniLight3D.new()
		light.name = "MarqueeLight"
		light.light_color = Color(1.0, 0.80, 0.55)
		light.omni_range = 11.0
		light.light_energy = 0.0
		light.shadow_enabled = false
		light.distance_fade_enabled = true
		light.distance_fade_begin = 90.0
		light.distance_fade_length = 30.0
		light.position = xf * Vector3(0.0, g - 0.8, 2.2)
		light.add_to_group("lamp_light")
		ch.add_child(light)


static func _build_apartments(o: DecoBuild.Orn, walls: DecoBuild.Walls, lp: Dictionary, pal: Dictionary, plinth: float) -> void:
	var a := apartment_dims(lp)
	var w: float = lp.w
	var d: float = a.d
	var top: float = a.top
	var gy: float = a.ground
	var fl: float = a.floor
	var storeys: int = a.storeys
	var trim := pal.trim as Color
	var pier_c := pal.pier as Color
	var p := {"shop": false, "ground": gy, "floor": fl, "bay": 1.6, "base_h": 1.0}
	DecoBuild.tier(walls, -w * 0.5, w * 0.5, -d, 0.0, -plinth, top, p)
	# The centre bay: two piers flanking the entrance rising past the parapet into a stepped
	# pediment, fluting between them, chevron spandrels under its windows.
	var cw := minf(4.8, w * 0.32)
	var pe := top + 2.6
	for s: float in [-1.0, 1.0]:
		o.aabb(Vector3(s * cw * 0.5 - 0.45, 0.0, 0.0), Vector3(s * cw * 0.5 + 0.45, pe, 0.42), _c(pier_c, DecoBuild.STONE, true), 0.0)
		DecoBuild.finial(o, s * cw * 0.5, 0.21, 0.9, 0.42, pe, 3, 0.45, _c(pier_c, DecoBuild.STONE, true), 0.0)
	var py := top + 0.9
	var pw := cw - 0.9
	for s in 3:
		o.aabb(Vector3(-pw * 0.5, py, -0.1), Vector3(pw * 0.5, py + 0.55, 0.25), _c(pier_c, DecoBuild.STONE, true), 0.0)
		py += 0.55
		pw -= 1.0
		if pw < 0.8:
			break
	o.panel(Vector3(-(cw - 0.9) * 0.5, top - 0.4, 0.26), Vector3.RIGHT, Vector3.UP, cw - 0.9, 1.3, _c(pal.span, DecoBuild.SUNBURST, true), 0.0)
	# Fluted strip up the centre bay above the door and the name.
	o.panel(Vector3(-0.35, 6.4, 0.02), Vector3.RIGHT, Vector3.UP, 0.7, top - 7.0, _c(pier_c, DecoBuild.FLUTE))
	# Corner piers.
	for s: float in [-1.0, 1.0]:
		o.aabb(Vector3(s * w * 0.5 - (0.8 if s > 0 else 0.0), 0.0, 0.0), Vector3(s * w * 0.5 + (0.0 if s > 0 else 0.8), top + 0.9, 0.3), _c(pier_c, DecoBuild.STONE), 0.0)
	# Spandrels under the windows of the two bays either side of the centre.
	for s: float in [-1.0, 1.0]:
		var xa := s * (cw * 0.5 + 0.5)
		var xb := s * (cw * 0.5 + 0.5 + 3.2)
		var aa := Vector2(maxf(xa, xb), 0.0)
		var bb := Vector2(minf(xa, xb), 0.0)
		DecoBuild.spandrels(o, aa, bb, gy, fl, storeys - 1, _c(pal.span, DecoBuild.CHEVRON), 0.3, 0.0, 1.6)
	# Horizontal bands at every other floor line across the end bays, a zigzag frieze up top.
	var run := DecoBuild.run_of([[Vector2(w * 0.5, 0.0), Vector2(-w * 0.5, 0.0)]])
	o.band(run[0], run[1], top - 0.8, top, 0.07, _c(pal.span, DecoBuild.ZIGZAG), 0.0, 0.8)
	o.band(run[0], run[1], top, top + 0.9, 0.0, _c(pier_c, DecoBuild.STONE), 0.0, 0.0, true)
	o.band(run[0], run[1], top + 0.9, top + 1.05, 0.14, _c(pier_c, DecoBuild.STONE), 0.0, 0.0, true, true)
	for f: Array in DecoBuild.rect_faces(-w * 0.5, w * 0.5, -d, 0.0).slice(1):
		var rr := DecoBuild.run_of([f])
		o.band(rr[0], rr[1], top, top + 0.9, 0.0, _c(pier_c, DecoBuild.STONE), 0.0, 0.0, true)
	o.band(run[0], run[1], gy + fl - 0.1, gy + fl + 0.12, 0.12, _c(pier_c, DecoBuild.STONE), 0.0, 0.0, true, true)
	# The portal and the name over the door: gilt letters by day, neon at night.
	var door_w := 1.9
	var ptop := _portal(o, 0.0, door_w, 2.7, pier_c, DecoBuild.STONE, trim, pal.span)
	var name: String = lp.name
	var cap := 0.36
	var tw := DecoBuild.text_width(name, cap)
	if tw > cw - 0.4:
		cap *= (cw - 0.4) / tw
	o.aabb(Vector3(-cw * 0.5 + 0.5, ptop + 0.05, 0.0), Vector3(cw * 0.5 - 0.5, ptop + 0.75, 0.2), _c(pier_c * 0.94, DecoBuild.STONE))
	o.text(name, Vector3(0.0, ptop + 0.4, 0.205), Vector3.RIGHT, Vector3.UP, cap, _c(trim, DecoBuild.GILT))
	# A small canopy over the door, its edge in neon.
	var can_w := door_w + 1.6
	o.aabb(Vector3(-can_w * 0.5, 3.05, 0.0), Vector3(can_w * 0.5, 3.25, 1.3), _c(trim, DecoBuild.METAL))
	o.panel(Vector3(-can_w * 0.5, 3.049, 1.3), Vector3.RIGHT, Vector3(0, 0, -1), can_w, 1.3, _c(pier_c, DecoBuild.SOFFIT))
	o.aabb(Vector3(-can_w * 0.5, 3.0, 1.28), Vector3(can_w * 0.5, 3.05, 1.33), _c(pal.neon, DecoBuild.NEON))
	# Steps up to the raised ground floor.
	for s in 3:
		o.aabb(Vector3(-door_w * 0.5 - 0.3, 0.0, 0.3 + float(2 - s) * 0.32), Vector3(door_w * 0.5 + 0.3, 0.17 * float(s + 1), 0.62 + float(2 - s) * 0.32),
			_c(Color(0.62, 0.60, 0.56), DecoBuild.STONE))
	lp.pools = [_pool(lp, Vector2(0.0, 0.5), Vector3(1, 0, 0), can_w + 1.0, 2.0, Color(1.0, 0.84, 0.6, 0.6))]


static func _build_courtyard(ch: CityChunk, o: DecoBuild.Orn, walls: DecoBuild.Walls, lp: Dictionary, pal: Dictionary, plinth: float, xf: Transform3D) -> void:
	var c := courtyard_dims(lp)
	var w: float = lp.w
	var d: float = lp.d
	var wg: float = c.wing
	var f0: float = c.front
	var e: float = c.eave
	var rear: float = c.rear
	var wall := pal.wall as Color
	var trim := pal.trim as Color
	var roofc := Color(0.66, 0.36, 0.22)
	var p := {"shop": false, "ground": 0.4, "floor": 3.0, "bay": 2.4, "base_h": 0.45}
	# Two wings down the lot and one across the back.
	DecoBuild.tier(walls, -w * 0.5, -w * 0.5 + wg, -d, -f0, -plinth, e, p, false)
	DecoBuild.tier(walls, w * 0.5 - wg, w * 0.5, -d, -f0, -plinth, e, p, false)
	DecoBuild.tier(walls, -w * 0.5 + wg, w * 0.5 - wg, -d, -d + rear, -plinth, e, p, false, [1, 3])
	o.gable(-w * 0.5, -w * 0.5 + wg, -d, -f0, e, float(c.pitch), 0.45, false, roofc, wall)
	o.gable(w * 0.5 - wg, w * 0.5, -d, -f0, e, float(c.pitch), 0.45, false, roofc, wall)
	o.gable(-w * 0.5 + wg, w * 0.5 - wg, -d, -d + rear, e - 0.25, float(c.pitch), 0.3, true, roofc, wall)
	# The courtyard: a tiled path from the gate, a tiled fountain in the middle.
	var cz0 := -d + rear
	var cz1 := -f0
	var cx0 := -w * 0.5 + wg
	var cx1 := w * 0.5 - wg
	var mz := (cz0 + cz1) * 0.5
	o.aabb(Vector3(-0.9, 0.0, cz0), Vector3(0.9, 0.06, 0.0), _c(Color(0.70, 0.42, 0.30), DecoBuild.TILE))
	var fr := minf(1.8, (cx1 - cx0) * 0.22)
	for k in 8:
		var a0 := TAU * float(k) / 8.0
		var a1 := TAU * float(k + 1) / 8.0
		var pa := Vector2(cos(a0), sin(a0)) * fr
		var pb := Vector2(cos(a1), sin(a1)) * fr
		var mid := (pa + pb) * 0.5
		var cc := Vector3(mid.x, 0.3, mz + mid.y)
		var len := pa.distance_to(pb)
		var b3 := Basis(Vector3(pb.x - pa.x, 0, pb.y - pa.y).normalized(), Vector3.UP, Vector3(mid.x, 0, mid.y).normalized())
		o.box(cc, Vector3(len + 0.05, 0.6, 0.3), _c(Color(0.8, 0.7, 0.5), DecoBuild.TILE), b3)
	o.quad(Vector3(-fr, 0.48, mz - fr), Vector3(fr, 0.48, mz - fr), Vector3(fr, 0.48, mz + fr), Vector3(-fr, 0.48, mz + fr), Vector3.UP,
		_c(Color(0.1, 0.2, 0.2), DecoBuild.WATER), Vector2(-fr, -fr), Vector2(fr, -fr), Vector2(fr, fr), Vector2(-fr, fr), Vector2.ZERO, Vector3.RIGHT)
	o.aabb(Vector3(-0.22, 0.0, mz - 0.22), Vector3(0.22, 1.3, mz + 0.22), _c(Color(0.85, 0.75, 0.55), DecoBuild.TILE))
	o.aabb(Vector3(-0.55, 1.3, mz - 0.55), Vector3(0.55, 1.42, mz + 0.55), _c(wall, DecoBuild.STUCCO))
	# A low wall across the front with an arched gate and the name on a tile plaque.
	var gate_w := 2.4
	for s: float in [-1.0, 1.0]:
		var xa := s * gate_w * 0.5
		var xb := s * (w * 0.5 - wg)
		o.aabb(Vector3(minf(xa, xb), 0.0, -0.2), Vector3(maxf(xa, xb), 1.05, 0.15), _c(wall, DecoBuild.STUCCO))
		o.aabb(Vector3(minf(xa, xb) - 0.02, 1.05, -0.25), Vector3(maxf(xa, xb) + 0.02, 1.13, 0.2), _c(roofc, DecoBuild.CLAY))
		o.aabb(Vector3(xa - (0.35 if s > 0 else -0.35) - 0.35, 0.0, -0.3), Vector3(xa - (0.35 if s > 0 else -0.35) + 0.35, 2.7, 0.25), _c(wall, DecoBuild.STUCCO))
	# The arch over the gate: a ring of stucco segments.
	var ar := gate_w * 0.5 + 0.35
	for k in 8:
		var a0 := PI * float(k) / 8.0
		var a1 := PI * float(k + 1) / 8.0
		var pa := Vector2(cos(a0), sin(a0)) * ar
		var pb := Vector2(cos(a1), sin(a1)) * ar
		var mid := (pa + pb) * 0.5
		var b3 := Basis(Vector3(pb.x - pa.x, pb.y - pa.y, 0).normalized(), Vector3(mid.x, mid.y, 0).normalized(), Vector3(0, 0, 1))
		o.box(Vector3(mid.x, 2.5 + mid.y, -0.02), Vector3(pa.distance_to(pb) + 0.06, 0.5, 0.5), _c(wall, DecoBuild.STUCCO), b3)
	o.aabb(Vector3(-1.1, 2.5 + ar + 0.2, -0.3), Vector3(1.1, 2.5 + ar + 0.32, 0.3), _c(roofc, DecoBuild.CLAY))
	var name: String = lp.name
	var cap := 0.2
	var tw := DecoBuild.text_width(name, cap)
	var pw := tw + 0.5
	o.panel(Vector3(-pw * 0.5, 2.5 + ar - 0.3, 0.24), Vector3.RIGHT, Vector3.UP, pw, 0.4, _c(Color(0.9, 0.85, 0.7), DecoBuild.TILE))
	o.text(name, Vector3(0.0, 2.5 + ar - 0.2, 0.25), Vector3.RIGHT, Vector3.UP, cap, _c(Color(0.12, 0.2, 0.42), DecoBuild.ENAMEL))
	# Wrought-iron lanterns either side of the gate, lit at night.
	for s: float in [-1.0, 1.0]:
		var lx := s * (gate_w * 0.5 + 0.35)
		o.aabb(Vector3(lx - 0.12, 2.0, 0.25), Vector3(lx + 0.12, 2.45, 0.49), _c(Color(1.0, 0.75, 0.4), DecoBuild.NEON))
		o.aabb(Vector3(lx - 0.15, 2.45, 0.22), Vector3(lx + 0.15, 2.52, 0.52), _c(Color(0.08, 0.08, 0.08), DecoBuild.METAL))
	# Wood trim: a balcony rail along each wing's courtyard face at the upper floor.
	for s: float in [-1.0, 1.0]:
		var bx := s * (w * 0.5 - wg)
		var out := -s
		o.aabb(Vector3(minf(bx, bx + out * 1.2), 3.25, cz0 + 1.0), Vector3(maxf(bx, bx + out * 1.2), 3.4, cz1 - 1.0), _c(trim, DecoBuild.STONE))
		o.aabb(Vector3(minf(bx + out * 1.15, bx + out * 1.2), 3.4, cz0 + 1.0), Vector3(maxf(bx + out * 1.15, bx + out * 1.2), 4.4, cz1 - 1.0), _c(trim, DecoBuild.STONE))
	# Planting: LotFill's forecourt pieces in the courtyard either side of the path, and palms.
	if LotFill.wanted(ch, CityPlan.District.MIDTOWN):
		var rng := LotFill._rng(ch, "deco_court", lp.seed)
		for side: float in [-1.0, 1.0]:
			var x0 := -0.9 if side < 0 else 0.9
			var x1 := cx0 + 0.4 if side < 0 else cx1 - 0.4
			var la := xf * Vector3(minf(x0, x1), 0.0, cz0 + 0.5)
			var lb := xf * Vector3(maxf(x0, x1), 0.0, mz - fr - 0.4)
			var r := Rect2(Vector2(minf(la.x, lb.x), minf(la.z, lb.z)), Vector2(absf(lb.x - la.x), absf(lb.z - la.z)))
			if r.size.x > 1.5 and r.size.y > 1.5:
				LotFill.forecourt(ch, r, rng)
	for k in 2:
		var px := (-1.0 if k == 0 else 1.0) * (cx1 - cx0) * 0.3
		var at := xf * Vector3(px, 0.0, mz + fr + 1.6)
		var variant := absi(hash([lp.seed, "court_palm", k])) % PropFactory.PALM_VARIANTS
		var s := 0.95 + 0.25 * _h01([lp.seed, "court_palm_s", k])
		ch._batch.add("palm_%d" % variant, PropFactory.palm(variant), Transform3D(Basis(Vector3.UP, _h01([lp.seed, k]) * TAU).scaled(Vector3(s, s, s)),
			Vector3(at.x, CityChunk.SIDEWALK_TOP, at.z)), Color(1, 1, 1))
	lp.pools = [_pool(lp, Vector2(0.0, 0.3), Vector3(1, 0, 0), gate_w + 2.0, 2.0, Color(1.0, 0.78, 0.5, 0.5))]
