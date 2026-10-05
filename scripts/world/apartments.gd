class_name Apartments
extends RefCounted
## Los Angeles stucco apartment buildings (G2's per-style kits, 2026-10-05) in MIDTOWN and the
## inner SUBURBS, built by the house kit's emitters (ApartmentBuild extends HouseBuild):
##   WALKUP          a two- or three-storey stucco walk-up, deep from the street, its units opening
##                   off cantilevered walkways (galleries) along a side court, reached by an open
##                   steel stair with concrete treads; flat roof behind a parapet or a low hip
##   BUNGALOW_COURT  a 1920s bungalow court: two rows of one-storey cottages facing each other
##                   across a planted court that runs back from the street, a larger one across the
##                   end; gable or hip roofs, stoops to the court
##   SPANISH_COURT   a 1920s Spanish courtyard building: two or three storeys of white stucco in a U
##                   round a tiled court with a fountain, clay-tile hip roofs, arched doors and
##                   windows, wrought-iron balconies
##   PODIUM          a four-storey podium apartment block: parking behind a steel garage gate and
##                   vented openings at street level, three floors of flats over it with balconies
##                   (midtown only)
## The beach town's dingbat is HouseKit's DINGBAT.
##
## A plan has HouseKit's shape (plan_house(): the frame "f", "wings", "door", "garage", "drive",
## ...), so YardFill lays the suburbs' yards round it and HouseBuild's walls, openings, roofs, LOD
## boxes and collision work unchanged; the apartment's own parts ride in "apt" keys: "galleries",
## "stairs", "court", "extra_ground" (frame rects YardFill keeps off: the court, the stairs) and
## "own_ground" (midtown, where no yard pass runs: the build lays the lot's ground itself).
##
## The claim is PURE and comes after every roll the lot already makes (CityChunk._build_lot(): the
## pad roll, the freeway corridor, the fire and police stations, Broadway, LotFill's car parks):
## a suburban lot is claimed inside HouseKit.plan_house() (so YardFill, GroundCoverage and the
## checks all see the same building), a midtown lot by one hook in _build_lot() before its
## Building. Every roll is a hash of the seed and the lot.

## Off: the lots get houses and Building boxes as before (the A/B: APARTMENTS=0 in the environment).
static var enabled: bool = OS.get_environment("APARTMENTS") != "0"

enum Kind { WALKUP, BUNGALOW_COURT, SPANISH_COURT, PODIUM }
const KIND_NAMES := ["walkup", "bungalow_court", "spanish_court", "podium"]

## Midtown: a lot whose massing (CityPlan.lot_height) is under this is low-rise, and MIDTOWN_ODDS of
## those are apartments (the rest keep their Building).
const MIDTOWN_MAX_H := 24.0
const MIDTOWN_ODDS := 0.45
## The inner suburbs: SUBURBS lots within INNER_RING m of the midtown ring (MacroMap.midtown_radius
## from downtown's extent) or of the westside centre's, at INNER_ODDS falling to 0 at the ring's end.
const INNER_RING := 900.0
const INNER_ODDS := 0.5
## Cumulative style odds per district (a style the yard is too small for falls to the next fitting).
const MIDTOWN_KINDS := [[Kind.PODIUM, 0.32], [Kind.SPANISH_COURT, 0.56], [Kind.BUNGALOW_COURT, 0.66], [Kind.WALKUP, 1.0]]
const SUBURB_KINDS := [[Kind.WALKUP, 0.45], [Kind.BUNGALOW_COURT, 0.75], [Kind.SPANISH_COURT, 1.0]]
## The smallest yard (U along the street, V back from it) each kind needs.
const MIN_YARD := [Vector2(15.0, 19.0), Vector2(17.0, 22.0), Vector2(19.0, 22.0), Vector2(17.0, 20.0)]

const STOREY := HouseKit.STOREY
## A gallery's depth off its wall, the stair's width, its riser and tread.
const GALLERY_D := 1.5
const STAIR_W := 1.15
const RISER := 0.18
const TREAD := 0.27
## The landing at the top of each flight (along the run).
const LANDING := 1.25
## A unit's frontage on a gallery or a street face.
const UNIT_W := 6.6

## Invented building names (the script letters on a parapet): plain words, never a real company.
const NAMES := ["Casa Linda", "The Royal Palms", "Las Brisas", "Villa Serena", "The Del Rey", "Sea Breeze",
	"Coral Terrace", "The Capri", "Casa Bonita", "Sunset Arms", "The Monterey", "La Paloma", "El Mirador",
	"The Kona", "Palm Court", "Villa Rosa", "The Tropicana", "Los Robles", "The Granada", "Casa del Sol",
	"The Aloha", "Bel Aire", "The Biscayne", "La Jolla Arms", "The Seville", "Casa Grande"]


static func _h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) / 100003.0


static func _range(v: Vector2, parts: Array) -> float:
	return lerpf(v.x, v.y, _h01(parts))


## Whether a lot of `district` at `center` is offered to the kit at all (before its yard's size).
static func _offered(plan: CityPlan, lot: Dictionary, district: int) -> bool:
	if not enabled or plan.macro == null or lot.get("yard", false) or lot.get("parking", false):
		return false
	var s: int = lot.seed
	var c: Vector2 = lot.center
	if plan.zone_at(c) != MacroMap.Zone.CITY:
		return false
	# A vacant lot or gravel car park (VacantLots) is claimed before this.
	if VacantLots.kind_of(plan, plan.block_index_at(c).x, plan.block_index_at(c).y, lot) != VacantLots.NONE:
		return false
	if district == CityPlan.District.MIDTOWN:
		if plan.lot_height(s, district, plan.macro.skyline_boost(c)) > MIDTOWN_MAX_H:
			return false
		return _h01([plan.seed, s, "apartments"]) < MIDTOWN_ODDS
	if district == CityPlan.District.SUBURBS:
		var m := plan.macro
		var d := minf(m.downtown_distance(c) - m.midtown_radius, c.distance_to(m.westside_center) - m.westside_radius)
		if d > INNER_RING:
			return false
		var odds := INNER_ODDS * clampf(1.0 - d / INNER_RING, 0.0, 1.0)
		return _h01([plan.seed, s, "apartments"]) < odds
	return false


## The kind an offered lot gets, from its yard's size; -1 when the yard is too small for any.
static func kind_for(plan: CityPlan, lot: Dictionary, district: int, U: float, V: float) -> int:
	var table: Array = MIDTOWN_KINDS if district == CityPlan.District.MIDTOWN else SUBURB_KINDS
	var roll := _h01([plan.seed, lot.seed, "apt_kind"])
	var start := 0
	for i in table.size():
		if roll < float(table[i][1]):
			start = i
			break
	for k in table.size():
		var kind: int = table[(start + k) % table.size()][0]
		var need: Vector2 = MIN_YARD[kind]
		if U >= need.x and V >= need.y:
			return kind
	return -1


## A midtown lot the kit claims (CityChunk._build_lot()'s hook: it builds it as a house, which
## HouseKit.plan_house() hands to plan_for()).
static func claims(plan: CityPlan, bx: int, bz: int, lot: Dictionary, district: int) -> bool:
	if district != CityPlan.District.MIDTOWN or not _offered(plan, lot, district):
		return false
	return not plan_house(plan, bx, bz, lot, district).is_empty()


## HouseKit.plan_house()'s hook: the apartment plan for a lot the kit takes, else {}.
static func plan_house(plan: CityPlan, bx: int, bz: int, lot: Dictionary, district: int) -> Dictionary:
	if not _offered(plan, lot, district):
		return {}
	var grid := YardFill.lot_grid(plan, bx, bz, [lot])
	var front := YardFill.lot_front(plan, bx, bz, lot, grid)
	if district == CityPlan.District.MIDTOWN:
		# A deco boulevard's lot is DecoBoulevard's; a block's service alley keeps its band (Alleys).
		if not DecoBoulevard.lot_plan(plan, bx, bz, lot).is_empty():
			return {}
		var yard := Alleys.trim(plan, bx, bz, front.yard)
		if yard.size.x < 1.0 or yard.size.y < 1.0:
			return {}
		front.yard = yard
	if front.walk_front:
		return {}
	var f := YardFill._frame(front.yard, int(front.side))
	var kind := kind_for(plan, lot, district, float(f.U), float(f.V))
	if kind < 0:
		return {}
	return plan_for(plan, lot, district, front, kind)


## The plan, in HouseKit's form (see the class note).
static func plan_for(plan: CityPlan, lot: Dictionary, district: int, front: Dictionary, kind: int) -> Dictionary:
	var f := YardFill._frame(front.yard, int(front.side))
	var U: float = f.U
	var V: float = f.V
	var s: int = lot.seed
	var ps := plan.seed
	var midtown := district == CityPlan.District.MIDTOWN
	var h := {"f": f, "side": front.side, "yard": front.yard, "walk_front": false, "style": HouseKit.Style.STUCCO_BOX,
		"seed": s, "wings": [], "porch": {}, "door": {}, "garage": {}, "drive": Vector2.ZERO, "drive_v": 0.0,
		"door_u": U * 0.5, "door_v": 2.0, "chimney": {}, "solar": false, "vents": 0, "breeze": Rect2(),
		"roof_mat": "h_flat", "shingle_kind": 1, "pitch": 0.28, "eave": 0.45, "beach": false,
		"apt": kind, "galleries": [], "stairs": [], "court": Rect2(), "extra_ground": [], "own_ground": midtown,
		"cell": lot.get("cell", front.yard), "lot": lot, "name": NAMES[absi(hash([ps, s, "apt_name"])) % NAMES.size()]}
	match kind:
		Kind.WALKUP:
			_plan_walkup(h, ps, s, U, V, midtown)
		Kind.BUNGALOW_COURT:
			_plan_bungalows(h, ps, s, U, V)
		Kind.SPANISH_COURT:
			_plan_spanish(h, ps, s, U, V, midtown)
		_:
			_plan_podium(h, ps, s, U, V)
	_colors(h, ps, s)
	var top := 0.0
	for w: Dictionary in h.wings:
		var wr: Rect2 = w.r
		var t := float(w.storeys) * STOREY + HouseKit.FLOOR_LIFT
		if w.roof == "hip" or w.roof == "gable":
			t += minf(wr.size.x, wr.size.y) * 0.5 * float(h.pitch) + float(h.eave) * float(h.pitch)
		elif w.roof == "flat":
			t += HouseKit.PARAPET
		top = maxf(top, t)
	h["height"] = top
	return h


static func _wing(r: Rect2, storeys: int, roof: String, role: String, ridge: int = 0) -> Dictionary:
	var w := HouseKit._wing(r, storeys, roof, role, ridge)
	w["apt_role"] = role
	w["doors"] = []
	return w


## The stair from the ground up to each gallery floor: straight flights along `dir` (a frame unit
## vector), beside the wall at `off` metres out (`out` the wall's outward normal), starting at `p`.
## Returns the frame rect it covers on the ground.
static func _stair_run(h: Dictionary, p: Vector2, dir: Vector2, out: Vector2, off: float, floors: int) -> Rect2:
	var y := -HouseKit.FLOOR_LIFT
	var at := p
	var lo := p + out * off
	var hi := lo
	for fl in range(1, floors + 1):
		var y1 := float(fl) * STOREY
		var risers := ceili((y1 - y) / RISER)
		var run := float(risers - 1) * TREAD
		h.stairs.append({"a": at + out * off, "dir": dir, "out": out, "y0": y, "y1": y1, "risers": risers, "run": run})
		at += dir * (run + LANDING)
		y = y1
	var end := at + out * (off + STAIR_W)
	for q: Vector2 in [end, at + out * off]:
		lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
		hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
	return Rect2(lo, hi - lo)


static func _plan_walkup(h: Dictionary, ps: int, s: int, U: float, V: float, midtown: bool) -> void:
	var storeys := 3 if _h01([ps, s, "three"]) < (0.6 if midtown else 0.35) else 2
	var fs := _range(Vector2(3.0, 5.0), [ps, s, "setback"])
	var ss := _range(Vector2(1.0, 1.6), [ps, s, "sideyard"])
	var bs := _range(Vector2(1.5, 3.5), [ps, s, "backyard"])
	var court := _range(Vector2(4.0, 5.2), [ps, s, "court_w"])
	var bw := clampf(U - 2.0 * ss - court, 8.0, 12.5)
	court = U - 2.0 * ss - bw
	var left := _h01([ps, s, "side"]) < 0.5
	var v0 := fs
	var v1 := V - bs
	var depth := v1 - v0
	# The stairs need their run: a third storey only with room for two flights and landings.
	var need := 0.8 + 2.0 * (17.0 * TREAD + LANDING) + 2.0
	if storeys == 3 and depth < need:
		storeys = 2
	var u0 := ss if left else U - ss - bw
	var main := _wing(Rect2(u0, v0, bw, depth), storeys, "flat", "main")
	h.roof_mat = "h_flat"
	if _h01([ps, s, "hip"]) < 0.4:
		main.roof = "hip"
		h.roof_mat = "h_roof" if _h01([ps, s, "clay"]) < 0.55 else "h_shingle"
		h.eave = _range(Vector2(0.45, 0.7), [ps, s, "eave"])
		h.pitch = _range(Vector2(0.22, 0.3), [ps, s, "pitch"])
	h.wings.append(main)
	# The gallery face looks into the side court.
	var face := "right" if left else "left"
	var out := Vector2(1, 0) if left else Vector2(-1, 0)
	var wall_u := u0 + bw if left else u0
	var floors: Array = []
	for fl in range(1, storeys):
		floors.append(fl)
	h.galleries.append({"wing": 0, "face": face, "a0": 0.0, "a1": depth, "depth": GALLERY_D, "floors": floors,
		"rail": "picket" if _h01([ps, s, "rail"]) < 0.6 else "solid", "posts": true})
	# Ground-floor and gallery doors along that face, one a unit.
	var units := maxi(1, int(depth / UNIT_W))
	for fl in storeys:
		for k in units:
			var a := (float(k) + 0.3) * depth / units
			main.doors.append([face, a, float(fl) * STOREY])
	# The stair at the street end of the court, flights running back beside the galleries.
	var stair := _stair_run(h, Vector2(wall_u, v0 + 0.6), Vector2(0, 1), out, GALLERY_D + 0.05, storeys - 1)
	h.extra_ground.append(stair.grow(0.15))
	# The court itself: a walk the length of the building.
	h.court = Rect2(minf(wall_u, wall_u + out.x * court), v0, court, depth)
	h.door = {"wing": 0, "u": wall_u + out.x * (GALLERY_D * 0.5), "kind": "none"}
	h.door_u = wall_u + out.x * (court * 0.5)
	h.door_v = v0


static func _plan_bungalows(h: Dictionary, ps: int, s: int, U: float, V: float) -> void:
	var fs := _range(Vector2(2.5, 4.0), [ps, s, "setback"])
	var ss := _range(Vector2(0.8, 1.3), [ps, s, "sideyard"])
	var bs := _range(Vector2(1.0, 2.2), [ps, s, "backyard"])
	var bd := clampf((U - 2.0 * ss) * 0.3, 5.0, 6.4)
	var cw := U - 2.0 * ss - 2.0 * bd
	var v0 := fs
	var v1 := V - bs
	# The cottage across the end of the court, then the rows down each side.
	var end_d := _range(Vector2(6.0, 7.5), [ps, s, "end_d"])
	var row_end := v1 - end_d - 1.2
	var bl := _range(Vector2(6.2, 7.6), [ps, s, "bung_l"])
	var gap := 1.4
	var n := maxi(1, int((row_end - v0 + gap) / (bl + gap)))
	bl = (row_end - v0 + gap) / n - gap
	var siding := _h01([ps, s, "siding"]) < 0.35
	var roof := "gable" if _h01([ps, s, "gable"]) < 0.6 else "hip"
	h.roof_mat = "h_roof" if _h01([ps, s, "clay"]) < (0.25 if siding else 0.6) else "h_shingle"
	h.pitch = _range(Vector2(0.3, 0.42), [ps, s, "pitch"])
	h.eave = _range(Vector2(0.45, 0.7), [ps, s, "eave"])
	for side in 2:
		var u0 := ss if side == 0 else U - ss - bd
		var face := "right" if side == 0 else "left"
		for k in n:
			var v := v0 + float(k) * (bl + gap)
			var w := _wing(Rect2(u0, v, bd, bl), 1, roof, "cottage", 2)
			if siding:
				w.mat = "h_siding"
				w.clad = 1.0
			w.doors.append([face, bl * 0.5, 0.0])
			w["stoop"] = face
			h.wings.append(w)
	var ew := minf(U - 2.0 * ss, 13.0)
	var end := _wing(Rect2((U - ew) * 0.5, v1 - end_d, ew, end_d), 1, roof, "cottage", 1)
	if siding:
		end.mat = "h_siding"
		end.clad = 1.0
	end.doors.append(["front", ew * 0.3, 0.0])
	end.doors.append(["front", ew * 0.7, 0.0])
	end["stoop"] = "front"
	h.wings.append(end)
	h.court = Rect2(ss + bd, v0, cw, (v1 - end_d) - v0)
	h.door = {"wing": h.wings.size() - 1, "u": U * 0.5, "kind": "none"}
	h.door_u = U * 0.5
	h.door_v = v0
	h["court_kind"] = "bungalow"


static func _plan_spanish(h: Dictionary, ps: int, s: int, U: float, V: float, midtown: bool) -> void:
	var storeys := 3 if midtown and _h01([ps, s, "three"]) < 0.4 else 2
	var fs := _range(Vector2(1.8, 3.2), [ps, s, "setback"])
	var ss := _range(Vector2(0.8, 1.4), [ps, s, "sideyard"])
	var bs := _range(Vector2(1.2, 2.6), [ps, s, "backyard"])
	var d := clampf((U - 2.0 * ss) * 0.33, 6.0, 8.5)
	var v0 := fs
	var v1 := V - bs
	var back_d := minf(d, (v1 - v0) * 0.4)
	h.roof_mat = "h_roof"
	h.pitch = _range(Vector2(0.24, 0.3), [ps, s, "pitch"])
	h.eave = _range(Vector2(0.25, 0.4), [ps, s, "eave"])
	var left := _wing(Rect2(ss, v0, d, v1 - v0), storeys, "hip", "main")
	var right := _wing(Rect2(U - ss - d, v0, d, v1 - v0), storeys, "hip", "main")
	var back := _wing(Rect2(ss + d, v1 - back_d, U - 2.0 * ss - 2.0 * d, back_d), storeys, "hip", "main")
	for w: Dictionary in [left, right, back]:
		w["arch"] = true
		w["spanish"] = true
		h.wings.append(w)
	var cl := v1 - back_d - v0
	var units := maxi(1, int(cl / UNIT_W))
	for k in units:
		var a := (float(k) + 0.5) * cl / units
		left.doors.append(["right", a, 0.0])
		right.doors.append(["left", (v1 - v0) - a, 0.0])
	back.doors.append(["front", (back.r as Rect2).size.x * 0.5, 0.0])
	# The upper floors are reached by a stair in the back corner, inside (not modelled); the court
	# has iron balconies instead of galleries.
	h.court = Rect2(ss + d, v0, U - 2.0 * ss - 2.0 * d, cl)
	h.door = {"wing": 2, "u": U * 0.5, "kind": "none"}
	h.door_u = U * 0.5
	h.door_v = v0
	h["court_kind"] = "spanish"
	h["entry_arch"] = _h01([ps, s, "entry_arch"]) < 0.7


static func _plan_podium(h: Dictionary, ps: int, s: int, U: float, V: float) -> void:
	var fs := _range(Vector2(1.5, 2.6), [ps, s, "setback"])
	var ss := _range(Vector2(0.6, 1.2), [ps, s, "sideyard"])
	var bs := _range(Vector2(1.0, 2.0), [ps, s, "backyard"])
	var r := Rect2(ss, fs, U - 2.0 * ss, V - fs - bs)
	var main := _wing(r, 4, "flat", "main")
	main["podium"] = true
	h.wings.append(main)
	h.roof_mat = "h_flat"
	var left := _h01([ps, s, "gate_side"]) < 0.5
	var gw := 5.6
	var g0 := (ss + 1.2) if left else (U - ss - 1.2 - gw)
	h.garage = {"wing": 0, "u0": g0, "u1": g0 + gw, "kind": "gate"}
	h.drive = Vector2(g0 - 0.2, g0 + gw + 0.2)
	h.drive_v = fs
	var du := (g0 + gw + 3.0) if left else (g0 - 3.0)
	h.door = {"wing": 0, "u": du, "kind": "none"}
	h.door_u = du
	h.door_v = fs
	main.doors.append(["front", du - ss, 0.0])
	h["balconies"] = _h01([ps, s, "balconies"]) < 0.85


## Colours: HouseKit's palettes (STUCCO, TRIM, ...) with the apartment's own leanings.
static func _colors(h: Dictionary, ps: int, s: int) -> void:
	HouseKit._colors(h, ps, s, false)
	var kind: int = h.apt
	if kind == Kind.SPANISH_COURT:
		h.colors.wall = HouseKit._pick([Color(0.97, 0.95, 0.90), Color(0.95, 0.91, 0.82), Color(0.93, 0.87, 0.76), Color(0.96, 0.92, 0.86)], [ps, s, "stucco"])
		h.colors.trim = HouseKit._pick([Color(0.28, 0.19, 0.12), Color(0.17, 0.27, 0.23), Color(0.40, 0.16, 0.12)], [ps, s, "trim"])
		h.colors.frame = h.colors.trim
	elif kind == Kind.PODIUM or kind == Kind.WALKUP:
		h.colors.frame = Color(0.82, 0.82, 0.80) if _h01([ps, s, "alu"]) < 0.65 else Color(0.16, 0.16, 0.16)
	# The accent: a contrasting stucco for the gallery fascias, stair stringers and a podium's panels.
	h.colors["accent"] = HouseKit._pick([Color(0.20, 0.36, 0.42), Color(0.55, 0.26, 0.18), Color(0.86, 0.64, 0.30),
		Color(0.32, 0.40, 0.32), Color(0.18, 0.18, 0.20), Color(0.94, 0.93, 0.90)], [ps, s, "accent"])
	h.colors["rail"] = HouseKit._pick([Color(0.12, 0.12, 0.12), Color(0.93, 0.93, 0.91), Color(0.20, 0.30, 0.34)], [ps, s, "rail_c"])


## HouseKit.ground_parts()'s hook: the frame rects of the ground the yard keeps off besides the wings
## (the stairs, the court).
static func extra_ground(h: Dictionary) -> Array[Rect2]:
	var out: Array[Rect2] = []
	if not h.has("apt"):
		return out
	var f: Dictionary = h.f
	for r: Rect2 in h.extra_ground:
		out.append(YardFill._fr(f, r.position.x, r.position.y, r.end.x, r.end.y))
	var c: Rect2 = h.court
	if c.size.x > 0.0:
		out.append(YardFill._fr(f, c.position.x, c.position.y, c.end.x, c.end.y))
	return out
