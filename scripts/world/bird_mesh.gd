class_name BirdMesh
extends RefCounted
## The city's birds, built in code at real size (VISUAL_ROADMAP #53, HANDOFF 9bk): a lofted body
## along a curved spine (breast, neck, head, beak in one surface), eyes, scaled legs and toes, and
## real feather cards - secondaries, tertials, primaries fanned to the wingtip, an alula, a covert
## sheet over their bases, a tail fan - each cut out of a painted feather in the species' atlas
## (tools/birds/make_bird_textures.py). One mesh per species and level of detail, drawn by one
## MultiMesh each (Birds) on shaders/bird.gdshader.
##
## Every vertex carries TWO poses: VERTEX is the bird in flight (wings spread, tail fanned, legs
## tucked back under the belly) and CUSTOM0.xyz the bird on the ground (wings folded along the
## flanks with the primaries crossed over the rump, tail closed, legs standing), CUSTOM1.xyz that
## pose's normal. The shader blends the two by the instance's `spread`, then flaps the spread
## wings about the shoulder and the wrist, bobs and pecks the head, walks the legs. CUSTOM0.w is
## the part (PART_*), CUSTOM1.w its weight: the head's share of the neck bend on the body and the
## eyes, the hand's share of the wing on a wing vertex, the leg's side on a leg.
##
## The bird faces -Z, up is +Y, its right is +X; the origin is between its feet on the ground.

enum Level { NEAR, MID, FAR }

const PART_BODY := 0.0
const PART_WING := 1.0
const PART_TAIL := 2.0
const PART_LEG := 3.0
const PART_EYE := 4.0

## Spine landmarks (0 tail base .. 1 beak tip), the rows the atlas paints neck, head and beak on.
## Mirrored by S_* in tools/birds/make_bird_textures.py.
const S_NECK := 0.58
const S_HEAD := 0.74
const S_EYE := 0.84
const S_BEAK := 0.915

## Atlas regions in pixels of the 1024 atlas (mirrored by the painter's SLOTS and regions).
const ATLAS := 1024.0
const SLOTS := {
	"P_OUT": Rect2(512, 0, 64, 448), "P_MID": Rect2(576, 0, 64, 448), "P_IN": Rect2(640, 0, 64, 448),
	"S_OUT": Rect2(704, 0, 64, 448), "S_IN": Rect2(768, 0, 64, 448), "TERT": Rect2(832, 0, 64, 448),
	"TAIL_OUT": Rect2(896, 0, 64, 448), "TAIL_IN": Rect2(960, 0, 64, 448),
	"COV_G": Rect2(512, 448, 64, 256), "COV_M": Rect2(576, 448, 64, 256), "P_COV": Rect2(640, 448, 64, 256),
	"ALULA": Rect2(704, 448, 64, 256),
}
const BODY_RECT := Rect2(0, 0, 512, 1024)
const FAR_WING_RECT := Rect2(512, 704, 512, 256)
const COV_SHEET_RECT := Rect2(768, 448, 256, 256)
const EYE_RECT := Rect2(512, 960, 64, 64)
const LEG_RECT := Rect2(576, 960, 64, 64)

## Where the painted far wing changes from secondaries to primaries (its span coordinate).
const FAR_WING_WRIST := 0.48

static var _cache: Dictionary = {}
static var _materials: Dictionary = {}

const TEXTURE_DIR := "res://assets/textures/birds/"

## Per-species shader numbers: the sheen's two colours (linear), its strength, the main grey a
## morph is measured against, and the wingbeat / glide shape - a pigeon's deep clap-and-flick,
## a gull's shallow stroke and crooked glide, a crow's rowing beat, a sparrow's whirr.
const LOOKS := {
	"pigeon": {"irid_a": Vector3(0.03, 0.2, 0.08), "irid_b": Vector3(0.2, 0.04, 0.17), "irid_strength": 0.8,
		"morph_ref": 0.343, "flap_angle": 1.0, "flap_bias": 0.2, "hand_flex": 0.45, "hand_sweep": 0.55,
		"glide_arm": 0.24, "glide_hand": 0.0, "peck_angle": 1.2, "stride_angle": 0.55},
	"gull": {"irid_a": Vector3.ZERO, "irid_b": Vector3.ZERO, "irid_strength": 0.0,
		"morph_ref": 0.3, "flap_angle": 0.62, "flap_bias": 0.1, "hand_flex": 0.35, "hand_sweep": 0.3,
		"glide_arm": 0.14, "glide_hand": -0.24, "peck_angle": 0.8, "stride_angle": 0.45},
	"crow": {"irid_a": Vector3(0.012, 0.018, 0.05), "irid_b": Vector3(0.035, 0.014, 0.05), "irid_strength": 0.4,
		"morph_ref": 0.01, "flap_angle": 0.8, "flap_bias": 0.12, "hand_flex": 0.4, "hand_sweep": 0.45,
		"glide_arm": 0.08, "glide_hand": -0.06, "peck_angle": 1.0, "stride_angle": 0.5},
	"sparrow": {"irid_a": Vector3.ZERO, "irid_b": Vector3.ZERO, "irid_strength": 0.0,
		"morph_ref": 0.1, "flap_angle": 1.1, "flap_bias": 0.25, "hand_flex": 0.5, "hand_sweep": 0.6,
		"glide_arm": 0.1, "glide_hand": 0.0, "peck_angle": 1.2, "stride_angle": 0.4},
}


## The species' material, shared by its three meshes.
static func material(name: String) -> ShaderMaterial:
	if _materials.has(name):
		return _materials[name]
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/bird.gdshader")
	for kind in ["albedo", "normal", "mask"]:
		var path := TEXTURE_DIR + "%s_%s.png" % [name, kind]
		if ResourceLoader.exists(path):
			mat.set_shader_parameter(kind + "_tex", load(path))
	var pv := pivots(name)
	mat.set_shader_parameter("shoulder", pv[0])
	mat.set_shader_parameter("wrist", pv[1])
	mat.set_shader_parameter("neck", pv[2])
	mat.set_shader_parameter("hip", pv[3])
	mat.set_shader_parameter("tail_base", species(name).tail.base)
	mat.set_shader_parameter("bob_amount", species(name).bob)
	var look: Dictionary = LOOKS.get(name, LOOKS.pigeon)
	for k: String in look:
		mat.set_shader_parameter(k, look[k])
	_materials[name] = mat
	return mat


## The species' measurements. Every length in metres; built from the real birds' sizes (rock
## dove 32 cm long and 0.68 m across the wings, Western gull 60 cm / 1.40 m, American crow 45 cm
## / 0.90 m, house sparrow 15 cm / 0.24 m) and their shapes: the pigeon's deep breast and small
## head, the gull's long flat body and narrow wings, the crow's heavy bill and fingered wingtip,
## the sparrow's round head and conical bill.
static func species(name: String) -> Dictionary:
	match name:
		"gull":
			return {
				# [s, z, y, radius up, radius down, radius side]
				"spine": [
					[0.0, 0.17, 0.215, 0.016, 0.016, 0.024], [0.08, 0.13, 0.215, 0.04, 0.042, 0.052],
					[0.2, 0.07, 0.21, 0.06, 0.07, 0.075], [0.34, 0.0, 0.212, 0.064, 0.078, 0.078],
					[0.46, -0.07, 0.22, 0.06, 0.07, 0.07], [0.54, -0.11, 0.24, 0.045, 0.052, 0.05],
					[0.58, -0.125, 0.262, 0.034, 0.036, 0.034], [0.66, -0.14, 0.296, 0.027, 0.027, 0.027],
					[0.74, -0.15, 0.318, 0.026, 0.026, 0.025], [0.8, -0.168, 0.33, 0.027, 0.026, 0.025],
					[0.84, -0.188, 0.332, 0.024, 0.022, 0.022], [0.9, -0.212, 0.325, 0.014, 0.014, 0.013],
					[0.915, -0.218, 0.322, 0.010, 0.012, 0.0085], [0.96, -0.246, 0.318, 0.0065, 0.009, 0.006],
					[0.985, -0.262, 0.314, 0.004, 0.009, 0.004], [1.0, -0.270, 0.306, 0.001, 0.002, 0.001],
				],
				"neck_pivot": Vector2(-0.125, 0.262),
				"tail": {"base": Vector3(0.0, 0.214, 0.155), "count": 10, "length": 0.15, "width": 0.05, "half": 0.024,
					"fan_ground": 5.0, "fan_flight": 24.0, "slope_ground": -0.06, "slope_flight": 0.02},
				"wing": {"shoulder": Vector3(0.036, 0.262, -0.06), "wrist_x": 0.24, "hand_x": 0.34,
					"le_z": [-0.075, -0.085, -0.07], "sec_n": 13, "sec_len": 0.17, "sec_w": 0.038,
					"prim_n": 10, "prim_len": 0.30, "prim_w": 0.034, "prim_profile": [0.5, 0.56, 0.62, 0.68, 0.75, 0.82, 0.89, 0.95, 1.0, 0.97],
					"prim_fan": Vector2(22.0, 80.0), "tert_n": 3, "tert_len": 0.13, "cov_depth": 0.085,
					"wrist_g": Vector3(0.0, 0.25, -0.08), "elbow_g": Vector3(0.0, 0.262, 0.03), "hand_fold": 0.07,
					"drop_g": 0.16, "inward_g": 0.08},
				"legs": {"hip": Vector3(0.026, 0.16, 0.02), "ankle": Vector3(0.03, 0.03, 0.01), "toe": 0.05, "hind": 0.012, "r": 0.0055, "webbed": true},
				"eye": {"r": 0.0058, "theta": 72.0},
				"bob": 0.0,
			}
		"crow":
			return {
				"spine": [
					[0.0, 0.12, 0.205, 0.014, 0.014, 0.02], [0.08, 0.095, 0.205, 0.032, 0.034, 0.04],
					[0.2, 0.05, 0.2, 0.05, 0.058, 0.06], [0.34, 0.0, 0.2, 0.056, 0.064, 0.064],
					[0.46, -0.05, 0.21, 0.054, 0.06, 0.058], [0.54, -0.08, 0.226, 0.042, 0.046, 0.044],
					[0.58, -0.092, 0.244, 0.034, 0.034, 0.033], [0.66, -0.104, 0.27, 0.03, 0.03, 0.029],
					[0.74, -0.112, 0.29, 0.03, 0.029, 0.028], [0.8, -0.128, 0.302, 0.031, 0.027, 0.028],
					[0.84, -0.146, 0.304, 0.027, 0.024, 0.025], [0.9, -0.166, 0.3, 0.019, 0.017, 0.016],
					[0.915, -0.172, 0.298, 0.015, 0.014, 0.0115], [0.96, -0.205, 0.294, 0.009, 0.008, 0.0072],
					[0.985, -0.226, 0.288, 0.0045, 0.004, 0.0038], [1.0, -0.236, 0.28, 0.001, 0.001, 0.001],
				],
				"neck_pivot": Vector2(-0.092, 0.244),
				"tail": {"base": Vector3(0.0, 0.205, 0.11), "count": 10, "length": 0.17, "width": 0.042, "half": 0.02,
					"fan_ground": 6.0, "fan_flight": 26.0, "slope_ground": -0.18, "slope_flight": 0.0},
				"wing": {"shoulder": Vector3(0.032, 0.248, -0.045), "wrist_x": 0.15, "hand_x": 0.215,
					"le_z": [-0.06, -0.07, -0.055], "sec_n": 12, "sec_len": 0.16, "sec_w": 0.036,
					"prim_n": 10, "prim_len": 0.235, "prim_profile": [0.62, 0.68, 0.74, 0.8, 0.86, 0.92, 0.97, 1.0, 0.96, 0.84],
					"prim_w": 0.034, "prim_fan": Vector2(20.0, 72.0), "tert_n": 3, "tert_len": 0.12, "cov_depth": 0.075,
					"wrist_g": Vector3(0.0, 0.235, -0.06), "elbow_g": Vector3(0.0, 0.248, 0.025), "hand_fold": 0.05,
					"drop_g": 0.2, "inward_g": 0.1},
				"legs": {"hip": Vector3(0.024, 0.15, 0.012), "ankle": Vector3(0.027, 0.03, 0.006), "toe": 0.045, "hind": 0.03, "r": 0.0048, "webbed": false},
				"eye": {"r": 0.0055, "theta": 70.0},
				"bob": 0.004,
			}
		"sparrow":
			return {
				"spine": [
					[0.0, 0.036, 0.052, 0.006, 0.006, 0.008], [0.08, 0.028, 0.052, 0.013, 0.014, 0.016],
					[0.2, 0.014, 0.052, 0.02, 0.023, 0.024], [0.34, 0.0, 0.053, 0.023, 0.026, 0.026],
					[0.46, -0.014, 0.056, 0.022, 0.024, 0.024], [0.54, -0.022, 0.062, 0.018, 0.019, 0.019],
					[0.58, -0.025, 0.068, 0.016, 0.016, 0.016], [0.66, -0.028, 0.075, 0.015, 0.015, 0.015],
					[0.74, -0.031, 0.08, 0.016, 0.015, 0.015], [0.8, -0.036, 0.084, 0.016, 0.014, 0.0145],
					[0.84, -0.042, 0.085, 0.014, 0.012, 0.0128], [0.9, -0.049, 0.083, 0.0095, 0.0085, 0.0085],
					[0.915, -0.051, 0.082, 0.0072, 0.0068, 0.0062], [0.96, -0.057, 0.0805, 0.0042, 0.0038, 0.0036],
					[0.985, -0.06, 0.08, 0.002, 0.0018, 0.0018], [1.0, -0.062, 0.0795, 0.0005, 0.0005, 0.0005],
				],
				"neck_pivot": Vector2(-0.025, 0.068),
				"tail": {"base": Vector3(0.0, 0.054, 0.033), "count": 8, "length": 0.058, "width": 0.014, "half": 0.006,
					"fan_ground": 8.0, "fan_flight": 28.0, "slope_ground": 0.25, "slope_flight": 0.0},
				"wing": {"shoulder": Vector3(0.012, 0.066, -0.012), "wrist_x": 0.032, "hand_x": 0.05,
					"le_z": [-0.016, -0.02, -0.014], "sec_n": 9, "sec_len": 0.045, "sec_w": 0.011,
					"prim_n": 9, "prim_len": 0.062, "prim_profile": [0.66, 0.72, 0.78, 0.85, 0.91, 0.96, 1.0, 0.99, 0.9],
					"prim_w": 0.0095, "prim_fan": Vector2(22.0, 76.0), "tert_n": 3, "tert_len": 0.036, "cov_depth": 0.022,
					"wrist_g": Vector3(0.0, 0.064, -0.016), "elbow_g": Vector3(0.0, 0.069, 0.008), "hand_fold": 0.014,
					"drop_g": 0.22, "inward_g": 0.08},
				"legs": {"hip": Vector3(0.008, 0.04, 0.002), "ankle": Vector3(0.009, 0.008, 0.0), "toe": 0.014, "hind": 0.009, "r": 0.0016, "webbed": false},
				"eye": {"r": 0.0026, "theta": 72.0},
				"bob": 0.0,
			}
	# The rock dove.
	return {
		"spine": [
			[0.0, 0.08, 0.112, 0.010, 0.010, 0.014], [0.08, 0.06, 0.111, 0.026, 0.027, 0.030],
			[0.2, 0.03, 0.107, 0.042, 0.046, 0.046], [0.34, -0.005, 0.106, 0.048, 0.054, 0.052],
			[0.46, -0.04, 0.113, 0.046, 0.056, 0.049], [0.54, -0.062, 0.128, 0.036, 0.042, 0.037],
			[0.58, -0.07, 0.143, 0.026, 0.028, 0.025], [0.66, -0.078, 0.166, 0.018, 0.019, 0.018],
			[0.74, -0.082, 0.185, 0.018, 0.017, 0.017], [0.8, -0.09, 0.197, 0.019, 0.016, 0.0168],
			[0.84, -0.1, 0.2, 0.017, 0.015, 0.0158], [0.9, -0.112, 0.196, 0.011, 0.0105, 0.0098],
			[0.915, -0.116, 0.193, 0.0072, 0.0068, 0.0062], [0.96, -0.128, 0.19, 0.0036, 0.0034, 0.0031],
			[0.985, -0.134, 0.1885, 0.0018, 0.0018, 0.0016], [1.0, -0.137, 0.187, 0.0004, 0.0004, 0.0004],
		],
		"neck_pivot": Vector2(-0.07, 0.143),
		"tail": {"base": Vector3(0.0, 0.113, 0.072), "count": 10, "length": 0.115, "width": 0.028, "half": 0.012,
			"fan_ground": 6.0, "fan_flight": 30.0, "slope_ground": -0.14, "slope_flight": 0.0},
		"wing": {"shoulder": Vector3(0.022, 0.138, -0.035), "wrist_x": 0.085, "hand_x": 0.13,
			"le_z": [-0.045, -0.055, -0.045], "sec_n": 11, "sec_len": 0.112, "sec_w": 0.025,
			"prim_n": 10, "prim_len": 0.18, "prim_profile": [0.56, 0.62, 0.69, 0.76, 0.83, 0.89, 0.94, 0.98, 1.0, 0.95],
			"prim_w": 0.04, "prim_fan": Vector2(10.0, 52.0), "tert_n": 3, "tert_len": 0.08, "cov_depth": 0.055,
			"wrist_g": Vector3(0.0, 0.126, -0.042), "elbow_g": Vector3(0.0, 0.138, 0.018), "hand_fold": 0.03,
			"drop_g": 0.18, "inward_g": 0.1},
		"legs": {"hip": Vector3(0.017, 0.075, 0.0), "ankle": Vector3(0.02, 0.022, 0.003), "toe": 0.032, "hind": 0.016, "r": 0.0032, "webbed": false},
		"eye": {"r": 0.0042, "theta": 76.0},
		"bob": 0.016,
	}


## The mesh for `name` at `level`, built once and cached.
static func mesh(name: String, level: int) -> ArrayMesh:
	var key := "%s:%d" % [name, level]
	if _cache.has(key):
		return _cache[key]
	var b := _Builder.new(species(name), level)
	b.build()
	var m := b.commit()
	_cache[key] = m
	return m


## The pivots the shader turns parts about, in the bird's space: [shoulder, wrist, neck, hip].
static func pivots(name: String) -> Array:
	var sp := species(name)
	var w: Dictionary = sp.wing
	var sh: Vector3 = w.shoulder
	var lz: Array = w.le_z
	var np2: Vector2 = sp.neck_pivot
	return [sh, Vector3(float(w.wrist_x), sh.y, float(lz[1]) + 0.25 * float(w.sec_len)),
		Vector3(0.0, np2.y, np2.x), sp.legs.hip]


static func _uv(r: Rect2, u: float, v: float) -> Vector2:
	return Vector2((r.position.x + u * r.size.x) / ATLAS, (r.position.y + v * r.size.y) / ATLAS)


class _Builder:
	var sp: Dictionary
	var level: int
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var c0 := PackedFloat32Array()
	var c1 := PackedFloat32Array()
	var idx := PackedInt32Array()
	# Folded poses and their normals (CUSTOM0 / CUSTOM1), kept as vectors until commit.
	var fold := PackedVector3Array()
	var fold_n := PackedVector3Array()
	var part := PackedFloat32Array()
	var weight := PackedFloat32Array()
	# The body loft sampled by z for the flank snap: [z, centre y, r up, r down, r side].
	var _flank_rows: Array = []

	func _init(species_data: Dictionary, lv: int) -> void:
		sp = species_data
		level = lv

	func build() -> void:
		_body()
		_tail()
		for side in [1.0, -1.0]:
			_wing(side)
			_leg(side)
			if level != Level.FAR:
				_eye(side)

	func commit() -> ArrayMesh:
		var tans := _tangents()
		for i in verts.size():
			var f: Vector3 = fold[i]
			var fnv: Vector3 = fold_n[i]
			c0.append(f.x)
			c0.append(f.y)
			c0.append(f.z)
			c0.append(part[i])
			c1.append(fnv.x)
			c1.append(fnv.y)
			c1.append(fnv.z)
			c1.append(weight[i])
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = norms
		arrays[Mesh.ARRAY_TANGENT] = tans
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_CUSTOM0] = c0
		arrays[Mesh.ARRAY_CUSTOM1] = c1
		arrays[Mesh.ARRAY_INDEX] = idx
		var fmt := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) \
			| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, fmt)
		# Bounds that hold both poses and a full flap, so nothing is culled mid-stroke.
		var lo := Vector3(INF, INF, INF)
		var hi := -lo
		for v in verts:
			lo = lo.min(v)
			hi = hi.max(v)
		var reach := maxf(absf(lo.x), absf(hi.x))
		m.custom_aabb = AABB(Vector3(-reach, lo.y - reach, lo.z - 0.05), Vector3(reach * 2.0, hi.y - lo.y + reach * 2.0, hi.z - lo.z + 0.1))
		return m

	func _add(p: Vector3, n: Vector3, uv: Vector2, fp: Vector3, fnv: Vector3, prt: float, w: float) -> int:
		verts.append(p)
		norms.append(n.normalized())
		uvs.append(uv)
		fold.append(fp)
		fold_n.append(fnv.normalized())
		part.append(prt)
		weight.append(w)
		return verts.size() - 1

	func _tri(a: int, b: int, c: int) -> void:
		idx.append(a)
		idx.append(b)
		idx.append(c)

	# Godot's front faces wind clockwise seen from the front; wind every triangle to face `n`.
	func _tri_facing(a: int, b: int, c: int) -> void:
		var fn := (verts[b] - verts[a]).cross(verts[c] - verts[a])
		var want := norms[a] + norms[b] + norms[c]
		if fn.dot(want) > 0.0:
			_tri(a, c, b)
		else:
			_tri(a, b, c)

	func _tangents() -> PackedFloat32Array:
		var t := PackedVector3Array()
		t.resize(verts.size())
		var bsum := PackedVector3Array()
		bsum.resize(verts.size())
		for k in range(0, idx.size(), 3):
			var i0 := idx[k]
			var i1 := idx[k + 1]
			var i2 := idx[k + 2]
			var e1 := verts[i1] - verts[i0]
			var e2 := verts[i2] - verts[i0]
			var d1 := uvs[i1] - uvs[i0]
			var d2 := uvs[i2] - uvs[i0]
			var r := d1.x * d2.y - d2.x * d1.y
			if absf(r) < 1e-12:
				continue
			r = 1.0 / r
			var sdir := (e1 * d2.y - e2 * d1.y) * r
			var tdir := (e2 * d1.x - e1 * d2.x) * r
			for i in [i0, i1, i2]:
				t[i] += sdir
				bsum[i] += tdir
		var out := PackedFloat32Array()
		for i in verts.size():
			var n := norms[i]
			var tt := t[i] - n * n.dot(t[i])
			if tt.length_squared() < 1e-14:
				tt = n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT)
			tt = tt.normalized()
			var w := -1.0 if n.cross(tt).dot(bsum[i]) < 0.0 else 1.0
			out.append_array([tt.x, tt.y, tt.z, w])
		return out

	# --- Body ---------------------------------------------------------------------------

	func _spine_at(s: float) -> Array:
		var rows: Array = sp.spine
		for i in rows.size() - 1:
			var a: Array = rows[i]
			var b: Array = rows[i + 1]
			if s <= float(b[0]) or i == rows.size() - 2:
				var k := clampf((s - float(a[0])) / maxf(float(b[0]) - float(a[0]), 1e-6), 0.0, 1.0)
				# Catmull-Rom on the centre line, linear on the radii.
				var p0: Array = rows[maxi(i - 1, 0)]
				var p3: Array = rows[mini(i + 2, rows.size() - 1)]
				var z := _cr(float(p0[1]), float(a[1]), float(b[1]), float(p3[1]), k)
				var y := _cr(float(p0[2]), float(a[2]), float(b[2]), float(p3[2]), k)
				return [z, y, lerpf(a[3], b[3], k), lerpf(a[4], b[4], k), lerpf(a[5], b[5], k)]
		return rows[0].slice(1)

	static func _cr(p0: float, p1: float, p2: float, p3: float, t: float) -> float:
		return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t)

	func _ring_point(s: float, theta: float) -> Array:
		var a := _spine_at(s)
		var b := _spine_at(minf(s + 0.01, 1.0))
		var c := _spine_at(maxf(s - 0.01, 0.0))
		var tz := float(b[0]) - float(c[0])
		var ty := float(b[1]) - float(c[1])
		var tl := sqrt(tz * tz + ty * ty)
		tz /= tl
		ty /= tl
		# The cross-section's "up" in the spine's plane: the tangent turned 90 degrees.
		var uz := ty
		var uy := -tz
		if uy < 0.0:
			uz = -uz
			uy = -uy
		var cu := cos(theta)
		var r_v: float = float(a[2]) if cu >= 0.0 else float(a[3])
		var off_v := cu * r_v
		var off_x := sin(theta) * float(a[4])
		var p := Vector3(off_x, float(a[1]) + uy * off_v, float(a[0]) + uz * off_v)
		# Normal of the ellipse cross-section, approximately (refined by averaging the faces).
		var n := Vector3(sin(theta) / maxf(float(a[4]), 1e-4), uy * cu / maxf(r_v, 1e-4), uz * cu / maxf(r_v, 1e-4))
		return [p, n.normalized()]

	func _body() -> void:
		var rings: int = [24, 12, 6][level]
		var around: int = [18, 10, 6][level]
		var base := verts.size()
		var head_w := func(s: float) -> float: return smoothstep(S_NECK - 0.02, S_HEAD, s)
		for r in rings + 1:
			# Denser rings round the head and the beak, where the shape turns fastest.
			var t := float(r) / float(rings)
			var s := t if level == Level.FAR else lerpf(t, 1.0 - pow(1.0 - t, 1.6), 0.5)
			for k in around + 1:
				var theta := TAU * float(k) / float(around)
				var pn := _ring_point(s, theta)
				var u := theta / PI * 0.5 if theta <= PI else (2.0 - theta / PI) * 0.5
				var uv := BirdMesh._uv(BODY_RECT, u * 2.0 * 0.5 + 0.0, 1.0 - s)
				uv.x = (BODY_RECT.position.x + u * BODY_RECT.size.x) / ATLAS
				_add(pn[0], pn[1], uv, pn[0], pn[1], PART_BODY, head_w.call(s))
		for r in rings:
			for k in around:
				var a := base + r * (around + 1) + k
				var b := a + 1
				var c := a + around + 1
				var d := c + 1
				_tri_facing(a, c, b)
				_tri_facing(b, c, d)
		# Cap the tail end (it sits under the tail fan).
		var cap := _add(verts[base] + Vector3(0, 0, 0.002), Vector3(0, 0, 1), uvs[base], verts[base] + Vector3(0, 0, 0.002), Vector3(0, 0, 1), PART_BODY, 0.0)
		for k in around:
			_tri_facing(base + k, base + k + 1, cap)
		# The flank snap table.
		for r in 41:
			var s := float(r) / 40.0 * S_NECK
			_flank_rows.append(_spine_at(s))

	## Half the body's width at height y, at depth z (0 off the body).
	func flank(y: float, z: float) -> float:
		var best: Array = []
		for i in _flank_rows.size() - 1:
			var a: Array = _flank_rows[i]
			var b: Array = _flank_rows[i + 1]
			var za := float(a[0])
			var zb := float(b[0])
			if (z <= za and z >= zb) or (z >= za and z <= zb):
				var k := (z - za) / (zb - za) if absf(zb - za) > 1e-6 else 0.0
				best = [lerpf(a[1], b[1], k), lerpf(a[2], b[2], k), lerpf(a[3], b[3], k), lerpf(a[4], b[4], k)]
				break
		if best.is_empty():
			return 0.0
		var dy := y - float(best[0])
		var r: float = float(best[1]) if dy > 0.0 else float(best[2])
		var q := 1.0 - (dy / r) * (dy / r)
		return float(best[3]) * sqrt(q) if q > 0.0 else 0.0

	# --- Feather cards ------------------------------------------------------------------

	## One feather: a card from `base` along `dir` with its width along `wdir` in flight, and the
	## same from `fbase` / `fdir` / `fwdir` on the ground. Cambered across, drooping toward the tip.
	## `layer` lifts it off the flank on the ground, `fsnap` puts its ground pose on the flank.
	func feather(slot: String, base: Vector3, dir: Vector3, wdir: Vector3, length: float, width: float,
			fbase: Vector3, fdir: Vector3, fwdir: Vector3, flength: float, layer: float, side: float,
			prt: float, hand: float, droop: float, fsnap: bool) -> void:
		var rect: Rect2 = SLOTS[slot]
		var along: int = [4, 2, 1][level]
		var across: int = [2, 1, 1][level]
		var up := wdir.cross(dir).normalized()
		if up.y < 0.0:
			up = -up
		var fup := fwdir.cross(fdir).normalized()
		if fup.dot(Vector3(side, 0.35, 0.0)) < 0.0:
			fup = -fup
		var first := verts.size()
		for i in along + 1:
			var t := float(i) / float(along)
			for j in across + 1:
				var a := float(j) / float(across) * 2.0 - 1.0
				var camber := (1.0 - a * a) * width * 0.08
				var p := base + dir * (t * length) + wdir * (a * width * 0.5) + up * (camber - droop * t * t * length)
				var fp := fbase + fdir * (t * flength) + fwdir * (a * width * 0.5) + fup * camber * 0.5
				if fsnap:
					fp = _snap(fp, side, layer)
				var uv := BirdMesh._uv(rect, (a + 1.0) * 0.5, 1.0 - t)
				_add(p, up, uv, fp, fup, prt, hand)
		var row := across + 1
		for i in along:
			for j in across:
				var a := first + i * row + j
				_tri_facing(a, a + row, a + 1)
				_tri_facing(a + 1, a + row, a + row + 1)

	## A ground-pose point laid on the bird's flank `layer` out, and over the rump flat on the back.
	func _snap(p: Vector3, side: float, layer: float) -> Vector3:
		var w := flank(p.y, p.z)
		var tb: Vector3 = sp.tail.base
		var over := smoothstep(tb.z - 0.4 * (tb.z - float(sp.wing.elbow_g.z)), tb.z + 0.01, p.z)
		var x := side * (w + layer)
		var q := Vector3(lerpf(x, p.x * 0.35 + side * layer, over), p.y, p.z)
		# Never under the closed tail.
		var tail_y := tb.y + float(sp.tail.slope_ground) * (p.z - tb.z) + float(sp.tail.width) * 0.06
		if p.z > tb.z - 0.01:
			q.y = maxf(q.y, tail_y + layer * 0.6)
		return q

	func _wing(side: float) -> void:
		var w: Dictionary = sp.wing
		var sh: Vector3 = w.shoulder
		var lez: Array = w.le_z
		var wrist_x: float = w.wrist_x
		var hand_x: float = w.hand_x
		var sec_len: float = w.sec_len
		var wrist_g: Vector3 = w.wrist_g
		var elbow_g: Vector3 = w.elbow_g
		var drop: float = w.drop_g
		var inward: float = w.inward_g
		var le := func(x: float) -> float:
			if x < wrist_x:
				return lerpf(float(lez[0]), float(lez[1]), x / wrist_x)
			return lerpf(float(lez[1]), float(lez[2]), clampf((x - wrist_x) / (hand_x - wrist_x), 0.0, 1.0))
		var gdir := Vector3(-side * inward, -drop, 1.0).normalized()
		var gw := Vector3(0.0, gdir.z, -gdir.y).normalized()
		if level == Level.FAR:
			_far_wing(side)
			return
		# Secondaries along the forearm, innermost (at the body) first.
		var sec_n: int = w.sec_n if level == Level.NEAR else int(ceil(float(w.sec_n) * 0.6))
		var spacing := (wrist_x - sh.x) / float(sec_n)
		var sw: float = maxf(float(w.sec_w), spacing * 1.8)
		for k in sec_n:
			var f := (float(k) + 0.5) / float(sec_n)
			var x := sh.x + f * (wrist_x - sh.x)
			var ang := deg_to_rad(2.0 + 12.0 * f)
			var dir := Vector3(side * sin(ang), -0.02, cos(ang)).normalized()
			var base := Vector3(side * x, sh.y + 0.0006 * float(k), float(le.call(x)) + 0.22 * sec_len)
			var wd := Vector3(cos(ang) * side, 0.0, -sin(ang)).normalized()
			var gb := elbow_g.lerp(wrist_g, f)
			var slot := "S_IN" if f < 0.5 else "S_OUT"
			feather(slot, base, dir, wd, sec_len * (1.0 - 0.08 * f), sw, gb, gdir, gw, sec_len * (1.0 - 0.08 * f),
				0.0038 + 0.0003 * float(k), side, PART_WING, smoothstep(0.75, 1.0, f) * 0.25, 0.05, true)
		# Tertials over the inner secondaries.
		var tert_n: int = w.tert_n if level == Level.NEAR else 1
		for k in tert_n:
			var f := (float(k) + 0.5) / float(tert_n)
			var x := sh.x + 0.03 * f * (wrist_x - sh.x) + 0.004
			var dir := Vector3(-side * 0.08, -0.02, 1.0).normalized()
			var base := Vector3(side * x, sh.y + 0.005, float(le.call(0.0)) + 0.3 * sec_len)
			var gb := elbow_g + Vector3(0.0, 0.004, -0.01 - 0.01 * f)
			var gd := Vector3(-side * inward * 2.5, -drop * 0.6, 1.0).normalized()
			feather("TERT", base, dir, Vector3(side, 0, 0), float(w.tert_len), float(w.sec_w) * 1.1, gb, gd,
				Vector3(0.0, gd.z, -gd.y).normalized(), float(w.tert_len), 0.0075 + 0.0004 * float(k), side, PART_WING, 0.0, 0.03, true)
		# Primaries from the hand, fanned out to the wingtip, innermost first.
		var prim_n: int = w.prim_n if level == Level.NEAR else int(ceil(float(w.prim_n) * 0.6))
		var prof: Array = w.prim_profile
		var fan: Vector2 = w.prim_fan
		for j in prim_n:
			var f := float(j) / float(maxi(prim_n - 1, 1))
			var pj := clampi(int(round(f * float(prof.size() - 1))), 0, prof.size() - 1)
			var x := wrist_x + f * (hand_x - wrist_x)
			var ang := deg_to_rad(lerpf(fan.x, fan.y, pow(f, 1.15)))
			var dir := Vector3(side * sin(ang), -0.03, cos(ang)).normalized()
			var wd := Vector3(cos(ang) * side, 0.0, -sin(ang)).normalized()
			var base := Vector3(side * x, sh.y - 0.0004 * float(j), float(le.call(x)) + 0.012)
			var length := float(w.prim_len) * float(prof[pj])
			var gb := wrist_g + Vector3(0.0, -0.0015 * float(j), f * float(w.hand_fold))
			var gd := Vector3(-side * inward * 0.9, -drop * 0.7, 1.0).normalized()
			var slot := "P_IN" if f < 0.35 else ("P_MID" if f < 0.7 else "P_OUT")
			var wid := float(w.prim_w) * (1.0 if level == Level.NEAR else 1.5)
			feather(slot, base, dir, wd, length, wid, gb, gd, Vector3(0.0, gd.z, -gd.y).normalized(), length,
				0.001 + 0.0003 * float(prim_n - 1 - j), side, PART_WING, 1.0, 0.04, true)
		# The alula at the wrist.
		if level == Level.NEAR:
			var ab := Vector3(side * (wrist_x + 0.004), sh.y + 0.004, float(lez[1]) + 0.002)
			var ad := Vector3(side * 0.5, 0.0, 1.0).normalized()
			feather("ALULA", ab, ad, Vector3(side, 0, -0.5 * side * side).normalized(), sec_len * 0.35, float(w.sec_w) * 0.6,
				wrist_g + Vector3(0, 0.004, -0.004), gdir, gw, sec_len * 0.3, 0.0105, side, PART_WING, 1.0, 0.0, true)
		_covert_sheet(side, le)

	## The coverts: one sheet over the leading edge and the bases of the flight feathers, painted
	## from the far wing's covert rows.
	func _covert_sheet(side: float, le: Callable) -> void:
		var w: Dictionary = sp.wing
		var sh: Vector3 = w.shoulder
		var wrist_x: float = w.wrist_x
		var hand_x: float = w.hand_x
		var depth: float = w.cov_depth
		var wrist_g: Vector3 = w.wrist_g
		var elbow_g: Vector3 = w.elbow_g
		var cols: int = [8, 4, 2][level]
		var rows: int = [3, 1, 1][level]
		var first := verts.size()
		for i in cols + 1:
			var fx := float(i) / float(cols)
			var x := sh.x * 0.6 + fx * (hand_x + 0.01 - sh.x * 0.6)
			var f_img := (x / wrist_x) * FAR_WING_WRIST if x < wrist_x else FAR_WING_WRIST + (x - wrist_x) / (hand_x - wrist_x) * 0.25
			# On the ground: along the folded forearm, then back along the folded hand.
			var g0: Vector3
			if x < wrist_x:
				g0 = elbow_g.lerp(wrist_g, clampf((x - sh.x * 0.6) / (wrist_x - sh.x * 0.6), 0.0, 1.0))
			else:
				g0 = wrist_g + Vector3(0.0, 0.0, (x - wrist_x) / (hand_x - wrist_x) * float(w.hand_fold) * 0.6)
			var dep := depth * (1.0 - 0.45 * smoothstep(wrist_x, hand_x + 0.01, x))
			for j in rows + 1:
				var c := float(j) / float(rows)
				var p := Vector3(side * x, sh.y + 0.006 - c * 0.003 + (1.0 - fx) * 0.002, float(le.call(x)) - 0.003 + c * dep)
				var gp := g0 + Vector3(0.0, -c * dep * 0.4, c * dep * 0.8)
				gp = _snap(gp, side, 0.0095)
				var uv := BirdMesh._uv(COV_SHEET_RECT, fx, c)
				var hand := smoothstep(wrist_x - 0.01, wrist_x + 0.01, x)
				_add(p, Vector3.UP, uv, gp, Vector3(side, 0.4, 0.0), PART_WING, hand)
		var row := rows + 1
		for i in cols:
			for j in rows:
				var a := first + i * row + j
				_tri_facing(a, a + 1, a + row)
				_tri_facing(a + 1, a + row + 1, a + row)

	## The far bird's wing: one strip shoulder to tip, both poses, from the painted far wing.
	func _far_wing(side: float) -> void:
		var w: Dictionary = sp.wing
		var sh: Vector3 = w.shoulder
		var lez: Array = w.le_z
		var wrist_x: float = w.wrist_x
		var hand_x: float = w.hand_x
		var tip_x := hand_x + float(w.prim_len) * 0.92
		var sec_len: float = w.sec_len
		var wrist_g: Vector3 = w.wrist_g
		var elbow_g: Vector3 = w.elbow_g
		var gdir := Vector3(-side * float(w.inward_g), -float(w.drop_g), 1.0).normalized()
		# [x, leading z, trailing z, image span, ground leading point]
		var xs := [sh.x, wrist_x, hand_x, tip_x]
		var lzs := [float(lez[0]), float(lez[1]), float(lez[2]), float(lez[2]) + float(w.prim_len) * 0.35]
		var tzs := [float(lez[0]) + sec_len * 1.15, float(lez[1]) + sec_len * 1.1, float(lez[2]) + float(w.prim_len) * 0.75, float(lez[2]) + float(w.prim_len) * 0.42]
		var fis := [0.0, FAR_WING_WRIST, 0.75, 1.0]
		var glead := [elbow_g, wrist_g, wrist_g + Vector3(0, 0, float(w.hand_fold)), wrist_g + Vector3(0, -0.01, float(w.hand_fold) + float(w.prim_len) * 0.85)]
		var first := verts.size()
		for i in 4:
			var gl: Vector3 = glead[i]
			var chord: float = float(tzs[i]) - float(lzs[i])
			for j in 2:
				var p := Vector3(side * float(xs[i]), sh.y, float(lzs[i]) if j == 0 else float(tzs[i]))
				var gp := gl if j == 0 else gl + gdir * (chord * (0.9 if i < 2 else 0.4))
				gp = _snap(gp, side, 0.008)
				var uv := BirdMesh._uv(FAR_WING_RECT, float(fis[i]), float(j))
				_add(p, Vector3.UP, uv, gp, Vector3(side, 0.4, 0.0), PART_WING, smoothstep(wrist_x - 0.01, wrist_x + 0.01, float(xs[i])))
		for i in 3:
			var a := first + i * 2
			_tri_facing(a, a + 2, a + 1)
			_tri_facing(a + 1, a + 2, a + 3)

	func _tail() -> void:
		var t: Dictionary = sp.tail
		var base: Vector3 = t.base
		var n: int = int(t.count) if level == Level.NEAR else (5 if level == Level.MID else 3)
		var half: float = t.half
		for i in n:
			var f := (float(i) / float(maxi(n - 1, 1))) * 2.0 - 1.0
			var side := 1.0 if f >= 0.0 else -1.0
			var af := deg_to_rad(float(t.fan_flight) * f)
			var ag := deg_to_rad(float(t.fan_ground) * f)
			var df := Vector3(sin(af), float(t.slope_flight), cos(af)).normalized()
			var dg := Vector3(sin(ag), float(t.slope_ground), cos(ag)).normalized()
			var wf := Vector3(cos(af), 0.0, -sin(af))
			var wg := Vector3(cos(ag), 0.0, -sin(ag))
			# The middle pair on top: each card a little lower toward the edges.
			var lift := -0.0012 * absf(f) * float(n) * 0.5
			var b := base + Vector3(f * half, lift, 0.0)
			var wid := float(t.width) * (1.0 if level == Level.NEAR else 1.8)
			var slot := "TAIL_OUT" if absf(f) > 0.7 else "TAIL_IN"
			feather(slot, b, df, wf, float(t.length), wid, b, dg, wg, float(t.length), 0.0, side, PART_TAIL, 0.0, 0.02, false)

	func _leg(side: float) -> void:
		var l: Dictionary = sp.legs
		var hip: Vector3 = l.hip
		hip.x *= side
		var ankle: Vector3 = l.ankle
		ankle.x *= side
		var r: float = l.r
		var segs := [[hip, ankle, r, r * 0.8]]
		if level == Level.NEAR:
			for a in [-28.0, 0.0, 28.0]:
				var ang := deg_to_rad(a + side * 6.0)
				var d := Vector3(sin(ang), 0.0, -cos(ang))
				segs.append([ankle, Vector3(ankle.x, r * 0.6, ankle.z) + d * float(l.toe), r * 0.7, r * 0.3])
			segs.append([ankle, Vector3(ankle.x, r * 0.6, ankle.z + float(l.hind)), r * 0.6, r * 0.3])
		var sides := 4 if level == Level.NEAR else (3 if level == Level.MID else 2)
		for sg in segs:
			_limb(sg[0], sg[1], sg[2], sg[3], sides, side, hip)

	## One tapered limb, both poses: on the ground as built, in flight swung back under the belly.
	func _limb(a: Vector3, b: Vector3, ra: float, rb: float, sides: int, side: float, hip: Vector3) -> void:
		var axis := (b - a).normalized()
		var ref := Vector3.FORWARD if absf(axis.z) < 0.9 else Vector3.RIGHT
		var u := axis.cross(ref).normalized()
		var v := axis.cross(u).normalized()
		var tuck := Basis(Vector3.RIGHT, deg_to_rad(-100.0))
		var first := verts.size()
		for e in 2:
			var c := a if e == 0 else b
			var rr := ra if e == 0 else rb
			for k in sides + 1:
				var ang := TAU * float(k) / float(sides)
				var n := u * cos(ang) + v * sin(ang)
				var gp := c + n * rr
				var fp := hip + tuck * (gp - hip) * Vector3(1.0, 0.8, 0.8)
				var uv := BirdMesh._uv(LEG_RECT, float(k) / float(sides), float(e))
				# Flight pose in VERTEX, ground pose in CUSTOM0.
				_add(fp, tuck * n, uv, gp, n, PART_LEG, side)
		var row := sides + 1
		for k in sides:
			var i0 := first + k
			_tri_facing(i0, i0 + row, i0 + 1)
			_tri_facing(i0 + 1, i0 + row, i0 + row + 1)

	func _eye(side: float) -> void:
		var e: Dictionary = sp.eye
		var r: float = e.r
		var pn := _ring_point(S_EYE, deg_to_rad(float(e.theta)) if side > 0.0 else TAU - deg_to_rad(float(e.theta)))
		var out: Vector3 = pn[1]
		var c: Vector3 = pn[0] - out * r * 0.45
		var u := out.cross(Vector3.UP).normalized()
		var v := u.cross(out).normalized()
		var rings := 4 if level == Level.NEAR else 2
		var around := 8 if level == Level.NEAR else 5
		var first := verts.size()
		var hw := smoothstep(S_NECK - 0.02, S_HEAD, S_EYE)
		for i in rings + 1:
			var phi := float(i) / float(rings) * PI * 0.62
			for k in around + 1:
				var th := TAU * float(k) / float(around)
				var n := out * cos(phi) + (u * cos(th) + v * sin(th)) * sin(phi)
				var p := c + n * r
				var rad := sin(phi) / sin(PI * 0.62)
				var uv := BirdMesh._uv(EYE_RECT, 0.5 + 0.5 * rad * cos(th), 0.5 + 0.5 * rad * sin(th))
				_add(p, n, uv, p, n, PART_EYE, hw)
		var row := around + 1
		for i in rings:
			for k in around:
				var a := first + i * row + k
				_tri_facing(a, a + row, a + 1)
				_tri_facing(a + 1, a + row, a + row + 1)
