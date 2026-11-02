class_name FilmShoot
extends RefCounted
## A film shoot on location (VISUAL_ROADMAP, the film-shoot row): one ordinary street every few
## kilometres closed for a production - barricades, cones and a production assistant with a
## walkie at both ends, the orange "filming in progress" notices on posts down both kerbs, the
## basecamp along one kerb (honeywagon, cast trailers, the grip and electric trucks, a tow-behind
## generator, the catering tent), and the set down the other: the camera on a dolly on its track,
## a camera crane, HMIs on roller stands and a balloon light over the action, black flags and
## bounce boards on C-stands, video village under a black pop-up, cables, sandbags, apple boxes,
## the crew in black, the actors on their marks on the pavement and the extras waiting about.
##
## WHERE is worked out, never placed (FarmersMarket's way, its own cells and salts): the map is cut
## into CELL squares, a hash of seed + cell says whether one has a shoot and where (up to TRIES
## points); the street beside the block under the point (its +X or +Z road, by hash) is the
## shoot's if it is a plain local street of a midtown, residential or industrial block nobody else
## claims - and not a farmers' market's street or the chunk that builds one. Closed between its two
## crossings from CLOSE_INSET past each crossing road's edge (CityPlan.road_open() asks
## `road_closed()`), so the junctions keep their signals and crosswalks. The chunk that owns the
## road (the block on its -X / -Z side) builds it (FilmShootBuild).
##
## The FarmersMarket decision never looks at a shoot (`road_closed()` answers false while a market
## decides), and a shoot's decision asks the markets directly, so the answer does not depend on
## which is asked first.
##
## A shoot is always set up (the city is always filming); its lights follow `lamp_factor`. Every
## roll is a hash of seed + cell / site + piece, never a chunk, block or Building rng.
##
## `FILM_SHOOT=0` in the environment turns it off (the A/B): no shoot, the street is open.

# --- Tunables --------------------------------------------------------------------------------

## Map cell (m) holding at most one shoot, and the odds a cell has one.
const CELL := 2300.0
const ODDS := 0.9
const TRIES := 6
const DISTRICTS := [CityPlan.District.MIDTOWN, CityPlan.District.SUBURBS, CityPlan.District.BEACHTOWN,
	CityPlan.District.INDUSTRIAL]
## Street widths (kerb to kerb): the basecamp along one kerb, the set down the other.
const MIN_WIDTH := 12.0
const MAX_WIDTH := 22.0
## Shortest block span (crossing edge to crossing edge).
const MIN_LEN := 80.0
const MAX_GRADE := 0.05
## The closure starts this far past each crossing road's edge (the junction stays a junction).
const CLOSE_INSET := 2.5
## Metres kept clear at each end (the barricade, the PA, the sign).
const END_CLEAR := 7.0
## The basecamp's vehicles stand this far off their kerb (m, to the body's side).
const CAMP_KERB := 0.35
const VEHICLE_GAP := 1.4
## The set: where the camera track runs (m in from the set side's kerb), its length.
const TRACK_IN := 4.6
const TRACK_LEN := 9.6
## The notices on posts down both kerbs, this far apart.
const NOTICE_STEP := 16.0
## Crew and extras (each in the crowd cap).
const MAX_EXTRAS := 10

## The basecamp in order from the low end: [kind, length (m), width (m)].
const CAMP := [["honeywagon", 13.6, 2.55], ["cast", 10.4, 2.55], ["grip", 7.6, 2.45], ["electric", 7.6, 2.45],
	["cast", 8.6, 2.55], ["genny", 3.9, 1.95]]

## Invented productions (working titles on the notices), the companies and the arrow codes.
const TITLES := ["NIGHT CROSSING", "LAKESIDE AFTER DARK", "THE PELICAN BRIEFCASE", "PALM STATIC", "NOON ON SEVENTH",
	"COYOTE SEASON", "BLUE HOUR KIDS", "PARKING ATTENDANT", "SANTA ANA WIND", "OVERPASS", "HARBOR LIGHTS PT 2", "GOLDEN STATE MOTEL",
	"RECKONING DRIVE", "THE QUIET FREEWAY", "MARQUEE", "SMOG CUTTER"]
const COMPANIES := ["HALCYON BAY PICTURES", "RED LANTERN FILMS", "MESA GRANDE PRODUCTIONS", "NORTH LIGHT MEDIA",
	"CANYON ROAD STUDIOS", "PELICAN POINT ENTERTAINMENT", "DOUBLE ARC PICTURES", "SIXTH STREET FILMWORKS"]
## Arrow codes on the yellow location signs (production working codes, invented).
const CODES := ["NXC", "LAD", "TPB", "PST", "NO7", "CYS", "BHK", "PKA", "SAW", "OVP", "HL2", "GSM", "RKD", "QFW", "MRQ", "SMC"]

static var enabled: bool = OS.get_environment("FILM_SHOOT") != "0"

static var _cells: Dictionary = {}
static var _closed: Dictionary = {}
static var _layouts: Dictionary = {}
static var _deciding: bool = false


static func _h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) / 100003.0


static func _cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.y / CELL))


## Drops every cached decision (a test that changes `enabled` or the plan).
static func reset() -> void:
	_cells.clear()
	_closed.clear()
	_layouts.clear()


# --- Where -----------------------------------------------------------------------------------

## The shoot of map cell `cell`, or {}: FarmersMarket's site keys ("cell", "axis", "index", "k",
## "owner", "lo", "hi", "centre", "width", "rect") plus "seed", "title", "company", "code",
## "camp_side" (+1 / -1 across: the basecamp's kerb; the set is the other). Cached per seed.
static func decide(plan: CityPlan, cell: Vector2i) -> Dictionary:
	var key := Vector3i(plan.seed, cell.x, cell.y)
	if _cells.has(key):
		return _cells[key]
	var out := {}
	_cells[key] = out
	if not enabled or plan.macro == null:
		return out
	if _h01([plan.seed, cell.x, cell.y, "fshoot"]) > ODDS:
		return out
	_deciding = true
	for attempt in TRIES:
		_try(plan, cell, attempt, out)
		if not out.is_empty():
			break
	_deciding = false
	return out


static func _try(plan: CityPlan, cell: Vector2i, attempt: int, out: Dictionary) -> void:
	var target := Vector2((float(cell.x) + lerpf(0.1, 0.9, _h01([plan.seed, cell.x, cell.y, attempt, "fs_x"]))) * CELL,
			(float(cell.y) + lerpf(0.1, 0.9, _h01([plan.seed, cell.x, cell.y, attempt, "fs_z"]))) * CELL)
	if plan.zone_at(target) != MacroMap.Zone.CITY:
		return
	var a := plan.block_index_at(target)
	if _cell_of(FarmersMarket._block_rect(plan, a).get_center()) != cell:
		return
	var axes := [CityPlan.AXIS_X, CityPlan.AXIS_Z]
	if _h01([plan.seed, cell.x, cell.y, attempt, "fs_axis"]) < 0.5:
		axes.reverse()
	for axis: int in axes:
		var site := _segment(plan, a, axis)
		if site.is_empty():
			continue
		var sseed := hash([plan.seed, cell.x, cell.y, "fs_site"])
		site.cell = cell
		site.seed = sseed
		var ti := int(_h01([sseed, "title"]) * TITLES.size()) % TITLES.size()
		site.title = TITLES[ti]
		site.code = CODES[ti]
		site.company = COMPANIES[int(_h01([sseed, "company"]) * COMPANIES.size()) % COMPANIES.size()]
		site.camp_side = 1 if _h01([sseed, "camp_side"]) < 0.5 else -1
		out.merge(site)
		return


## The street on block `a`'s +X (axis X) or +Z (axis Z) side, if a shoot fits there.
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
	var owner := Vector2i(index - 1, k) if axis == CityPlan.AXIS_X else Vector2i(k, index - 1)
	# Never a farmers' market's street, nor the chunk that builds one (FarmersMarket's own answer:
	# it never looks at a shoot).
	if not FarmersMarket.market_on(plan, axis, index, k).is_empty() or not FarmersMarket.market_of_chunk(plan, owner.x, owner.y).is_empty():
		return {}
	var centre := plan.road_pos(axis, index)
	var rect := Rect2(centre - width * 0.5, lo, width, hi - lo) if axis == CityPlan.AXIS_X else Rect2(lo, centre - width * 0.5, hi - lo, width)
	var other := a + (Vector2i(1, 0) if axis == CityPlan.AXIS_X else Vector2i(0, 1))
	for b: Vector2i in [a, other]:
		if not _eligible(plan, b):
			return {}
	if not FarmersMarket._street_clear(plan, axis, index, rect):
		return {}
	var p0 := FarmersMarket._point(axis, centre, lo + 4.0, 0.0)
	var p1 := FarmersMarket._point(axis, centre, hi - 4.0, 0.0)
	if absf(plan.macro.relief_at(p0) - plan.macro.relief_at(p1)) > MAX_GRADE * (hi - lo):
		return {}
	return {"axis": axis, "index": index, "k": k, "lo": lo, "hi": hi, "centre": centre, "width": width, "rect": rect,
		"owner": owner}


## FarmersMarket's rule for the blocks either side, with this shoot's districts.
static func _eligible(plan: CityPlan, k: Vector2i) -> bool:
	var b := plan.block(k.x, k.y)
	if not (int(b.district) in DISTRICTS):
		return false
	if b.has("chinatown") or b.has("site") or b.has("grounds") or b.has("school") or b.has("hospital") or b.get("was_plaza", false):
		return false
	if int(b.kind) != CityPlan.BlockKind.BUILDINGS and int(b.kind) != CityPlan.BlockKind.PARK:
		return false
	var macro: MacroMap = plan.macro
	var rect: Rect2 = b.rect
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


static func point(site: Dictionary, t: float, o: float) -> Vector2:
	return FarmersMarket._point(int(site.axis), float(site.centre), t, o)


static func dirs(site: Dictionary) -> Array[Vector2]:
	return FarmersMarket.dirs(site)


## The shoot on road (axis, index) between crossings `other` and `other + 1`, or {}.
static func shoot_on(plan: CityPlan, axis: int, index: int, other: int) -> Dictionary:
	if not enabled or plan.macro == null:
		return {}
	var owner := Vector2i(index - 1, other) if axis == CityPlan.AXIS_X else Vector2i(other, index - 1)
	var m := decide(plan, _cell_of(FarmersMarket._block_rect(plan, owner).get_center()))
	if m.is_empty() or int(m.axis) != axis or int(m.index) != index or int(m.k) != other:
		return {}
	return m


## The shoot chunk (ix, iz) builds (it owns the road), or {}.
static func shoot_of_chunk(plan: CityPlan, ix: int, iz: int) -> Dictionary:
	if not enabled or plan == null or plan.macro == null:
		return {}
	var m := decide(plan, _cell_of(FarmersMarket._block_rect(plan, Vector2i(ix, iz)).get_center()))
	if m.is_empty() or m.owner != Vector2i(ix, iz):
		return {}
	return m


## CityPlan.road_open()'s hook: true along a shoot's street, CLOSE_INSET past each crossing edge.
## False while a farmers' market (or a shoot) is deciding: neither decision may see this one.
static func road_closed(plan: CityPlan, axis: int, index: int, along: float) -> bool:
	if _deciding or FarmersMarket._deciding or not enabled or plan.macro == null:
		return false
	var other := plan._index_at(1 - axis, along)
	var key := Vector4i(plan.seed, axis, index, other)
	var m: Variant = _closed.get(key)
	if m == null:
		var found := shoot_on(plan, axis, index, other)
		m = found if not found.is_empty() else false
		_closed[key] = m
	if m is bool:
		return false
	var d: Dictionary = m
	return along > float(d.lo) + CLOSE_INSET and along < float(d.hi) - CLOSE_INSET


## Whether chunk (ix, iz)'s road on `axis` is its shoot's street (the chunk paves it itself).
static func paves(plan: CityPlan, ix: int, iz: int, axis: int) -> bool:
	var m := shoot_of_chunk(plan, ix, iz)
	return not m.is_empty() and int(m.axis) == axis


## True where a parked car may not stand (CityChunk._park_car, after its rolls): on a shoot's street.
static func blocks_parking(plan: CityPlan, spot: Vector3) -> bool:
	if not enabled or plan == null or plan.macro == null:
		return false
	var p := Vector2(spot.x, spot.z)
	var bi := plan.block_index_at(p)
	for axis: int in [CityPlan.AXIS_X, CityPlan.AXIS_Z]:
		var c := p.x if axis == CityPlan.AXIS_X else p.y
		var index := plan._index_at(axis, c)
		for idx: int in [index, index + 1]:
			if absf(plan.road_pos(axis, idx) - c) > plan.road_width(axis, idx) * 0.5:
				continue
			var other := bi.y if axis == CityPlan.AXIS_X else bi.x
			var along := p.y if axis == CityPlan.AXIS_X else p.x
			if not shoot_on(plan, axis, idx, other).is_empty() and road_closed(plan, axis, idx, along):
				return true
	return false


# --- The layout ------------------------------------------------------------------------------

## The shoot's pieces in its street frame (pure, cached): `t` along the road (world coordinate),
## `o` across from the centre line, `face` the unit direction (t, o) a piece faces.
## {"camp": [{kind, t, o, len, w, dir, paint}], "tent": {t, o}, "track": {t0, t1, o},
##  "dolly_t", "crane": {t, o, yaw}, "hmis": [{t, o, aim}], "balloon": {t, o}, "flags": [{t, o, aim}],
##  "bounces": [...], "village": {t, o}, "actors": [{t, o}], "action": {t, o}, "notices": [{t, side}],
##  "ends": [t0, t1], "len0", "len1", "crew": [{t, o, aim, role}], "cables": [[Vector2 (t, o), ...]]}
static func layout(site: Dictionary) -> Dictionary:
	var key: int = site.seed
	if _layouts.has(key):
		return _layouts[key]
	var lo: float = site.lo
	var hi: float = site.hi
	var half := float(site.width) * 0.5
	var cs := int(site.camp_side)
	var ss := -cs
	var s0 := lo + END_CLEAR + 2.0
	var s1 := hi - END_CLEAR - 2.0
	var dir := 1 if _h01([site.seed, "camp_dir"]) < 0.5 else -1
	# The basecamp along its kerb, from whichever end the hash says, as far as it fits.
	var camp: Array = []
	var t := s0 if dir > 0 else s1
	var ends_at := t
	for i in CAMP.size():
		var c: Array = CAMP[i]
		var length := float(c[1])
		if (dir > 0 and t + length > s1 - 10.0) or (dir < 0 and t - length < s0 + 10.0):
			break
		var w := float(c[2])
		var mid := t + float(dir) * length * 0.5
		camp.append({"kind": c[0], "t": mid, "o": float(cs) * (half - CAMP_KERB - w * 0.5), "len": length, "w": w,
			"dir": dir if String(c[0]) != "genny" else -dir, "paint": int(_h01([site.seed, i, "paint"]) * 997.0)})
		t += float(dir) * (length + VEHICLE_GAP)
		ends_at = t
	# The catering tent at the far end of the basecamp's kerb.
	var tent_t := (s1 - 3.4) if dir > 0 else (s0 + 3.4)
	var tent := {"t": tent_t, "o": float(cs) * (half - 1.9)}
	# The set: centred on the stretch the basecamp leaves, the camera on its track looking at the
	# action on the set side's pavement.
	var set_mid := (ends_at + tent_t) * 0.5
	set_mid = clampf(set_mid, s0 + TRACK_LEN, s1 - TRACK_LEN)
	var track_o := float(ss) * (half - TRACK_IN)
	var track := {"t0": set_mid - TRACK_LEN * 0.5, "t1": set_mid + TRACK_LEN * 0.5, "o": track_o}
	var dolly_t := set_mid + (_h01([site.seed, "dolly"]) - 0.5) * TRACK_LEN * 0.6
	var action := {"t": set_mid, "o": float(ss) * (half + 2.1)}
	var actors := [{"t": set_mid - 0.7, "o": action.o}, {"t": set_mid + 0.7, "o": action.o}]
	# The crane down the street from the dolly, its arm over the kerb.
	var crane_t := set_mid + float(-dir) * 10.5
	var crane := {"t": crane_t, "o": float(ss) * (half - 3.2), "yaw": 0.0}
	# Two HMIs on roller stands either side of the camera, at the kerb, aimed at the action; the
	# balloon light over the road in front of the action.
	var hmis: Array = []
	for sx: float in [-1.0, 1.0]:
		var ht := set_mid + sx * 7.2
		var ho := float(ss) * (half - 1.5)
		hmis.append({"t": ht, "o": ho, "aim": Vector2(set_mid - ht, float(action.o) - ho).normalized()})
	var balloon := {"t": set_mid + float(dir) * 2.5, "o": float(ss) * (half - 2.0)}
	# Black flags and bounce boards on C-stands near the action.
	var flags: Array = []
	var bounces: Array = []
	for sx: float in [-1.0, 1.0]:
		var ft := set_mid + sx * 3.6
		var fo := float(ss) * (half - 0.9)
		flags.append({"t": ft, "o": fo, "aim": Vector2(-sx, 0.0)})
		bounces.append({"t": set_mid + sx * 2.2, "o": float(ss) * (half - 5.8), "aim": Vector2(0.0, float(ss))})
	# Video village: a black pop-up on the camp side of the road, back from the camera.
	var village := {"t": set_mid + float(-dir) * 4.0, "o": float(cs) * maxf(half - 2.55 - 2.2 - 1.6, 0.6)}
	# Notices: down both kerbs on the pavement's edge.
	var notices: Array = []
	var nt := lo + 6.0
	while nt < hi - 5.0:
		for side: int in [-1, 1]:
			notices.append({"t": nt + (0.0 if side > 0 else NOTICE_STEP * 0.5), "side": side})
		nt += NOTICE_STEP
	# Crew at their posts (faces as (t, o) directions).
	var to_action := func(tt: float, oo: float) -> Vector2:
		return Vector2(float(action.t) - tt, float(action.o) - oo).normalized()
	var crew: Array = []
	crew.append({"t": dolly_t - 0.2, "o": track_o - float(ss) * 0.9, "aim": to_action.call(dolly_t, track_o), "role": "operator"})
	crew.append({"t": dolly_t - 1.4, "o": track_o - float(ss) * 0.2, "aim": Vector2(1.0, 0.0), "role": "dolly"})
	crew.append({"t": dolly_t + 1.0, "o": track_o - float(ss) * 0.7, "aim": to_action.call(dolly_t + 1.0, track_o), "role": "focus"})
	crew.append({"t": crane_t + float(-dir) * 2.2, "o": float(crane.o) - float(ss) * 1.0, "aim": to_action.call(crane_t, float(crane.o)), "role": "crane"})
	crew.append({"t": float(village.t) - 0.8, "o": float(village.o), "aim": to_action.call(float(village.t), float(village.o)), "role": "director"})
	crew.append({"t": float(village.t) + 0.9, "o": float(village.o) + float(cs) * 0.4, "aim": to_action.call(float(village.t), float(village.o)), "role": "script"})
	crew.append({"t": float(hmis[0].t) + 0.9, "o": float(hmis[0].o) - float(ss) * 0.8, "aim": to_action.call(float(hmis[0].t), float(hmis[0].o)), "role": "gaffer"})
	crew.append({"t": set_mid + 1.6, "o": track_o + float(ss) * 1.6, "aim": to_action.call(set_mid, track_o), "role": "boom"})
	crew.append({"t": lo + END_CLEAR - 1.0, "o": float(ss) * (half - 2.2), "aim": Vector2(-1.0, 0.0), "role": "pa"})
	crew.append({"t": hi - END_CLEAR + 1.0, "o": float(cs) * (half - 3.6), "aim": Vector2(1.0, 0.0), "role": "pa"})
	crew.append({"t": tent_t, "o": float(cs) * (half - 0.9), "aim": Vector2(0.0, -float(cs)), "role": "caterer"})
	# Cables: from the generator (or the electric truck) to each HMI and the balloon, laid along
	# the road with a few kinks.
	var cables: Array = []
	var src := Vector2(set_mid, float(cs) * (half - 2.0))
	for c: Dictionary in camp:
		if String(c.kind) == "genny" or String(c.kind) == "electric":
			src = Vector2(float(c.t) - float(dir) * float(c.len) * 0.5, float(c.o) - float(cs) * float(c.w) * 0.5)
	for target: Dictionary in hmis + [balloon]:
		var dst := Vector2(float(target.t), float(target.o))
		var pts: Array = [src]
		var mid_o := lerpf(src.y, dst.y, 0.5) + (_h01([site.seed, dst.x, "cable"]) - 0.5) * 2.0
		pts.append(Vector2(src.x + (dst.x - src.x) * 0.25, src.y + (mid_o - src.y) * 0.6))
		pts.append(Vector2((src.x + dst.x) * 0.5, mid_o))
		pts.append(Vector2(dst.x - (dst.x - src.x) * 0.15, dst.y + (mid_o - dst.y) * 0.3))
		pts.append(dst)
		cables.append(pts)
	var out := {"camp": camp, "tent": tent, "track": track, "dolly_t": dolly_t, "crane": crane, "hmis": hmis,
		"balloon": balloon, "flags": flags, "bounces": bounces, "village": village, "actors": actors, "action": action,
		"notices": notices, "ends": [lo + CLOSE_INSET + 1.4, hi - CLOSE_INSET - 1.4], "crew": crew, "cables": cables,
		"len0": s0, "len1": s1, "dir": dir}
	_layouts[key] = out
	return out


## Where the extras wait and wander (the strip between the basecamp's vehicles and the set's
## track): {"t0", "t1", "o0", "o1"} in the street frame.
static func holding(site: Dictionary) -> Dictionary:
	var lay := layout(site)
	var half := float(site.width) * 0.5
	var cs := float(site.camp_side)
	var a := cs * (half - CAMP_KERB - 2.6 - 0.6)
	var b := -cs * (half - TRACK_IN - 1.4)
	var tr: Dictionary = lay.track
	var t0 := float(tr.t0) - 6.0
	var t1 := float(tr.t1) + 6.0
	return {"t0": t0, "t1": t1, "o0": minf(a, b), "o1": maxf(a, b)}
