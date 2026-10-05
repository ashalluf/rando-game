class_name HistoricCore
extends RefCounted
## Downtown's historic core (2026-10-05, "the old banks and office blocks as beaux-arts
## buildings"): the lots fronting Spring St and Main St between 2nd St and 9th St, which
## DowntownReal pins 1:1 on every seed (Spring x 3113, Main x 3236). The real streets' FORMS - the
## "Wall Street of the West" of 1900-1930: banks and office blocks of glazed terracotta, granite
## and pressed brick, a rusticated two-storey base with arched windows, a giant order of pilasters
## or engaged columns, a heavy bracketed cornice, a decorated attic, bronze shopfronts and a lit
## entrance with the building's name over it - and every NAME invented.
##
## Nothing is placed by hand: the lots are the seeded plan's own (CityPlan.lots()), and a lot is
## historic when it fronts one of the two avenues inside the stretch. dress() turns its Building
## (set up by CityChunk._build_lot(), every roll of the chunk already made) into a beaux-arts
## block BEFORE it generates - a slab filling its lot, terracotta or brick, punched windows,
## under the old 150 ft limit, no balconies, bays or canopies, bronze shop frames, no kit window
## surrounds (the facade brings its own) - and after_building() hands it to HistoricFacade, which
## models the ornament on its street faces at real geometry, aligned to the very window grid the
## building shader draws (Building.part_grid()), as time-sliced build steps. LOD chunks and the
## far city keep FarBuilding's coded boxes (the building is still a Building, so its facade,
## shops and lit offices are coded as before) plus the cornice as a far box per street face, so
## the silhouette keeps its overhang. Every choice is a hash of the seed and the lot.
##
## Off (HISTORIC_CORE=0 in the environment): none of it, the A/B for stills and frame counts.

## The two avenues and the stretch (DowntownReal.AVENUES / STREETS names).
const AVENUES := ["SPRING ST", "MAIN ST"]
const NORTH_STREET := "2ND ST"
const SOUTH_STREET := "9TH ST"
## Heights per avenue (m): Spring St's banks and twelve-storey offices, Main St's lower blocks.
## The old city height limit was 150 ft (46 m); the SLAB layout caps itself at 40.
const HEIGHTS := {"SPRING ST": Vector2(24.0, 40.0), "MAIN ST": Vector2(13.0, 30.0)}
## Wall palettes (Building.palette_override). Glazed terracotta and limestone: cream, buff, ivory,
## grey granite, a warm pink; and pressed brick for the brick fronts.
const TERRACOTTA := [Color(0.84, 0.80, 0.70), Color(0.80, 0.74, 0.62), Color(0.88, 0.85, 0.77),
	Color(0.70, 0.69, 0.66), Color(0.82, 0.70, 0.60), Color(0.78, 0.76, 0.70)]
const PRESSED_BRICK := [Color(0.62, 0.36, 0.26), Color(0.70, 0.52, 0.38), Color(0.56, 0.32, 0.24),
	Color(0.74, 0.60, 0.46)]
## Share of the brick fronts (their ornament is in TERRACOTTA, as the real ones are).
const BRICK_SHARE := 0.3
## Invented names for the lettering over the entrance and on the frieze. Never a real building,
## bank or company.
const NAMES := ["HALCOMBE BUILDING", "THE VARDEN", "ORCHARD NATIONAL BANK", "BELLWETHER SAVINGS",
	"CITRUS GROWERS TRUST", "LINDQUIST BLOCK", "THE ASHGROVE", "CALLOWAY BUILDING",
	"SIERRA TRUST CO", "MARROW & STEIN", "THE WESTMERE", "PALISADE SAVINGS",
	"MERCHANTS EXCHANGE", "HOLLISTER BLOCK", "BASIN THRIFT BANK", "THE CORWIN",
	"DRAYTON BUILDING", "ARROYO NATIONAL BANK", "THE MARLOWE", "PIONEER MUTUAL TRUST"]

static var enabled: bool = OS.get_environment("HISTORIC_CORE") != "0"
## How many historic Buildings have been dressed (probes and checks).
static var dressed_count: int = 0
## The longest ornament build step so far (microseconds; probes and checks) and which it was.
static var max_step_us: int = 0
static var max_step_label: String = ""
## HISTORIC_TIME=1: print every ornament build step over a millisecond (tools/historic/steps.tscn).
static var time_steps: bool = OS.get_environment("HISTORIC_TIME") == "1"


## An avenue's centre line x and width (the pinned real street), or [] when it is not pinned.
static func avenue(name: String) -> Array:
	var pin := DowntownReal.named(CityPlan.AXIS_X, name)
	if pin.is_empty():
		return []
	return [float(pin[0]), float(pin[1])]


## The stretch's two ends in z (2nd St's and 9th St's centre lines).
static func z_range() -> Vector2:
	return Vector2(Broadway.street_z(NORTH_STREET), Broadway.street_z(SOUTH_STREET))


## Which avenue edges block (bx, bz) fronts inside the stretch: an Array of [avenue name, side]
## (side -1: the block is west of the avenue, its +x edge on it; +1 east, its -x edge).
static func block_fronts(plan: CityPlan, bx: int, bz: int) -> Array:
	var out: Array = []
	if not enabled or plan == null or plan.macro == null:
		return out
	var b := plan.block(bx, bz)
	if int(b.kind) != CityPlan.BlockKind.BUILDINGS or int(b.district) != CityPlan.District.DOWNTOWN:
		return out
	var r: Rect2 = b.rect
	var zr := z_range()
	if is_nan(zr.x) or is_nan(zr.y):
		return out
	var c := r.get_center()
	if c.y < zr.x or c.y > zr.y:
		return out
	for name: String in AVENUES:
		var av := avenue(name)
		if av.is_empty():
			continue
		var half: float = float(av[1]) * 0.5
		if absf(r.end.x - (float(av[0]) - half)) < 1.0:
			out.append([name, -1])
		elif absf(r.position.x - (float(av[0]) + half)) < 1.0:
			out.append([name, 1])
	return out


## The avenue `lot` of block (bx, bz) fronts (its edge on that avenue's pavement), or "".
static func lot_avenue(plan: CityPlan, bx: int, bz: int, lot: Dictionary) -> String:
	if lot.get("yard", false) or lot.get("parking", false):
		return ""
	var fronts := block_fronts(plan, bx, bz)
	if fronts.is_empty():
		return ""
	var inner := (plan.block(bx, bz).rect as Rect2).grow(-plan.sidewalk_width)
	var c: Vector2 = lot.center
	var s: Vector2 = lot.size
	for f: Array in fronts:
		var side: int = f[1]
		if side < 0 and c.x + s.x * 0.5 > inner.end.x - 3.0:
			return f[0]
		if side > 0 and c.x - s.x * 0.5 < inner.position.x + 3.0:
			return f[0]
	return ""


## The outward normals (building space, Vector3) of a lot's faces that front a street: the
## block's four edges are all streets, so a face within a few metres of the block's pavement
## ring is a street face.
static func street_faces(plan: CityPlan, bx: int, bz: int, lot: Dictionary) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var inner := (plan.block(bx, bz).rect as Rect2).grow(-plan.sidewalk_width)
	var c: Vector2 = lot.center
	var h: Vector2 = (lot.size as Vector2) * 0.5
	if c.x + h.x > inner.end.x - 3.0:
		out.append(Vector3(1, 0, 0))
	if c.x - h.x < inner.position.x + 3.0:
		out.append(Vector3(-1, 0, 0))
	if c.y + h.y > inner.end.y - 3.0:
		out.append(Vector3(0, 0, 1))
	if c.y - h.y < inner.position.y + 3.0:
		out.append(Vector3(0, 0, -1))
	return out


## What a historic lot's building is, worked out from the seed and the lot alone: {"avenue",
## "brick" (bool), "columns" (engaged columns instead of pilasters), "name", "height" Vector2,
## "palette" index, "tint" (the ornament's colour)}.
static func spec_for(plan: CityPlan, bx: int, bz: int, lot: Dictionary) -> Dictionary:
	var av := lot_avenue(plan, bx, bz, lot)
	if av == "":
		return {}
	var s := int(lot.seed)
	var brick := h01([s, "hc brick"]) < BRICK_SHARE
	var pal := int(h01([s, "hc palette"]) * float(TERRACOTTA.size())) % TERRACOTTA.size()
	return {"avenue": av, "brick": brick,
		"columns": h01([s, "hc columns"]) < (0.4 if av == "SPRING ST" else 0.15),
		"name": name_for(plan, av, lot),
		"height": HEIGHTS[av], "palette": pal, "tint": TERRACOTTA[pal]}


## The lettering of a lot's building: consecutive lots along one side of an avenue take
## consecutive names from a seeded starting point, so neighbours never share one.
static func name_for(plan: CityPlan, av: String, lot: Dictionary) -> String:
	var c: Vector2 = lot.center
	var side := 0 if c.x < float(avenue(av)[0]) else 1
	var start := absi(hash([plan.seed, av, side, "hc names"]))
	var k := floori((c.y + 2000.0) / 26.0)
	return NAMES[(start + k) % NAMES.size()]


## CityChunk._build_lot(): a lot fronting Spring St or Main St in the stretch becomes a beaux-arts
## block. Set before the building generates (both levels, so the far copy agrees). A lot that
## runs through to Broadway keeps Broadway's shop names (its name_pool) and height limit.
static func dress(ch: CityChunk, lot: Dictionary, building: Building) -> void:
	if not enabled:
		return
	var spec := spec_for(ch.plan, ch.ix, ch.iz, lot)
	if spec.is_empty():
		return
	var hr: Vector2 = spec.height
	building.force_shape = Building.Shape.SLAB
	building.fill_lot = true
	building.finish_options.assign([Building.Finish.BRICK] if spec.brick else [Building.Finish.FLAT])
	building.palette_override = PRESSED_BRICK if spec.brick else [spec.tint]
	building.max_height = lerpf(hr.x, hr.y, h01([int(lot.seed), "hc height"]))
	building.min_height = building.max_height
	building.chamfer_chance = 0.0
	building.balcony_chance = 0.0
	building.bay_chance = 0.0
	building.canopy_chance = 0.0
	building.string_course_every = 0
	building.podium_lot = false
	building.kit_surround_force = "none"
	building.kit_cornice_force = "none"
	building.shop_frame_force = 1
	building.window_style_force = Building.WindowStyle.PUNCHED
	# The rusticated base and its belt course are the facade's (HistoricFacade), not a painted band.
	building.allow_base_course = false
	building.roof_bands = false
	building.set_meta("historic", spec)
	dressed_count += 1


## CityChunk._build_lot(), once the building is set up (FULL: in the tree; LOD: planned): the
## ornament (FULL, HistoricFacade, as build steps of its own) or the far cornice boxes (LOD and
## the far city's capture).
static func after_building(ch: CityChunk, lot: Dictionary, building: Building, style: Dictionary = {}) -> void:
	if not enabled or not building.has_meta("historic"):
		return
	var spec: Dictionary = building.get_meta("historic")
	var faces := street_faces(ch.plan, ch.ix, ch.iz, lot)
	if faces.is_empty():
		return
	if ch.level == CityChunk.Level.FULL:
		# The main front faces the avenue: the entrance and the name go there.
		var main_n := faces[0]
		var av := avenue(str(spec.avenue))
		if not av.is_empty():
			var want := Vector3(signf(float(av[0]) - (lot.center as Vector2).x), 0.0, 0.0)
			if faces.has(want):
				main_n = want
		# Each job is [label, Callable]; a job that returns false is called again next step (a
		# commit cut into slices), anything else moves on.
		var jobs := HistoricFacade.jobs(building, spec, faces, main_n)
		var i := [0]
		ch._run_or_defer(func() -> bool:
			if not is_instance_valid(building):
				return true
			if i[0] < jobs.size():
				var job: Array = jobs[i[0]]
				var t0 := Time.get_ticks_usec()
				var r: Variant = (job[1] as Callable).call()
				var dt := Time.get_ticks_usec() - t0
				if dt > max_step_us:
					max_step_us = dt
					max_step_label = HistoricFacade.step_label
				if time_steps and dt > 1000:
					print("HISTORIC step %.2f ms (slowest job %s)" % [float(dt) / 1000.0, HistoricFacade.step_label])
				if not (r is bool and r == false):
					i[0] += 1
			return i[0] >= jobs.size())
	else:
		HistoricFacade.far_boxes(ch, building, style, faces, spec)


static func h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) / 100003.0
