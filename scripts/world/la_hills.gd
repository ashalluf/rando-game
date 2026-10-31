class_name LaHills
extends RefCounted
## Los Angeles' named hills (owner, 2026-10-31: "not every street in Los Angeles is flat ... make
## the geography as realistic as possible"). The basin stays the flat plain it really is; these
## are the places it breaks: Bunker Hill under downtown's west side, the steep knolls of Echo Park,
## Elysian Heights and the Elysian slopes north-west and north of downtown, the bluff east of the
## river (Boyle Heights), the bluffs over the port (San Pedro), and a skirt that lets the oil
## field's hill (Baldwin Hills, OilField) come down into rolling streets instead of a mesa.
##
## A DATA TABLE, like the replica areas: each hill is a convex outline in world XZ, a height, a
## crest tilt and per-edge FACE widths (the face is where it drops: `w` is a list of [share,
## width] pairs, so an edge can be a short steep scarp on a long gentle slope). The lift at a point
## is height x the product of every edge's face profile, so a hill is a terrace with mitred,
## rounded corners; hills combine by max(), so knolls that touch read as one ridge. The outline is
## wobbled by a seeded noise (never a roll on any rng) so contours do not run ruler-straight.
##
## MacroMap._relief_natural() adds lift() to its BASE (like the replica's terrace), after the
## plateau and before the seeded rolling noise, so: downtown's flatness (which only fades the
## noise) keeps the 1:1 grid on Bunker Hill's terrace; every landmark still holds itself level
## (lift() holds the hill's own lift at the landmark's anchor over the same disc the noise is
## flattened on); and where a range rises under a hill the hill hands over to it (the replica's
## rule), so the two make one slope instead of stacking.
##
## Streets: a street's grade is the relief along it. A street stretch (one block between two
## crossings) steeper than STAIR_GRADE becomes a public stairway, closed to cars through
## CityPlan.road_open() (road_closed() here), built by LaHillsBuild. `LA_HILLS=0` in the
## environment is the A/B: the city exactly as before.

static var enabled: bool = OS.get_environment("LA_HILLS") != "0"

## A street stretch steeper than this (rise over run, its steepest 12 m) is a stairway.
const STAIR_GRADE := 0.30
## How the grade is measured: samples every SAMPLE_STEP m, the steepest SAMPLE_SPAN m window.
const SAMPLE_STEP := 4.0
const SAMPLE_SPAN := 12.0
## How far the outline wobbles (m) and how big the wobble is.
const WOBBLE := 14.0
const WOBBLE_FREQ := 0.006
## Surface undulation on top of a hill (m), so a crest is not a table.
const TOP_ROLL := 3.0

## Downtown's grid in world XZ (DowntownReal: x = 2800 + u, z = 102.7 + v).
const _DX := 2800.0
const _DZ := 102.7

## The table. `poly`: convex outline, any winding; `h`: crest height (m over the plain); `tilt`:
## m per m across the crest from its centroid; `w`: per edge (in poly order, edge i from point i
## to i + 1) a list of [share, face width]; `stairs`: whether its streets may turn to stairs.
const HILLS := [
	# Bunker Hill: the crest along Grand / Hope, 2nd to 4th; the steep east face down the Olive -
	# Hill block to Hill St (the incline and the stairs stand there), the long fall south to 5th St
	# past the towers' plazas, the north face down to Temple, the west side easing to Figueroa and
	# the 110 in its trench.
	{"id": "bunker_hill", "name": "Bunker Hill", "h": 25.0, "tilt": Vector2(0.006, 0.0), "stairs": true,
		"poly": [Vector2(_DX - 700.0, _DZ - 1200.0), Vector2(_DX + 55.0, _DZ - 1200.0),
			Vector2(_DX + 55.0, _DZ - 112.0), Vector2(_DX - 700.0, _DZ - 112.0)],
		# north (Temple), east (Hill St), south (5th St), west (the 110)
		"w": [[[1.0, 280.0]], [[0.55, 120.0], [0.45, 330.0]], [[1.0, 300.0]], [[1.0, 170.0]]]},
	# Echo Park: a steep knoll in the wedge between the front range's foot and downtown.
	{"id": "echo_park", "name": "Echo Park", "h": 36.0, "tilt": Vector2(-0.02, -0.01), "stairs": true,
		"poly": [Vector2(1250.0, -1930.0), Vector2(1520.0, -1960.0), Vector2(1640.0, -1760.0),
			Vector2(1590.0, -1500.0), Vector2(1340.0, -1450.0), Vector2(1220.0, -1650.0)],
		"w": [[[1.0, 190.0]], [[1.0, 170.0]], [[1.0, 190.0]], [[1.0, 200.0]], [[1.0, 170.0]], [[1.0, 190.0]]]},
	# Elysian Heights: knolls against the range's foot north of Echo Park, rising into it.
	{"id": "elysian_heights", "name": "Elysian Heights", "h": 38.0, "tilt": Vector2(0.0, -0.03), "stairs": true,
		"poly": [Vector2(1480.0, -2260.0), Vector2(1980.0, -2260.0), Vector2(1960.0, -1980.0),
			Vector2(1700.0, -1880.0), Vector2(1500.0, -1990.0)],
		"w": [[[1.0, 120.0]], [[1.0, 190.0]], [[1.0, 190.0]], [[1.0, 180.0]], [[1.0, 180.0]]]},
	# The Elysian slopes north of Chinatown, between the 110's stub and Chinatown.
	{"id": "elysian_slopes", "name": "Solano Canyon", "h": 32.0, "tilt": Vector2(0.0, -0.025), "stairs": true,
		"poly": [Vector2(2240.0, -2280.0), Vector2(2640.0, -2280.0), Vector2(2640.0, -1880.0),
			Vector2(2260.0, -1880.0)],
		"w": [[[1.0, 120.0]], [[1.0, 200.0]], [[1.0, 200.0]], [[1.0, 190.0]]]},
	# Boyle Heights: the bluff east of the river, its scarp facing the river flats, running back
	# to the east range's foot.
	{"id": "boyle_heights", "name": "Boyle Heights", "h": 24.0, "tilt": Vector2(0.004, 0.0), "stairs": true,
		"poly": [Vector2(4470.0, -700.0), Vector2(5200.0, -700.0), Vector2(5200.0, 1350.0),
			Vector2(4590.0, 1350.0)],
		"w": [[[1.0, 220.0]], [[1.0, 60.0]], [[1.0, 260.0]], [[0.7, 70.0], [0.3, 240.0]]]},
	# San Pedro: the headland's foot east of the peninsula, its bluff facing the port and the 110.
	{"id": "san_pedro", "name": "San Pedro", "h": 30.0, "tilt": Vector2(-0.01, 0.0), "stairs": true,
		"poly": [Vector2(1700.0, 5150.0), Vector2(2390.0, 5150.0), Vector2(2390.0, 5950.0),
			Vector2(1700.0, 5950.0)],
		"w": [[[1.0, 200.0]], [[0.65, 60.0], [0.35, 210.0]], [[1.0, 120.0]], [[1.0, 80.0]]]},
	# Baldwin Hills: a skirt round the oil field (OilField) so its hill comes down into rolling
	# streets; OilField's own hill takes over inside its kerb.
	{"id": "baldwin_hills", "name": "Baldwin Hills", "h": 14.0, "tilt": Vector2.ZERO, "stairs": false,
		"poly": [Vector2(40.0, 1000.0), Vector2(1440.0, 1000.0), Vector2(1440.0, 2280.0),
			Vector2(40.0, 2280.0)],
		"w": [[[1.0, 420.0]], [[1.0, 420.0]], [[1.0, 420.0]], [[1.0, 420.0]]]},
]

var macro: MacroMap
var _noise: FastNoiseLite
## Per hill: {poly, normals (inward), offsets, faces, h, tilt, c, box}.
var _hills: Array = []
## The union of every hill's box, for the cheap reject.
var _box := Rect2()


static func make(m: MacroMap) -> LaHills:
	if not enabled:
		return null
	var lh := LaHills.new()
	lh.macro = m
	lh._setup(m.seed)
	return lh


func _setup(sd: int) -> void:
	_noise = FastNoiseLite.new()
	_noise.seed = hash([sd, "la_hills"]) & 0x7fffffff
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = WOBBLE_FREQ
	_noise.fractal_octaves = 2
	var first := true
	for row: Dictionary in HILLS:
		var pts := PackedVector2Array(row.poly)
		var c := Vector2.ZERO
		for p in pts:
			c += p
		c /= float(pts.size())
		var normals := PackedVector2Array()
		var offs := PackedFloat32Array()
		for i in pts.size():
			var a := pts[i]
			var b := pts[(i + 1) % pts.size()]
			var n := Vector2(-(b - a).y, (b - a).x).normalized()
			if n.dot(c - a) < 0.0:
				n = -n
			normals.append(n)
			offs.append(n.dot(a))
		var box := Rect2(pts[0], Vector2.ZERO)
		for p in pts:
			box = box.expand(p)
		box = box.grow(WOBBLE + 2.0)
		_hills.append({"id": row.id, "name": row.name, "poly": pts, "n": normals, "o": offs,
			"w": row.w, "h": float(row.h), "tilt": row.tilt, "c": c, "box": box, "stairs": row.stairs})
		_box = box if first else _box.merge(box)
		first = false


## Every hill's record (tests, the probe).
func hills() -> Array:
	return _hills


## The hill whose box holds `pos`, or {}.
func hill_at(pos: Vector2) -> Dictionary:
	var best := {}
	var top := 0.0
	for hl: Dictionary in _hills:
		if (hl.box as Rect2).has_point(pos):
			var v := _one(hl, pos)
			if v > top:
				top = v
				best = hl
	return best


## The hills' lift at `pos` before landmarks hold it level or a range takes over (m).
func lift_raw(pos: Vector2) -> float:
	if not _box.has_point(pos):
		return 0.0
	var top := 0.0
	for hl: Dictionary in _hills:
		if (hl.box as Rect2).has_point(pos):
			top = maxf(top, _one(hl, pos))
	return top


func _one(hl: Dictionary, pos: Vector2) -> float:
	var wob := _noise.get_noise_2dv(pos) * WOBBLE
	var normals: PackedVector2Array = hl.n
	var offs: PackedFloat32Array = hl.o
	var faces: Array = hl.w
	var f := 1.0
	for i in normals.size():
		var d := normals[i].dot(pos) - offs[i] + wob
		if d <= 0.0:
			return 0.0
		var fe := 0.0
		for part: Array in faces[i]:
			fe += float(part[0]) * smoothstep(0.0, float(part[1]), d)
		f *= fe
		if f <= 0.0:
			return 0.0
	var top: float = hl.h + (hl.tilt as Vector2).dot(pos - (hl.c as Vector2))
	top += _noise.get_noise_2d(pos.x * 0.35 + 913.0, pos.y * 0.35 - 211.0) * TOP_ROLL
	return maxf(top, 0.0) * f


## The lift MacroMap folds into its base at `pos`, over mountains of height `raw`: held level over
## every landmark's flattened disc (the same disc and fade the rolling noise is flattened on), and
## handed over to a range that rises under it.
func lift(pos: Vector2, raw: float) -> float:
	if not _box.has_point(pos):
		return 0.0
	var v := lift_raw(pos)
	var grid: Dictionary = macro._lm_grid
	for lm: Dictionary in grid.get(Vector2i(floori(pos.x / MacroMap.LM_CELL), floori(pos.y / MacroMap.LM_CELL)), []):
		if lm.has("flat_rect"):
			var fr: Rect2 = lm.flat_rect
			var f := MacroMap._rect_fade(pos, fr, float(lm.flat_margin))
			if f < 1.0:
				v = lerpf(lift_raw(fr.get_center()), v, f)
			continue
		var radius: float = lm.radius
		var a: Vector2 = lm.anchor
		if absf(pos.x - a.x) > radius + 150.0 or absf(pos.y - a.y) > radius + 150.0:
			continue
		var f := smoothstep(radius + 30.0, radius + 150.0, pos.distance_to(a))
		if f < 1.0:
			v = lerpf(lift_raw(a), v, f)
	if v <= 0.0:
		return 0.0
	return v * (1.0 - smoothstep(0.0, maxf(v, 1.0), raw))


## The ground a landmark at `anchor` stands on from the hills (LandmarkDowntown lifts its towers
## by it): 0 with the hills off, so the city is exactly as before.
static func landmark_lift(plan: CityPlan, anchor: Vector2) -> float:
	if not enabled or plan == null or plan.macro == null or plan.macro.la_hills == null:
		return 0.0
	return plan.macro.la_hills.lift(anchor, plan.macro.raw_height_at(anchor))


# --- Streets --------------------------------------------------------------------------------------

## The stretch of road (axis, index) between crossings k and k + 1 of the other axis: the steepest
## grade along its centre line (rise over run over SAMPLE_SPAN m) and its ends' heights.
## Cached per plan.
static func stretch(plan: CityPlan, axis: int, index: int, k: int) -> Dictionary:
	var cache: Dictionary
	if plan.has_meta("la_hills_stretch"):
		cache = plan.get_meta("la_hills_stretch")
	else:
		cache = {}
		plan.set_meta("la_hills_stretch", cache)
	var key := Vector3i(axis, index, k)
	if cache.has(key):
		return cache[key]
	var other := CityPlan.AXIS_Z if axis == CityPlan.AXIS_X else CityPlan.AXIS_X
	var at := plan.road_pos(axis, index)
	var s0 := plan.road_pos(other, k)
	var s1 := plan.road_pos(other, k + 1)
	var res := {"grade": 0.0, "h0": 0.0, "h1": 0.0, "s0": s0, "s1": s1, "steep_at": s0}
	var lh: LaHills = plan.macro.la_hills if plan.macro else null
	if lh == null:
		cache[key] = res
		return res
	var a := Vector2(at, s0) if axis == CityPlan.AXIS_X else Vector2(s0, at)
	var b := Vector2(at, s1) if axis == CityPlan.AXIS_X else Vector2(s1, at)
	var bb := Rect2(a, Vector2.ZERO).expand(b)
	var near := false
	for hl: Dictionary in lh._hills:
		if (hl.box as Rect2).intersects(bb):
			near = true
	if not near:
		cache[key] = res
		return res
	var n := maxi(int(ceil((s1 - s0) / SAMPLE_STEP)), 1)
	var hs := PackedFloat32Array()
	for i in n + 1:
		# The ground itself (mountains and relief): where a hill meets a range's foot the relief
		# hands over to the mountain, and the two together are the slope.
		var q := a.lerp(b, float(i) / n)
		var raw := plan.macro.raw_height_at(q)
		hs.append(raw + plan.macro._relief_at(q, raw))
	var step := (s1 - s0) / n
	var span := maxi(int(round(SAMPLE_SPAN / step)), 1)
	var g := 0.0
	var at_s := s0
	for i in range(0, n + 1 - span):
		var gi := absf(hs[i + span] - hs[i]) / (step * span)
		if gi > g:
			g = gi
			at_s = s0 + (i + span * 0.5) * step
	# Only a city street is a street: past a range's foot the stretch is the hills' ground.
	var sp := Vector2(at, at_s) if axis == CityPlan.AXIS_X else Vector2(at_s, at)
	if plan.macro.zone_at(sp) != MacroMap.Zone.CITY or plan.macro.zone_at(a.lerp(b, 0.5)) != MacroMap.Zone.CITY:
		cache[key] = res
		return res
	res.grade = g
	res.h0 = hs[0]
	res.h1 = hs[n]
	res.steep_at = at_s
	res.near = true
	cache[key] = res
	return res


## True where a street is a stairway, not a carriageway (CityPlan.road_open()).
static func road_closed(plan: CityPlan, axis: int, index: int, along: float) -> bool:
	if not enabled or plan.macro == null or plan.macro.la_hills == null:
		return false
	# Most roads are nowhere near a hill: one compare, no cache.
	var box: Rect2 = plan.macro.la_hills._box
	var at := plan.road_pos(axis, index)
	if axis == CityPlan.AXIS_X:
		if at < box.position.x or at > box.end.x or along < box.position.y - 400.0 or along > box.end.y + 400.0:
			return false
	elif at < box.position.y or at > box.end.y or along < box.position.x - 400.0 or along > box.end.x + 400.0:
		return false
	var other := CityPlan.AXIS_Z if axis == CityPlan.AXIS_X else CityPlan.AXIS_X
	var k := plan._index_at(other, along)
	return is_stairs(plan, axis, index, k)


## Whether the stretch of road (axis, index) between crossings k and k + 1 is a stairway.
static func is_stairs(plan: CityPlan, axis: int, index: int, k: int) -> bool:
	if not enabled or plan.macro == null or plan.macro.la_hills == null:
		return false
	var st := stretch(plan, axis, index, k)
	if not st.has("near"):
		return false
	# Only a hill whose streets may turn to stairs (the oil field's skirt never does).
	var lh: LaHills = plan.macro.la_hills
	var mid := plan.road_pos(axis, index)
	var at: float = st.steep_at
	var p := Vector2(mid, at) if axis == CityPlan.AXIS_X else Vector2(at, mid)
	var hl := lh.hill_at(p)
	if hl.is_empty() or not hl.stairs:
		return false
	return float(st.grade) > STAIR_GRADE
