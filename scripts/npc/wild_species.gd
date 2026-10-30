class_name WildSpecies
extends RefCounted
## The city's urban wildlife (HANDOFF "Urban wildlife"): coyotes, mule deer, raccoons, fox
## squirrels and cottontail rabbits. Their bodies are DogMesh's - the same lofted torso, head, leg
## tubes, ears, tail and fur shells on the 28-bone skeleton, posed by DogRig's procedural gait -
## built from each animal's own proportions in `SPECIES` (DogMesh.breed() looks here after its own
## breeds), at real size: a coyote stands 0.58 m at the withers, a mule deer 0.98 m, a raccoon
## 0.3 m, a fox squirrel 0.11 m, a cottontail 0.16 m. The coats are painted on the dogs' chart by
## tools/wildlife/make_wild_coats.py (assets/textures/dogs/wild_*.jpg). A buck carries antlers
## (`antler_mesh()`, code-built tines on the head bone).
##
## Keys beyond the dogs' (DogRig and WildAnimal read them): `tail_pose` the tail's carriage
## [base pitch, curl per segment] (degrees), `bound` the gallop's foot phases replaced by a
## bound / hop (front pair together, hind pair together), `pronk` all four together (a mule
## deer's stot), `gait` [trot_at, gallop_at] for DogRig, `flee` the bolt speed (m/s, before
## Dog's sqrt-of-height scaling), `flush` how close the player may come on foot (m), `alert` the
## distance it freezes and watches him, `wander` its walking speed (m/s).
##
## When and where each is out is `activity()` (pure: the hour) and Wildlife's habitat rules.

## Withers height, body length and every DogMesh key, as in DogMesh.BREEDS.
const SPECIES := {
	"coyote": {"h": 0.58, "l": 0.7, "chest": 0.5, "cw": 0.098, "tuck": 0.6, "croup": 0.02,
		"neck": 0.33, "neck_r": 0.098, "neck_a": 34.0, "hl": 0.235, "sw": 0.06, "muzzle": 0.53, "mw": 0.46,
		"dome": 0.24, "stop": 0.22, "ear": ["prick", 0.115, 0.08], "tail": ["brush", 0.38, 0.034],
		"tail_pose": [-62.0, 5.0], "leg": 0.04, "thigh": 0.9, "paw": 0.14, "coat": 0.034,
		"coat_mult": {"neck": 1.45, "head": 0.35, "leg": 0.35, "tail": 2.2, "belly": 0.9, "ear": 0.25},
		"cell": 0.0022, "eye_r": 0.0115, "eye": Color(0.42, 0.28, 0.07),
		"looks": [["wild_coyote", 0.6], ["wild_coyote_pale", 0.4]],
		"gait": [2.05, 5.2], "flee": 8.4, "flush": 16.0, "alert": 34.0, "wander": 1.25},
	"deer": {"h": 0.98, "l": 1.02, "chest": 0.44, "cw": 0.15, "tuck": 0.6, "croup": -0.02,
		"neck": 0.42, "neck_r": 0.09, "neck_a": 47.0, "hl": 0.31, "sw": 0.075, "muzzle": 0.5, "mw": 0.5,
		"dome": 0.22, "stop": 0.12, "ear": ["bat", 0.2, 0.14], "tail": ["whip", 0.17, 0.034],
		"tail_pose": [-70.0, 2.0], "leg": 0.03, "thigh": 1.05, "paw": 0.07, "coat": 0.016,
		"coat_mult": {"neck": 1.2, "head": 0.4, "leg": 0.3, "tail": 1.6, "belly": 1.0, "ear": 0.3},
		"cell": 0.002, "eye_r": 0.017, "eye": Color(0.05, 0.03, 0.02),
		"looks": [["wild_deer", 1.0]], "pronk": true,
		"gait": [1.6, 3.6], "flee": 7.6, "flush": 26.0, "alert": 55.0, "wander": 0.7},
	"raccoon": {"h": 0.3, "l": 0.42, "chest": 0.56, "cw": 0.1, "tuck": 0.42, "croup": -0.16,
		"neck": 0.24, "neck_r": 0.15, "neck_a": 22.0, "hl": 0.13, "sw": 0.052, "muzzle": 0.36, "mw": 0.48,
		"dome": 0.3, "stop": 0.32, "ear": ["prick_thick", 0.046, 0.05], "tail": ["brush", 0.25, 0.034],
		"tail_pose": [-30.0, 6.0], "leg": 0.075, "thigh": 1.2, "paw": 0.2, "coat": 0.04,
		"coat_mult": {"neck": 1.1, "head": 0.5, "leg": 0.4, "tail": 1.4, "belly": 1.0, "ear": 0.3},
		"cell": 0.0024, "eye_r": 0.0085, "eye": Color(0.03, 0.02, 0.015),
		"looks": [["wild_raccoon", 1.0]],
		"gait": [1.2, 2.6], "flee": 5.0, "flush": 6.0, "alert": 14.0, "wander": 0.55},
	"squirrel": {"h": 0.11, "l": 0.2, "chest": 0.55, "cw": 0.04, "tuck": 0.45, "croup": -0.24,
		"neck": 0.22, "neck_r": 0.17, "neck_a": 30.0, "hl": 0.058, "sw": 0.021, "muzzle": 0.34, "mw": 0.62,
		"dome": 0.42, "stop": 0.5, "ear": ["prick_thick", 0.02, 0.016], "tail": ["plume", 0.22, 0.02],
		"tail_pose": [72.0, 26.0], "leg": 0.08, "thigh": 1.2, "paw": 0.26, "coat": 0.012,
		"coat_mult": {"neck": 1.0, "head": 0.6, "leg": 0.5, "tail": 3.4, "belly": 1.0, "ear": 0.4},
		"cell": 0.0012, "eye_r": 0.0055, "eye": Color(0.02, 0.015, 0.012),
		"looks": [["wild_squirrel", 1.0]], "bound": true,
		"gait": [0.35, 0.7], "flee": 14.0, "flush": 4.5, "alert": 9.0, "wander": 0.45},
	"rabbit": {"h": 0.16, "l": 0.25, "chest": 0.6, "cw": 0.055, "tuck": 0.42, "croup": -0.3,
		"neck": 0.14, "neck_r": 0.22, "neck_a": 30.0, "hl": 0.08, "sw": 0.031, "muzzle": 0.3, "mw": 0.72,
		"dome": 0.42, "stop": 0.32, "ear": ["prick", 0.092, 0.036], "tail": ["erect", 0.045, 0.022],
		"tail_pose": [40.0, 10.0], "leg": 0.07, "thigh": 1.35, "paw": 0.34, "coat": 0.014,
		"coat_mult": {"neck": 1.0, "head": 0.55, "leg": 0.5, "tail": 2.4, "belly": 1.0, "ear": 0.25},
		"cell": 0.0013, "eye_r": 0.0085, "eye": Color(0.02, 0.012, 0.01),
		"looks": [["wild_rabbit", 1.0]], "bound": true,
		"gait": [0.4, 0.8], "flee": 15.0, "flush": 6.5, "alert": 13.0, "wander": 0.3},
}
const NAMES := ["coyote", "deer", "raccoon", "squirrel", "rabbit"]

## When each is about: [hour, activity 0..1] keys, wrapped round midnight. Coyotes at dusk and
## through the night, deer at dawn (and a little at dusk), raccoons deep in the night, squirrels
## through the day, rabbits morning and evening.
const ACTIVITY := {
	"coyote": [[0.0, 0.8], [4.5, 0.7], [6.5, 0.35], [8.0, 0.05], [17.0, 0.05], [18.5, 0.75], [20.0, 1.0], [24.0, 0.8]],
	"deer": [[0.0, 0.05], [4.8, 0.2], [5.8, 1.0], [7.6, 0.9], [9.0, 0.08], [17.5, 0.06], [18.8, 0.55], [20.5, 0.1], [24.0, 0.05]],
	"raccoon": [[0.0, 1.0], [4.5, 0.6], [5.5, 0.0], [19.8, 0.0], [21.0, 0.85], [24.0, 1.0]],
	"squirrel": [[0.0, 0.0], [6.4, 0.0], [7.5, 0.85], [11.0, 1.0], [15.0, 0.75], [18.0, 0.6], [19.2, 0.0], [24.0, 0.0]],
	"rabbit": [[0.0, 0.15], [5.0, 0.3], [6.2, 1.0], [9.5, 0.6], [12.0, 0.25], [16.5, 0.45], [18.5, 1.0], [20.5, 0.5], [24.0, 0.15]],
}

static var _antler_cache: Dictionary = {}
static var _antler_mat: StandardMaterial3D


static func has(name: String) -> bool:
	return SPECIES.has(name)


static func data(name: String) -> Dictionary:
	return SPECIES.get(name, SPECIES.coyote)


## How active `name` is at `hour` (0..1), from ACTIVITY.
static func activity(name: String, hour: float) -> float:
	var keys: Array = ACTIVITY.get(name, [])
	if keys.is_empty():
		return 0.0
	var h := fposmod(hour, 24.0)
	for i in range(1, keys.size()):
		var a: Array = keys[i - 1]
		var b: Array = keys[i]
		if h <= float(b[0]):
			var t := (h - float(a[0])) / maxf(float(b[0]) - float(a[0]), 1e-4)
			return lerpf(float(a[1]), float(b[1]), smoothstep(0.0, 1.0, t))
	return float(keys[-1][1])


## Every species' meshes (the loading screen, after the dogs').
static func warm() -> void:
	for name: String in NAMES:
		DogMesh.skin(name)
		for lv in 3:
			DogMesh.meshes(name, lv)
	antler_mesh(2, 0)
	antler_mesh(3, 1)


# --- antlers -------------------------------------------------------------------------------------

## A mule deer buck's antlers in the head's space (the head bone's rest at the origin, the deer
## facing -Z): each beam rises from its pedicle up, back and out, and forks twice - the
## dichotomous branching a mule deer's antlers have (a whitetail's tines grow off one beam) - into
## `points` tips a side (2 young, 3-4 mature), with a brow tine on the older ones. `level` 0 near,
## 1 far (fewer sides and rings).
static func antler_mesh(points: int, level: int) -> ArrayMesh:
	var key := "%d/%d" % [points, level]
	if _antler_cache.has(key):
		return _antler_cache[key]
	var j := DogMesh.joints("deer")
	var b := data("deer")
	var hd: Vector3 = j["head_dir"]
	var hl: float = b.hl
	var sides := 7 if level == 0 else 4
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in [-1.0, 1.0]:
		var base: Vector3 = hd * (hl * 0.3) + Vector3(s * float(b.sw) * 0.55, hl * 0.3, 0.0)
		var out := Vector3(s, 0.0, 0.0)
		# The main beam: up and back, then out and forward over the face.
		var beam := [base, base + Vector3(s * 0.05, 0.12, 0.05), base + Vector3(s * 0.15, 0.22, 0.06),
			base + Vector3(s * 0.24, 0.3, 0.0)]
		_branch(st, beam, 0.02, 0.013, sides, level)
		# The first fork: a back tine and a front one, each forking again.
		var fork: Vector3 = beam[2]
		var back := [fork, fork + Vector3(s * 0.05, 0.12, 0.06), fork + Vector3(s * 0.07, 0.24, 0.05)]
		_branch(st, back, 0.013, 0.006, sides, level)
		var front := [beam[3], beam[3] + Vector3(s * 0.04, 0.1, -0.07), beam[3] + Vector3(s * 0.03, 0.2, -0.11)]
		_branch(st, front, 0.012, 0.005, sides, level)
		if points >= 3:
			var mid: Vector3 = back[1]
			_branch(st, [mid, mid + Vector3(s * 0.02, 0.09, -0.05), mid + Vector3(s * 0.0, 0.17, -0.08)], 0.009, 0.004, sides, level)
		if points >= 4:
			var fm: Vector3 = front[1]
			_branch(st, [fm, fm + Vector3(s * 0.06, 0.08, 0.02), fm + Vector3(s * 0.1, 0.15, 0.02)], 0.008, 0.004, sides, level)
		if points >= 3:
			# The brow tine, short, forward over the eye.
			var bb: Vector3 = (beam[0] as Vector3).lerp(beam[1], 0.4)
			_branch(st, [bb, bb + out * 0.015 + Vector3(0.0, 0.04, -0.045)], 0.008, 0.003, sides, level)
		# The burr at the pedicle.
		_branch(st, [base - Vector3(0, 0.006, 0), base + Vector3(0, 0.012, 0)], 0.027, 0.024, sides, level)
	st.generate_normals()
	var m := st.commit()
	if _antler_mat == null:
		_antler_mat = StandardMaterial3D.new()
		_antler_mat.albedo_color = Color(0.36, 0.3, 0.23)
		_antler_mat.roughness = 0.72
		_antler_mat.vertex_color_use_as_albedo = true
	m.surface_set_material(0, _antler_mat)
	_antler_cache[key] = m
	return m


## A tapering tube along a Catmull-Rom through `pts`, `r0` at the root to `r1`, a pointed tip; the
## vertex colour pales toward the tip (the polished points over the darker, ridged beam).
static func _branch(st: SurfaceTool, pts: Array, r0: float, r1: float, sides: int, level: int) -> void:
	var rings := (3 if level == 0 else 2) * (pts.size() - 1)
	var ring_pts: Array = []
	for i in rings + 1:
		var t := float(i) / float(rings)
		var f := t * float(pts.size() - 1)
		var k := mini(int(f), pts.size() - 2)
		var u := f - float(k)
		var p0: Vector3 = pts[maxi(k - 1, 0)]
		var p1: Vector3 = pts[k]
		var p2: Vector3 = pts[k + 1]
		var p3: Vector3 = pts[mini(k + 2, pts.size() - 1)]
		ring_pts.append(DogMesh._cr3(p0, p1, p2, p3, u))
	for i in rings:
		var a: Vector3 = ring_pts[i]
		var bpt: Vector3 = ring_pts[i + 1]
		var ta := float(i) / float(rings)
		var tb := float(i + 1) / float(rings)
		var ra := lerpf(r0, r1, ta)
		var rb := lerpf(r0, r1, tb) if i + 1 < rings else 0.0006
		var d := (bpt - a).normalized()
		var x := d.cross(Vector3.FORWARD if absf(d.z) < 0.9 else Vector3.RIGHT).normalized()
		var y := d.cross(x)
		var ca := Color(0.78, 0.72, 0.64).lerp(Color(1.0, 0.96, 0.88), ta * ta)
		var cb := Color(0.78, 0.72, 0.64).lerp(Color(1.0, 0.96, 0.88), tb * tb)
		for k in sides:
			var a0 := TAU * float(k) / float(sides)
			var a1 := TAU * float(k + 1) / float(sides)
			var o0 := x * cos(a0) + y * sin(a0)
			var o1 := x * cos(a1) + y * sin(a1)
			var v00 := a + o0 * ra
			var v01 := a + o1 * ra
			var v10 := bpt + o0 * rb
			var v11 := bpt + o1 * rb
			for tri: Array in [[v00, ca, v10, cb, v11, cb], [v00, ca, v11, cb, v01, ca]]:
				for q in 3:
					st.set_color(tri[q * 2 + 1])
					st.add_vertex(tri[q * 2])
