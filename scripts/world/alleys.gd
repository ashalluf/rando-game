class_name Alleys
extends RefCounted
## The backs of blocks (2026-10-05, the alleys pass). Los Angeles' commercial and downtown blocks
## are two rows of lots back to back with a service alley down the middle: cracked concrete with
## a V-gutter, patched asphalt, oil, drains, dumpsters and grease bins, back doors under caged
## bulkhead lamps, loading docks, fire escapes with their drop ladders, condensers on brackets,
## gas meters, wooden power poles with sagging wires. Here the strip between the two rows was the
## forecourt paving LotFill lays round every downtown and midtown building, planters and all.
##
## The plan is PURE where it has to be: spec() says from CityPlan.lots() alone whether a block has
## an alley and where its band lies (the seam of the lot grid across the block's long axis, out to
## HALF_BAND either side), so LotFill can keep its forecourt paving, planters and car parks off
## the band while the lots are being built (trim(), keep_out()), and the parked cars and the
## pavement's lamps and trees off its mouths (keeps_clear(), in_mouth()). Where the alley runs
## inside the band, and how wide, is worked out in the block step from the buildings the lots
## actually stood up (record(), from LotFill.after_building at every level): runs() walks the band
## from each mouth for as long as the buildings leave MIN_WIDTH clear.
##
## Every roll is a hash of the plan seed and the block (and the run, side and face), never a
## chunk, block or Building rng: no lot, building, car or walker moves. A FULL chunk's alley
## ground is ONE mesh (AlleyGround, shaders/alley_ground.gdshader, no shadow) and everything
## upright ONE casting mesh (AlleyWalls, on IndustrialKit's material and writers - AlleyKit); the
## poles and wires ride StreetDetail's batches, the lamps' light pools one additive batch. LOD
## chunks and the far city's capture get the band's ground as slabs, nothing else.

## Off (the A/B): ALLEYS=0 in the environment.
static var enabled: bool = OS.get_environment("ALLEYS") != "0"

## Districts with alleys, and the odds a block of buildings there has one (a hash of the block).
const DISTRICTS := [CityPlan.District.DOWNTOWN, CityPlan.District.MIDTOWN]
const ODDS := {CityPlan.District.DOWNTOWN: 0.85, CityPlan.District.MIDTOWN: 0.75}
## Downtown only outside the financial core (skyline boost over this): the historic core's blocks
## have alleys; the core's towers stand on podiums that fill their lots.
const MAX_BOOST := 0.55
## Half the band kept for the alley either side of the seam (metres): LotFill keeps off it.
const HALF_BAND := 3.6
## A full alley (20 ft) and the narrowest that is still one (metres).
const WIDTH := 6.1
const MIN_WIDTH := 3.2
## Clearance kept from a building's wall, and the shortest run worth laying (metres).
const WALL_CLEAR := 0.15
const MIN_RUN := 10.0
## Sample step of the clearance walk (metres).
const STEP := 0.5
## Top of the alley's ground over the pavement slab; the V-gutter's sag at the centre line (from the
## edges, metres).
const LIFT := 0.045
const SAG := 0.03
## Odds an alley mouth has chain-link gates, a run has a speed bump per this many metres, a back
## door is a loading dock, a building's back has a fire escape.
const GATE_ODDS := 0.3
const BUMP_EVERY := 45.0
const DOCK_ODDS := 0.22
const FIRE_ESCAPE_ODDS := 0.55
## Utility poles down the alley: odds an alley has them, spacing (StreetDetail's), inset from the
## alley's edge.
const POLE_ODDS := 0.7
const POLE_SPACING := 30.0
## Most props of a kind one chunk's alleys hold.
const MAX_LAMPS := 18
const MAX_LIGHTS := 5
## Cooks on a smoke break by a back door: the most a chunk, and the odds a door has one.
const MAX_COOKS := 2
const COOK_ODDS := 0.18
## Kinds in alley_ground.gdshader (COLOR.r in 16ths).
const G_ALLEY := 0
const G_APRON := 1
const G_PAVE := 2
const G_BUMP := 3
const G_PAINT := 4
## The far ground's colour for the band (a slab's tint, linear-ish like LotFill's).
const FAR_COLOR := Color(0.47, 0.46, 0.44)
## The invented waste haulers stencilled on the dumpsters (never a real company).
const HAULERS := ["BASIN HAULING", "ARROYO DISPOSAL", "MESA WASTE CO", "SEPULVEDA ROLL-OFF", "TOLUCA SANITATION"]
## Dumpster bodies by hauler (sRGB): forest green, navy, brown, slate, rust red.
const HAULER_PAINT := [Color(0.13, 0.27, 0.16), Color(0.12, 0.17, 0.32), Color(0.30, 0.20, 0.12), Color(0.28, 0.30, 0.31), Color(0.42, 0.13, 0.09)]

static var _specs: Dictionary = {}


static func _h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) / 100003.0


static func _rng(plan: CityPlan, parts: Array) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([plan.seed, "alley"] + parts)
	return rng


# --- The pure plan --------------------------------------------------------------------------

## The block's alley band, from the lot grid alone: {} for none, else {"along_x": the alley runs
## along x (a line of constant z), "seam": the across coordinate of the lot-grid seam it follows,
## "band": the band inside the block's inner rect, "inner", "rect" (the block between the kerbs),
## "district", "lots"}. Cached per plan and block.
static func spec(plan: CityPlan, bx: int, bz: int) -> Dictionary:
	if not enabled or plan == null or plan.macro == null:
		return {}
	var key := hash([plan.get_instance_id(), plan.seed, bx, bz])
	if _specs.has(key):
		return _specs[key]
	if _specs.size() > 40000:
		_specs.clear()
	var out := _spec(plan, bx, bz)
	_specs[key] = out
	return out


static func _spec(plan: CityPlan, bx: int, bz: int) -> Dictionary:
	var b: Dictionary = plan.block(bx, bz)
	if int(b.kind) != CityPlan.BlockKind.BUILDINGS or b.has("site") or b.has("grounds"):
		return {}
	var district: int = b.district
	if not district in DISTRICTS:
		return {}
	var rect: Rect2 = b.rect
	var centre := rect.get_center()
	if plan.zone_at(centre) != MacroMap.Zone.CITY or plan.river_block(bx, bz):
		return {}
	if district == CityPlan.District.DOWNTOWN and plan.macro.skyline_boost(centre) > MAX_BOOST:
		return {}
	if _h01([plan.seed, bx, bz, "alley_roll"]) >= float(ODDS[district]):
		return {}
	if plan.macro.replica and plan.macro.replica.block_role(plan, bx, bz) != 0:
		return {}
	if Landmarks.claims(rect):
		return {}
	var inner := rect.grow(-plan.sidewalk_width)
	# A landmark's square in the block (a downtown tower, the masjid): its own ground, not ours.
	for lm in Landmarks.all():
		var r: float = lm.radius
		if Rect2((lm.anchor as Vector2) - Vector2(r, r), Vector2(r * 2.0, r * 2.0)).intersects(inner):
			return {}
	if plan.macro.runway_clear_zone().intersects(inner):
		return {}
	var lots := plan.lots(bx, bz)
	if lots.size() < 2:
		return {}
	for lot: Dictionary in lots:
		if YardFill.is_corridor(plan, lot) or FireStation.claims(plan, bx, bz, lot):
			return {}
	var cell: Vector2 = (lots[0].cell as Rect2).size
	var nx := roundi(inner.size.x / cell.x)
	var nz := roundi(inner.size.y / cell.y)
	# Down the block's long axis (the alley parallel to the long streets), across a grid of at
	# least two rows; else the other way, if that has two.
	var along_x := inner.size.x >= inner.size.y
	if (nz if along_x else nx) < 2:
		along_x = not along_x
	var n := nz if along_x else nx
	if n < 2:
		return {}
	var k := n / 2
	if n % 2 == 1 and _h01([plan.seed, bx, bz, "alley_seam"]) < 0.5:
		k += 1
	var seam: float
	var band: Rect2
	if along_x:
		seam = inner.position.y + cell.y * float(k)
		band = Rect2(inner.position.x, seam - HALF_BAND, inner.size.x, HALF_BAND * 2.0)
	else:
		seam = inner.position.x + cell.x * float(k)
		band = Rect2(seam - HALF_BAND, inner.position.y, HALF_BAND * 2.0, inner.size.y)
	return {"along_x": along_x, "seam": seam, "band": band, "inner": inner, "rect": rect, "district": district, "lots": lots, "bx": bx, "bz": bz}


## A lot's cell (or any rect of the block) less the alley band: one rect, since the band runs the
## whole block on a cell edge. The rect itself when the block has no alley; a zero rect when the
## band eats it.
static func trim(plan: CityPlan, bx: int, bz: int, r: Rect2) -> Rect2:
	var sp := spec(plan, bx, bz)
	if sp.is_empty():
		return r
	var band: Rect2 = sp.band
	if not band.intersects(r):
		return r
	if sp.along_x:
		if r.get_center().y < float(sp.seam):
			return Rect2(r.position, Vector2(r.size.x, maxf(0.0, band.position.y - r.position.y)))
		return Rect2(Vector2(r.position.x, band.end.y), Vector2(r.size.x, maxf(0.0, r.end.y - band.end.y)))
	if r.get_center().x < float(sp.seam):
		return Rect2(r.position, Vector2(maxf(0.0, band.position.x - r.position.x), r.size.y))
	return Rect2(Vector2(band.end.x, r.position.y), Vector2(maxf(0.0, r.end.x - band.end.x), r.size.y))


## What LotFill's forecourts keep off (the band), as rects; [] for a block without an alley.
static func keep_out(plan: CityPlan, bx: int, bz: int) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var sp := spec(plan, bx, bz)
	if not sp.is_empty():
		out.append(sp.band)
	return out


## True where `p` (true world XZ) is on the pavement across an alley's mouth: the pavement's lamps
## and trees keep off it. The block the point is in, and its neighbours (a point on the kerb line).
static func in_mouth(plan: CityPlan, bx: int, bz: int, p: Vector2) -> bool:
	var sp := spec(plan, bx, bz)
	if sp.is_empty():
		return false
	var inner: Rect2 = sp.inner
	var across := p.y if sp.along_x else p.x
	if absf(across - float(sp.seam)) > HALF_BAND + 0.9:
		return false
	return not inner.has_point(p)


## True where a parked car at `p` (true world XZ, in a parking lane) would stand across an alley's
## mouth: red kerb there. Asks the blocks either side of the road.
static func keeps_clear(plan: CityPlan, p: Vector2) -> bool:
	if not enabled or plan == null or plan.macro == null:
		return false
	var k := plan.block_index_at(p)
	for d: Vector2i in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var sp := spec(plan, k.x + d.x, k.y + d.y)
		if sp.is_empty():
			continue
		var rect: Rect2 = sp.rect
		if sp.along_x:
			if absf(p.y - float(sp.seam)) < HALF_BAND + 2.6 and (absf(p.x - rect.position.x) < 16.0 or absf(p.x - rect.end.x) < 16.0) and (p.x < rect.position.x or p.x > rect.end.x):
				return true
		else:
			if absf(p.x - float(sp.seam)) < HALF_BAND + 2.6 and (absf(p.y - rect.position.y) < 16.0 or absf(p.y - rect.end.y) < 16.0) and (p.y < rect.position.y or p.y > rect.end.y):
				return true
	return false


# --- What the lots stood up -------------------------------------------------------------------

static func _state(ch: CityChunk) -> Dictionary:
	if not ch.has_meta("alley"):
		ch.set_meta("alley", {"foot": {}, "ground": [], "walls": null, "lamps": 0, "lights": 0, "runs": []})
	return ch.get_meta("alley")


## The face of a lot's building that looks at the alley (Building.back_face: 1 +X, 2 -X, 3 +Z,
## 4 -Z), or 0 for a lot whose cell does not meet the seam.
static func back_face(plan: CityPlan, bx: int, bz: int, lot: Dictionary) -> int:
	var sp := spec(plan, bx, bz)
	if sp.is_empty() or not lot.has("cell") or lot.get("yard", false):
		return 0
	var cell: Rect2 = lot.cell
	var seam: float = sp.seam
	if sp.along_x:
		if absf(cell.end.y - seam) < 0.05:
			return 3
		if absf(cell.position.y - seam) < 0.05:
			return 4
	else:
		if absf(cell.end.x - seam) < 0.05:
			return 1
		if absf(cell.position.x - seam) < 0.05:
			return 2
	return 0


## A lot's building, as LotFill lays its forecourt round it (any level): its ground parts (world
## rects), for runs(), and its back strip (back_strip()), laid as the alley's service ground.
static func record(ch: CityChunk, lot: Dictionary, holes: Array[Rect2]) -> void:
	if spec(ch.plan, ch.ix, ch.iz).is_empty():
		return
	var st := _state(ch)
	st.foot[int(lot.seed)] = holes.duplicate()
	var back := back_strip(ch.plan, ch.ix, ch.iz, lot, holes)
	if back.size.x > 0.3 and back.size.y > 0.3:
		if not st.has("backs"):
			st["backs"] = []
		(st.backs as Array).append([back, int(lot.seed)])


## The ground behind a lot's building on the alley's side: from the building's back (the furthest
## its ground parts reach toward the seam) to the band, the cell's whole width. Not forecourt but
## the building's service yard: the alley's ground, its dumpsters and back doors. A zero rect for a
## lot whose cell does not meet the seam (or a block without an alley).
static func back_strip(plan: CityPlan, bx: int, bz: int, lot: Dictionary, holes: Array[Rect2]) -> Rect2:
	var sp := spec(plan, bx, bz)
	if sp.is_empty() or holes.is_empty() or not lot.has("cell"):
		return Rect2()
	var cell: Rect2 = lot.cell
	var seam: float = sp.seam
	var along_x: bool = sp.along_x
	var c0 := cell.position.y if along_x else cell.position.x
	var c1 := cell.end.y if along_x else cell.end.x
	var low := absf(c1 - seam) < 0.05
	if not low and absf(c0 - seam) > 0.05:
		return Rect2()
	var ext := -INF if low else INF
	for h: Rect2 in holes:
		if low:
			ext = maxf(ext, h.end.y if along_x else h.end.x)
		else:
			ext = minf(ext, h.position.y if along_x else h.position.x)
	var a := ext if low else seam + HALF_BAND
	var b := seam - HALF_BAND if low else ext
	if b - a < 0.3:
		return Rect2()
	if along_x:
		return Rect2(cell.position.x, a, cell.size.x, b - a)
	return Rect2(a, cell.position.y, b - a, cell.size.y)


## What stands in the band, from the lots: every recorded building's ground parts, a pocket
## garden's lot, and any lot nothing was recorded for (a pad, a station) as its whole lot.
## [obstacles, ground keep-outs (what the band's own ground must not cover)].
static func obstacles(sp: Dictionary, foot: Dictionary) -> Array:
	var obs: Array[Rect2] = []
	var keep: Array[Rect2] = []
	for lot: Dictionary in sp.lots:
		var size: Vector2 = lot.size
		var lr := Rect2((lot.center as Vector2) - size * 0.5, size)
		if lot.get("parking", false):
			continue
		if foot.has(int(lot.seed)):
			obs.append_array(foot[int(lot.seed)])
			continue
		obs.append(lr)
		keep.append(lr)
	return [obs, keep]


## The alley's runs inside the band: from each mouth, as far as the buildings leave MIN_WIDTH
## clear on a straight line (the band's free interval narrows as it goes; a run stops where it
## would fall under MIN_WIDTH). [{"s0", "s1" (along), "c" (the centre line, across), "w" (width),
## "m0", "m1" (the run reaches the low / high mouth)}].
static func runs(sp: Dictionary, obs: Array) -> Array:
	var along_x: bool = sp.along_x
	var inner: Rect2 = sp.inner
	var seam: float = sp.seam
	var a0 := inner.position.x if along_x else inner.position.y
	var a1 := inner.end.x if along_x else inner.end.y
	var n := maxi(2, ceili((a1 - a0) / STEP) + 1)
	# The free interval round the seam at each sample.
	var lo := PackedFloat32Array()
	var hi := PackedFloat32Array()
	lo.resize(n)
	hi.resize(n)
	for i in n:
		lo[i] = seam - HALF_BAND
		hi[i] = seam + HALF_BAND
	for r: Rect2 in obs:
		var r0 := (r.position.x if along_x else r.position.y) - WALL_CLEAR
		var r1 := (r.end.x if along_x else r.end.y) + WALL_CLEAR
		var c0 := (r.position.y if along_x else r.position.x) - WALL_CLEAR
		var c1 := (r.end.y if along_x else r.end.x) + WALL_CLEAR
		if c1 <= seam - HALF_BAND or c0 >= seam + HALF_BAND or r1 <= a0 or r0 >= a1:
			continue
		var i0 := clampi(floori((r0 - a0) / STEP), 0, n - 1)
		var i1 := clampi(ceili((r1 - a0) / STEP), 0, n - 1)
		for i in range(i0, i1 + 1):
			if c0 <= seam and c1 >= seam:
				# Across the seam: nothing passes.
				lo[i] = seam
				hi[i] = seam
			elif c1 < seam:
				lo[i] = maxf(lo[i], c1)
			else:
				hi[i] = minf(hi[i], c0)
	var out: Array = []
	var first := _grow(lo, hi, 0, 1, n)
	var reach0: int = first[0]
	if reach0 > 0:
		out.append(_run(sp, a0, a0 + float(reach0) * STEP, first, true, reach0 >= n - 1))
	if reach0 < n - 1:
		var second := _grow(lo, hi, n - 1, -1, n)
		var reach1: int = second[0]
		var start := maxi(reach1, reach0 + 1)
		if start < n - 1:
			out.append(_run(sp, a0 + float(start) * STEP, a1, second, false, true))
	var kept: Array = []
	for r: Dictionary in out:
		if float(r.s1) - float(r.s0) >= MIN_RUN:
			kept.append(r)
	return kept


## How far a straight run gets from sample `from` going `dir`: [the last sample index it keeps,
## its low edge, its high edge].
static func _grow(lo: PackedFloat32Array, hi: PackedFloat32Array, from: int, dir: int, n: int) -> Array:
	var l := -INF
	var h := INF
	var last := from
	var i := from
	var any := false
	while i >= 0 and i < n:
		var nl := maxf(l, lo[i])
		var nh := minf(h, hi[i])
		if nh - nl < MIN_WIDTH:
			break
		l = nl
		h = nh
		last = i
		any = true
		i += dir
	if not any:
		return [from if dir < 0 else 0, 0.0, 0.0]
	return [last, l, h]


static func _run(sp: Dictionary, s0: float, s1: float, g: Array, m0: bool, m1: bool) -> Dictionary:
	var l: float = g[1]
	var h: float = g[2]
	var w := minf(WIDTH, h - l)
	var c := clampf(float(sp.seam), l + w * 0.5, h - w * 0.5)
	var inner: Rect2 = sp.inner
	var a1 := inner.end.x if sp.along_x else inner.end.y
	s1 = minf(s1, a1)
	return {"s0": s0, "s1": s1, "c": c, "w": w, "m0": m0, "m1": m1}


# --- The block step ---------------------------------------------------------------------------

## After every lot of the block is down (any level): the band's ground, and on a FULL chunk the
## alley's furniture as deferred build steps.
static func block_step(ch: CityChunk, block: Dictionary) -> void:
	var sp := spec(ch.plan, ch.ix, ch.iz)
	if sp.is_empty():
		return
	var st := _state(ch)
	var ob := obstacles(sp, st.foot)
	var rs := runs(sp, ob[0])
	st.runs = rs
	var full := ch.level == CityChunk.Level.FULL and not ch.capturing
	var band: Rect2 = sp.band
	var along_x: bool = sp.along_x
	# The alley rects (inside the inner rect) and what is left of the band round them.
	var holes: Array[Rect2] = []
	holes.append_array(ob[1])
	for r: Dictionary in rs:
		holes.append(_run_rect(sp, r))
	var rest := LotFill._minus(band, holes, 0.0)
	var backs: Array = st.get("backs", [])
	if not full:
		# From afar the band is one concrete strip (the alley and its edges alike), and the
		# buildings' service yards behind it.
		for r: Dictionary in rs:
			_far_slab(ch, _run_rect(sp, r))
		for piece: Rect2 in rest:
			_far_slab(ch, piece)
		for b: Array in backs:
			_far_slab(ch, b[0])
		return
	for b: Array in backs:
		# Old concrete, or now and then asphalt, behind each building (a hash of the lot).
		st.ground.append(["pave", b[0], 1.0 if _h01([ch.plan.seed, int(b[1]), "alley_back"]) < 0.35 else 0.0])
	for r: Dictionary in rs:
		st.ground.append(["alley", sp, r])
		for end: int in [0, 1]:
			if r.m0 if end == 0 else r.m1:
				st.ground.append(["apron", sp, r, end])
	for piece: Rect2 in rest:
		if piece.size.x >= 0.3 and piece.size.y >= 0.3:
			st.ground.append(["pave", piece, 0.0])
	var jobs: Array[Callable] = []
	for i in rs.size():
		jobs.append(AlleyKit.dress.bind(ch, sp, rs[i], i))
	if not rs.is_empty():
		jobs.append(AlleyKit.poles.bind(ch, sp, rs))
		jobs.append(AlleyKit.wear.bind(ch, sp, rs))
	if OS.get_environment("ALLEY_TIME") == "1":
		var timed: Array[Callable] = []
		for j: Callable in jobs:
			timed.append(func() -> void:
				var t0 := Time.get_ticks_usec()
				j.call()
				print("ALLEY_JOB %.1f ms" % (float(Time.get_ticks_usec() - t0) / 1000.0)))
		jobs = timed
	YardFill._defer(ch, jobs)


## A run's rect in the inner block (along x: x0..x1, centre +- w/2 in z).
static func _run_rect(sp: Dictionary, r: Dictionary) -> Rect2:
	var s0: float = r.s0
	var s1: float = r.s1
	var c: float = r.c
	var w: float = r.w
	if sp.along_x:
		return Rect2(s0, c - w * 0.5, s1 - s0, w)
	return Rect2(c - w * 0.5, s0, w, s1 - s0)


static func _far_slab(ch: CityChunk, r: Rect2) -> void:
	if maxf(r.size.x, r.size.y) < 6.0 or minf(r.size.x, r.size.y) < 1.0:
		return
	var c := r.get_center()
	ch._add_slab(Vector3(c.x, CityChunk.SIDEWALK_TOP + LIFT - 0.02, c.y), Vector3(r.size.x, 0.04, r.size.y), FAR_COLOR, false, far_material(ch))


static func far_material(ch: CityChunk) -> Material:
	return PropFactory.road("concrete", 4.0, Color(0.74, 0.73, 0.71), hash([ch.plan.seed, "alley_far"]), 0.0, 0.6)


# --- The FULL chunk's meshes --------------------------------------------------------------------

## The upright mesh being written (AlleyKit through IndustrialKit's writers).
static func walls(ch: CityChunk) -> SurfaceTool:
	var st := _state(ch)
	if st.walls == null:
		var s := SurfaceTool.new()
		s.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.walls = s
	return st.walls


static var _ground_material: ShaderMaterial = null


static func ground_material() -> ShaderMaterial:
	if _ground_material != null:
		return _ground_material
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/alley_ground.gdshader")
	mat.set_shader_parameter("asphalt_tex", PropFactory.texture("asphalt", "Color"))
	mat.set_shader_parameter("concrete_tex", PropFactory.texture("concrete", "Color"))
	mat.set_shader_parameter("cracked_tex", PropFactory.texture("concrete_cracked", "Color"))
	_ground_material = mat
	return mat


## The chunk's alley ground (one mesh, no shadow) and upright props (one mesh, casting). In the
## finish, before the batches build.
static func commit(ch: CityChunk) -> void:
	if not ch.has_meta("alley"):
		return
	var st: Dictionary = ch.get_meta("alley")
	ch._batch.set_no_shadow("alley_pool")
	if not (st.ground as Array).is_empty():
		var g := SurfaceTool.new()
		g.begin(Mesh.PRIMITIVE_TRIANGLES)
		for piece: Array in st.ground:
			match str(piece[0]):
				"alley":
					_g_alley(g, ch, piece[1], piece[2])
				"apron":
					_g_apron(g, ch, piece[1], piece[2], int(piece[3]))
				"pave":
					_g_flat(g, ch, piece[1], G_PAVE, float(piece[2]))
		var mi := MeshInstance3D.new()
		mi.name = "AlleyGround"
		mi.mesh = g.commit()
		mi.material_override = ground_material()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ch.add_child(mi)
	if st.walls != null:
		var mi := MeshInstance3D.new()
		mi.name = "AlleyWalls"
		mi.mesh = (st.walls as SurfaceTool).commit()
		mi.material_override = IndustrialKit.walls_material()
		ch.add_child(mi)
	ch.set_meta("alley_runs", st.runs)
	ch.remove_meta("alley")


# --- The ground mesh --------------------------------------------------------------------------
# Vertex layout (the contract with shaders/alley_ground.gdshader):
#   COLOR.r  the kind (G_*), in 16ths      COLOR.g  a variant (paint: 0 white, 1 yellow)
#   COLOR.b  1 where the alley runs along z
#   UV       on the alley, apron and bump: (metres along the alley, metres across from its centre
#            line); elsewhere world (x, z)
#   UV2      (the alley's half width, a per-run seed)

## The across profile of an alley `hw` wide: the inverted crown, falling SAG to the centre line,
## and a shallow V-gutter ribbon down the middle.
static func surface(o: float, hw: float) -> float:
	var a := absf(o)
	return -SAG * clampf(1.0 - a / maxf(hw, 0.1), 0.0, 1.0) - 0.012 * clampf(1.0 - a / 0.45, 0.0, 1.0)


static func _col(kind: int, variant: float, along_z: bool) -> Color:
	return Color((float(kind) + 0.5) / 16.0, variant, 1.0 if along_z else 0.0, 1.0)


## A point of the run's frame: along `s`, across `o` off the centre line `c`, `y` over the relief.
static func _pt(ch: CityChunk, along_x: bool, s: float, c: float, o: float, y: float) -> Vector3:
	var x := s if along_x else c + o
	var z := c + o if along_x else s
	return Vector3(x, y + ch._gy(x, z), z)


## One triangle facing up (or `n` when given), winding fixed to face it (Godot: clockwise seen from
## the front).
static func _tri(g: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, col: Color, uv2: Vector2, want: Vector3 = Vector3.UP) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-12:
		return
	n = n.normalized()
	if n.dot(want) > 0.0:
		var t := b
		b = c
		c = t
		var tu := ub
		ub = uc
		uc = tu
	else:
		n = -n
	for k in 3:
		g.set_normal(n)
		g.set_color(col)
		g.set_uv([ua, ub, uc][k])
		g.set_uv2(uv2)
		g.add_vertex([a, b, c][k])


static func _quad(g: SurfaceTool, p: Array, uv: Array, col: Color, uv2: Vector2, want: Vector3 = Vector3.UP) -> void:
	_tri(g, p[0], p[1], p[2], uv[0], uv[1], uv[2], col, uv2, want)
	_tri(g, p[0], p[2], p[3], uv[0], uv[2], uv[3], col, uv2, want)


## The alley itself: the crowned slab with its gutter, a skirt down its sides, speed bumps, and the
## NO PARKING stencils by its mouths.
static func _g_alley(g: SurfaceTool, ch: CityChunk, sp: Dictionary, r: Dictionary) -> void:
	var along_x: bool = sp.along_x
	var s0: float = r.s0
	var s1: float = r.s1
	var c: float = r.c
	var hw: float = float(r.w) * 0.5
	var top := CityChunk.SIDEWALK_TOP + LIFT
	var seed01 := _h01([ch.plan.seed, sp.bx, sp.bz, "alley_run", int(s0)])
	var uv2 := Vector2(hw, seed01)
	var col := _col(G_ALLEY, 0.0, not along_x)
	var os := [-hw, -0.45, 0.0, 0.45, hw]
	var n := clampi(ceili((s1 - s0) / 3.0), 1, 80)
	for j in n:
		var sa := lerpf(s0, s1, float(j) / float(n))
		var sb := lerpf(s0, s1, float(j + 1) / float(n))
		for i in os.size() - 1:
			var oa: float = os[i]
			var ob: float = os[i + 1]
			_quad(g, [_pt(ch, along_x, sa, c, oa, top + surface(oa, hw)), _pt(ch, along_x, sb, c, oa, top + surface(oa, hw)),
				_pt(ch, along_x, sb, c, ob, top + surface(ob, hw)), _pt(ch, along_x, sa, c, ob, top + surface(ob, hw))],
				[Vector2(sa, oa), Vector2(sb, oa), Vector2(sb, ob), Vector2(sa, ob)], col, uv2)
		# The skirt down each side, under the neighbouring ground.
		for side: float in [-1.0, 1.0]:
			var o := hw * side
			var out := Vector3(0.0, 0.0, side) if along_x else Vector3(side, 0.0, 0.0)
			var pa := _pt(ch, along_x, sa, c, o, top)
			var pb := _pt(ch, along_x, sb, c, o, top)
			_quad(g, [pa, pb, pb - Vector3(0.0, 0.12, 0.0), pa - Vector3(0.0, 0.12, 0.0)],
				[Vector2(sa, o), Vector2(sb, o), Vector2(sb, o), Vector2(sa, o)], col, uv2, out)
	# Speed bumps: one every BUMP_EVERY metres or so, by hash.
	var length := s1 - s0
	var nb := floori(length / BUMP_EVERY)
	for k in nb:
		if _h01([ch.plan.seed, sp.bx, sp.bz, "alley_bump", int(s0), k]) < 0.35:
			continue
		var sb := s0 + (float(k) + 0.5) * length / float(nb)
		_g_bump(g, ch, along_x, sb, c, hw, top, uv2)
	# The stencils, 5 m in from each mouth the run reaches, reading to whoever drives in.
	var yellow := 1.0 if _h01([ch.plan.seed, sp.bx, sp.bz, "alley_paint"]) < 0.4 else 0.0
	if r.m0 and length > 14.0:
		_g_text(g, ch, along_x, s0 + 5.0, c, hw, 1.0, top, yellow)
	if r.m1 and length > 14.0:
		_g_text(g, ch, along_x, s1 - 5.0, c, hw, -1.0, top, yellow)


static func _g_bump(g: SurfaceTool, ch: CityChunk, along_x: bool, s: float, c: float, hw: float, top: float, uv2: Vector2) -> void:
	var col := _col(G_BUMP, 0.0, not along_x)
	var half := hw - 0.3
	var prof := [0.0, 0.045, 0.07, 0.045, 0.0]
	var os := [-half, -0.45, 0.0, 0.45, half]
	for j in prof.size() - 1:
		var sa := s - 0.45 + 0.225 * float(j)
		var sb := sa + 0.225
		for i in os.size() - 1:
			var oa: float = os[i]
			var ob: float = os[i + 1]
			_quad(g, [_pt(ch, along_x, sa, c, oa, top + surface(oa, hw) + float(prof[j]) + 0.002),
				_pt(ch, along_x, sb, c, oa, top + surface(oa, hw) + float(prof[j + 1]) + 0.002),
				_pt(ch, along_x, sb, c, ob, top + surface(ob, hw) + float(prof[j + 1]) + 0.002),
				_pt(ch, along_x, sa, c, ob, top + surface(ob, hw) + float(prof[j]) + 0.002)],
				[Vector2(sa - s, oa), Vector2(sb - s, oa), Vector2(sb - s, ob), Vector2(sa - s, ob)], col, uv2)
	# Its two ends, down to the slab.
	for side: float in [-1.0, 1.0]:
		var o := half * side
		var out := Vector3(0.0, 0.0, side) if along_x else Vector3(side, 0.0, 0.0)
		for j in prof.size() - 1:
			var sa := s - 0.45 + 0.225 * float(j)
			var sb := sa + 0.225
			var y0 := top + surface(o, hw)
			_quad(g, [_pt(ch, along_x, sa, c, o, y0 + float(prof[j]) + 0.002), _pt(ch, along_x, sb, c, o, y0 + float(prof[j + 1]) + 0.002),
				_pt(ch, along_x, sb, c, o, y0 - 0.01), _pt(ch, along_x, sa, c, o, y0 - 0.01)],
				[Vector2(sa - s, o), Vector2(sb - s, o), Vector2(sb - s, o), Vector2(sa - s, o)], col, uv2, out)


static var _text_cache: Dictionary = {}


static func text_geo(text: String, cap: float) -> Array:
	var key := "%s_%.2f" % [text, cap]
	if _text_cache.has(key):
		return _text_cache[key]
	var tm := TextMesh.new()
	tm.text = text
	tm.font_size = 48
	tm.pixel_size = cap / 34.0
	tm.depth = 0.0
	tm.curve_step = 2.5
	tm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var arr := tm.get_mesh_arrays()
	var geo := []
	if arr.size() > Mesh.ARRAY_INDEX and arr[Mesh.ARRAY_VERTEX] != null:
		geo = [arr[Mesh.ARRAY_VERTEX], arr[Mesh.ARRAY_INDEX]]
	_text_cache[key] = geo
	return geo


## "NO PARKING" laid on the alley at `s`, read by someone driving in the direction `dir` (+1 up s).
static func _g_text(g: SurfaceTool, ch: CityChunk, along_x: bool, s: float, c: float, hw: float, dir: float, top: float, yellow: float) -> void:
	var geo := text_geo("NO PARKING", 0.5)
	if geo.is_empty():
		return
	var verts: PackedVector3Array = geo[0]
	var idx = geo[1]
	if verts.is_empty():
		return
	var wide := 0.0
	for v in verts:
		wide = maxf(wide, absf(v.x))
	var fit := minf(1.0, (hw - 0.35) / maxf(wide, 0.01))
	# Facing +s, the driver's right is +across along x and -across along z (forward x, right +z;
	# forward z, right -x); facing -s, the other way.
	var right := dir * (1.0 if along_x else -1.0)
	var col := _col(G_PAINT, yellow, not along_x)
	var pts: Array[Vector3] = []
	var uvs: Array[Vector2] = []
	for v in verts:
		var o := right * v.x * fit
		var sv := s + dir * v.y * fit
		pts.append(_pt(ch, along_x, sv, c, o, top + surface(o, hw) + 0.006))
		uvs.append(Vector2(sv, o))
	var ids: PackedInt32Array = idx if idx != null else PackedInt32Array()
	if ids.is_empty():
		for k in verts.size():
			ids.append(k)
	for k in range(0, ids.size() - 2, 3):
		_tri(g, pts[ids[k]], pts[ids[k + 1]], pts[ids[k + 2]], uvs[ids[k]], uvs[ids[k + 1]], uvs[ids[k + 2]], col, Vector2(hw, 0.0))


## The driveway apron across the pavement at a mouth (`end` 0 the low end), falling to the kerb,
## and the wedge in the gutter that takes it down to the road.
static func _g_apron(g: SurfaceTool, ch: CityChunk, sp: Dictionary, r: Dictionary, end: int) -> void:
	var along_x: bool = sp.along_x
	var rect: Rect2 = sp.rect
	var inner: Rect2 = sp.inner
	var c: float = r.c
	var hw: float = float(r.w) * 0.5
	var kerb := (rect.position.x if along_x else rect.position.y) if end == 0 else (rect.end.x if along_x else rect.end.y)
	var edge := (inner.position.x if along_x else inner.position.y) if end == 0 else (inner.end.x if along_x else inner.end.y)
	var out := -1.0 if end == 0 else 1.0
	var col := _col(G_APRON, 0.0, not along_x)
	var uv2 := Vector2(hw, 0.0)
	var top := CityChunk.SIDEWALK_TOP
	var os := [-hw, -0.45, 0.0, 0.45, hw]
	var steps := 3
	for j in steps:
		var ta := float(j) / float(steps)
		var tb := float(j + 1) / float(steps)
		var sa := lerpf(edge, kerb, ta)
		var sb := lerpf(edge, kerb, tb)
		for i in os.size() - 1:
			var oa: float = os[i]
			var ob: float = os[i + 1]
			var ya := func(o: float, t: float) -> float:
				return top + lerpf(LIFT, 0.012, t) + surface(o, hw) * (1.0 - t)
			_quad(g, [_pt(ch, along_x, sa, c, oa, ya.call(oa, ta)), _pt(ch, along_x, sb, c, oa, ya.call(oa, tb)),
				_pt(ch, along_x, sb, c, ob, ya.call(ob, tb)), _pt(ch, along_x, sa, c, ob, ya.call(ob, ta))],
				[Vector2(sa, oa), Vector2(sb, oa), Vector2(sb, ob), Vector2(sa, ob)], col, uv2)
		for side: float in [-1.0, 1.0]:
			var o := hw * side
			var dir := Vector3(0.0, 0.0, side) if along_x else Vector3(side, 0.0, 0.0)
			var pa := _pt(ch, along_x, sa, c, o, top + lerpf(LIFT, 0.012, ta))
			var pb := _pt(ch, along_x, sb, c, o, top + lerpf(LIFT, 0.012, tb))
			_quad(g, [pa, pb, pb - Vector3(0.0, 0.08, 0.0), pa - Vector3(0.0, 0.08, 0.0)],
				[Vector2(sa, o), Vector2(sb, o), Vector2(sb, o), Vector2(sa, o)], col, uv2, dir)
	# The wedge: from the kerb's top down to the road over 0.6 m.
	var foot := kerb + out * 0.6
	var road := CityChunk.ROAD_TOP + 0.004
	for i in os.size() - 1:
		var oa: float = os[i]
		var ob: float = os[i + 1]
		_quad(g, [_pt(ch, along_x, kerb, c, oa, top + 0.012), _pt(ch, along_x, foot, c, oa, road),
			_pt(ch, along_x, foot, c, ob, road), _pt(ch, along_x, kerb, c, ob, top + 0.012)],
			[Vector2(kerb, oa), Vector2(foot, oa), Vector2(foot, ob), Vector2(kerb, ob)], col, uv2)
	for side: float in [-1.0, 1.0]:
		var o := hw * side
		var dir := Vector3(0.0, 0.0, side) if along_x else Vector3(side, 0.0, 0.0)
		var a := _pt(ch, along_x, kerb, c, o, top + 0.012)
		var b := _pt(ch, along_x, foot, c, o, road)
		var d := _pt(ch, along_x, kerb, c, o, road)
		_tri(g, a, b, d, Vector2(kerb, o), Vector2(foot, o), Vector2(kerb, o), col, uv2, dir)


## A flat piece of ground at the band's height (world UV).
static func _g_flat(g: SurfaceTool, ch: CityChunk, r: Rect2, kind: int, variant: float) -> void:
	var top := CityChunk.SIDEWALK_TOP + LIFT
	var col := _col(kind, variant, false)
	var nx := clampi(ceili(r.size.x / 4.0), 1, 40)
	var nz := clampi(ceili(r.size.y / 4.0), 1, 40)
	for j in nz:
		for i in nx:
			var x0 := r.position.x + r.size.x * float(i) / float(nx)
			var x1 := r.position.x + r.size.x * float(i + 1) / float(nx)
			var z0 := r.position.y + r.size.y * float(j) / float(nz)
			var z1 := r.position.y + r.size.y * float(j + 1) / float(nz)
			_quad(g, [Vector3(x0, top + ch._gy(x0, z0), z0), Vector3(x1, top + ch._gy(x1, z0), z0), Vector3(x1, top + ch._gy(x1, z1), z1), Vector3(x0, top + ch._gy(x0, z1), z1)],
				[Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)], col, Vector2.ZERO)
