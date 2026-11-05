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
const GLINT := 1.3
const MAX_MASTS := 32
## The pavement ring's cells (metres).
const RING_CELL := 6.0
## The verge at the fence's foot: its width (metres, out from the fence), the weed tufts' spacing
## and odds, the tall weeds' odds and the batches' cell (metres).
const VERGE_W := 1.3
const TUFT_STEP := 0.42
const TUFT_ODDS := 0.8
const TALL_ODDS := 0.05
const WEED_CELL := 40.0
## Puffs of soot a flare.
const SMOKE_PUFFS := 14
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
	# In cells (Industrial._ground_rect()'s rule: on the Compatibility renderer every lamp is an
	# additive pass that must land on the same depth, and a long triangle clipped at the near plane
	# does not).
	var nx := clampi(ceili(r.size.x / RING_CELL), 1, 64)
	var nz := clampi(ceili(r.size.y / RING_CELL), 1, 64)
	for j in nz:
		for i in nx:
			var x0 := r.position.x + r.size.x * i / nx
			var x1 := r.position.x + r.size.x * (i + 1) / nx
			var z0 := r.position.y + r.size.y * j / nz
			var z1 := r.position.y + r.size.y * (j + 1) / nz
			var qa := Vector3(x0, y + gy.call(x0, z0), z0)
			var qb := Vector3(x1, y + gy.call(x1, z0), z0)
			var qc := Vector3(x1, y + gy.call(x1, z1), z1)
			var qd := Vector3(x0, y + gy.call(x0, z1), z1)
			for v: Vector3 in [qa, qb, qc, qa, qc, qd]:
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


## The verge along the fence's foot, outside it (FULL chunks): a strip of weedy dirt over the
## pavement ring's inner edge and tufts of dry grass and the odd mustard along it - a perimeter is
## never paved right up to its chain-link. Hashes of the seed and the place. Returns the tufts laid.
static func verge(ch: CityChunk, lay: Dictionary, area: Rect2, ground: SurfaceTool) -> int:
	if not enabled:
		return 0
	var inner: Rect2 = lay.inner
	var g: Vector2 = lay.gate.at
	var gate := Rect2(g.x - Refinery.GATE_W * 0.5 - 2.0, g.y - 8.0, Refinery.GATE_W + 4.0, 16.0)
	# [piece, runs along x, the fence line's coordinate, which way is out from the fence].
	var strips: Array = []
	for r: Rect2 in Parks.minus(inner.grow(VERGE_W), [inner], 0.02):
		var ax := r.size.x >= r.size.y
		var fence := 0.0
		var out := 1.0
		if ax:
			fence = inner.end.y if absf(r.position.y - inner.end.y) < 0.05 else inner.position.y
			out = 1.0 if absf(r.position.y - inner.end.y) < 0.05 else -1.0
		else:
			fence = inner.end.x if absf(r.position.x - inner.end.x) < 0.05 else inner.position.x
			out = 1.0 if absf(r.position.x - inner.end.x) < 0.05 else -1.0
		for q: Rect2 in Parks.minus(r, [gate], 0.02):
			var p := q.intersection(area)
			if p.size.x > 0.05 and p.size.y > 0.05:
				strips.append([p, ax, fence, out])
	var seed: int = ch.plan.seed
	var n := 0
	var keys: Dictionary = {}
	for sp: Array in strips:
		var r: Rect2 = sp[0]
		var along_x: bool = sp[1]
		var fence_at: float = sp[2]
		var out_dir: float = sp[3]
		Industrial._ground_rect(ground, ch, r, CityChunk.SIDEWALK_TOP + 0.012, Industrial.G_WEEDS, 0.3 + 0.4 * h01([seed, r.position, "rr_vg"]), false)
		var length := r.size.x if along_x else r.size.y
		var steps := int(length / TUFT_STEP)
		for k in steps:
			var t := (float(k) + h01([seed, r.position, k, "rr_t"])) * TUFT_STEP
			var off := h01([seed, r.position, k, "rr_o"]) * (VERGE_W - 0.15) + 0.08
			# Measured out from the fence (the strip's inner edge is the fence line).
			var p := Vector2(r.position.x + t, fence_at + out_dir * off) if along_x else Vector2(fence_at + out_dir * off, r.position.y + t)
			if not area.has_point(p):
				continue
			var h := h01([seed, p.snapped(Vector2(0.01, 0.01)), "rr_w"])
			# Thicker against the fence, in patches along it.
			var patch := 0.45 + 0.9 * h01([seed, floorf(t / 6.0), r.position, "rr_p"])
			if h > TUFT_ODDS * patch * (1.15 - 0.5 * off / VERGE_W):
				continue
			var y := CityChunk.SIDEWALK_TOP + 0.02 + ch._gy(p.x, p.y)
			var cell := "%d_%d" % [floori(p.x / WEED_CELL), floori(p.y / WEED_CELL)]
			var yaw := TAU * h01([seed, p, "rr_y"])
			var sc := lerpf(0.7, 1.35, h01([seed, p, "rr_s"]))
			var dry := h01([seed, p, "rr_d"])
			var tint := Color(lerpf(0.8, 1.1, dry), lerpf(0.8, 1.05, dry), lerpf(0.7, 0.95, dry))
			if h < TALL_ODDS:
				var mustard := h01([seed, p, "rr_m"]) < 0.6
				var key := "rr_%s_%s" % ["mustard" if mustard else "fennel", cell]
				keys[key] = VacantLots.TALL_WEED_DISTANCE
				ch._batch.add(key, VacantKit.mustard() if mustard else VacantKit.fennel(), Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(sc, sc, sc)), Vector3(p.x, y, p.y)), tint)
			else:
				var v := 0 if dry > 0.3 else 1
				var key := "rr_tuft_%d_%s" % [v, cell]
				keys[key] = VacantLots.TUFT_DISTANCE
				ch._batch.add(key, VacantKit.tuft(v), Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(sc, sc * lerpf(0.8, 1.3, h), sc)), Vector3(p.x, y, p.y)), tint)
			n += 1
	for key: String in keys:
		ch._batch.set_no_shadow(key)
		ch._batch.set_draw_distance(key, float(keys[key]))
	ch.set_meta("rr_verge", n)
	return n


static var _smoke_mat: ShaderMaterial


## The flare smoke's material (shaders/refinery_flare_smoke.gdshader).
static func smoke_material() -> ShaderMaterial:
	if _smoke_mat == null:
		_smoke_mat = ShaderMaterial.new()
		_smoke_mat.shader = load("res://shaders/refinery_flare_smoke.gdshader")
		_smoke_mat.set_shader_parameter("puff_tex", WeaponFX.puff_texture())
	return _smoke_mat


## The soot off the flames at `flames` (their tips, in `parent`'s space) as one node under `parent`:
## camera-facing puffs placed in the shader from TIME (Refinery._puff_mesh()'s layout).
static func add_smoke(parent: Node3D, flames: Array) -> void:
	if not enabled or flames.is_empty():
		return
	var mi := MeshInstance3D.new()
	mi.name = "RefineryFlareSmoke"
	mi.mesh = Refinery._puff_mesh(flames, SMOKE_PUFFS if not OS.has_feature("web") else SMOKE_PUFFS / 2, false, "flare_smoke")
	mi.material_override = smoke_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.custom_aabb = Refinery._fx_aabb(flames, 110.0, 130.0)
	mi.extra_cull_margin = 2000.0
	parent.add_child(mi)


## The plant's own material (RefineryKit.material(), from RefineryNight.apply()): the tanks' floods
## as light on their paint in tight fans, the flares' light following the facing (rc4_look).
static func apply_plant(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("rc4_look", 1.0 if enabled else 0.0)
