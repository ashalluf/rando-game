class_name MidCity
## The mid distance (owner's bar "make it look like GTA 6"; docs/HANDOFF.md "The mid distance"):
## what the LOD chunks and the far city (Skyline) draw from 400 m to 3 km. From the hills the
## suburbs read as scattered white boxes on pale lawn between black streets: the far tiers planted
## only the kerb rows and the parks, a house's flat roof wore a tower's bright membrane, every clay
## roof was one orange, the far streets were drawn black and empty. Real Los Angeles from Griffith
## Park is a grain of varied roofs under dark street and yard trees, palms, pools and car-lined
## streets in the haze.
##
## What this adds, every bit of it from hashes of the seed and the place (no chunk, block or
## Building rng is touched, so nothing a seed builds moves):
## - Yard trees (`yard_trees()`): Skyline plants the ground a block leaves green - the suburbs'
##   lawns, the yards' lawn pieces, a court's garden - on a jittered grid at the district's canopy
##   share, never on a building, a car park or a plaza (an occupancy raster of the captured
##   block). They stand under a LOD chunk on the real ground (Skyline's street trees' rule) and go
##   under a FULL one, which plants its own.
## - House roofs: the far roof colour is the house's own clay tint or shingle (`roof_far()`), the
##   pitched slabs are flagged (`ROOF_FLAG`, building_lod.gdshader draws tile or shingle courses)
##   and so is a house wing's box (`HOUSE_FLAG`: its flat roof wears a house's coverings).
## - Pools (`pool()`): YardFill's pools, which the LOD tiers left out, as a flat box (`POOL_FLAG`).
## - The far streets (far_cars.gdshaderinc): a weathered grey, parked cars along the kerbs and the
##   far traffic's own cars by day; the canopy shader's crowns dappled (far_canopy.gdshader).
##
## MID_CITY=0 in the environment is the A/B: none of it (the shaders' `mid_city` false).

static var enabled: bool = OS.get_environment("MID_CITY") != "0"

## INSTANCE_CUSTOM.a flags building_lod.gdshader reads. A house wing's box (0.25 behaves as the
## old path's 0 everywhere else), its pitched roof slabs (1.25 behaves as plain 1), a pool.
const HOUSE_FLAG := 0.25
const ROOF_FLAG := 1.25
const POOL_FLAG := 5.0
## A pool's water from up there (sRGB, the palette numbers building_lod decodes).
const POOL_FAR := Color(0.22, 0.66, 0.74)

## The occupancy raster's cell, the yard trees' grid step and how far a tree stands off a wall.
const CELL := 3.0
const STEP := 7.5
const WALL_CLEAR := 0.6
## How much of the green ground a district shades with yard trees (the grid's odds). LA's suburbs
## and older beach towns are under a canopy; downtown and industry have next to none.
const ODDS := {
	CityPlan.District.SUBURBS: 0.7,
	CityPlan.District.BEACHTOWN: 0.38,
	CityPlan.District.MIDTOWN: 0.45,
	CityPlan.District.CAMPUS: 0.4,
	CityPlan.District.DOWNTOWN: 0.15,
	CityPlan.District.INDUSTRIAL: 0.12,
}
## At most this many yard trees a block.
const MAX_PER_BLOCK := 70
## Canopy colours (LINEAR, far_canopy multiplies its shade by them): dark live oak and ficus,
## olive and eucalyptus grey-green, a fresher sycamore green, the odd jacaranda.
const GREENS := [
	[Color(0.030, 0.048, 0.020), 0.32],
	[Color(0.048, 0.070, 0.030), 0.58],
	[Color(0.066, 0.076, 0.048), 0.74],
	[Color(0.080, 0.105, 0.040), 0.88],
	[Color(0.060, 0.068, 0.058), 0.97],
	[Color(0.20, 0.16, 0.32), 1.0],
]
## The kerb rows' crowns are darker too (Skyline's own colours times this), and a share of the
## kerb slots the district's roll left empty get a tree (`KERB_FILL`): LA's residential streets
## are lined almost unbroken.
const KERB_DARKEN := 0.7
const KERB_FILL := {
	CityPlan.District.SUBURBS: 0.65,
	CityPlan.District.BEACHTOWN: 0.4,
	CityPlan.District.MIDTOWN: 0.55,
	CityPlan.District.CAMPUS: 0.5,
}
## Of the paved ground a block leaves (forecourts, a court's paving), the share of the district's
## odds that still gets a tree (a planter, a tree well).
const PAVED_SHARE := 0.3


static func h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100000) / 100000.0


## The colour a house's roof is drawn in from the LOD tiers (sRGB, building_lod's palette): clay is
## the near roof's own tile under its own tint (HouseKit.CLAY, the same multiplier the near
## material carries), shingle its own colour. Off: the old single clay and the lightened shingle.
static func roof_far(clay: bool, colors: Dictionary) -> Color:
	if not enabled:
		return HouseKit.CLAY_FAR if clay else (colors.shingle as Color).lightened(0.12)
	if clay:
		var t: Color = colors.clay
		var c := Color(HouseKit.CLAY_FAR.r * t.r, HouseKit.CLAY_FAR.g * t.g, HouseKit.CLAY_FAR.b * t.b)
		# Weathered clay from up there is a muted terracotta, never the fresh orange.
		return c.lerp(Color(0.52, 0.42, 0.36), 0.18)
	return (colors.shingle as Color).lightened(0.05)


## The INSTANCE_CUSTOM a house wing's LOD box carries (HouseBuild.lod()).
static func house_custom(seed_v: int) -> Color:
	return Color(0.25, 0.32, float(absi(seed_v) % 997) / 997.0, HOUSE_FLAG if enabled else 0.0)


## A pitched roof slab's (HouseBuild._lod_roof()).
static func roof_custom(plain: Color) -> Color:
	return Color(plain.r, plain.g, plain.b, ROOF_FLAG if enabled else plain.a)


## A yard's pool in a LOD chunk or the far city's capture: a flat box in the lod_box batch, its
## top a little over the yard. `r` is the pool in chunk space.
static func pool(ch: CityChunk, r: Rect2) -> void:
	if not enabled or r.size.x < 1.5 or r.size.y < 1.5:
		return
	var c := r.get_center()
	var xf := Transform3D(Basis().scaled(Vector3(r.size.x, 0.12, r.size.y)), Vector3(c.x, CityChunk.SIDEWALK_TOP + 0.04, c.y))
	ch._batch.add("lod_box", PropFactory.unit_box(), xf, POOL_FAR,
		Color(0.0, 0.0, float(absi(hash([c.x, c.y])) % 997) / 997.0, POOL_FLAG))


## The yard trees of a captured city block, appended to Skyline's planting arrays. `cap` is the
## block's capture (CityChunk.captured), `gy` the chunk's ground height (a Callable(x, z)), `under`
## its freeway test (a Callable(Vector2) -> bool). Returns how many it planted.
static func yard_trees(plan: CityPlan, k: Vector2i, b: Dictionary, cap: Dictionary, gy: Callable, under: Callable,
		veg: Array, colors: Array, customs: Array) -> int:
	if not enabled:
		return 0
	var odds: float = ODDS.get(b.district, 0.0)
	if odds <= 0.0 or b.kind == CityPlan.BlockKind.PARK and not b.has("grounds"):
		return 0
	var rect: Rect2 = (b.rect as Rect2).grow(-plan.sidewalk_width - 0.5)
	if rect.size.x < STEP or rect.size.y < STEP:
		return 0
	var nx := int(ceil(rect.size.x / CELL))
	var nz := int(ceil(rect.size.y / CELL))
	# 0 unknown (the block's own ground), 1 green, 2 blocked (standing), 3 paved.
	var occ := PackedByteArray()
	occ.resize(nx * nz)
	# The block's ground, bottom up (the build lays it in that order): the top slab decides.
	for g: Array in cap.get("ground", []):
		var gr: Rect2 = (g[0] as Rect2).intersection(rect)
		if gr.size.x <= 0.0 or gr.size.y <= 0.0:
			continue
		var fc: Color = g[3]
		var v: int = 1 if fc.g > fc.r * 1.08 and fc.g > fc.b * 1.15 else 3
		_fill(occ, nx, nz, rect, gr, v)
	# Whatever stands: the buildings and boxes, grown by the clearance.
	var batch: Dictionary = cap.get("batch", {})
	if batch.has("lod_box"):
		var lb: Dictionary = batch["lod_box"]
		for i in (lb.xforms as Array).size():
			_fill(occ, nx, nz, rect, _footprint(lb.xforms[i]).grow(WALL_CLEAR), 2)
	for box: Array in cap.get("boxes", []):
		_fill(occ, nx, nz, rect, _footprint(box[0]).grow(WALL_CLEAR), 2)
	# The suburbs' block is its lawn (YardFill lays only the yards' other pieces there).
	# The suburbs' block is its lawn (YardFill lays only the yards' other pieces there), and a beach
	# town's yards under 6 m are not laid at all from out here: both count as green.
	var lawn_block: bool = b.district == CityPlan.District.SUBURBS or b.district == CityPlan.District.BEACHTOWN \
		or b.has("grounds") and String(b.grounds) == "cemetery"
	var gx := int(rect.size.x / STEP)
	var gz := int(rect.size.y / STEP)
	var placed := 0
	for i in gx:
		for j in gz:
			if placed >= MAX_PER_BLOCK:
				return placed
			var key := [plan.seed, "yard_tree", k, i, j]
			var roll := h01(key)
			if roll >= odds:
				continue
			var p := rect.position + Vector2((float(i) + 0.15 + 0.7 * h01(key + ["x"])) * STEP,
				(float(j) + 0.15 + 0.7 * h01(key + ["z"])) * STEP)
			var ci := clampi(int((p.x - rect.position.x) / CELL), 0, nx - 1)
			var cj := clampi(int((p.y - rect.position.y) / CELL), 0, nz - 1)
			var o := occ[cj * nx + ci]
			if o == 2 or (o == 0 and not lawn_block) or (o == 3 and roll >= odds * PAVED_SHARE):
				continue
			if under.call(p):
				continue
			var v := h01(key + ["v"])
			var r := 3.4 + 3.2 * v
			var th := 4.2 + 3.6 * h01(key + ["t"])
			var lift := 1.8 + 1.4 * v
			var pick := h01(key + ["c"])
			var col: Color = GREENS[0][0]
			for gc: Array in GREENS:
				if pick <= float(gc[1]):
					col = gc[0]
					break
			# A tall fan palm now and then in the beach town and the suburbs: a small crown high up.
			if b.district != CityPlan.District.MIDTOWN and h01(key + ["palm"]) < 0.09:
				r = 2.2 + 0.8 * v
				th = 1.8
				lift = 12.0 + 8.0 * v
				col = Color(0.11, 0.14, 0.06)
			var y: float = float(gy.call(p.x, p.y)) + CityChunk.SIDEWALK_TOP
			veg.append(Transform3D(Basis(Vector3.UP, h01(key + ["yaw"]) * TAU).scaled(Vector3(r, th, r * (0.85 + 0.25 * h01(key + ["e"])))),
				Vector3(p.x, y + lift + th * 0.5, p.y)))
			colors.append(col)
			customs.append(Color(1.0, 0.0, 0.0, 0.0))
			placed += 1
	return placed


## The XZ bounds of a scaled, maybe turned, unit box.
static func _footprint(xf: Transform3D) -> Rect2:
	var b := xf.basis
	var hx := (absf(b.x.x) + absf(b.y.x) + absf(b.z.x)) * 0.5
	var hz := (absf(b.x.z) + absf(b.y.z) + absf(b.z.z)) * 0.5
	return Rect2(xf.origin.x - hx, xf.origin.z - hz, hx * 2.0, hz * 2.0)


static func _fill(occ: PackedByteArray, nx: int, nz: int, rect: Rect2, r: Rect2, v: int) -> void:
	var i0 := maxi(int(floor((r.position.x - rect.position.x) / CELL)), 0)
	var i1 := mini(int(ceil((r.end.x - rect.position.x) / CELL)), nx)
	var j0 := maxi(int(floor((r.position.y - rect.position.y) / CELL)), 0)
	var j1 := mini(int(ceil((r.end.y - rect.position.y) / CELL)), nz)
	for j in range(j0, j1):
		var row := j * nx
		for i in range(i0, i1):
			occ[row + i] = v


## The kerb slots Skyline's own roll left empty that get a tree anyway (KERB_FILL), as positions
## for Skyline to plant with its own kerb-row look. `ring` and the slot count are Skyline's.
static func kerb_fill(plan: CityPlan, k: Vector2i, district: int, _odds: float, e: int, i: int) -> bool:
	if not enabled:
		return false
	var fill: float = KERB_FILL.get(district, 0.0)
	return fill > 0.0 and h01([plan.seed, "kerb_fill", k, e, i]) < fill
