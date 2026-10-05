class_name Construction
extends RefCounted
## A real city is always being built: high-rise sites downtown and in midtown (a concrete frame
## and core rising behind hoarding, formwork and rebar on the top deck, safety netting, a material
## hoist, a tower crane slewing over it), timber-frame houses going up in the suburbs and the beach
## town (studs, joists, trusses, OSB and house wrap part-way round, a toilet, a skip, a pickup), and
## road works in the parking lane (cones, drums, an arrow board, trench plates, an excavator, a
## flagger with a STOP / SLOW paddle) - so the traffic, which never uses the parking lane, is
## untouched.
##
## Every decision is a hash of the seed and the place (block, lot, road), taken AFTER every roll
## the city already makes, so nothing a seed builds outside a site moves: a tower site replaces the
## Building the lot would have had (its own rng never runs), a house frame replaces HouseKit's
## house (whose plan it follows), road works take the parked cars' spots after their rolls and
## count as parked. Plans are pure (`tower_site()`, `house_site()`, `road_works()`).
##
## Drawn: a FULL chunk's sites are ONE mesh on ONE material (ConstructionKit / construction
## .gdshader) plus its shadowless ground and one node per tower crane (the same shader with its
## slew); LOD chunks and the far city (capture mode) get the frame, the core and the crane as
## lod_boxes (FarBuilding's plant boxes, so the far city keeps them and the crane's beacons glow).
## Workers are crowd rigs in hi-vis and hard hats (ConstructionWorker), in the crowd cap, only in
## working hours.

## Off: no sites at all (the A/B; `CONSTRUCTION=0` in the environment).
static var enabled: bool = OS.get_environment("CONSTRUCTION") != "0"
## The hour the crews are built for, for tests and stills (negative: the city's clock).
static var force_hour: float = -1.0

# --- High-rise sites ----------------------------------------------------------------------------
## Share of blocks that carry a tower site, per district (the site is the block's best lot).
const TOWER_BLOCK_ODDS := {CityPlan.District.DOWNTOWN: 0.07, CityPlan.District.MIDTOWN: 0.045}
## A lot must be at least this big (m) and its planned building this tall (m) to be a site.
const TOWER_MIN_LOT := 24.0
const TOWER_MIN_HEIGHT := 30.0
## Storey heights (m): the ground storey and the rest.
const GROUND_STOREY := 4.8
const STOREY := 3.6
const SLAB := 0.3
## The tower's plan never exceeds this (m), and stands this far in from the lot's street sides.
const TOWER_MAX := Vector2(44.0, 36.0)
const STREET_INSET := 3.0
const SIDE_INSET := 1.6
## Share of the planned storeys poured, and how many under the top are still open frame.
const BUILT_SHARE := Vector2(0.28, 0.85)
const OPEN_FLOORS := Vector2i(5, 9)
## Column grid spacing (m).
const COLUMN_PITCH := 8.4
## The crane's jib lengths tried (m, longest first) and its counter-jib.
const JIBS := [50.0, 44.0, 38.0, 32.0, 27.0]
const COUNTER_SHARE := 0.32
## Clearance the jib keeps over everything it swings over (m).
const CRANE_CLEAR := 7.0
## The hoarding's height and the covered walkway's (m).
const HOARDING_H := 2.44
const WALKWAY_H := 3.0

# --- House frames -------------------------------------------------------------------------------
## Share of house lots (HouseKit) that are a timber frame going up.
const HOUSE_ODDS := 0.03
const STUD := Vector2(0.038, 0.089)
const STUD_PITCH := 0.406
const TRUSS_PITCH := 0.61

# --- Road works ---------------------------------------------------------------------------------
## Share of a chunk's kerb lanes (its +X and +Z roads, either side) with road works, per district.
const ROAD_ODDS := {CityPlan.District.DOWNTOWN: 0.032, CityPlan.District.MIDTOWN: 0.026, CityPlan.District.SUBURBS: 0.012,
	CityPlan.District.INDUSTRIAL: 0.022, CityPlan.District.CAMPUS: 0.012, CityPlan.District.BEACHTOWN: 0.014}
const CLOSURE_LEN := Vector2(26.0, 44.0)
## Metres a closure keeps off each end of its block (the crosswalks and the junction).
const END_CLEAR := 11.0
## The taper: its length (m) and the sign upstream of it.
const TAPER := 12.0
const SIGN_AHEAD := 18.0

# --- Crews --------------------------------------------------------------------------------------
const WORK_HOURS := Vector2(6.5, 17.5)
const MAX_WORKERS := 7

## Invented developers, projects and taglines (never a real company or building).
const DEVELOPERS := ["HALVERSON & REED", "MERIDIAN VALE PARTNERS", "SUNSTONE DEVELOPMENT", "ARROYO CROWN GROUP",
	"PALISADE & KEEL", "TORREY LANE CAPITAL"]
const PROJECTS := ["THE CALLOWAY", "ONE ARROYO", "VERANO TOWER", "THE MERIDIAN", "HALCYON PLACE", "SOLANA HOUSE",
	"THE ALDER", "CORONET SQUARE"]
const TAGLINES := ["LUXURY RESIDENCES  -  LEASING 2028", "OFFICE  -  RETAIL  -  OPENING 2027", "NOW PRE-LEASING  (213) 555-0147",
	"HOMES FROM THE 900s  -  2028", "CLASS A OFFICE  (213) 555-0182"]
const TOILET_PAINTS := [Color(0.16, 0.36, 0.62), Color(0.18, 0.48, 0.24), Color(0.62, 0.62, 0.60), Color(0.80, 0.42, 0.10)]
const SKIP_PAINTS := [Color(0.18, 0.32, 0.55), Color(0.62, 0.12, 0.08), Color(0.22, 0.38, 0.22), Color(0.82, 0.55, 0.10)]

static var _cache: Dictionary = {}
static var _crane_meshes: Dictionary = {}
static var _paddle: ArrayMesh


static func _h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) / 100003.0


static func _pick(list: Array, parts: Array) -> Variant:
	return list[absi(hash(parts)) % list.size()]


static func lot_rect(lot: Dictionary) -> Rect2:
	return Rect2((lot.center as Vector2) - (lot.size as Vector2) * 0.5, lot.size)


static func lot_cell(lot: Dictionary) -> Rect2:
	return lot.get("cell", lot_rect(lot))


# --- Plans (pure) ---------------------------------------------------------------------------------

## The tower site on block (bx, bz), or {}: one block in a few downtown and in midtown, its biggest
## lot whose planned building is tall enough and where a crane fits. {"lot", "seed", "cell",
## "foot" (Rect2), "built", "clad", "total", "top" (the top slab's height over the floor), "core",
## "crane": {"at", "ring", "jib", "counter", "drop", "yaw"} or {}, "hoist" (side 0..3), "street"
## (sides 0 -z, 1 +z, 2 -x, 3 +x the cell faces a street on), "gate", "walkway", "way", "names"}.
static func tower_site(plan: CityPlan, bx: int, bz: int) -> Dictionary:
	if not enabled or plan == null or plan.macro == null:
		return {}
	var key := "t|%d|%d|%d" % [plan.seed, bx, bz]
	if _cache.has(key):
		return _cache[key]
	var site := _tower_site(plan, bx, bz)
	_cache[key] = site
	return site


static func _tower_site(plan: CityPlan, bx: int, bz: int) -> Dictionary:
	var b := plan.block(bx, bz)
	if int(b.kind) != CityPlan.BlockKind.BUILDINGS or b.has("site") or b.has("grounds") or plan.river_block(bx, bz) \
			or plan.zone_at((b.rect as Rect2).get_center()) != MacroMap.Zone.CITY:
		return {}
	var district: int = b.district
	if not TOWER_BLOCK_ODDS.has(district):
		return {}
	var ps := plan.seed
	if _h01([ps, bx, bz, "tower_site"]) >= float(TOWER_BLOCK_ODDS[district]):
		return {}
	var rect: Rect2 = b.rect
	var inner := rect.grow(-plan.sidewalk_width)
	var best := {}
	var best_h := INF
	for lot: Dictionary in plan.lots(bx, bz):
		if lot.yard or lot.get("parking", false):
			continue
		var size: Vector2 = lot.size
		if size.x < TOWER_MIN_LOT or size.y < TOWER_MIN_LOT:
			continue
		var cell := lot_cell(lot)
		if plan.macro.freeway and plan.macro.freeway.blocks_rect(cell, 16.0):
			continue
		if FireStation.claims(plan, bx, bz, lot):
			continue
		var boost := plan.macro.skyline_boost(lot.center)
		var target := plan.lot_height(lot.seed, district, boost)
		if target < TOWER_MIN_HEIGHT:
			continue
		var hh := _h01([ps, lot.seed, "tower_lot"])
		if hh < best_h:
			best_h = hh
			best = {"lot": lot, "target": target, "boost": boost}
	if best.is_empty():
		return {}
	return _lay_out(plan, bx, bz, best.lot, float(best.target), inner, district)


static func _lay_out(plan: CityPlan, bx: int, bz: int, lot: Dictionary, target: float, inner: Rect2, district: int) -> Dictionary:
	var ps := plan.seed
	var s: int = lot.seed
	var cell := lot_cell(lot)
	var lr := lot_rect(lot)
	# Which cell sides face a street (the cell reaches the lot grid's edge there).
	var street: Array[int] = []
	if absf(cell.position.y - inner.position.y) < 1.0:
		street.append(0)
	if absf(cell.end.y - inner.end.y) < 1.0:
		street.append(1)
	if absf(cell.position.x - inner.position.x) < 1.0:
		street.append(2)
	if absf(cell.end.x - inner.end.x) < 1.0:
		street.append(3)
	# The tower's plan: in from the street sides, capped, centred in what is left.
	var x0 := lr.position.x + (STREET_INSET if 2 in street else SIDE_INSET)
	var x1 := lr.end.x - (STREET_INSET if 3 in street else SIDE_INSET)
	var z0 := lr.position.y + (STREET_INSET if 0 in street else SIDE_INSET)
	var z1 := lr.end.y - (STREET_INSET if 1 in street else SIDE_INSET)
	var w := minf(x1 - x0, TOWER_MAX.x)
	var d := minf(z1 - z0, TOWER_MAX.y)
	if w < 16.0 or d < 14.0:
		return {}
	var fc := Vector2((x0 + x1) * 0.5, (z0 + z1) * 0.5)
	# Pushed toward the back of the lot (away from the first street side), leaving a yard in front.
	if not street.is_empty():
		var sd: int = street[0]
		var room := Vector2((x1 - x0) - w, (z1 - z0) - d) * 0.5
		match sd:
			0:
				fc.y += room.y
			1:
				fc.y -= room.y
			2:
				fc.x += room.x
			3:
				fc.x -= room.x
	var foot := Rect2(fc - Vector2(w, d) * 0.5, Vector2(w, d))
	var total := clampi(roundi((target - GROUND_STOREY) / STOREY) + 1, 8, 70)
	var built := maxi(4, roundi(float(total) * lerpf(BUILT_SHARE.x, BUILT_SHARE.y, _h01([ps, s, "built"]))))
	built = mini(built, total)
	var open_n := OPEN_FLOORS.x + absi(hash([ps, s, "open"])) % (OPEN_FLOORS.y - OPEN_FLOORS.x + 1)
	var clad := maxi(0, built - open_n)
	var top := slab_y(built)
	# The core: a lift and stair core off centre.
	var cw := clampf(w * 0.3, 7.0, 12.0)
	var cd := clampf(d * 0.32, 6.0, 10.0)
	var off := Vector2((_h01([ps, s, "core_x"]) - 0.5) * (w - cw) * 0.4, (_h01([ps, s, "core_z"]) - 0.5) * (d - cd) * 0.4)
	var core := Rect2(fc + off - Vector2(cw, cd) * 0.5, Vector2(cw, cd))
	var site := {"lot": lot, "seed": s, "cell": cell, "foot": foot, "total": total, "built": built, "clad": clad,
		"top": top, "core": core, "street": street, "district": district,
		"hoist": absi(hash([ps, s, "hoist"])) % 4, "way": absi(hash([ps, s, "way"])) % 4,
		"names": [_pick(DEVELOPERS, [ps, s, "dev"]), _pick(PROJECTS, [ps, s, "proj"]), _pick(TAGLINES, [ps, s, "tag"])],
		"walkway": street[absi(hash([ps, s, "walk"])) % street.size()] if not street.is_empty() else -1}
	site["gate"] = _gate_side(site)
	site["crane"] = _fit_crane(plan, bx, bz, site)
	if (site.crane as Dictionary).is_empty():
		return {}
	return site


## The slab height of storey k (0 the ground slab) over the floor.
static func slab_y(k: int) -> float:
	return 0.0 if k <= 0 else GROUND_STOREY + float(k - 1) * STOREY


## The street side the trucks come in at: the longest street side that is not the walkway's.
static func _gate_side(site: Dictionary) -> int:
	var cell: Rect2 = site.cell
	var best := -1
	var best_len := 0.0
	for sd: int in site.street:
		var l := cell.size.x if sd < 2 else cell.size.y
		if sd == int(site.walkway) and (site.street as Array).size() > 1:
			l *= 0.5
		if l > best_len:
			best_len = l
			best = sd
	return best


## The tower crane: its mast beside the core, the longest jib that swings clear of the freeway,
## the landmarks and (with CRANE_CLEAR over them) every planned building round it; the ring high
## enough for that and over the top of the core. {} when none fits.
static func _fit_crane(plan: CityPlan, bx: int, bz: int, site: Dictionary) -> Dictionary:
	var ps := plan.seed
	var s: int = site.seed
	var core: Rect2 = site.core
	var foot: Rect2 = site.foot
	var side := 1.0 if _h01([ps, s, "mast_side"]) < 0.5 else -1.0
	var at := Vector2(core.get_center().x + side * (core.size.x * 0.5 + 2.6), core.get_center().y)
	at.x = clampf(at.x, foot.position.x + 2.0, foot.end.x - 2.0)
	var core_top := float(site.top) + STOREY + 4.5
	var lms := Landmarks.all()
	for jib: float in JIBS:
		var reach := jib + 3.0
		var circle := Rect2(at - Vector2(reach, reach), Vector2(reach * 2.0, reach * 2.0))
		if plan.macro.freeway and plan.macro.freeway.blocks_rect(circle, 3.0):
			continue
		var blocked := false
		for lm: Dictionary in lms:
			if lm.get("area") is Dictionary:
				continue
			if (lm.anchor as Vector2).distance_to(at) < reach + float(lm.radius):
				blocked = true
				break
		if blocked:
			continue
		# Everything planned under the swing (the 3 x 3 blocks round this one).
		var need := core_top + 4.0
		for jx in range(bx - 1, bx + 2):
			for jz in range(bz - 1, bz + 2):
				var nb := plan.block(jx, jz)
				for lot: Dictionary in plan.lots(jx, jz):
					if int(lot.seed) == s and jx == bx and jz == bz:
						continue
					var lr := lot_rect(lot)
					var dx := maxf(absf((lot.center as Vector2).x - at.x) - lr.size.x * 0.5, 0.0)
					var dz := maxf(absf((lot.center as Vector2).y - at.y) - lr.size.y * 0.5, 0.0)
					if dx * dx + dz * dz > reach * reach:
						continue
					var boost := plan.macro.skyline_boost(lot.center)
					need = maxf(need, plan.lot_height(lot.seed, nb.district, boost) + 6.0 + CRANE_CLEAR)
		# A crane stands at most ~70 m free over its last tie to the building.
		if need - float(site.top) > 70.0:
			continue
		var ring := ceilf(need)
		var counter := roundf(jib * COUNTER_SHARE)
		return {"at": at, "ring": ring, "jib": jib, "counter": counter,
			"drop": clampf(ring - float(site.top) - 3.0, 6.0, 120.0), "yaw": _h01([ps, s, "yaw"]) * TAU}
	return {}


## Whether house lot `lot` is a timber frame going up.
static func house_site(plan: CityPlan, lot: Dictionary) -> bool:
	return enabled and plan != null and _h01([plan.seed, lot.seed, "house_frame"]) < HOUSE_ODDS


## The road works on chunk (bx, bz)'s own kerb lanes (its +X road along the block's z range and
## its +Z road along its x range), at most one: [{"axis", "index", "side", "a", "b" (the closure's
## extent along the road), "lane" (the parking lane's centre across), "dir" (+1 / -1: the traffic
## in the lane next to it runs toward +along or -along), "seed"}] or [].
static func road_works(plan: CityPlan, bx: int, bz: int) -> Array:
	if not enabled or plan == null or plan.macro == null:
		return []
	var key := "r|%d|%d|%d" % [plan.seed, bx, bz]
	if _cache.has(key):
		return _cache[key]
	var out := _road_works(plan, bx, bz)
	_cache[key] = out
	return out


static func _road_works(plan: CityPlan, bx: int, bz: int) -> Array:
	var b := plan.block(bx, bz)
	if b.has("site") or plan.river_block(bx, bz) or plan.zone_at((b.rect as Rect2).get_center()) != MacroMap.Zone.CITY:
		return []
	if plan.macro.replica and plan.macro.replica.block_role(plan, bx, bz) != 0:
		return []
	var odds: float = float(ROAD_ODDS.get(int(b.district), 0.0))
	var rect: Rect2 = b.rect
	var ps := plan.seed
	for axis: int in [CityPlan.AXIS_X, CityPlan.AXIS_Z]:
		for side: float in [-1.0, 1.0]:
			if _h01([ps, bx, bz, axis, side, "roadworks"]) >= odds:
				continue
			var index := bx + 1 if axis == CityPlan.AXIS_X else bz + 1
			var rpos := plan.road_pos(axis, index)
			var width := plan.road_width(axis, index)
			var lo := (rect.position.y if axis == CityPlan.AXIS_X else rect.position.x) + END_CLEAR
			var hi := (rect.end.y if axis == CityPlan.AXIS_X else rect.end.x) - END_CLEAR
			var len := lerpf(CLOSURE_LEN.x, CLOSURE_LEN.y, _h01([ps, bx, bz, axis, side, "rw_len"]))
			len = minf(len, hi - lo - SIGN_AHEAD)
			if len < 20.0:
				continue
			# Traffic beside the lane (Traffic._lane_offset): on an AXIS_X road side +x runs -z, on
			# an AXIS_Z road side +z runs +x.
			var dir := -int(side) if axis == CityPlan.AXIS_X else int(side)
			# Room upstream for the sign.
			var a: float
			var span := hi - lo - len - SIGN_AHEAD
			var start := lo + span * _h01([ps, bx, bz, axis, side, "rw_at"])
			a = start + (SIGN_AHEAD if dir > 0 else 0.0)
			var bb := a + len
			var lane := rpos + side * CityPlan.parking_offset(width)
			var ok := plan.road_open(axis, index, (a + bb) * 0.5)
			var t := a - (SIGN_AHEAD if dir > 0 else 0.0)
			while ok and t <= bb + (SIGN_AHEAD if dir < 0 else 0.0):
				var p := Vector2(lane, t) if axis == CityPlan.AXIS_X else Vector2(t, lane)
				if BigVehicles.in_stop_zone(plan, p) or FireStation.keeps_clear(plan, p):
					ok = false
				t += 4.0
			if not ok:
				continue
			return [{"axis": axis, "index": index, "side": side, "a": a, "b": bb, "lane": lane, "dir": dir,
				"width": width, "seed": hash([ps, bx, bz, axis, side])}]
	return []


## A closure point at `along` and `off` metres across from the lane's centre toward the traffic.
static func cl_point(c: Dictionary, along: float, off: float) -> Vector2:
	var across: float = float(c.lane) - float(c.side) * off
	return Vector2(across, along) if int(c.axis) == CityPlan.AXIS_X else Vector2(along, across)


## The along-road position `s` metres downstream of the closure's upstream end.
static func cl_along(c: Dictionary, s: float) -> float:
	return float(c.a) + s if int(c.dir) > 0 else float(c.b) - s


## Whether the parked car at `spot` (plan space) would stand in road works' stretch of kerb.
static func blocks_parking(ch: Node, spot: Vector3) -> bool:
	if not ch.has_meta("construction_closures"):
		return false
	for c: Dictionary in ch.get_meta("construction_closures"):
		var across := spot.x if int(c.axis) == CityPlan.AXIS_X else spot.z
		var along := spot.z if int(c.axis) == CityPlan.AXIS_X else spot.x
		if absf(across - float(c.lane)) > 2.0:
			continue
		var lo: float = float(c.a) - (SIGN_AHEAD + 3.0 if int(c.dir) > 0 else 3.0)
		var hi: float = float(c.b) + (SIGN_AHEAD + 3.0 if int(c.dir) < 0 else 3.0)
		if along > lo - 2.5 and along < hi + 2.5:
			return true
	return false


## Whether block (bx, bz) has any construction a FULL build needs steps for.
static func wanted(ch: CityChunk, block: Dictionary) -> bool:
	if not enabled or ch.level != CityChunk.Level.FULL or ch.capturing or ch.plan == null:
		return false
	return not road_works(ch.plan, ch.ix, ch.iz).is_empty() or not tower_site(ch.plan, ch.ix, ch.iz).is_empty() \
		or HouseKit.wanted(ch, int(block.district))


## The block steps (after the vendors, before the parked cars): the road works, then the crews.
static func steps(ch: CityChunk, block: Dictionary) -> Array[Callable]:
	var out: Array[Callable] = []
	out.append(func() -> void: build_road_works(ch))
	for i in MAX_WORKERS:
		out.append(func() -> void: spawn_worker(ch, i))
	return out


## The hour the crews are built for.
static func hour_now(node: Node) -> float:
	if force_hour >= 0.0:
		return force_hour
	return StreetVendors.hour_now(node)


static func working(node: Node) -> bool:
	var h := hour_now(node)
	return h >= WORK_HOURS.x and h <= WORK_HOURS.y


# --- Chunk state ------------------------------------------------------------------------------

static func _state(ch: CityChunk) -> Dictionary:
	if not ch.has_meta("construction"):
		ch.set_meta("construction", {"st": null, "ground": null, "shapes": [], "cranes": [], "workers": []})
	return ch.get_meta("construction")


static func _st(ch: CityChunk) -> SurfaceTool:
	var s := _state(ch)
	if s.st == null:
		s.st = ConstructionKit.new_st()
	return s.st


static func _ground(ch: CityChunk) -> SurfaceTool:
	var s := _state(ch)
	if s.ground == null:
		s.ground = ConstructionKit.new_st()
	return s.ground


static func _shape(ch: CityChunk, size: Vector3, xf: Transform3D) -> void:
	(_state(ch).shapes as Array).append([size, xf])


## The chunk's finish: the site mesh, its ground, the cranes, one static body.
static func commit(ch: CityChunk) -> void:
	if not ch.has_meta("construction"):
		return
	var s: Dictionary = ch.get_meta("construction")
	if s.st != null:
		var mi := MeshInstance3D.new()
		mi.name = "ConstructionSite"
		mi.mesh = (s.st as SurfaceTool).commit()
		mi.material_override = ConstructionKit.material()
		ch.add_child(mi)
		s.st = null
	if s.ground != null:
		var mg := MeshInstance3D.new()
		mg.name = "ConstructionGround"
		mg.mesh = (s.ground as SurfaceTool).commit()
		mg.material_override = ConstructionKit.material()
		mg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ch.add_child(mg)
		s.ground = null
	for c: Array in s.cranes:
		var cn := MeshInstance3D.new()
		cn.name = "TowerCrane"
		cn.mesh = c[1]
		cn.material_override = ConstructionKit.crane_material()
		cn.transform = c[0]
		cn.custom_aabb = c[2]
		cn.add_to_group("tower_crane")
		ch.add_child(cn)
	(s.cranes as Array).clear()
	if not (s.shapes as Array).is_empty():
		var body := StaticBody3D.new()
		body.name = "ConstructionBody"
		body.collision_layer = 1
		body.collision_mask = 0
		for sh: Array in s.shapes:
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = sh[0]
			cs.shape = bs
			cs.transform = sh[1]
			body.add_child(cs)
		ch.add_child(body)
		(s.shapes as Array).clear()


# --- High-rise site: build ----------------------------------------------------------------------

## CityChunk._build_lot(), for a lot whose Building is set up but not yet built: when the lot is
## this block's tower site, builds the site instead and returns true (the chunk frees the
## Building, whose own rolls never ran). FULL, LOD and capture.
static func build_lot(ch: CityChunk, lot: Dictionary) -> bool:
	var site := tower_site(ch.plan, ch.ix, ch.iz)
	if site.is_empty() or int((site.lot as Dictionary).seed) != int(lot.seed):
		return false
	var c: Vector2 = (site.foot as Rect2).get_center()
	var g := ch._gy(c.x, c.y)
	if ch.level == CityChunk.Level.FULL and not ch.capturing:
		_tower_full(ch, site, g)
	else:
		_tower_far(ch, site, g)
	return true


## The far copy: the finished floors as one glazed box, each open slab, the core and the crane.
static func _tower_far(ch: CityChunk, site: Dictionary, g: float) -> void:
	var foot: Rect2 = site.foot
	var c := foot.get_center()
	var base := CityChunk.SIDEWALK_TOP
	var unit := PropFactory.unit_box()
	var keep := Color(float(FarBuilding.Plant.UNIT), 1.0, 0.0, FarBuilding.PLANT_FLAG)
	var clad: int = site.clad
	var built: int = site.built
	var top: float = site.top
	var y_clad := slab_y(clad) + (STOREY if clad > 0 else 0.0)
	if clad > 0:
		ch._batch.add("lod_box", unit, Transform3D(Basis().scaled(Vector3(foot.size.x, y_clad, foot.size.y)), Vector3(c.x, base + y_clad * 0.5, c.y)), Color(0.22, 0.27, 0.31), keep)
	for k in range(maxi(clad + 1, 1), built + 1):
		var y := slab_y(k)
		ch._batch.add("lod_box", unit, Transform3D(Basis().scaled(Vector3(foot.size.x, 0.45, foot.size.y)), Vector3(c.x, base + y, c.y)), Color(0.66, 0.65, 0.62), keep)
	var core: Rect2 = site.core
	var core_h := top + STOREY + 4.5
	ch._batch.add("lod_box", unit, Transform3D(Basis().scaled(Vector3(core.size.x, core_h, core.size.y)), Vector3(core.get_center().x, base + core_h * 0.5, core.get_center().y)), Color(0.70, 0.69, 0.66), keep)
	var cr: Dictionary = site.crane
	var at: Vector2 = cr.at
	var ring: float = cr.ring
	for fb: Array in ConstructionKit.crane_far_boxes(ring, cr.jib, cr.counter, cr.yaw):
		var xf: Transform3D = fb[0]
		ch._batch.add("lod_box", unit, Transform3D(xf.basis, xf.origin + Vector3(at.x, base + ring, at.y)), fb[1], fb[2])
	var env := Vector3(foot.size.x, top, foot.size.y)
	var centre := Vector3(c.x, base + g + top * 0.5, c.y)
	ch._add_lod_shape(env, centre)
	if clad > 0:
		ch._occluder_boxes.append([Transform3D(), Vector3(c.x, base + g + y_clad * 0.5, c.y), Vector3(foot.size.x - 1.0, y_clad, foot.size.y - 1.0)])
	ch._occluder_boxes.append([Transform3D(), Vector3(core.get_center().x, base + g + core_h * 0.5, core.get_center().y), Vector3(core.size.x - 0.6, core_h, core.size.y - 0.6)])


static func _tower_full(ch: CityChunk, site: Dictionary, g: float) -> void:
	var st := _st(ch)
	var ps := ch.plan.seed
	var s: int = site.seed
	var foot: Rect2 = site.foot
	var cell: Rect2 = site.cell
	var fc := foot.get_center()
	var floor_y := CityChunk.SIDEWALK_TOP + g
	var built: int = site.built
	var clad: int = site.clad
	var top: float = site.top
	var W := foot.size.x
	var D := foot.size.y
	var form: Color = _pick(ConstructionKit.FORM_PAINTS, [ps, s, "form"])
	var net: Color = _pick(ConstructionKit.NET_PAINTS, [ps, s, "net"])
	var K := ConstructionKit
	# The plinth down to the lowest corner of the cell, and the site's ground.
	var gmin := g
	for k: Vector2 in [cell.position, cell.end, Vector2(cell.position.x, cell.end.y), Vector2(cell.end.x, cell.position.y)]:
		gmin = minf(gmin, ch._gy(k.x, k.y))
	if g - gmin > 0.02:
		K.box(st, Transform3D(Basis(), Vector3(fc.x, floor_y - (g - gmin + 0.3) * 0.5, fc.y)), Vector3(W + 0.2, g - gmin + 0.3, D + 0.2), K.K_CONCRETE, K.CONCRETE, -1.0, 0, 48)
	_ground_rect(ch, cell, 0.04, K.K_DIRT)
	_ground_rect(ch, foot.grow(0.6), 0.06, K.K_GRAVEL)
	# --- The finished floors: curtain wall over the slabs up to `clad` ---
	var y_clad := slab_y(clad) + (STOREY if clad > 0 else 0.0)
	if clad > 0:
		# The glass from 2.4 m under the floor, so its storey lines land on the slabs.
		var gh := y_clad + 2.4
		K.box(st, Transform3D(Basis(), Vector3(fc.x, floor_y - 2.4 + gh * 0.5, fc.y)), Vector3(W + 0.2, gh, D + 0.2), K.K_GLASS, Color.WHITE, -1.0, 0, 32 | 16)
		K.box(st, Transform3D(Basis(), Vector3(fc.x, floor_y + y_clad - 0.15, fc.y)), Vector3(W + 0.1, SLAB, D + 0.1), K.K_CONCRETE, K.CONCRETE, -1.0, 0, 32)
		_shape(ch, Vector3(W + 0.2, y_clad, D + 0.2), Transform3D(Basis(), Vector3(fc.x, floor_y + y_clad * 0.5, fc.y)))
	else:
		K.box(st, Transform3D(Basis(), Vector3(fc.x, floor_y + 0.15, fc.y)), Vector3(W, SLAB, D), K.K_CONCRETE, K.CONCRETE, -1.0, 0, 32)
	# --- Open floors: slabs, columns, guardrails ---
	for k in range(clad + 1, built + 1):
		var y := floor_y + slab_y(k)
		K.box(st, Transform3D(Basis(), Vector3(fc.x, y - SLAB * 0.5, fc.y)), Vector3(W, SLAB, D), K.K_CONCRETE, K.CONCRETE)
		_shape(ch, Vector3(W, SLAB, D), Transform3D(Basis(), Vector3(fc.x, y - SLAB * 0.5, fc.y)))
	var core: Rect2 = site.core
	var cr: Dictionary = site.crane
	var mast: Vector2 = cr.at
	var y_col0 := floor_y + y_clad
	var y_col1 := floor_y + slab_y(built) - SLAB
	var nx := maxi(2, roundi(W / COLUMN_PITCH)) + 1
	var nz := maxi(2, roundi(D / COLUMN_PITCH)) + 1
	var columns: Array[Vector2] = []
	for i in nx:
		for j in nz:
			var p := Vector2(lerpf(foot.position.x + 0.5, foot.end.x - 0.5, float(i) / float(nx - 1)), lerpf(foot.position.y + 0.5, foot.end.y - 0.5, float(j) / float(nz - 1)))
			if core.grow(0.8).has_point(p) or p.distance_to(mast) < 2.6:
				continue
			columns.append(p)
	if y_col1 > y_col0 + 0.5:
		for p in columns:
			var hcol := y_col1 - y_col0
			K.box(st, Transform3D(Basis(), Vector3(p.x, y_col0 + hcol * 0.5, p.y)), Vector3(0.6, hcol, 0.6), K.K_CONCRETE, K.CONCRETE, -1.0, 0, 48)
			_shape(ch, Vector3(0.6, hcol, 0.6), Transform3D(Basis(), Vector3(p.x, y_col0 + hcol * 0.5, p.y)))
	# Guardrails on the open floors under the netted top two (posts every 2.4 m, two rails).
	for k in range(clad + 1, built - 1):
		_guardrail(st, foot, floor_y + slab_y(k))
	# Safety netting round the top three storeys, standing out from the slab edge.
	var net_lo := floor_y + slab_y(maxi(built - 2, clad))
	var net_hi := floor_y + top + 1.3
	if built - 2 > clad or built > 0:
		_net_ring(st, foot.grow(0.35), net_lo, net_hi, net)
	# --- The top deck: edge forms, the rebar mat over half of it, column starters, shores under ---
	var ty := floor_y + top
	for e in 4:
		var seg := _edge(foot, e)
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		K.beam(st, Vector3(a.x, ty + 0.22, a.y), Vector3(b.x, ty + 0.22, b.y), Vector2(0.05, 0.45), K.K_FORM, form)
	var half := Rect2(foot.position, Vector2(W * 0.5, D)) if _h01([ps, s, "mat"]) < 0.5 else Rect2(foot.position + Vector2(W * 0.5, 0.0), Vector2(W * 0.5, D))
	half = half.grow(-0.4)
	K.quad(st, Vector3(half.position.x, ty + 0.12, half.end.y), Vector3(half.end.x, ty + 0.12, half.end.y), Vector3(half.end.x, ty + 0.12, half.position.y), Vector3(half.position.x, ty + 0.12, half.position.y), K.K_MAT, Color.WHITE)
	K.quad(st, Vector3(half.position.x, ty + 0.2, half.end.y), Vector3(half.end.x, ty + 0.2, half.end.y), Vector3(half.end.x, ty + 0.2, half.position.y), Vector3(half.position.x, ty + 0.2, half.position.y), K.K_MAT, Color.WHITE)
	# The other half is formwork decking waiting for its mat: plywood over the slab.
	var other := Rect2(foot.position, Vector2(W * 0.5, D)) if half.position.x > foot.position.x + 1.0 else Rect2(foot.position + Vector2(W * 0.5, 0.0), Vector2(W * 0.5, D))
	K.box(st, Transform3D(Basis(), Vector3(other.get_center().x, ty + 0.02, other.get_center().y)), Vector3(other.size.x - 0.6, 0.04, other.size.y - 0.6), K.K_FORM, form)
	for p in columns:
		for b in 8:
			var a := TAU * float(b) / 8.0
			var q := p + Vector2(cos(a), sin(a)) * 0.22
			K.box(st, Transform3D(Basis(), Vector3(q.x, ty + 0.7, q.y)), Vector3(0.025, 1.4, 0.025), K.K_REBAR, Color.WHITE, -1.0, 0, 32)
	if built > clad + 1:
		var sy0 := floor_y + slab_y(built - 1)
		var sh := top - slab_y(built - 1) - SLAB
		var px := foot.position.x + 1.2
		while px < foot.end.x - 0.8:
			var pz := foot.position.y + 1.2
			while pz < foot.end.y - 0.8:
				if not core.grow(0.5).has_point(Vector2(px, pz)):
					K.box(st, Transform3D(Basis(), Vector3(px, sy0 + sh * 0.5, pz)), Vector3(0.06, sh, 0.06), K.K_GALV, Color.WHITE, -1.0, 0, 48)
				pz += 2.4
			px += 2.4
		# The forms' beams under the deck (aluminium joists one way).
		var bz := foot.position.y + 1.2
		while bz < foot.end.y - 0.8:
			K.box(st, Transform3D(Basis(), Vector3(fc.x, ty - SLAB - 0.12, bz)), Vector3(W - 1.0, 0.2, 0.1), K.K_GALV, Color.WHITE, -1.0, 0, 32)
			bz += 2.4
	# --- The core with its jump form on top ---
	var core_h := top + STOREY
	K.box(st, Transform3D(Basis(), Vector3(core.get_center().x, floor_y + core_h * 0.5, core.get_center().y)), Vector3(core.size.x, core_h, core.size.y), K.K_CONCRETE, K.CONCRETE * Color(0.97, 0.97, 0.95))
	_shape(ch, Vector3(core.size.x, core_h, core.size.y), Transform3D(Basis(), Vector3(core.get_center().x, floor_y + core_h * 0.5, core.get_center().y)))
	var jf := core.grow(0.9)
	var jy := floor_y + core_h - 1.2
	_net_ring(st, jf, jy, jy + 5.0, Color(0.30, 0.34, 0.31), K.K_STEEL)
	K.box(st, Transform3D(Basis(), Vector3(jf.get_center().x, jy + 5.0, jf.get_center().y)), Vector3(jf.size.x, 0.12, jf.size.y), K.K_GALV, Color.WHITE, -1.0, 0, 32)
	for e in 4:
		var seg := _edge(core, e)
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		K.beam(st, Vector3(a.x, floor_y + core_h + 0.7, a.y), Vector3(b.x, floor_y + core_h + 0.7, b.y), Vector2(0.06, 1.4), K.K_FORM, form)
	# Starter bars out of the core's walls.
	var t := 0.0
	var perim := 2.0 * (core.size.x + core.size.y)
	while t < perim:
		var q := _perimeter_point(core.grow(-0.15), t)
		K.box(st, Transform3D(Basis(), Vector3(q.x, floor_y + core_h + 0.6, q.y)), Vector3(0.025, 1.2, 0.025), K.K_REBAR, Color.WHITE, -1.0, 0, 32)
		t += 0.45
	# --- The material hoist on the hoist side ---
	_hoist(ch, st, site, floor_y)
	# --- The crane ---
	var ring: float = cr.ring
	var key := "%d|%d|%d|%d" % [int(ring), int(cr.jib), int(cr.counter), int(cr.drop)]
	if not _crane_meshes.has(key):
		_crane_meshes[key] = K.crane_mesh(ring, cr.jib, cr.counter, cr.drop)
	var reach := maxf(float(cr.jib), float(cr.counter)) + 4.0
	var aabb := AABB(Vector3(-reach, -ring - 2.0, -reach), Vector3(reach * 2.0, ring + K.JIB_Y + K.JIB_D + K.CATHEAD_H + 4.0, reach * 2.0))
	(_state(ch).cranes as Array).append([Transform3D(Basis(Vector3.UP, float(cr.yaw)), Vector3(mast.x, floor_y + ring, mast.y)), _crane_meshes[key], aabb])
	_shape(ch, Vector3(K.MAST_W, ring, K.MAST_W), Transform3D(Basis(), Vector3(mast.x, floor_y + ring * 0.5, mast.y)))
	# --- Hoarding, the gate, the covered walkway, signs ---
	_hoarding(ch, st, site, g)
	# --- The yard: cabins, a skip, toilets, stacks ---
	_yard(ch, st, site, floor_y)
	# --- Crew spots ---
	var crew: Array = _state(ch).workers
	var block_rect: Rect2 = (ch.plan.block(ch.ix, ch.iz).rect as Rect2)
	for i in 3:
		var p := Vector2(lerpf(foot.position.x + 2.0, foot.end.x - 2.0, _h01([ps, s, "crew_x", i])), lerpf(foot.position.y + 2.0, foot.end.y - 2.0, _h01([ps, s, "crew_z", i])))
		if core.grow(1.0).has_point(p) or p.distance_to(mast) < 3.0:
			continue
		crew.append({"at": p, "yaw": _h01([ps, s, "crew_yaw", i]) * TAU, "lift": floor_y + top + 0.04 - ch.ground_y(p.x, p.y) - 0.1, "rect": block_rect,
			"seed": hash([ps, s, "crew", i]), "paddle": false, "deck": true})


## A ring of netting (or screens: `kind`) round `r` from y0 to y1, its posts every 3 m.
static func _net_ring(st: SurfaceTool, r: Rect2, y0: float, y1: float, paint: Color, kind: int = ConstructionKit.K_NET) -> void:
	var K := ConstructionKit
	for e in 4:
		var seg := _edge(r, e)
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		var mid := (a + b) * 0.5
		var len := a.distance_to(b)
		var along := (b - a) / maxf(len, 1e-4)
		var yaw := atan2(-along.y, along.x)
		K.box(st, Transform3D(Basis(Vector3.UP, yaw), Vector3(mid.x, (y0 + y1) * 0.5, mid.y)), Vector3(len, y1 - y0, 0.02), kind, paint, -1.0, 0, 48)
		var t := 0.0
		while t <= len + 0.01:
			var q := a + along * t
			K.box(st, Transform3D(Basis(), Vector3(q.x, (y0 + y1) * 0.5, q.y)), Vector3(0.06, y1 - y0, 0.06), K.K_GALV, Color.WHITE, -1.0, 0, 48)
			t += 3.0


## Edge guardrails round a slab at y: posts every 2.4 m, a top and a mid rail, a toe board.
static func _guardrail(st: SurfaceTool, r: Rect2, y: float) -> void:
	var K := ConstructionKit
	for e in 4:
		var seg := _edge(r.grow(-0.1), e)
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		for hh: float in [0.5, 1.05]:
			K.beam(st, Vector3(a.x, y + hh, a.y), Vector3(b.x, y + hh, b.y), Vector2(0.05, 0.05), K.K_STEEL, K.RAIL_PAINT)
		K.beam(st, Vector3(a.x, y + 0.08, a.y), Vector3(b.x, y + 0.08, b.y), Vector2(0.025, 0.15), K.K_LUMBER, K.LUMBER)
		var len := a.distance_to(b)
		var t := 0.0
		while t <= len:
			var q := a.lerp(b, t / maxf(len, 0.01))
			K.box(st, Transform3D(Basis(), Vector3(q.x, y + 0.55, q.y)), Vector3(0.05, 1.1, 0.05), K.K_STEEL, K.RAIL_PAINT, -1.0, 0, 48)
			t += 2.4


## Edge e of a rect (0 -z, 1 +z, 2 -x, 3 +x) as [a, b] going counter-clockwise seen from above.
static func _edge(r: Rect2, e: int) -> Array:
	match e:
		0:
			return [r.position, Vector2(r.end.x, r.position.y)]
		1:
			return [r.end, Vector2(r.position.x, r.end.y)]
		2:
			return [Vector2(r.position.x, r.end.y), r.position]
		_:
			return [Vector2(r.end.x, r.position.y), r.end]


static func _perimeter_point(r: Rect2, t: float) -> Vector2:
	var w := r.size.x
	var d := r.size.y
	t = fmod(t, 2.0 * (w + d))
	if t < w:
		return r.position + Vector2(t, 0.0)
	t -= w
	if t < d:
		return Vector2(r.end.x, r.position.y + t)
	t -= d
	if t < w:
		return Vector2(r.end.x - t, r.end.y)
	t -= w
	return Vector2(r.position.x, r.end.y - t)


## The rack-and-pinion material hoist up one face: its lattice mast, ties to the slabs every three
## storeys, a cage car at a floor, the landing gate at its foot.
static func _hoist(ch: CityChunk, st: SurfaceTool, site: Dictionary, floor_y: float) -> void:
	var K := ConstructionKit
	var foot: Rect2 = site.foot
	var side: int = site.hoist
	var built: int = site.built
	var top: float = site.top
	var fc := foot.get_center()
	var out: Vector2
	var at: Vector2
	match side:
		0:
			out = Vector2(0, -1)
			at = Vector2(fc.x + foot.size.x * 0.22, foot.position.y)
		1:
			out = Vector2(0, 1)
			at = Vector2(fc.x - foot.size.x * 0.22, foot.end.y)
		2:
			out = Vector2(-1, 0)
			at = Vector2(foot.position.x, fc.y - foot.size.y * 0.22)
		_:
			out = Vector2(1, 0)
			at = Vector2(foot.end.x, fc.y + foot.size.y * 0.22)
	var m := at + out * 1.6
	var mh := top + 4.0
	K.lattice(st, Transform3D(Basis(), Vector3(m.x, floor_y, m.y)), mh, 0.9, Color(0.82, 0.82, 0.80))
	_shape(ch, Vector3(1.0, mh, 1.0), Transform3D(Basis(), Vector3(m.x, floor_y + mh * 0.5, m.y)))
	var k := 3
	while k <= built:
		var y := floor_y + slab_y(k) + 0.6
		K.beam(st, Vector3(at.x, y, at.y), Vector3(m.x, y, m.y), Vector2(0.1, 0.1), K.K_STEEL, Color(0.82, 0.82, 0.80))
		k += 3
	# The car beside the mast at a floor picked from the seed.
	var floor_k := absi(hash([ch.plan.seed, site.seed, "hoist_k"])) % maxi(built, 1)
	var cy := floor_y + slab_y(floor_k)
	var along := Vector2(-out.y, out.x)
	var cc := m + along * 1.6
	var yaw := atan2(-out.x, -out.y)
	K.box(st, Transform3D(Basis(Vector3.UP, yaw), Vector3(cc.x, cy + 0.12, cc.y)), Vector3(2.2, 0.24, 1.6), K.K_STEEL, Color(0.86, 0.66, 0.10))
	K.box(st, Transform3D(Basis(Vector3.UP, yaw), Vector3(cc.x, cy + 1.4, cc.y)), Vector3(2.2, 2.4, 1.6), K.K_NET, Color(0.86, 0.66, 0.10), -1.0, 0, 32)
	K.box(st, Transform3D(Basis(Vector3.UP, yaw), Vector3(cc.x, cy + 2.62, cc.y)), Vector3(2.24, 0.06, 1.64), K.K_STEEL, Color(0.86, 0.66, 0.10), -1.0, 0, 32)
	# The landing enclosure at the foot.
	K.box(st, Transform3D(Basis(Vector3.UP, yaw), Vector3(cc.x + out.x * 0.9, floor_y + 1.0, cc.y + out.y * 0.9)), Vector3(3.2, 2.0, 0.05), K.K_NET, Color(0.86, 0.66, 0.10), -1.0, 0, 48)


## The hoarding along the cell's street sides (with the gate), the covered walkway over the
## pavement on one side, the developer's names and the safety signs.
static func _hoarding(ch: CityChunk, st: SurfaceTool, site: Dictionary, g: float) -> void:
	var K := ConstructionKit
	var cell: Rect2 = site.cell
	var way: int = site.way
	var names: Array = site.names
	var gate: int = site.gate
	var walk: int = site.walkway
	var sidewalk := ch.plan.sidewalk_width
	var sides: Array = site.street
	# Every side of the cell is closed: plywood on the street sides, chain-link on the others.
	for e in 4:
		var seg := _edge(cell, e)
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		var len := a.distance_to(b)
		var along := (b - a) / maxf(len, 0.01)
		# Outward from the cell (to the street side): the edges run counter-clockwise from above.
		var out := Vector2(along.y, -along.x)
		var yaw := atan2(-along.y, along.x)
		var street := e in sides
		var gate_lo := len
		var gate_hi := len
		if e == gate:
			gate_lo = len * 0.5 - 4.5
			gate_hi = len * 0.5 + 4.5
		for piece: Vector2 in [Vector2(0.0, gate_lo), Vector2(gate_hi, len)]:
			if piece.y - piece.x < 0.3:
				continue
			var p0 := a + along * piece.x
			var p1 := a + along * piece.y
			var mid := (p0 + p1) * 0.5
			var gy := CityChunk.SIDEWALK_TOP + ch._gy(mid.x, mid.y)
			var plen := piece.y - piece.x
			if street:
				# The boards face the street: their front (+z of the box) is `out`.
				var xf := Transform3D(Basis(Vector3.UP, yaw + PI), Vector3(mid.x, gy + HOARDING_H * 0.5, mid.y) + Vector3(out.x, 0.0, out.y) * 0.03)
				K.box(st, xf, Vector3(plen, HOARDING_H, 0.04), K.K_HOARDING, Color.WHITE, float(way) + 0.01, 0, 32)
				_shape(ch, Vector3(plen, HOARDING_H, 0.1), xf)
				# Back braces every 2.4 m.
				var t := 1.2
				while t < plen:
					var q := p0 + along * t - out * 0.6
					K.beam(st, Vector3(q.x, gy, q.y), Vector3(q.x + out.x * 0.55, gy + 1.9, q.y + out.y * 0.55), Vector2(0.05, 0.09), K.K_LUMBER, K.LUMBER)
					t += 2.4
				# The names on the long pieces, facing the street.
				if plen > 14.0:
					var front := Basis(Vector3.UP, atan2(out.x, out.y))
					var tc := Vector3(mid.x, gy, mid.y) + Vector3(out.x, 0.0, out.y) * 0.06
					var right := front * Vector3.RIGHT
					var txt := Color(0.96, 0.95, 0.92) if way != 3 else Color(0.08, 0.1, 0.14)
					K.text(st, String(names[1]), 0.42, Transform3D(front, tc + Vector3(0.0, 1.55, 0.0) + right * plen * 0.22), txt)
					K.text(st, String(names[2]), 0.13, Transform3D(front, tc + Vector3(0.0, 1.12, 0.0) + right * plen * 0.22), txt)
					K.text(st, String(names[0]), 0.12, Transform3D(front, tc + Vector3(0.0, 0.42, 0.0) - right * plen * 0.3), txt)
			else:
				var xf2 := Transform3D(Basis(Vector3.UP, yaw), Vector3(mid.x, gy + 1.0, mid.y))
				K.box(st, xf2, Vector3(plen, 2.0, 0.03), K.K_NET, Color(0.55, 0.56, 0.55), -1.0, 0, 48)
				_shape(ch, Vector3(plen, 2.0, 0.1), xf2)
				var t2 := 0.0
				while t2 <= plen + 0.01:
					var q2 := p0 + along * t2
					K.box(st, Transform3D(Basis(), Vector3(q2.x, gy + 1.05, q2.y)), Vector3(0.05, 2.1, 0.05), K.K_GALV, Color.WHITE, -1.0, 0, 48)
					t2 += 3.0
		if e == gate:
			# The gate: two chain-link leaves standing open, its posts, the signs.
			var g0 := a + along * gate_lo
			var g1 := a + along * gate_hi
			var gy0 := CityChunk.SIDEWALK_TOP + ch._gy(g0.x, g0.y)
			for gp: Vector2 in [g0, g1]:
				K.box(st, Transform3D(Basis(), Vector3(gp.x, gy0 + 1.25, gp.y)), Vector3(0.12, 2.5, 0.12), K.K_GALV, Color.WHITE, -1.0, 0, 32)
			for leaf: Array in [[g0, 1.0], [g1, -1.0]]:
				var hinge: Vector2 = leaf[0]
				var dirv: Vector2 = (-out).rotated(float(leaf[1]) * 0.25)
				var lc := hinge + dirv * 2.2
				K.box(st, Transform3D(Basis(Vector3.UP, atan2(-dirv.y, dirv.x)), Vector3(lc.x, gy0 + 1.05, lc.y)), Vector3(4.4, 1.9, 0.03), K.K_NET, Color(0.6, 0.6, 0.6), -1.0, 0, 48)
			var sb := Basis(Vector3.UP, atan2(out.x, out.y))
			var sp := g1 + along * 1.4 + out * 0.08
			K.box(st, Transform3D(sb, Vector3(sp.x, gy0 + 1.55, sp.y)), Vector3(0.9, 0.6, 0.02), K.K_SIGN, Color(0.95, 0.75, 0.10), -1.0, 0, 48)
			K.text(st, "HARD HAT AREA", 0.075, Transform3D(sb, Vector3(sp.x, gy0 + 1.6, sp.y) + Vector3(out.x, 0.0, out.y) * 0.015), Color(0.05, 0.05, 0.05))
			K.text(st, "TRUCKS ENTERING", 0.06, Transform3D(sb, Vector3(sp.x, gy0 + 1.45, sp.y) + Vector3(out.x, 0.0, out.y) * 0.015), Color(0.05, 0.05, 0.05))
			var sp2 := g0 - along * 1.4 + out * 0.08
			K.box(st, Transform3D(sb, Vector3(sp2.x, gy0 + 1.55, sp2.y)), Vector3(0.75, 0.5, 0.02), K.K_SIGN, Color(0.92, 0.92, 0.9), -1.0, 0, 48)
			K.text(st, "NO TRESPASSING", 0.07, Transform3D(sb, Vector3(sp2.x, gy0 + 1.55, sp2.y) + Vector3(out.x, 0.0, out.y) * 0.015), Color(0.75, 0.06, 0.04))
			# The flagger at the gate, on the pavement.
			var fp := (g0 + g1) * 0.5 + out * 1.6
			(_state(ch).workers as Array).append({"at": fp, "yaw": atan2(-out.x, -out.y), "lift": 0.0,
				"rect": (ch.plan.block(ch.ix, ch.iz).rect as Rect2), "seed": hash([ch.plan.seed, site.seed, "gateman"]), "paddle": true, "deck": false})
		if e == walk and street:
			# The covered walkway (a sidewalk shed): posts at the kerb side and at the boards, a
			# deck at WALKWAY_H with a plywood parapet, lamps under it.
			var depth := sidewalk - 0.7
			var y0 := CityChunk.SIDEWALK_TOP + ch._gy(a.x * 0.5 + b.x * 0.5, a.y * 0.5 + b.y * 0.5)
			var t3 := 0.0
			while t3 <= len + 0.01:
				var q3 := a + along * t3
				for off: float in [0.15, depth]:
					var qq := q3 + out * off
					K.box(st, Transform3D(Basis(), Vector3(qq.x, y0 + WALKWAY_H * 0.5, qq.y)), Vector3(0.1, WALKWAY_H, 0.1), K.K_STEEL, Color(0.20, 0.32, 0.22), -1.0, 0, 32)
				t3 += 2.44
			var dm := (a + b) * 0.5 + out * depth * 0.5
			K.box(st, Transform3D(Basis(Vector3.UP, yaw), Vector3(dm.x, y0 + WALKWAY_H + 0.15, dm.y)), Vector3(len, 0.3, depth + 0.2), K.K_STEEL, Color(0.20, 0.32, 0.22))
			K.box(st, Transform3D(Basis(Vector3.UP, yaw), Vector3(dm.x, y0 + WALKWAY_H + 0.31, dm.y)), Vector3(len, 0.03, depth + 0.2), K.K_FORM, Color(0.62, 0.55, 0.42), -1.0, 0, 32)
			var pk := (a + b) * 0.5 + out * (depth + 0.1)
			K.box(st, Transform3D(Basis(Vector3.UP, yaw + PI), Vector3(pk.x, y0 + WALKWAY_H + 0.85, pk.y)), Vector3(len, 1.1, 0.03), K.K_HOARDING, Color.WHITE, float(way) + 0.01, 0, 32)
			_shape(ch, Vector3(len, 0.35, depth + 0.2), Transform3D(Basis(Vector3.UP, yaw), Vector3(dm.x, y0 + WALKWAY_H + 0.17, dm.y)))
			var t4 := 1.2
			while t4 < len:
				var q4 := a + along * t4 + out * depth * 0.5
				K.box(st, Transform3D(Basis(Vector3.UP, yaw), Vector3(q4.x, y0 + WALKWAY_H - 0.04, q4.y)), Vector3(1.2, 0.05, 0.12), K.K_STRIP, Color.WHITE, -1.0, 0, 16)
				t4 += 4.88


## The yard between the tower and the hoarding: stacked cabins, a skip, toilets and stacks of
## materials, laid in whichever strip has room (all hashes of the lot).
static func _yard(ch: CityChunk, st: SurfaceTool, site: Dictionary, floor_y: float) -> void:
	var K := ConstructionKit
	var ps := ch.plan.seed
	var s: int = site.seed
	var foot: Rect2 = site.foot
	var cell: Rect2 = site.cell.grow(-0.6)
	# The four strips round the tower: [rect, along-x?].
	var strips := [
		[Rect2(cell.position.x, cell.position.y, cell.size.x, foot.position.y - cell.position.y - 0.5), true],
		[Rect2(cell.position.x, foot.end.y + 0.5, cell.size.x, cell.end.y - foot.end.y - 0.5), true],
		[Rect2(cell.position.x, foot.position.y, foot.position.x - cell.position.x - 0.5, foot.size.y), false],
		[Rect2(foot.end.x + 0.5, foot.position.y, cell.end.x - foot.end.x - 0.5, foot.size.y), false],
	]
	strips.sort_custom(func(p: Array, q: Array) -> bool: return minf((p[0] as Rect2).size.x, (p[0] as Rect2).size.y) > minf((q[0] as Rect2).size.x, (q[0] as Rect2).size.y))
	var items: Array = [["cabin", 6.4, 2.8], ["skip", 6.4, 2.6], ["toilet", 2.6, 1.4], ["rebar", 12.0, 1.4], ["lumber", 5.2, 1.5],
		["form", 2.8, 1.5], ["form", 2.8, 1.5], ["lumber", 5.2, 1.5]]
	var at_item := 0
	for sv: Array in strips:
		var r: Rect2 = sv[0]
		var along_x: bool = sv[1]
		var deep := r.size.y if along_x else r.size.x
		var long := r.size.x if along_x else r.size.y
		if deep < 1.6 or long < 3.0:
			continue
		var t := 0.8
		while at_item < items.size():
			var it: Array = items[at_item]
			var need: float = it[1]
			var wide: float = it[2]
			if wide > deep - 0.2:
				at_item += 1
				continue
			if t + need > long - 0.5:
				break
			var c := Vector2(r.position.x + t + need * 0.5, r.get_center().y) if along_x else Vector2(r.get_center().x, r.position.y + t + need * 0.5)
			var yaw := PI * 0.5 if along_x else 0.0
			var gy := CityChunk.SIDEWALK_TOP + ch._gy(c.x, c.y) + 0.06
			var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(c.x, gy, c.y))
			match String(it[0]):
				"cabin":
					K.cabin(st, Transform3D(Basis(Vector3.UP, yaw - PI * 0.5), xf.origin))
					K.cabin(st, Transform3D(Basis(Vector3.UP, yaw - PI * 0.5), xf.origin + Vector3(0.0, 2.8, 0.0)))
					_shape(ch, Vector3(6.0, 5.6, 2.4), Transform3D(Basis(Vector3.UP, yaw - PI * 0.5), xf.origin + Vector3(0.0, 2.8, 0.0)))
				"skip":
					K.skip(st, xf, _pick(SKIP_PAINTS, [ps, s, "skip"]), 0.4 + 0.5 * _h01([ps, s, "skip_load"]))
					_shape(ch, Vector3(2.4, 1.6, 6.0), Transform3D(xf.basis, xf.origin + Vector3(0.0, 0.8, 0.0)))
				"toilet":
					var tp: Color = _pick(TOILET_PAINTS, [ps, s, "toilet"])
					K.toilet(st, Transform3D(xf.basis, xf.origin + xf.basis * Vector3(0.0, 0.0, -0.62)), tp)
					K.toilet(st, Transform3D(xf.basis, xf.origin + xf.basis * Vector3(0.0, 0.0, 0.62)), tp)
				"rebar":
					K.rebar_bundle(st, xf)
				"lumber":
					K.lumber_stack(st, xf)
				"form":
					K.form_stack(st, xf, _pick(ConstructionKit.FORM_PAINTS, [ps, s, "form"]))
			t += need + 0.6
			at_item += 1
		if at_item >= items.size():
			break


## A ground rect at `lift` over the pavement (following the relief), into the shadowless ground.
static func _ground_rect(ch: CityChunk, r: Rect2, lift: float, kind: int) -> void:
	if r.size.x < 0.1 or r.size.y < 0.1:
		return
	var st := _ground(ch)
	var col := ConstructionKit.kind_color(kind, Color.WHITE)
	var nx := clampi(ceili(r.size.x / 6.0), 1, 24)
	var nz := clampi(ceili(r.size.y / 6.0), 1, 24)
	var pt := func(i: int, j: int) -> Vector3:
		var x := r.position.x + r.size.x * float(i) / float(nx)
		var z := r.position.y + r.size.y * float(j) / float(nz)
		return Vector3(x, CityChunk.SIDEWALK_TOP + ch._gy(x, z) + lift, z)
	for i in nx:
		for j in nz:
			var a: Vector3 = pt.call(i, j)
			var b: Vector3 = pt.call(i + 1, j)
			var c: Vector3 = pt.call(i + 1, j + 1)
			var d: Vector3 = pt.call(i, j + 1)
			# Facing up: a (x0 z0), d (x0 z1), c (x1 z1) is clockwise seen from above.
			for q: Vector3 in [a, b, c, a, c, d]:
				st.set_normal(Vector3.UP)
				st.set_color(col)
				st.set_uv(Vector2(q.x, q.z))
				st.set_uv2(Vector2(1.0, 0.0))
				st.add_vertex(q)


# --- House frames -------------------------------------------------------------------------------

## CityChunk._build_house(), for house lot `lot` and HouseKit's plan of it: when the lot is a frame
## going up, builds the frame instead of the house and returns true.
static func build_house(ch: CityChunk, lot: Dictionary, h: Dictionary) -> bool:
	if not house_site(ch.plan, lot):
		return false
	var b := HouseBuild.new()
	b.setup(ch, h)
	if ch.level == CityChunk.Level.FULL and not ch.capturing:
		_frame_full(ch, lot, h, b)
	else:
		_frame_far(ch, h, b)
	return true


static func _frame_far(ch: CityChunk, h: Dictionary, b: HouseBuild) -> void:
	var plain := Color(0.0, 0.0, float(absi(int(h.seed)) % 997) / 997.0, 1.0)
	for w: Dictionary in h.wings:
		if String(w.role) == "carport":
			continue
		var r: Rect2 = w.r
		var ye := float(w.storeys) * HouseKit.STOREY
		var c := r.get_center()
		var size := b._world_size(r, ye - b.base)
		var centre := b.W(c.x, (b.base + ye) * 0.5, c.y)
		var o3 := centre
		o3.y -= ch._gy(o3.x, o3.z)
		ch._batch.add("lod_box", PropFactory.unit_box(), Transform3D(Basis().scaled(size), o3), ConstructionKit.OSB, plain)
		ch._add_lod_shape(size, centre)


## A timber frame on HouseKit's plan: the slab, each wing's walls as studs on plates with window
## and door openings (headers, sills), the floor joists, the roof as trusses (gable / hip) or
## joists (flat), OSB on some walls and house wrap over some of that (the stage is a hash), and
## the site round it - a skip on the drive, a toilet, lumber stacks, a pickup at the kerb.
static func _frame_full(ch: CityChunk, lot: Dictionary, h: Dictionary, b: HouseBuild) -> void:
	var st := _st(ch)
	var K := ConstructionKit
	var ps := ch.plan.seed
	var s: int = h.seed
	var stage := _h01([ps, s, "frame_stage"])
	var wall_i := 0
	for wi in (h.wings as Array).size():
		var w: Dictionary = h.wings[wi]
		var r: Rect2 = w.r
		var storeys: int = w.storeys
		var role := String(w.role)
		# The slab: poured, a little proud of the ground, under the whole wing.
		var c := r.get_center()
		var slab := b._world_size(r.grow(0.15), 0.4 - b.base)
		var sc := b.W(c.x, (b.base + 0.0) * 0.5 - 0.0, c.y)
		K.box(st, Transform3D(Basis(), sc + Vector3(0.0, -0.2 + 0.2, 0.0)), Vector3(slab.x, -b.base, slab.z), K.K_CONCRETE, K.CONCRETE, -1.0, 0, 32)
		_shape(ch, Vector3(slab.x, -b.base, slab.z), Transform3D(Basis(), sc))
		if role == "carport":
			continue
		var wall_h := HouseKit.STOREY - 0.12
		for f in storeys:
			var y0 := float(f) * HouseKit.STOREY
			# The floor deck of an upper storey: joists across the short span, OSB over most of it.
			if f > 0:
				var along_u := r.size.x >= r.size.y
				var span_len := r.size.y if along_u else r.size.x
				var run := r.size.x if along_u else r.size.y
				var t := 0.2
				while t < run - 0.1:
					var p0 := Vector2(r.position.x + t, r.position.y) if along_u else Vector2(r.position.x, r.position.y + t)
					var p1 := p0 + (Vector2(0.0, span_len) if along_u else Vector2(span_len, 0.0))
					K.beam(st, b.W(p0.x, y0 - 0.15, p0.y), b.W(p1.x, y0 - 0.15, p1.y), Vector2(0.038, 0.235), K.K_LUMBER, K.LUMBER)
					t += STUD_PITCH
				var deck := r.grow(-0.02)
				var dsz := b._world_size(deck, 0.02)
				K.box(st, Transform3D(Basis(), b.W(deck.get_center().x, y0 + 0.0, deck.get_center().y)), Vector3(dsz.x, 0.02, dsz.z), K.K_OSB, K.OSB, -1.0, 0, 0)
				_shape(ch, Vector3(dsz.x, 0.1, dsz.z), Transform3D(Basis(), b.W(deck.get_center().x, y0 - 0.05, deck.get_center().y)))
			for e in 4:
				var sheathe := _h01([ps, s, "osb", wall_i]) < stage * 1.3 - 0.15
				var wrap := sheathe and _h01([ps, s, "wrap", wall_i]) < stage * 1.4 - 0.75
				_stud_wall(ch, st, b, r, e, y0, wall_h, sheathe, wrap, hash([ps, s, wall_i]))
				wall_i += 1
		var ye := float(storeys) * HouseKit.STOREY
		match String(w.roof):
			"gable", "hip":
				_trusses(st, b, w, ye, float(h.pitch), stage > 0.55)
			_:
				# A flat roof: joists and, later, its deck.
				var t2 := 0.2
				while t2 < r.size.x - 0.1:
					K.beam(st, b.W(r.position.x + t2, ye + 0.12, r.position.y), b.W(r.position.x + t2, ye + 0.12, r.end.y), Vector2(0.038, 0.235), K.K_LUMBER, K.LUMBER)
					t2 += STUD_PITCH
	# The site: dirt round the house, a skip on the drive, a toilet by the kerb, lumber stacks.
	for wv: Dictionary in h.wings:
		var gr := (wv.r as Rect2).grow(1.8)
		var a := b.P(gr.position.x, gr.position.y)
		var c2 := b.P(gr.end.x, gr.end.y)
		_ground_rect(ch, Rect2(Vector2(minf(a.x, c2.x), minf(a.y, c2.y)), (c2 - a).abs()), 0.075, K.K_DIRT)
	var f: Dictionary = h.f
	var U: float = f.U
	var front := b.P(U * 0.5, 0.8)
	var fy := CityChunk.SIDEWALK_TOP + ch._gy(front.x, front.y) + 0.07
	var yaw := atan2(-(f.u as Vector2).y, (f.u as Vector2).x)
	var drive: Vector2 = h.drive
	if drive.y > drive.x + 2.0:
		var dc := b.P((drive.x + drive.y) * 0.5, 3.4)
		K.skip(st, Transform3D(Basis(Vector3.UP, yaw + PI * 0.5), Vector3(dc.x, CityChunk.SIDEWALK_TOP + ch._gy(dc.x, dc.y) + 0.06, dc.y)), _pick(SKIP_PAINTS, [ps, s, "skip"]), 0.5)
		_shape(ch, Vector3(2.4, 1.6, 6.0), Transform3D(Basis(Vector3.UP, yaw + PI * 0.5), Vector3(dc.x, CityChunk.SIDEWALK_TOP + ch._gy(dc.x, dc.y) + 0.86, dc.y)))
	var tu := 0.9 if U * 0.5 > (drive.x + drive.y) * 0.5 else U - 0.9
	var tp := b.P(tu, 0.9)
	K.toilet(st, Transform3D(Basis(Vector3.UP, yaw + PI), Vector3(tp.x, CityChunk.SIDEWALK_TOP + ch._gy(tp.x, tp.y) + 0.06, tp.y)), _pick(TOILET_PAINTS, [ps, s, "toilet"]))
	var lp := b.P(clampf(U * 0.5 + (2.5 if tu < U * 0.5 else -2.5), 1.0, U - 1.0), 1.6)
	K.lumber_stack(st, Transform3D(Basis(Vector3.UP, yaw + PI * 0.5), Vector3(lp.x, CityChunk.SIDEWALK_TOP + ch._gy(lp.x, lp.y) + 0.07, lp.y)), 4.9)
	_state(ch)
	var crew: Array = _state(ch).workers
	var mid: Vector2 = ((h.wings[0] as Dictionary).r as Rect2).get_center()
	var wp := b.P(mid.x, (((h.wings[0] as Dictionary).r) as Rect2).position.y - 1.2)
	crew.append({"at": wp, "yaw": yaw + PI, "lift": fy - ch.ground_y(wp.x, wp.y) - 0.03, "rect": (ch.plan.block(ch.ix, ch.iz).rect as Rect2),
		"seed": hash([ps, s, "framer"]), "paddle": false, "deck": true})
	# The builder's pickup at the kerb in front (a parked Vehicle, after every roll of the chunk's).
	(_state(ch) as Dictionary)["pickups"] = (_state(ch) as Dictionary).get("pickups", []) + [{"seed": s, "front": front, "f": f}]


## One wall of a wing (edge e of its rect in the house frame) on storey base y0: bottom plate,
## double top plate, studs every STUD_PITCH, a window opening (header, sill, king and jack studs)
## every few metres and the front door; OSB over it when `sheathe`, house wrap over that when
## `wrap`.
static func _stud_wall(ch: CityChunk, st: SurfaceTool, b: HouseBuild, r: Rect2, e: int, y0: float, wall_h: float, sheathe: bool, wrap: bool, s: int) -> void:
	var K := ConstructionKit
	var seg := _edge(r, e)
	var a: Vector2 = seg[0]
	var c: Vector2 = seg[1]
	var len := a.distance_to(c)
	if len < 0.5:
		return
	var along := (c - a) / len
	var out := Vector2(along.y, -along.x)
	# The wall's centre line sits half a stud in from the slab edge.
	var inset := out * (-STUD.y * 0.5)
	var wa := a + inset
	var wc := c + inset
	K.beam(st, b.W(wa.x, y0 + 0.02, wa.y), b.W(wc.x, y0 + 0.02, wc.y), Vector2(STUD.y, 0.038), K.K_LUMBER, K.LUMBER)
	for k in 2:
		var yy := y0 + wall_h - 0.02 - float(k) * 0.038
		K.beam(st, b.W(wa.x, yy, wa.y), b.W(wc.x, yy, wc.y), Vector2(STUD.y, 0.038), K.K_LUMBER, K.LUMBER)
	# Openings: windows centred every ~3.2 m, sill 0.9, head 2.15; none on short walls.
	var openings: Array = []
	var nwin := floori((len - 1.2) / 3.2)
	for i in nwin:
		var cx := (float(i) + 0.5) * len / float(nwin)
		openings.append([cx - 0.55, cx + 0.55, 0.9, 2.15])
	var t := 0.0
	while t <= len + 0.001:
		var tt := minf(t, len - 0.02)
		var in_open := false
		for o: Array in openings:
			if tt > float(o[0]) - 0.04 and tt < float(o[1]) + 0.04:
				in_open = true
				# Cripples over the header and under the sill.
				var q := wa + along * tt
				K.beam(st, b.W(q.x, y0 + 2.15 + 0.29, q.y), b.W(q.x, y0 + wall_h - 0.08, q.y), Vector2(STUD.x, STUD.y), K.K_LUMBER, K.LUMBER, 0, b.N(out))
				K.beam(st, b.W(q.x, y0 + 0.04, q.y), b.W(q.x, y0 + 0.88, q.y), Vector2(STUD.x, STUD.y), K.K_LUMBER, K.LUMBER, 0, b.N(out))
		if not in_open:
			var q2 := wa + along * tt
			K.beam(st, b.W(q2.x, y0 + 0.04, q2.y), b.W(q2.x, y0 + wall_h - 0.08, q2.y), Vector2(STUD.x, STUD.y), K.K_LUMBER, K.LUMBER, 0, b.N(out))
		t += STUD_PITCH
	for o: Array in openings:
		var p0 := wa + along * float(o[0])
		var p1 := wa + along * float(o[1])
		# King and jack studs either side, the header (doubled 2x12) and the sill.
		for pe: Vector2 in [p0 - along * 0.04, p1 + along * 0.04]:
			K.beam(st, b.W(pe.x, y0 + 0.04, pe.y), b.W(pe.x, y0 + wall_h - 0.08, pe.y), Vector2(STUD.x, STUD.y), K.K_LUMBER, K.LUMBER, 0, b.N(out))
		K.beam(st, b.W(p0.x, y0 + 2.15 + 0.14, p0.y), b.W(p1.x, y0 + 2.15 + 0.14, p1.y), Vector2(STUD.y, 0.28), K.K_LUMBER, K.LUMBER)
		K.beam(st, b.W(p0.x, y0 + 0.9, p0.y), b.W(p1.x, y0 + 0.9, p1.y), Vector2(STUD.y, 0.038), K.K_LUMBER, K.LUMBER)
	# Sheathing: OSB sheets on the outside face (with the openings cut), the wrap over it.
	if sheathe:
		var pieces: Array = []
		var last := 0.0
		for o: Array in openings:
			pieces.append([last, float(o[0]), 0.0, wall_h])
			pieces.append([float(o[0]), float(o[1]), 0.0, 0.9])
			pieces.append([float(o[0]), float(o[1]), 2.43, wall_h])
			last = float(o[1])
		pieces.append([last, len, 0.0, wall_h])
		var yaw := atan2(-b.N(along).z, b.N(along).x)
		for pc: Array in pieces:
			var u0: float = pc[0]
			var u1: float = pc[1]
			if u1 - u0 < 0.05:
				continue
			var m := wa + along * ((u0 + u1) * 0.5) + out * (STUD.y * 0.5 + 0.006)
			var hh: float = float(pc[3]) - float(pc[2])
			var xf := Transform3D(Basis(Vector3.UP, yaw), b.W(m.x, y0 + (float(pc[2]) + float(pc[3])) * 0.5, m.y))
			K.box(st, xf, Vector3(u1 - u0, hh, 0.012), K.K_WRAP if wrap else K.K_OSB, K.OSB, -1.0, 0, 0)
	if absi(s) % 3 == 0 and not sheathe:
		# A diagonal let-in brace on a bare wall.
		var p3 := wa + along * minf(0.3, len * 0.1)
		var p4 := wa + along * minf(2.6, len * 0.6)
		K.beam(st, b.W(p3.x, y0 + 0.1, p3.y) + b.N(out) * 0.05, b.W(p4.x, y0 + wall_h - 0.1, p4.y) + b.N(out) * 0.05, Vector2(0.02, 0.09), K.K_LUMBER, K.LUMBER.darkened(0.1))


## Roof trusses over a wing (a gable's ridge along its plan, a hip's along its longer side), every
## TRUSS_PITCH: two top chords, the bottom chord and a W of webs; OSB on part of the roof later.
static func _trusses(st: SurfaceTool, b: HouseBuild, w: Dictionary, ye: float, pitch: float, sheathed: bool) -> void:
	var K := ConstructionKit
	var r: Rect2 = w.r
	var along_u: bool = b._along_u(w) if String(w.roof) == "gable" else r.size.x >= r.size.y
	var run := r.size.x if along_u else r.size.y
	var span := r.size.y if along_u else r.size.x
	var rise := span * 0.5 * pitch
	var eave := 0.35
	var t := 0.05
	while t <= run - 0.04:
		var at := func(across: float, y: float) -> Vector3:
			var u := r.position.x + t if along_u else r.position.x + across
			var v := r.position.y + across if along_u else r.position.y + t
			return b.W(u, ye + y, v)
		var l: Vector3 = at.call(-eave, -eave * pitch)
		var top: Vector3 = at.call(span * 0.5, rise)
		var rr: Vector3 = at.call(span + eave, -eave * pitch)
		var bl: Vector3 = at.call(0.0, 0.0)
		var br: Vector3 = at.call(span, 0.0)
		K.beam(st, l, top, Vector2(0.038, 0.14), K.K_LUMBER, K.LUMBER)
		K.beam(st, top, rr, Vector2(0.038, 0.14), K.K_LUMBER, K.LUMBER)
		K.beam(st, bl, br, Vector2(0.038, 0.14), K.K_LUMBER, K.LUMBER)
		var q1: Vector3 = at.call(span * 0.25, 0.0)
		var q3: Vector3 = at.call(span * 0.75, 0.0)
		var m1: Vector3 = at.call(span * 0.333, rise * 0.666)
		var m3: Vector3 = at.call(span * 0.667, rise * 0.666)
		K.beam(st, q1, m1, Vector2(0.038, 0.089), K.K_LUMBER, K.LUMBER)
		K.beam(st, m1, at.call(span * 0.5, 0.0), Vector2(0.038, 0.089), K.K_LUMBER, K.LUMBER)
		K.beam(st, at.call(span * 0.5, 0.0), m3, Vector2(0.038, 0.089), K.K_LUMBER, K.LUMBER)
		K.beam(st, m3, q3, Vector2(0.038, 0.089), K.K_LUMBER, K.LUMBER)
		t += TRUSS_PITCH
	if sheathed:
		# OSB on the first half of one slope.
		var a0 := func(across: float, y: float, tt: float) -> Vector3:
			var u := r.position.x + tt if along_u else r.position.x + across
			var v := r.position.y + across if along_u else r.position.y + tt
			return b.W(u, ye + y + 0.09, v)
		var p0: Vector3 = a0.call(-eave, -eave * pitch, 0.0)
		var p1: Vector3 = a0.call(-eave, -eave * pitch, run * 0.55)
		var p2: Vector3 = a0.call(span * 0.5, rise, run * 0.55)
		var p3: Vector3 = a0.call(span * 0.5, rise, 0.0)
		K.quad(st, p0, p1, p2, p3, K.K_OSB, K.OSB)


# --- Road works ---------------------------------------------------------------------------------

## The chunk's road works (FULL; a block step before the parked cars, which keep off it).
static func build_road_works(ch: CityChunk) -> void:
	var works := road_works(ch.plan, ch.ix, ch.iz)
	var closures: Array = []
	for c: Dictionary in works:
		# A street vendor's truck already at this kerb (StreetVendors) keeps it.
		var mid := cl_point(c, (float(c.a) + float(c.b)) * 0.5, 0.0)
		if StreetVendors.blocks_parking(ch, Vector3(mid.x, 0.4, mid.y)) \
				or StreetVendors.blocks_parking(ch, Vector3(cl_point(c, float(c.a), 0.0).x, 0.4, cl_point(c, float(c.a), 0.0).y)) \
				or StreetVendors.blocks_parking(ch, Vector3(cl_point(c, float(c.b), 0.0).x, 0.4, cl_point(c, float(c.b), 0.0).y)):
			continue
		closures.append(c)
		_closure(ch, c)
	if not closures.is_empty():
		ch.set_meta("construction_closures", closures)
	_spawn_pickups(ch)


static func _closure(ch: CityChunk, c: Dictionary) -> void:
	var st := _st(ch)
	var K := ConstructionKit
	var s: int = c.seed
	var L: float = float(c.b) - float(c.a)
	var side: float = c.side
	var axis: int = c.axis
	var dir: int = c.dir
	# The direction of travel (downstream), and the yaw that turns a prop's front (+z) toward the
	# oncoming traffic (a person's -z forward is that plus PI).
	var down := Vector2(0.0, float(dir)) if axis == CityPlan.AXIS_X else Vector2(float(dir), 0.0)
	var face_up := atan2(-down.x, -down.y)
	var road_y := func(p: Vector2) -> float: return CityChunk.ROAD_TOP + ch._gy(p.x, p.y)
	var lane_edge := CityPlan.PARKING_LANE * 0.5 + 0.15
	var place := func(sv: float, off: float) -> Transform3D:
		var p := cl_point(c, cl_along(c, sv), off)
		return Transform3D(Basis(Vector3.UP, face_up), Vector3(p.x, road_y.call(p), p.y))
	# The sign upstream: ROAD WORK AHEAD, an orange diamond on a spring stand.
	var sxf: Transform3D = place.call(-SIGN_AHEAD + 2.0, -0.4)
	_road_sign(st, sxf)
	# The taper: cones from the kerb out to the lane line over TAPER m, then along the line.
	var n_taper := 6
	for i in n_taper + 1:
		var f := float(i) / float(n_taper)
		K.cone(st, place.call(f * TAPER, lerpf(-1.1, lane_edge, f)))
	var sv := TAPER + 4.0
	while sv < L - 0.5:
		K.cone(st, place.call(sv, lane_edge))
		sv += 4.5
	K.drum(st, place.call(TAPER + 0.8, lane_edge - 0.25))
	K.drum(st, place.call(L - 0.4, lane_edge - 0.3))
	K.drum(st, place.call(L - 0.4, -0.6))
	# The arrow board behind the taper, facing the traffic.
	var axf: Transform3D = place.call(TAPER + 4.5, 0.0)
	K.arrow_board(st, axf)
	_shape(ch, Vector3(1.6, 1.2, 2.2), Transform3D(axf.basis, axf.origin + Vector3(0.0, 0.6, 0.0)))
	# The trench: plates over it, a spoil heap, the excavator digging at its end.
	var tz0 := TAPER + 9.0
	var tz1 := L - 7.5
	var plates := maxi(1, floori((tz1 - tz0) / 3.2))
	for i in plates:
		var pxf: Transform3D = place.call(tz0 + 1.6 + float(i) * 3.2, -0.1)
		K.trench_plate(st, pxf, Vector2(2.4, 3.05))
	var hxf: Transform3D = place.call(tz1 + 2.0, 0.55)
	K.box(st, hxf * Transform3D(Basis(Vector3.UP, 0.3), Vector3(0.0, 0.25, 0.0)), Vector3(1.2, 0.5, 1.8), K.K_DIRT, Color(0.85, 0.78, 0.68), -1.0, 0, 32)
	var exf: Transform3D = place.call(L - 3.6, 0.0)
	var swing := (_h01([s, "ex_swing"]) - 0.5) * 1.4 + PI
	K.excavator(st, exf, swing, 0.4 + 0.5 * _h01([s, "ex_dig"]))
	_shape(ch, Vector3(2.0, 2.5, 2.4), Transform3D(exf.basis, exf.origin + Vector3(0.0, 1.25, 0.0)))
	# A barricade across the lane at the downstream end.
	K.barricade(st, place.call(L + 0.6, 0.1), 2.0)
	# The crew: a flagger at the taper's end on the lane line with the paddle, one at the trench.
	var rect: Rect2 = ch.plan.block(ch.ix, ch.iz).rect
	var fpt := cl_point(c, cl_along(c, TAPER - 2.0), lane_edge - 0.5)
	var crew: Array = _state(ch).workers
	var lift := CityChunk.ROAD_TOP - CityChunk.SIDEWALK_TOP
	crew.append({"at": fpt, "yaw": face_up + PI, "lift": lift, "rect": rect, "seed": hash([s, "flagger"]), "paddle": true, "deck": true})
	var wpt := cl_point(c, cl_along(c, tz1 + 0.8), -0.6)
	crew.append({"at": wpt, "yaw": face_up + PI * 0.5 * side, "lift": lift, "rect": rect, "seed": hash([s, "digger"]), "paddle": false, "deck": true})


## ROAD WORK AHEAD: a 1.2 m orange diamond on a spring stand with two flags.
static func _road_sign(st: SurfaceTool, xf: Transform3D) -> void:
	var K := ConstructionKit
	K.box(st, xf * Transform3D(Basis(), Vector3(0.0, 0.03, 0.0)), Vector3(1.2, 0.06, 0.12), K.K_PAINT, Color(0.1, 0.1, 0.1))
	K.box(st, xf * Transform3D(Basis(), Vector3(0.0, 0.03, 0.0)), Vector3(0.12, 0.06, 1.0), K.K_PAINT, Color(0.1, 0.1, 0.1))
	K.box(st, xf * Transform3D(Basis(), Vector3(0.0, 0.5, 0.0)), Vector3(0.05, 1.0, 0.05), K.K_GALV, Color.WHITE)
	var d := xf * Transform3D(Basis(Vector3.BACK, PI * 0.25), Vector3(0.0, 1.45, 0.03))
	K.box(st, d, Vector3(0.85, 0.85, 0.015), K.K_SIGN, Color(0.98, 0.45, 0.05), -1.0, 0, 0)
	var face := xf * Transform3D(Basis(), Vector3(0.0, 1.45, 0.04))
	K.text(st, "ROAD", 0.13, face * Transform3D(Basis(), Vector3(0.0, 0.17, 0.0)), Color(0.04, 0.04, 0.04), K.K_SIGN)
	K.text(st, "WORK", 0.13, face, Color(0.04, 0.04, 0.04), K.K_SIGN)
	K.text(st, "AHEAD", 0.13, face * Transform3D(Basis(), Vector3(0.0, -0.17, 0.0)), Color(0.04, 0.04, 0.04), K.K_SIGN)
	for sx: float in [-0.42, 0.42]:
		K.box(st, xf * Transform3D(Basis(Vector3.BACK, sx), Vector3(sx * 0.9, 2.0, 0.03)), Vector3(0.02, 0.6, 0.02), K.K_PAINT, Color(0.15, 0.15, 0.15))
		K.box(st, xf * Transform3D(Basis(Vector3.BACK, sx), Vector3(sx * 1.05, 2.25, 0.03)), Vector3(0.28, 0.2, 0.005), K.K_SIGN, Color(0.98, 0.42, 0.05), -1.0, 0, 0)


## The builders' pickups at the kerb in front of their house frames (parked Vehicles, after every
## roll of the chunk's: their own rng, so the block's stream is untouched).
static func _spawn_pickups(ch: CityChunk) -> void:
	var list: Array = _state(ch).get("pickups", [])
	for p: Dictionary in list:
		if not PhysicsBudget.can_spawn():
			return
		var f: Dictionary = p.f
		var front: Vector2 = p.front
		var vv: Vector2 = f.v
		# The kerb is the cell's street edge (v = 0) less the pavement: stand in the parking lane.
		var kerb := front - vv * (ch.plan.sidewalk_width + 0.8 + CityPlan.PARKING_LANE * 0.5)
		var rng := RandomNumberGenerator.new()
		var car: Vehicle = null
		for k in 24:
			rng.seed = hash([ch.plan.seed, p.seed, "pickup", k])
			var probe := RandomNumberGenerator.new()
			probe.seed = rng.seed
			if Vehicle._body_for_roll(probe.randi_range(0, 999)) == Vehicle.BodyType.PICKUP:
				car = Vehicle.random_car(rng)
				break
		if car == null:
			continue
		var holder: Node = ch.get_parent() if ch.get_parent() else ch
		var at := Vector3(kerb.x, 0.3 + CityChunk.ROAD_TOP + ch._gy(kerb.x, kerb.y) + 0.4, kerb.y)
		car.position = WorldState.to_local(at) if holder != ch else at
		var uu: Vector2 = f.u
		car.rotation.y = atan2(-uu.x, -uu.y)
		holder.add_child(car)
		car.visible = ch.visible
		ch._cars.append(car)


# --- Crews --------------------------------------------------------------------------------------

## One worker of the chunk's crews (a block step; in the crowd cap, only in working hours).
static func spawn_worker(ch: CityChunk, index: int) -> void:
	if not ch.has_meta("construction"):
		return
	var crew: Array = _state(ch).workers
	if index >= crew.size() or not working(ch):
		return
	if not ch._take_crowd_room():
		return
	var w: Dictionary = crew[index]
	var ped := ConstructionWorker.new()
	ped.setup_vendor(w.rect, int(w.seed), w.at, float(w.yaw), bool(w.deck), float(w.lift))
	ped.paddle = bool(w.paddle)
	var at: Vector2 = w.at
	ped.position = Vector3(at.x, ch.ground_y(at.x, at.y) + float(w.lift) + 0.05, at.y)
	ch.add_child(ped)


static func paddle_mesh() -> ArrayMesh:
	if _paddle == null:
		_paddle = ConstructionKit.paddle_mesh()
	return _paddle
