class_name RcRefineryRoad
extends RefCounted
## The refinery's road at night (rc4-refinery-road, fleet wave 7; refcam `refinery_night` in
## tools/refcams/cameras_w6.json; docs/HANDOFF.md "The refinery's road at night"). From the street
## outside the fence the foreground road read as a flat pale-grey sheet against the dark plant:
##   - it was lit by its street lamps' additive pools (a mast-arm LED's pool, laid as an unshaded
##     quad, adds the same amount to tarmac and paint alike: no texture, no contrast) overlapping
##     down the kerb, and by nothing the plant throws - the 90 m flares and the high masts are not
##     renderer lights;
##   - so on the plant's perimeter streets the asphalt and the pavement ring take the flares' and
##     masts' light in road.gdshader (refinery_road.gdshaderinc: light x the surface's albedo, the
##     damp of a harbour night, the flames standing in the tarmac as glints), and the street lamps
##     along those streets are old and patchy: a share are out (no pool, no light, dark head), the
##     rest throw a tight dim pool.
## RC4_REFINERY_ROAD=0 is the A/B: no material is dressed and every lamp is as it was.

static var enabled: bool = OS.get_environment("RC4_REFINERY_ROAD") != "0"

## How far past the plant's kerbs a street lamp counts as the plant's perimeter street's (metres:
## the far kerb of the widest perimeter road plus its pavement).
const LAMP_REACH := 32.0
## The share of those lamps that are out, and the rest's pool and light gains.
const LAMP_OUT := 0.45
const LAMP_POOL := 0.28
const LAMP_LIGHT := 0.4
## Past how far from the plant's centre the road shader works nothing out (metres).
const REACH := 900.0
## How far past the plant's kerbs the roads and pavements take its light (metres).
const NEAR := 420.0
## The flares' and masts' light on the road (refinery_road.gdshaderinc's uniforms).
const FLARE_GAIN := 1.4
const FLARE_HALF := 40.0
const FLARE_REACH := 480.0
const MAST_GAIN := 1.4
const MAST_HALF := 12.0
const MAST_REACH := 70.0
## The share of a perimeter mast's floods that spills out over the fence onto the street.
const MAST_SPILL := 0.35
const DAMP := 0.5
const GLINT := 1.0
const MAX_MASTS := 32
## How far inside the fence a mast stands to count as the fence line's (its floods spill over it).
const MAST_FENCE := 8.0

static var _road_mats: Dictionary = {}


static func h01(parts: Array) -> float:
	return float(hash(parts) & 0x7fffffff) / float(0x7fffffff)


## The flame bodies (TRUE world, w a phase) the road takes its light from.
static func flares(lay: Dictionary, plan: CityPlan) -> Array[Vector4]:
	return RefineryNight.flare_tips(lay, plan)


## The masts' flood heads (TRUE world, w the spill share).
static func masts(lay: Dictionary, plan: CityPlan) -> Array[Vector4]:
	var out: Array[Vector4] = []
	if lay.is_empty():
		return out
	var inner: Rect2 = lay.inner
	for it: Dictionary in lay.items:
		if String(it.type) != "mast" or out.size() >= MAX_MASTS:
			continue
		var at: Vector2 = it.at
		# Only the masts along the fence throw any light over it (the process units' are deep inside).
		var edge := minf(minf(at.x - inner.position.x, inner.end.x - at.x), minf(at.y - inner.position.y, inner.end.y - at.y))
		if edge > MAST_FENCE:
			continue
		var rel := plan.macro.relief_at(at) if plan != null and plan.macro != null else 0.0
		out.append(Vector4(at.x, Refinery.BASE_Y + rel + float(it.h) - 1.0, at.y, MAST_SPILL))
	return out


## True when the road (axis, index) runs along one of the plant's four sides.
static func perimeter_road(plan: CityPlan, axis: int, index: int) -> bool:
	var lay := Refinery.layout(plan)
	if lay.is_empty():
		return false
	var rect: Rect2 = lay.rect
	var pos := plan.road_pos(axis, index)
	var half := plan.road_width(axis, index) * 0.5 + 2.0
	if axis == CityPlan.AXIS_X:
		return absf(pos - rect.position.x) < half or absf(pos - rect.end.x) < half
	return absf(pos - rect.position.y) < half or absf(pos - rect.end.y) < half


## True when the road (axis, index) passes within NEAR of the plant's kerbs (the flares' light
## reaches it: every road there takes it, or it would stop dead at the edge of the next street).
static func near_road(plan: CityPlan, axis: int, index: int) -> bool:
	var lay := Refinery.layout(plan)
	if lay.is_empty():
		return false
	var rect: Rect2 = (lay.rect as Rect2).grow(NEAR)
	var pos := plan.road_pos(axis, index)
	if axis == CityPlan.AXIS_X:
		return pos > rect.position.x and pos < rect.end.x
	return pos > rect.position.y and pos < rect.end.y


## True when a block's `rect` lies within NEAR of the plant's kerbs.
static func near_rect(plan: CityPlan, r: Rect2) -> bool:
	var lay := Refinery.layout(plan)
	return not lay.is_empty() and (lay.rect as Rect2).grow(NEAR).intersects(r)


## The road's material, dressed with the plant's light when the road runs near the plant (a copy,
## cached per road: PropFactory.road()'s cache is shared). Any other road: `mat` unchanged.
static func road_material(mat: ShaderMaterial, plan: CityPlan, axis: int, index: int) -> ShaderMaterial:
	if not enabled or plan == null or not near_road(plan, axis, index):
		return mat
	return _dressed(mat, plan)


## A block's pavement material (CityChunk's paving, one per block), dressed when the block is near.
static func paving_material(mat: ShaderMaterial, plan: CityPlan, r: Rect2) -> ShaderMaterial:
	if not enabled or plan == null or not near_rect(plan, r):
		return mat
	return _dressed(mat, plan)


static func _dressed(mat: ShaderMaterial, plan: CityPlan) -> ShaderMaterial:
	var key := [plan.get_instance_id(), mat.get_instance_id()]
	if _road_mats.has(key):
		return _road_mats[key]
	var m := mat.duplicate() as ShaderMaterial
	dress(m, plan)
	_road_mats[key] = m
	return m


## A junction square's material (it wears its x road's look): dressed when either road crossing
## there runs along the plant.
static func junction_material(mat: ShaderMaterial, plan: CityPlan, ix_road: int, iz_road: int) -> ShaderMaterial:
	if not enabled or plan == null:
		return mat
	if near_road(plan, CityPlan.AXIS_X, ix_road) or near_road(plan, CityPlan.AXIS_Z, iz_road):
		return _dressed(mat, plan)
	return mat


## Hands a road.gdshader material the plant's lights (the refinery's pavement ring uses this too).
static func dress(mat: ShaderMaterial, plan: CityPlan) -> void:
	if not enabled:
		return
	var lay := Refinery.layout(plan)
	if lay.is_empty():
		return
	var fl := flares(lay, plan)
	var ms := masts(lay, plan)
	var fa := PackedVector4Array()
	fa.resize(8)
	for i in fl.size():
		fa[i] = fl[i]
	var ma := PackedVector4Array()
	ma.resize(MAX_MASTS)
	for i in ms.size():
		ma[i] = ms[i]
	var c: Vector2 = (lay.rect as Rect2).get_center()
	mat.set_shader_parameter("rr_on", 1.0)
	mat.set_shader_parameter("rr_flares", fa)
	mat.set_shader_parameter("rr_flare_count", fl.size())
	mat.set_shader_parameter("rr_masts", ma)
	mat.set_shader_parameter("rr_mast_count", ms.size())
	mat.set_shader_parameter("rr_centre", Vector3(c.x, REACH, c.y))
	mat.set_shader_parameter("rr_flare_gain", FLARE_GAIN)
	mat.set_shader_parameter("rr_flare_half", FLARE_HALF)
	mat.set_shader_parameter("rr_flare_reach", FLARE_REACH)
	mat.set_shader_parameter("rr_mast_gain", MAST_GAIN)
	mat.set_shader_parameter("rr_mast_reach", MAST_REACH)
	mat.set_shader_parameter("rr_mast_half", MAST_HALF)
	mat.set_shader_parameter("rr_damp", DAMP)
	mat.set_shader_parameter("rr_glint", GLINT)


## How a street lamp at `at` (TRUE world foot) burns: 1 as before, 0 out, else the share of its
## pool and light it throws. Only the lamps along the plant's perimeter streets change.
static func lamp_state(plan: CityPlan, at: Vector2) -> Dictionary:
	if not enabled or plan == null:
		return {}
	var lay := Refinery.layout(plan)
	if lay.is_empty():
		return {}
	var rect: Rect2 = lay.rect
	if not rect.grow(LAMP_REACH).has_point(at) or rect.has_point(at):
		return {}
	if h01([plan.seed, at.snapped(Vector2(0.1, 0.1)), "rr_lamp"]) < LAMP_OUT:
		return {"out": true, "pool": 0.0, "light": 0.0}
	return {"out": false, "pool": LAMP_POOL, "light": LAMP_LIGHT}


## The diffuse light (unitless, before colour) at TRUE world `p` facing up: refinery_road's
## rr_fall() summed over the flares (no flicker) and masts - the checks hold the two together.
static func light_at(lay: Dictionary, plan: CityPlan, p: Vector3) -> float:
	var sum := 0.0
	for f: Vector4 in flares(lay, plan):
		sum += _fall(Vector3(f.x, f.y, f.z), p, FLARE_HALF, FLARE_REACH) * FLARE_GAIN
	for m: Vector4 in masts(lay, plan):
		sum += _pool(Vector3(m.x, m.y, m.z), p, MAST_HALF, MAST_REACH) * m.w * MAST_GAIN
	return sum


static func _fall(s: Vector3, p: Vector3, half_d: float, reach: float) -> float:
	var d := s - p
	var dist := d.length()
	var cosv := clampf(d.y / maxf(dist, 0.01), 0.0, 1.0)
	var fall := (half_d * half_d) / (half_d * half_d + dist * dist)
	return fall * cosv * (1.0 - smoothstep(reach * 0.7, reach, dist))


static func _pool(s: Vector3, p: Vector3, half_d: float, reach: float) -> float:
	var r := Vector2(s.x - p.x, s.z - p.z).length()
	var q := 1.0 + (r * r) / (half_d * half_d)
	return pow(q, -1.5) * (1.0 - smoothstep(reach * 0.7, reach, r))


## The pavement ring's piece `r` (inside the plant's kerb-to-kerb `rect`) at height `y` over the
## relief, into `st`: wound to face up (FilmStudio._flat() winds its quad face down, so the
## refinery's pavement ring was culled - the street saw the horizon plane through a 4.5 m slot
## along every fence), and a kerb face down to the road wherever the piece meets the plant's kerb.
static func ring_piece(ch: CityChunk, st: SurfaceTool, r: Rect2, rect: Rect2, y: float) -> void:
	var gy := func(x: float, z: float) -> float: return ch._gy(x, z)
	var a := Vector3(r.position.x, y + gy.call(r.position.x, r.position.y), r.position.y)
	var b := Vector3(r.end.x, y + gy.call(r.end.x, r.position.y), r.position.y)
	var c := Vector3(r.end.x, y + gy.call(r.end.x, r.end.y), r.end.y)
	var d := Vector3(r.position.x, y + gy.call(r.position.x, r.end.y), r.end.y)
	for v: Vector3 in [a, b, c, a, c, d]:
		st.set_color(Color.WHITE)
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(v.x, v.z))
		st.add_vertex(v)
	var drop := y - CityChunk.ROAD_TOP
	# The kerb faces: [edge start, edge end, outward normal] where the piece's edge is the kerb.
	var edges: Array = []
	if absf(r.position.y - rect.position.y) < 0.05:
		edges.append([a, b, Vector3.FORWARD])
	if absf(r.end.y - rect.end.y) < 0.05:
		edges.append([c, d, Vector3.BACK])
	if absf(r.position.x - rect.position.x) < 0.05:
		edges.append([d, a, Vector3.LEFT])
	if absf(r.end.x - rect.end.x) < 0.05:
		edges.append([b, c, Vector3.RIGHT])
	for e: Array in edges:
		var p0: Vector3 = e[0]
		var p1: Vector3 = e[1]
		var n: Vector3 = e[2]
		var q0 := p0 - Vector3(0.0, drop, 0.0)
		var q1 := p1 - Vector3(0.0, drop, 0.0)
		# Clockwise seen from outside (along -n): p0 top, p1 top, q1, q0.
		var tri := [p0, p1, q1, p0, q1, q0]
		var face_n := (p1 - p0).cross(q1 - p0).normalized()
		if face_n.dot(n) > 0.0:
			tri = [p0, q1, p1, p0, q0, q1]
		for v: Vector3 in tri:
			st.set_color(Color.WHITE)
			st.set_normal(n)
			st.set_uv(Vector2(v.x + v.z, v.y))
			st.add_vertex(v)
