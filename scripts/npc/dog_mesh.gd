class_name DogMesh
extends RefCounted
## The city's dogs, built in code at real size (GAME_PLAN G5 follow-up, VISUAL_ROADMAP dogs): six
## breeds by proportion - a labrador, a German shepherd, a small terrier, a chihuahua, a pit bull
## mix and a husky - each a skinned mesh on a 28-bone skeleton (DogRig poses it procedurally).
##
## The body is a loft along the topline and the underline (rows by z: top, bottom, half width and
## how much the chest narrows to its keel) from the rump over the croup, the ribs, the withers and
## the forechest up the neck to the poll; the head its own loft from the occiput to the nose (skull,
## stop, muzzle, nose leather; the lower muzzle on the jaw bone); legs are tubes down the joint
## chain (upper arm / thigh, forearm / gaskin, pastern / hock, a paw with pads on its own bone);
## ears are curved two-sided cards of five kinds (prick, bat, drop, button, rose); the tail is a
## tapering tube on four bones posed into each breed's carriage; eyes are wet spheres set into
## the head. Every vertex carries:
##   UV      the coat atlas (tools/dogs/make_dog_coats.py paints one per breed and colourway; the
##           chart is the same for every breed, so `S_*` landmarks are breed-agnostic)
##   UV2     metres over the surface, the fur strands' cells (dog_fur.gdshader)
##   TANGENT the way the hair lies (back along the body, down the legs, back from the nose, out
##           along the tail and the ears); the shells comb along it, and skinning turns it
##   COLOR   r part (PART_* / 8), g fur length factor (/ 2), b baked occlusion, a 1
##   CUSTOM0 x the shell layer (0 the skin, else 0..1 up the coat), yzw 0
## Fur is shells: the coat surfaces drawn again `SHELLS[level]` times, each lifted further along
## the normal, a strand cut-out in dog_fur.gdshader (the hill shells' technique on a skinned mesh).
##
## The dog faces -Z, up is +Y, its right is +X; the origin is on the ground under the middle of
## the body (between the front and hind paws). Rest pose: standing square; bones' rests are pure
## translations (identity bases), so the bind poses are plain offsets.

enum Level { NEAR, MID, FAR }

const PART_FUR := 0.0
const PART_NOSE := 1.0
const PART_EYE := 2.0
const PART_PAD := 3.0
const PART_EAR_IN := 4.0
const PART_LIP := 5.0
const PART_CLAW := 6.0

## Shell layers per level (FAR draws none: its skin material paints the coat's average).
const SHELLS := [10, 5, 0]
## Rings / around per piece and level.
const TORSO_RES := [[40, 24], [22, 14], [12, 9]]
const HEAD_RES := [[26, 20], [14, 12], [7, 7]]
const LEG_RES := [[16, 12], [9, 8], [5, 5]]
const PAW_RES := [[8, 12], [5, 8], [3, 5]]
const TAIL_RES := [[14, 10], [8, 7], [4, 4]]
const EAR_RES := [[10, 7], [6, 4], [3, 3]]
const EYE_RES := [[12, 10], [8, 6], [0, 0]]

## Coat atlas regions (fractions of the 1024 atlas; mirrored by tools/dogs/make_dog_coats.py).
const R_TORSO := Rect2(0.0, 0.0, 0.5, 0.5)
const R_HEAD := Rect2(0.5, 0.0, 0.5, 0.25)
const R_EAR_OUT := Rect2(0.5, 0.25, 0.125, 0.25)
const R_EAR_IN := Rect2(0.625, 0.25, 0.125, 0.25)
const R_TAIL := Rect2(0.75, 0.25, 0.25, 0.25)
const R_FRONT := Rect2(0.0, 0.5, 0.25, 0.5)
const R_HIND := Rect2(0.25, 0.5, 0.25, 0.5)
const R_PAW := Rect2(0.5, 0.5, 0.25, 0.125)
const R_EYE := Rect2(0.75, 0.5, 0.0625, 0.0625)

## The torso's control rows (the chart's v is the row index / TORSO_ROWS - 1): 0 rump, 1 buttock,
## 2 croup, 3 loin, 4 last rib, 5 ribs, 6 withers, 7 shoulder, 8 forechest, 9 neck base, 10-13 up
## the neck to the poll. The head's: 0 neck join, 1 occiput, 2 skull, 3 brow, 4 stop, 5 muzzle,
## 6 mid muzzle, 7 nose, 8 tip. Mirrored by the painter.
const TORSO_ROWS := 14
const HEAD_ROWS := 9
## Where the eye sits in the head chart (row, angle from the top in degrees).
const EYE_ROW := 3.3
const EYE_THETA := 62.0

## The bones: [name, parent].
const BONES := [
	["Pelvis", -1], ["Spine", 0], ["Chest", 1], ["Neck", 2], ["Head", 3], ["Jaw", 4], ["EarL", 4], ["EarR", 4],
	["Tail0", 0], ["Tail1", 8], ["Tail2", 9], ["Tail3", 10],
	["HumL", 2], ["RadL", 12], ["CarL", 13], ["PawL", 14],
	["HumR", 2], ["RadR", 16], ["CarR", 17], ["PawR", 18],
	["FemL", 0], ["TibL", 20], ["TarL", 21], ["HPawL", 22],
	["FemR", 0], ["TibR", 24], ["TarR", 25], ["HPawR", 26],
]
const B_PELVIS := 0
const B_SPINE := 1
const B_CHEST := 2
const B_NECK := 3
const B_HEAD := 4
const B_JAW := 5
const B_EAR := [6, 7]
const B_TAIL := [8, 9, 10, 11]
## [upper, lower, meta, paw] per leg: front left, front right, hind left, hind right.
const B_LEGS := [[12, 13, 14, 15], [16, 17, 18, 19], [20, 21, 22, 23], [24, 25, 26, 27]]

## The breeds. Lengths in metres: `h` withers height, `l` body length (point of shoulder to
## point of buttock), `chest` how deep the chest is (share of h from the withers to the
## brisket), `cw` half the chest's width, `tuck` the underline at the loin (share of h above the
## ground), `croup` how far the croup sits under the withers, `neck` / `neck_r` / `neck_a` its
## length (share of h), radius (share of h) and angle up from horizontal (degrees), `hl` head
## length, `sw` half the skull's width, `muzzle` the muzzle's share of the head, `mw` its width
## against the skull's, `dome` skull height (share of hl), `stop` how far the forehead drops to
## the muzzle, `ear` [kind, length, width], `tail` [kind, length, base radius], `leg` forearm
## radius (share of h), `thigh` thigh bulk, `paw` paw length (share of h), `coat` fur length,
## `coat_mult` fur length by region, `cell` a strand's cell (metres), `eye_r` eyeball radius,
## `eye` iris colour (linear), `looks` the coat textures it comes in with their odds.
const BREEDS := {
	"labrador": {"h": 0.57, "l": 0.64, "chest": 0.5, "cw": 0.135, "tuck": 0.56, "croup": 0.02,
		"neck": 0.33, "neck_r": 0.105, "neck_a": 40.0, "hl": 0.25, "sw": 0.072, "muzzle": 0.43, "mw": 0.66,
		"dome": 0.3, "stop": 0.55, "ear": ["drop", 0.11, 0.075], "tail": ["otter", 0.36, 0.032],
		"leg": 0.05, "thigh": 1.0, "paw": 0.15, "coat": 0.022,
		"coat_mult": {"neck": 1.1, "head": 0.4, "leg": 0.45, "tail": 1.0, "belly": 0.8, "ear": 0.22},
		"cell": 0.0024, "eye_r": 0.0125, "eye": Color(0.17, 0.07, 0.02),
		"looks": [["lab_yellow", 0.45], ["lab_black", 0.35], ["lab_chocolate", 0.2]]},
	"shepherd": {"h": 0.62, "l": 0.72, "chest": 0.52, "cw": 0.125, "tuck": 0.57, "croup": 0.07,
		"neck": 0.36, "neck_r": 0.1, "neck_a": 46.0, "hl": 0.26, "sw": 0.066, "muzzle": 0.5, "mw": 0.56,
		"dome": 0.27, "stop": 0.35, "ear": ["prick", 0.13, 0.085], "tail": ["sickle", 0.44, 0.03],
		"leg": 0.046, "thigh": 1.05, "paw": 0.15, "coat": 0.04,
		"coat_mult": {"neck": 1.45, "head": 0.3, "leg": 0.4, "tail": 1.9, "belly": 1.0, "ear": 0.22},
		"cell": 0.0024, "eye_r": 0.012, "eye": Color(0.13, 0.05, 0.01),
		"looks": [["shepherd", 0.75], ["shepherd_dark", 0.25]]},
	"terrier": {"h": 0.31, "l": 0.34, "chest": 0.5, "cw": 0.07, "tuck": 0.6, "croup": 0.0,
		"neck": 0.36, "neck_r": 0.12, "neck_a": 48.0, "hl": 0.15, "sw": 0.044, "muzzle": 0.42, "mw": 0.62,
		"dome": 0.3, "stop": 0.45, "ear": ["button", 0.06, 0.05], "tail": ["erect", 0.13, 0.018],
		"leg": 0.055, "thigh": 1.0, "paw": 0.15, "coat": 0.016,
		"coat_mult": {"neck": 1.0, "head": 0.7, "leg": 0.7, "tail": 0.9, "belly": 1.0, "ear": 0.22},
		"cell": 0.002, "eye_r": 0.009, "eye": Color(0.08, 0.035, 0.01),
		"looks": [["terrier_tan", 0.6], ["terrier_tricolor", 0.4]]},
	"chihuahua": {"h": 0.2, "l": 0.21, "chest": 0.47, "cw": 0.046, "tuck": 0.58, "croup": 0.0,
		"neck": 0.36, "neck_r": 0.13, "neck_a": 52.0, "hl": 0.095, "sw": 0.04, "muzzle": 0.3, "mw": 0.6,
		"dome": 0.48, "stop": 0.9, "ear": ["bat", 0.066, 0.05], "tail": ["sickle_up", 0.14, 0.012],
		"leg": 0.05, "thigh": 0.9, "paw": 0.14, "coat": 0.006,
		"coat_mult": {"neck": 1.0, "head": 0.6, "leg": 0.6, "tail": 1.0, "belly": 0.8, "ear": 0.22},
		"cell": 0.0012, "eye_r": 0.0105, "eye": Color(0.05, 0.022, 0.008),
		"looks": [["chihuahua_fawn", 0.6], ["chihuahua_blacktan", 0.4]]},
	"pitbull": {"h": 0.48, "l": 0.5, "chest": 0.54, "cw": 0.14, "tuck": 0.5, "croup": 0.01,
		"neck": 0.27, "neck_r": 0.125, "neck_a": 38.0, "hl": 0.22, "sw": 0.084, "muzzle": 0.4, "mw": 0.78,
		"dome": 0.3, "stop": 0.6, "ear": ["rose", 0.07, 0.06], "tail": ["whip", 0.28, 0.024],
		"leg": 0.056, "thigh": 1.3, "paw": 0.15, "coat": 0.006,
		"coat_mult": {"neck": 1.0, "head": 0.8, "leg": 0.8, "tail": 0.8, "belly": 0.8, "ear": 0.22},
		"cell": 0.0012, "eye_r": 0.0115, "eye": Color(0.16, 0.08, 0.02),
		"looks": [["pitbull_blue", 0.4], ["pitbull_brindle", 0.35], ["pitbull_white", 0.25]]},
	"husky": {"h": 0.56, "l": 0.6, "chest": 0.48, "cw": 0.12, "tuck": 0.58, "croup": 0.02,
		"neck": 0.34, "neck_r": 0.11, "neck_a": 44.0, "hl": 0.23, "sw": 0.068, "muzzle": 0.46, "mw": 0.56,
		"dome": 0.28, "stop": 0.4, "ear": ["prick_thick", 0.09, 0.07], "tail": ["plume", 0.4, 0.03],
		"leg": 0.046, "thigh": 1.0, "paw": 0.15, "coat": 0.05,
		"coat_mult": {"neck": 1.4, "head": 0.3, "leg": 0.35, "tail": 1.9, "belly": 0.9, "ear": 0.22},
		"cell": 0.0024, "eye_r": 0.0118, "eye": Color(0.18, 0.42, 0.75),
		"looks": [["husky_grey", 0.65], ["husky_red", 0.35]]},
}
## Breeds in the order the crowd rolls them, with their odds (the pavement's LA mix).
const BREED_ODDS := [["labrador", 0.24], ["pitbull", 0.2], ["chihuahua", 0.18], ["shepherd", 0.14], ["husky", 0.12], ["terrier", 0.12]]

const TEXTURE_DIR := "res://assets/textures/dogs/"

static var _cache: Dictionary = {}
static var _skins: Dictionary = {}
static var _joints: Dictionary = {}


static func breed(name: String) -> Dictionary:
	return BREEDS.get(name, BREEDS.labrador)


## A breed rolled from a 0..1 number (the crowd's pavement mix).
static func pick_breed(r: float) -> String:
	for row: Array in BREED_ODDS:
		if r < float(row[1]):
			return row[0]
		r -= float(row[1])
	return BREED_ODDS[0][0]


## A look (coat texture) of the breed rolled from a 0..1 number.
static func pick_look(name: String, r: float) -> String:
	var looks: Array = breed(name).looks
	for row: Array in looks:
		if r < float(row[1]):
			return row[0]
		r -= float(row[1])
	return looks[0][0]


## The rest pose's joints, model space (metres): every bone's head plus a few landmarks (`ball_*`,
## the toe tips, the nose, the poll's axis) the rig and the mesh agree on.
static func joints(name: String) -> Dictionary:
	if _joints.has(name):
		return _joints[name]
	var b := breed(name)
	var h: float = b.h
	var l: float = b.l
	var cw: float = b.cw
	var zf := -l * 0.5
	var zr := l * 0.5
	var j := {}
	j["Pelvis"] = Vector3(0.0, h * (0.74 - b.croup), zr - 0.2 * l)
	j["Spine"] = Vector3(0.0, h * (0.78 - b.croup * 0.5), 0.02 * l)
	j["Chest"] = Vector3(0.0, h * 0.76, zf + 0.24 * l)
	j["Neck"] = Vector3(0.0, h * 0.84, zf + 0.04 * l)
	var a := deg_to_rad(float(b.neck_a))
	var nl: float = b.neck * h
	j["Head"] = j["Neck"] + Vector3(0.0, sin(a) * nl, -cos(a) * nl)
	# The head's axis (occiput to nose), down a little from horizontal.
	var hd := Vector3(0.0, -0.17, -1.0).normalized()
	j["head_dir"] = hd
	var hl: float = b.hl
	j["Jaw"] = j["Head"] + hd * (hl * 0.32) + Vector3(0.0, -hl * 0.2, 0.0)
	j["nose"] = j["Head"] + hd * (hl * 0.92) + Vector3(0.0, -hl * 0.02, 0.0)
	for s in [-1.0, 1.0]:
		var sl := "L" if s < 0.0 else "R"
		var ex: Vector3 = j["Head"] + hd * (hl * 0.22) + Vector3(s * b.sw * 0.62, hl * 0.22, 0.0)
		j["Ear" + sl] = ex
		# Front leg: point of shoulder, elbow, carpus, the ball of the foot, the toes.
		var x: float = s * cw * 0.72
		var sh := Vector3(x, h * 0.6, zf + 0.07 * l)
		var el := Vector3(x * 0.95, h * 0.45, sh.z + 0.1 * h)
		var ca := Vector3(x * 0.9, h * 0.13, el.z - 0.02 * h)
		var ba := Vector3(x * 0.9, h * 0.042, ca.z - 0.045 * h)
		j["Hum" + sl] = sh
		j["Rad" + sl] = el
		j["Car" + sl] = ca
		j["Paw" + sl] = ba
		j["toe" + sl] = ba + Vector3(0.0, -h * 0.03, -h * float(b.paw) * 0.8)
		# Hind leg: hip joint, stifle, hock, the ball of the foot.
		var hx: float = s * cw * 0.66
		var hp := Vector3(hx, j["Pelvis"].y - h * 0.08, j["Pelvis"].z + 0.02 * l)
		var st := Vector3(hx * 1.05, h * 0.37, hp.z - 0.13 * h)
		var ho := Vector3(hx, h * 0.2, hp.z + 0.14 * h)
		var hb := Vector3(hx, h * 0.042, ho.z - 0.005 * h)
		j["Fem" + sl] = hp
		j["Tib" + sl] = st
		j["Tar" + sl] = ho
		j["HPaw" + sl] = hb
		j["htoe" + sl] = hb + Vector3(0.0, -h * 0.03, -h * float(b.paw) * 0.75)
	var tb := Vector3(0.0, h * (0.86 - b.croup), zr - 0.02 * l)
	var tl: float = b.tail[1]
	for i in 4:
		j["Tail%d" % i] = tb + Vector3(0.0, 0.0, tl * 0.25 * i)
	j["tail_tip"] = tb + Vector3(0.0, 0.0, tl)
	_joints[name] = j
	return j


## The skeleton's rest (bone index -> model-space joint).
static func rest_positions(name: String) -> PackedVector3Array:
	var j := joints(name)
	var out := PackedVector3Array()
	for row: Array in BONES:
		out.append(j[row[0]])
	return out


## A Skeleton3D in the breed's rest pose (rests are translations from the parent's joint).
static func make_skeleton(name: String) -> Skeleton3D:
	var sk := Skeleton3D.new()
	var rest := rest_positions(name)
	for i in BONES.size():
		var row: Array = BONES[i]
		sk.add_bone(row[0])
		var p: int = row[1]
		if p >= 0:
			sk.set_bone_parent(i, p)
		var off: Vector3 = rest[i] - (rest[p] if p >= 0 else Vector3.ZERO)
		sk.set_bone_rest(i, Transform3D(Basis(), off))
		sk.set_bone_pose_position(i, off)
	return sk


static func skin(name: String) -> Skin:
	if _skins.has(name):
		return _skins[name]
	var s := Skin.new()
	var rest := rest_positions(name)
	for i in BONES.size():
		s.add_bind(i, Transform3D(Basis(), -rest[i]))
	_skins[name] = s
	return s


## [skin mesh, shells mesh or null] for the breed at a level.
static func meshes(name: String, level: int) -> Array:
	var key := "%s/%d" % [name, level]
	if _cache.has(key):
		return _cache[key]
	var bld := Builder.new(name, level)
	bld.build()
	var out := [bld.commit_skin(), bld.commit_shells(SHELLS[level])]
	_cache[key] = out
	return out


## Builds every breed's meshes, skins and skeleton tables (the loading screen).
static func warm() -> void:
	for name: String in BREEDS:
		skin(name)
		for lv in 3:
			meshes(name, lv)


static func triangle_count(name: String, level: int) -> Vector2i:
	var m: Array = meshes(name, level)
	var a := 0
	var b := 0
	var skin_mesh: ArrayMesh = m[0]
	for s in skin_mesh.get_surface_count():
		a += skin_mesh.surface_get_array_index_len(s) / 3
	if m[1] != null:
		var sh: ArrayMesh = m[1]
		for s in sh.get_surface_count():
			b += sh.surface_get_array_index_len(s) / 3
	return Vector2i(a, b)


static func _uv(r: Rect2, u: float, v: float) -> Vector2:
	return Vector2(r.position.x + clampf(u, 0.0, 1.0) * r.size.x, r.position.y + clampf(v, 0.0, 1.0) * r.size.y)


static func _cr(p0: float, p1: float, p2: float, p3: float, t: float) -> float:
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t)


static func _cr3(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	return Vector3(_cr(p0.x, p1.x, p2.x, p3.x, t), _cr(p0.y, p1.y, p2.y, p3.y, t), _cr(p0.z, p1.z, p2.z, p3.z, t))


class Builder:
	var name: String
	var b: Dictionary
	var j: Dictionary
	var level: int
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var outs := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var flows := PackedVector3Array()
	var cols := PackedColorArray()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var piece := PackedInt32Array()
	var idx := PackedInt32Array()
	var _piece := 0
	var _torso_rows: Array = []
	var _head_rows: Array = []

	func _init(breed_name: String, lv: int) -> void:
		name = breed_name
		b = DogMesh.breed(breed_name)
		j = DogMesh.joints(breed_name)
		level = lv

	func build() -> void:
		_torso()
		_head()
		for s in [-1.0, 1.0]:
			_front_leg(s)
			_hind_leg(s)
			_ear(s)
			if level != Level.FAR:
				_eye(s)
		_tail()
		_smooth_normals()

	func coat_len(region: String) -> float:
		return float(b.coat) * float((b.coat_mult as Dictionary).get(region, 1.0))

	# --- vertices ----------------------------------------------------------------------------

	## A vertex: position, an outward reference (for winding), coat UV, metric UV2, the hair's
	## flow, part, fur length (metres), occlusion, and up to four [bone, weight] pairs.
	func add(p: Vector3, out: Vector3, uv: Vector2, uv2: Vector2, flow: Vector3, part: float, fur: float, ao: float, bw: Array) -> int:
		verts.append(p)
		outs.append(out.normalized() if out.length_squared() > 1e-12 else Vector3.UP)
		norms.append(Vector3.ZERO)
		uvs.append(uv)
		uv2s.append(uv2)
		flows.append(flow)
		cols.append(Color(part / 8.0, clampf(fur / maxf(float(b.coat), 1e-4) * 0.5, 0.0, 1.0) if part == PART_FUR or part == PART_EAR_IN else 0.0, clampf(ao, 0.0, 1.0), 1.0))
		piece.append(_piece)
		# Normalise the weights, keep the four largest.
		var pairs := bw.duplicate()
		pairs.sort_custom(func(x, y): return float(x[1]) > float(y[1]))
		var tot := 0.0
		for k in mini(pairs.size(), 4):
			tot += float(pairs[k][1])
		for k in 4:
			if k < pairs.size() and tot > 0.0:
				bones.append(int(pairs[k][0]))
				weights.append(float(pairs[k][1]) / tot)
			else:
				bones.append(0)
				weights.append(0.0)
		return verts.size() - 1

	func tri(a: int, c: int, d: int) -> void:
		# Godot's front faces wind clockwise seen from the front; face the outward reference.
		var fn := (verts[c] - verts[a]).cross(verts[d] - verts[a])
		if fn.dot(outs[a] + outs[c] + outs[d]) > 0.0:
			idx.append_array([a, d, c])
		else:
			idx.append_array([a, c, d])

	func grid(base: int, rows: int, around: int, closed_end := false) -> void:
		for r in rows - 1:
			for k in around:
				var a := base + r * (around + 1) + k
				tri(a, a + around + 1, a + 1)
				tri(a + 1, a + around + 1, a + around + 2)

	## Caps a ring (its `around` + 1 vertices from `start`) with a fan to a centre vertex.
	func cap(start: int, around: int, centre: Vector3, out: Vector3, uv: Vector2, part: float, fur: float, bw: Array, flow: Vector3) -> void:
		var c := add(centre, out, uv, uv2s[start], flow, part, fur, cols[start].b, bw)
		for k in around:
			tri(start + k, start + k + 1, c)

	# --- torso -------------------------------------------------------------------------------

	## The torso's control rows: [z, top y, bottom y, half width, keel (bottom narrowing 0..1)].
	func torso_controls() -> Array:
		var h: float = b.h
		var l: float = b.l
		var cw: float = b.cw
		var zf := -l * 0.5
		var zr := l * 0.5
		var cr: float = b.croup
		var brisket := h * (1.0 - float(b.chest))
		var tuck: float = b.tuck * h
		var rows: Array = [
			[zr + 0.035 * l, h * (0.84 - cr), h * (0.72 - cr), cw * 0.28, 0.9],
			[zr, h * (0.92 - cr), h * (0.56 - cr), cw * 0.62 * float(b.thigh), 0.85],
			[zr - 0.1 * l, h * (0.95 - cr), h * 0.52, cw * 0.82 * sqrt(float(b.thigh)), 0.85],
			[zr - 0.26 * l, h * (0.955 - cr * 0.7), tuck, cw * 0.74, 0.8],
			[0.06 * l, h * (0.97 - cr * 0.4), lerpf(tuck, brisket, 0.55), cw * 0.9, 0.62],
			[zf + 0.36 * l, h * 0.985, brisket, cw * 1.0, 0.45],
			[zf + 0.2 * l, h * 1.0, brisket + 0.01 * h, cw * 1.0, 0.42],
			[zf + 0.07 * l, h * 0.95, brisket + 0.05 * h, cw * 0.96, 0.5],
			[zf - 0.01 * l, h * 0.92, h * 0.6, cw * 0.78, 0.6],
		]
		# The neck: from its base (in front of the withers) up to the poll.
		var nb: Vector3 = j["Neck"]
		var hd: Vector3 = j["Head"]
		var nr: float = b.neck_r * h
		var a := deg_to_rad(float(b.neck_a))
		var vr := nr / maxf(cos(a), 0.35)
		var base_c := Vector3(0.0, h * 0.82, zf - 0.075 * h)
		rows.append([base_c.z, base_c.y + vr * 1.25, base_c.y - vr * 1.2, nr * 1.25, 0.7])
		for t in [0.36, 0.7, 1.0, 1.13]:
			var c := base_c.lerp(hd + Vector3(0.0, -nr * 0.15, 0.0), t)
			var shrink := lerpf(1.08, 0.9, t)
			rows.append([c.z, c.y + vr * shrink, c.y - vr * shrink * lerpf(1.1, 1.0, t), nr * shrink, 0.75])
		return rows

	func _torso() -> void:
		_piece += 1
		var ctl := torso_controls()
		_torso_rows = ctl
		var n := ctl.size()
		var res: Array = TORSO_RES[level]
		var rings: int = res[0]
		var around: int = res[1]
		var base := verts.size()
		var h: float = b.h
		var along := 0.0
		var prev_c := Vector3.INF
		for r in rings + 1:
			var s := float(r) / float(rings) * float(n - 1)
			var i := mini(int(s), n - 2)
			var t := s - float(i)
			var p0: Array = ctl[maxi(i - 1, 0)]
			var p1: Array = ctl[i]
			var p2: Array = ctl[i + 1]
			var p3: Array = ctl[mini(i + 2, n - 1)]
			var row: Array = []
			for k in 5:
				row.append(DogMesh._cr(p0[k], p1[k], p2[k], p3[k], t))
			var z: float = row[0]
			var top: float = row[1]
			var bot: float = row[2]
			var w: float = maxf(row[3], 0.004)
			var keel: float = row[4]
			var mid := (top + bot) * 0.5
			var hh := maxf((top - bot) * 0.5, 0.004)
			var centre := Vector3(0.0, mid, z)
			if prev_c != Vector3.INF:
				along += prev_c.distance_to(centre)
			prev_c = centre
			var v := s / float(n - 1)
			var neck_w := smoothstep(8.5, 10.5, s)
			for k in around + 1:
				var th := TAU * float(k) / float(around)
				var st := sin(th)
				var ct := cos(th)
				# A squarer section over the back, the keel narrowing toward the brisket.
				var e := 2.0 / lerpf(2.7, 2.1, neck_w)
				var sx := signf(st) * pow(absf(st), e)
				var cy := signf(ct) * pow(absf(ct), e)
				var narrow := lerpf(1.0, 1.0 - keel * 0.55, smoothstep(0.25, -0.95, ct))
				var p := Vector3(sx * w * narrow, mid + cy * hh, z)
				var out := Vector3(sx / w, cy / hh, 0.0)
				# The ends close: lean the outward reference along z there.
				if s < 0.6:
					out.z += (0.6 - s) * 3.0 / maxf(w, hh)
				if s > float(n - 1) - 0.3:
					out.z -= 2.0 / maxf(w, hh)
				var u := (th / PI) if th <= PI else (2.0 - th / PI)
				var uv := DogMesh._uv(DogMesh.R_TORSO, u, v)
				var uv2 := Vector2(along, th * (w + hh) * 0.5)
				# The hair: back along the body, down the flanks, down and back on the neck.
				var flow := Vector3(0.0, -absf(sx) * 0.7 - 0.25, 1.0)
				if neck_w > 0.0:
					flow = flow.lerp(Vector3(0.0, -1.0, 0.45), neck_w * 0.8)
				# Fur by region: the neck's ruff, a shorter coat on the belly.
				var belly := smoothstep(-0.2, -0.9, cy) * (1.0 - neck_w)
				var fur := lerpf(coat_len("body"), coat_len("neck"), neck_w)
				fur = lerpf(fur, coat_len("belly"), belly)
				# Occlusion: under the belly and between the legs, the armpits and the groin.
				var ao := 1.0 - 0.35 * smoothstep(-0.3, -1.0, cy) * (1.0 - neck_w)
				var bw := _torso_weights(s, p)
				add(p, out, uv, uv2, flow, PART_FUR, fur, ao, bw)
		grid(base, rings + 1, around)
		# The rump's cap (under the tail).
		var last_rear := base
		var rc := verts[last_rear]
		var cc := Vector3(0.0, (verts[base].y + verts[base + around / 2].y) * 0.5, verts[base].z + 0.01 * h)
		cap(last_rear, around, cc, Vector3(0, 0, 1), DogMesh._uv(DogMesh.R_TORSO, 0.5, 0.0), PART_FUR, coat_len("body"), [[B_PELVIS, 1.0]], Vector3(0, -1, 0.3))
		# The neck's end is inside the head; leave it open.
		var _unused := rc

	func _torso_weights(s: float, p: Vector3) -> Array:
		var bw: Array = []
		var add_w := func(bone: int, w: float) -> void:
			if w > 0.001:
				bw.append([bone, w])
		var pelvis := 1.0 - smoothstep(2.2, 4.3, s)
		var spine := smoothstep(2.2, 4.3, s) * (1.0 - smoothstep(4.6, 6.4, s))
		var chest := smoothstep(4.6, 6.4, s) * (1.0 - smoothstep(8.6, 10.2, s))
		var neck := smoothstep(8.6, 10.2, s) * (1.0 - smoothstep(11.8, 12.9, s))
		var head := smoothstep(11.8, 12.9, s)
		add_w.call(B_PELVIS, pelvis)
		add_w.call(B_SPINE, spine)
		add_w.call(B_CHEST, chest)
		add_w.call(B_NECK, neck)
		add_w.call(B_HEAD, head)
		# The skin over the shoulder and the thigh follows the leg a little.
		var h: float = b.h
		for li in 4:
			var leg: Array = B_LEGS[li]
			var jn: Vector3 = j[BONES[leg[0]][0]]
			if signf(p.x) != signf(jn.x):
				continue
			var reach := h * (0.2 if li < 2 else 0.24)
			var d := Vector2(p.y - jn.y, p.z - jn.z).length()
			var side := smoothstep(0.2, 0.75, absf(p.x) / maxf(absf(jn.x) * 1.4, 1e-3))
			var below := smoothstep(jn.y + h * 0.12, jn.y - h * 0.1, p.y)
			var w := (1.0 - smoothstep(reach * 0.3, reach, d)) * side * below * 0.85
			add_w.call(leg[0], w)
		return bw

	# --- head --------------------------------------------------------------------------------

	## Head rows in the head's frame: [along (share of hl), drop (share of hl), up, down (share of
	## hl), half width (share of the skull's)].
	func head_controls() -> Array:
		var m: float = b.muzzle
		var dome: float = b.dome
		var stop: float = b.stop
		var mw: float = b.mw
		var ms := 1.0 - m
		return [
			[-0.12, -0.08, 0.22, 0.34, 0.95],
			[0.0, 0.0, dome * 0.95, 0.3, 1.0],
			[ms * 0.42, 0.0, dome * 1.05, 0.3, 1.07],
			[ms * 0.82, 0.02, dome * 0.92, 0.27, 0.92],
			[ms + 0.02, 0.06 + stop * 0.06, dome * (0.62 - stop * 0.25), 0.25, lerpf(0.86, mw, 0.5)],
			[ms + m * 0.3, 0.1 + stop * 0.05, 0.13, 0.21, mw],
			[ms + m * 0.62, 0.11 + stop * 0.04, 0.11, 0.18, mw * 0.9],
			[ms + m * 0.88, 0.1 + stop * 0.04, 0.095, 0.13, mw * 0.74],
			[1.0, 0.11 + stop * 0.04, 0.035, 0.06, mw * 0.36],
		]

	## A point of the head loft at row parameter s (0..HEAD_ROWS-1) and angle th (0 top).
	func head_point(s: float, th: float, ctl: Array) -> Array:
		var n := ctl.size()
		var i := mini(int(s), n - 2)
		var t := s - float(i)
		var p0: Array = ctl[maxi(i - 1, 0)]
		var p1: Array = ctl[i]
		var p2: Array = ctl[i + 1]
		var p3: Array = ctl[mini(i + 2, n - 1)]
		var row: Array = []
		for k in 5:
			row.append(DogMesh._cr(p0[k], p1[k], p2[k], p3[k], t))
		var hl: float = b.hl
		var sw: float = b.sw
		var hd: Vector3 = j["head_dir"]
		var up := Vector3.RIGHT.cross(hd).normalized() * -1.0
		if up.y < 0.0:
			up = -up
		var c: Vector3 = j["Head"] + hd * (float(row[0]) * hl) - up * (float(row[1]) * hl)
		var ct := cos(th)
		var st := sin(th)
		var r_v: float = (float(row[2]) if ct >= 0.0 else float(row[3])) * hl
		var w: float = float(row[4]) * sw
		# Cheeks: the lower half bulges out on the skull, flat sides on the muzzle.
		var e := 2.0 / 2.25
		var sx := signf(st) * pow(absf(st), e)
		var cy := signf(ct) * pow(absf(ct), e)
		var p := c + Vector3(sx * w, 0.0, 0.0) + up * (cy * r_v)
		var out := Vector3(sx / maxf(w, 1e-4), 0.0, 0.0) + up * (cy / maxf(r_v, 1e-4))
		return [p, out, row]

	func _head() -> void:
		_piece += 1
		var ctl := head_controls()
		_head_rows = ctl
		var n := ctl.size()
		var res: Array = HEAD_RES[level]
		var rings: int = res[0]
		var around: int = res[1]
		var base := verts.size()
		var hd: Vector3 = j["head_dir"]
		var along := 0.0
		var prev := Vector3.INF
		var muzzle_s := 4.6
		for r in rings + 1:
			# Denser toward the nose, where the shape turns fastest.
			var tt := float(r) / float(rings)
			var s := lerpf(tt, 1.0 - pow(1.0 - tt, 1.5), 0.45) * float(n - 1)
			var cpt: Array = head_point(s, 0.0, ctl)
			var cdn: Array = head_point(s, PI, ctl)
			var centre: Vector3 = ((cpt[0] as Vector3) + (cdn[0] as Vector3)) * 0.5
			if prev != Vector3.INF:
				along += prev.distance_to(centre)
			prev = centre
			var v := s / float(n - 1)
			for k in around + 1:
				var th := TAU * float(k) / float(around)
				var hp: Array = head_point(s, th, ctl)
				var p: Vector3 = hp[0]
				var out: Vector3 = hp[1]
				if s < 0.3:
					out += hd * -2.0 / float(b.hl)
				if s > float(n - 1) - 0.25:
					out += hd * 3.0 / float(b.hl)
				var u := (th / PI) if th <= PI else (2.0 - th / PI)
				var uv := DogMesh._uv(DogMesh.R_HEAD, u, v)
				var uv2 := Vector2(along, th * float(b.sw))
				var ct := cos(th)
				# The nose leather: the last rows, above the mouth.
				var nose := s > float(n - 1) - 0.62 and ct > -0.35
				var part := PART_NOSE if nose else PART_FUR
				# The lip line: where the upper lip meets the lower jaw along the muzzle.
				var jaw_side := ct < -0.32 and s > muzzle_s - 1.2
				if jaw_side and absf(ct + 0.42) < 0.12 and s > muzzle_s - 0.6:
					part = PART_LIP
				var hair := (-hd + Vector3(0.0, -0.6 * absf(sin(th)), 0.0)).normalized()
				var fur := coat_len("head") * lerpf(1.0, 0.45, smoothstep(muzzle_s - 1.0, float(n - 1), s))
				if s < 1.2:
					fur = lerpf(coat_len("neck"), fur, smoothstep(0.0, 1.2, s))
				var ao := 1.0 - 0.3 * smoothstep(-0.2, -0.9, ct) * smoothstep(muzzle_s - 1.5, muzzle_s, s)
				var jaw := 0.0
				if jaw_side:
					jaw = smoothstep(-0.3, -0.55, ct) * smoothstep(muzzle_s - 1.6, muzzle_s - 0.4, s)
				var neckw := 1.0 - smoothstep(0.0, 0.9, s)
				var bw: Array = [[B_HEAD, 1.0 - jaw - neckw * 0.5]]
				if jaw > 0.0:
					bw.append([B_JAW, jaw])
				if neckw > 0.0:
					bw.append([B_NECK, neckw * 0.5])
				add(p, out, uv, uv2, hair, part, fur if part == PART_FUR else 0.0, ao, bw)
		grid(base, rings + 1, around)
		# Close the nose tip.
		var last := base + rings * (around + 1)
		var tip: Vector3 = j["Head"] + hd * float(b.hl) * 1.004
		var tip_c := Vector3.ZERO
		for k in around:
			tip_c += verts[last + k]
		tip_c /= float(around)
		cap(last, around, tip_c + hd * float(b.hl) * 0.012, hd, DogMesh._uv(DogMesh.R_HEAD, 0.3, 1.0), PART_NOSE, 0.0, [[B_HEAD, 1.0]], -hd)
		var _t := tip

	# --- eyes --------------------------------------------------------------------------------

	func eye_centre(s: float) -> Array:
		var hp: Array = head_point(DogMesh.EYE_ROW, deg_to_rad(DogMesh.EYE_THETA) * (1.0 if s > 0.0 else -1.0), head_controls())
		var p: Vector3 = hp[0]
		var out: Vector3 = (hp[1] as Vector3).normalized()
		# Look forward more than the head's side does.
		var hd: Vector3 = j["head_dir"]
		var look := (out * 0.55 + hd * 0.85).normalized()
		var r: float = b.eye_r
		return [p - out * r * 0.48, look, r]

	func _eye(s: float) -> void:
		_piece += 1
		var ec := eye_centre(s)
		var c: Vector3 = ec[0]
		var look: Vector3 = ec[1]
		var r: float = ec[2]
		var res: Array = EYE_RES[level]
		var rings: int = res[0]
		var around: int = res[1]
		var side := look.cross(Vector3.UP).normalized()
		var upv := side.cross(look).normalized()
		var base := verts.size()
		for i in rings + 1:
			var a := PI * float(i) / float(rings) # 0 at the front pole
			for k in around + 1:
				var t := TAU * float(k) / float(around)
				var d := look * cos(a) + (side * cos(t) + upv * sin(t)) * sin(a)
				var uv := DogMesh._uv(DogMesh.R_EYE, 0.5 + 0.5 * sin(a) * cos(t), 0.5 + 0.5 * sin(a) * sin(t))
				add(c + d * r, d, uv, Vector2(a, t), look, PART_EYE, 0.0, 1.0, [[B_HEAD, 1.0]])
		grid(base, rings + 1, around)

	# --- ears --------------------------------------------------------------------------------

	func _ear(s: float) -> void:
		_piece += 1
		var kind: String = b.ear[0]
		var el: float = b.ear[1]
		var ew: float = b.ear[2]
		var res: Array = EAR_RES[level]
		var rows: int = res[0]
		var across: int = res[1]
		var root: Vector3 = j["Ear" + ("L" if s < 0.0 else "R")]
		var hd: Vector3 = j["head_dir"]
		var fwd := Vector3(hd.x, 0.0, hd.z).normalized()
		var outx := Vector3(s, 0.0, 0.0)
		# The ear's centre line from base to tip, and its across direction, per kind.
		var pts: Array = []
		var acr: Array = []
		var cup := 0.25
		var thick := clampf(el * 0.06, 0.0025, 0.007)
		match kind:
			"prick", "prick_thick":
				var dir := (Vector3.UP * 1.0 + outx * 0.32 + fwd * 0.12).normalized()
				for i in 4:
					pts.append(root + dir * el * float(i) / 3.0 + fwd * (-0.05 * el * float(i) / 3.0))
				acr = [fwd, fwd, fwd, fwd]
				cup = 0.45
				if kind == "prick_thick":
					thick *= 1.8
			"bat":
				var dir := (Vector3.UP * 0.8 + outx * 0.62 + fwd * 0.08).normalized()
				for i in 4:
					pts.append(root + dir * el * float(i) / 3.0)
				acr = [fwd, fwd, fwd, fwd]
				cup = 0.5
			"drop":
				var a0 := root + outx * el * 0.08 + Vector3.UP * el * 0.05
				var a1 := root + outx * el * 0.24 - Vector3.UP * el * 0.12 + fwd * el * 0.06
				var a2 := root + outx * el * 0.3 - Vector3.UP * el * 0.55 + fwd * el * 0.1
				var a3 := root + outx * el * 0.27 - Vector3.UP * el * 0.95 + fwd * el * 0.12
				pts = [root, a0, a1, a2, a3]
				acr = [fwd, fwd, fwd, fwd, fwd]
				cup = 0.12
			"button":
				var a0 := root + Vector3.UP * el * 0.32 + outx * el * 0.12
				var a1 := root + Vector3.UP * el * 0.48 + outx * el * 0.22 + fwd * el * 0.2
				var a2 := root + Vector3.UP * el * 0.2 + outx * el * 0.3 + fwd * el * 0.55
				pts = [root, a0, a1, a2]
				acr = [fwd, fwd, (fwd + Vector3.UP * 0.4).normalized(), (fwd * 0.3 + Vector3.UP).normalized()]
				cup = 0.15
			_: # rose: small, folded back along the skull
				var a0 := root + Vector3.UP * el * 0.3 + outx * el * 0.18
				var a1 := root + Vector3.UP * el * 0.42 + outx * el * 0.42 - fwd * el * 0.3
				var a2 := root + Vector3.UP * el * 0.25 + outx * el * 0.5 - fwd * el * 0.75
				pts = [root, a0, a1, a2]
				acr = [fwd, fwd, (fwd - Vector3.UP * 0.3).normalized(), (outx + Vector3.UP * 0.5).normalized()]
				cup = 0.2
		var n := pts.size()
		var face_out := outx
		var base := verts.size()
		var bear: int = B_EAR[0 if s < 0.0 else 1]
		var pointed := kind != "drop"
		for side_i in 2:
			var sign_f := 1.0 if side_i == 0 else -1.0
			for i in rows + 1:
				var t := float(i) / float(rows)
				var st := t * float(n - 1)
				var ii := mini(int(st), n - 2)
				var ft := st - float(ii)
				var c := DogMesh._cr3(pts[maxi(ii - 1, 0)], pts[ii], pts[ii + 1], pts[mini(ii + 2, n - 1)], ft)
				var c2 := DogMesh._cr3(pts[maxi(ii - 1, 0)], pts[ii], pts[ii + 1], pts[mini(ii + 2, n - 1)], minf(ft + 0.05, 1.0))
				var along := (c2 - c)
				if along.length_squared() < 1e-12:
					along = (pts[n - 1] - pts[0])
				along = along.normalized()
				var a_dir: Vector3 = (acr[ii] as Vector3).lerp(acr[ii + 1], ft).normalized()
				a_dir = (a_dir - along * along.dot(a_dir)).normalized()
				var nrm := along.cross(a_dir).normalized()
				if nrm.dot(face_out + Vector3.UP * 0.2 - fwd * 0.6) < 0.0:
					nrm = -nrm
				var width := ew * 0.5 * (pow(1.0 - t, 0.85) if pointed else sqrt(maxf(1.0 - pow(t, 3.0), 0.0)) * (0.8 + 0.25 * sin(t * PI)))
				width = maxf(width, 0.0004)
				for k in across + 1:
					var q := float(k) / float(across) * 2.0 - 1.0
					var bend := (q * q - 0.35) * width * cup
					var p := c + a_dir * q * width + nrm * (bend + sign_f * thick * 0.5 * (1.0 - t * 0.6))
					var o := nrm * sign_f
					var uvr := DogMesh.R_EAR_OUT if side_i == 0 else DogMesh.R_EAR_IN
					var uv := DogMesh._uv(uvr, (q + 1.0) * 0.5, t)
					var part := PART_FUR if side_i == 0 else PART_EAR_IN
					var fur := coat_len("ear") * (1.0 if side_i == 0 else 0.4)
					var bw: Array = [[bear, smoothstep(0.0, 0.25, t) * 0.8 + 0.2], [B_HEAD, 1.0 - (smoothstep(0.0, 0.25, t) * 0.8 + 0.2)]]
					add(p, o, uv, Vector2(t * el, q * width), along, part, fur, 1.0 - 0.25 * float(side_i), bw)
		var per := (rows + 1) * (across + 1)
		for side_i in 2:
			var sb := base + side_i * per
			for i in rows:
				for k in across:
					var a := sb + i * (across + 1) + k
					tri(a, a + across + 1, a + 1)
					tri(a + 1, a + across + 1, a + across + 2)
		# The rim between the two faces.
		for i in rows:
			for edge in [0, across]:
				var a: int = base + i * (across + 1) + edge
				var c2: int = a + across + 1
				var a2: int = a + per
				var c3: int = c2 + per
				var mid := (verts[a] + verts[c2]) * 0.5
				var o := (mid - (verts[base + i * (across + 1) + across / 2])).normalized()
				outs[a] = (outs[a] + o).normalized()
				tri(a, c2, a2)
				tri(a2, c2, c3)

	# --- legs --------------------------------------------------------------------------------

	## A tube down a joint chain: `pts` the centre line, `rad` [front-back, side] radii at each
	## point, `seg_bones` the bone of each point-to-point segment (and the one above the first),
	## `rect` its chart. Returns the index of its first vertex and its rings / around.
	func _tube(pts: Array, rad: Array, seg_bones: Array, rect: Rect2, s_side: float, fur_top: float, fur_bot: float, flow_down: bool, bulge: Array = []) -> Array:
		var res: Array = LEG_RES[level]
		var rings: int = res[0]
		var around: int = res[1]
		var n := pts.size()
		var base := verts.size()
		var along := 0.0
		var prev := Vector3.INF
		for r in rings + 1:
			var tt := float(r) / float(rings)
			var st := tt * float(n - 1)
			var i := mini(int(st), n - 2)
			var t := st - float(i)
			var c := DogMesh._cr3(pts[maxi(i - 1, 0)], pts[i], pts[i + 1], pts[mini(i + 2, n - 1)], t)
			var c2 := DogMesh._cr3(pts[maxi(i - 1, 0)], pts[i], pts[i + 1], pts[mini(i + 2, n - 1)], minf(t + 0.04, 1.0))
			var c0 := DogMesh._cr3(pts[maxi(i - 1, 0)], pts[i], pts[i + 1], pts[mini(i + 2, n - 1)], maxf(t - 0.04, 0.0))
			var dir := (c2 - c0)
			if dir.length_squared() < 1e-12:
				dir = (pts[i + 1] as Vector3) - (pts[i] as Vector3)
			dir = dir.normalized()
			var side := Vector3.RIGHT
			var fwd := side.cross(dir).normalized() # toward -Z for a downward leg
			if fwd.z > 0.0:
				fwd = -fwd
			side = dir.cross(fwd).normalized()
			if side.x < 0.0:
				side = -side
			var ra: Vector2 = (rad[i] as Vector2).lerp(rad[i + 1], smoothstep(0.0, 1.0, t))
			var bl := 0.0
			if not bulge.is_empty():
				bl = lerpf(bulge[i], bulge[i + 1], t)
			if prev != Vector3.INF:
				along += prev.distance_to(c)
			prev = c
			for k in around + 1:
				var th := TAU * float(k) / float(around)
				# th 0 at the front, PI/2 lateral, PI at the back, 3PI/2 medial.
				var lat := sin(th) * s_side
				var fb := cos(th)
				var rr := Vector2(ra.x * (1.0 + bl * maxf(-fb, 0.0)), ra.y)
				var off := fwd * fb * rr.x + side * lat * rr.y
				var p := c + off
				var out := fwd * fb / maxf(rr.x, 1e-4) + side * lat / maxf(rr.y, 1e-4)
				if tt < 0.02:
					out += dir * -0.5 / maxf(rr.x, 1e-4)
				var uv := DogMesh._uv(rect, th / TAU, tt)
				var uv2 := Vector2(along, th * (rr.x + rr.y) * 0.5)
				var fl := dir if flow_down else -dir
				var medial := maxf(-sin(th), 0.0)
				var ao := 1.0 - 0.3 * smoothstep(0.2, 1.0, medial) * (1.0 - tt * 0.6)
				var fur := lerpf(fur_top, fur_bot, smoothstep(0.0, 0.7, tt))
				# Weights: segment i's bone, blended over the joints.
				var bw: Array = []
				var seg := float(i) + t
				var k0 := int(floor(seg))
				var f := seg - float(k0)
				var b_here: int = seg_bones[mini(k0 + 1, seg_bones.size() - 1)]
				var b_prev: int = seg_bones[mini(k0, seg_bones.size() - 1)]
				var b_next: int = seg_bones[mini(k0 + 2, seg_bones.size() - 1)]
				var wp := 0.5 * (1.0 - smoothstep(0.0, 0.28, f))
				var wn := 0.5 * smoothstep(0.72, 1.0, f)
				bw.append([b_here, 1.0 - wp - wn])
				if wp > 0.0 and b_prev != b_here:
					bw.append([b_prev, wp])
				elif wp > 0.0:
					bw[0][1] = float(bw[0][1]) + wp
				if wn > 0.0 and b_next != b_here:
					bw.append([b_next, wn])
				elif wn > 0.0:
					bw[0][1] = float(bw[0][1]) + wn
				add(p, out, uv, uv2, fl, PART_FUR, fur, ao, bw)
		grid(base, rings + 1, around)
		return [base, rings, around]

	func _front_leg(s: float) -> void:
		_piece += 1
		var sl := "L" if s < 0.0 else "R"
		var h: float = b.h
		var legr: float = b.leg * h
		var sh: Vector3 = j["Hum" + sl]
		var el: Vector3 = j["Rad" + sl]
		var ca: Vector3 = j["Car" + sl]
		var ba: Vector3 = j["Paw" + sl]
		var top := Vector3(sh.x * 0.5, sh.y + h * 0.16, sh.z - h * 0.02)
		var bones_l: Array = B_LEGS[0 if s < 0.0 else 1]
		var pts := [top, Vector3(sh.x * 0.82, sh.y, sh.z), el, ca, ba]
		var rad := [Vector2(h * 0.11, h * 0.055), Vector2(h * 0.1, h * 0.062), Vector2(legr * 1.2, legr * 0.95), Vector2(legr * 0.82, legr * 0.78), Vector2(legr * 0.82, legr * 0.85)]
		var seg := [B_CHEST, B_CHEST, bones_l[0], bones_l[1], bones_l[2], bones_l[2]]
		var tube := _tube(pts, rad, seg, DogMesh.R_FRONT, s, coat_len("body") * 0.9, coat_len("leg"), true, [0.0, 0.1, 0.35, 0.0, 0.0])
		_paw(s, false, tube)

	func _hind_leg(s: float) -> void:
		_piece += 1
		var sl := "L" if s < 0.0 else "R"
		var h: float = b.h
		var legr: float = b.leg * h
		var hp: Vector3 = j["Fem" + sl]
		var st: Vector3 = j["Tib" + sl]
		var ho: Vector3 = j["Tar" + sl]
		var hb: Vector3 = j["HPaw" + sl]
		var th: float = b.thigh
		var top := Vector3(hp.x * 0.5, hp.y + h * 0.14, hp.z + h * 0.02)
		var bones_l: Array = B_LEGS[2 if s < 0.0 else 3]
		var gas := st.lerp(ho, 0.45) + Vector3(0.0, 0.0, h * 0.02)
		var pts := [top, Vector3(hp.x * 0.88, hp.y, hp.z), st, gas, ho, hb]
		var rad := [Vector2(h * 0.16 * th, h * 0.085), Vector2(h * 0.15 * th, h * 0.088 * th), Vector2(h * 0.085 * th, h * 0.06), Vector2(legr * 1.25 * sqrt(th), legr * 0.9),
			Vector2(legr * 0.78, legr * 0.62), Vector2(legr * 0.8, legr * 0.82)]
		var seg := [B_PELVIS, B_PELVIS, bones_l[0], bones_l[1], bones_l[1], bones_l[2], bones_l[2]]
		var tube := _tube(pts, rad, seg, DogMesh.R_HIND, s, coat_len("body") * 1.1, coat_len("leg"), true, [0.0, 0.25, 0.25, 0.45, 0.0, 0.0])
		_paw(s, true, tube)

	## The paw: a domed foot from the ball of the foot forward, pads underneath, toes painted.
	func _paw(s: float, hind: bool, _tube_info: Array) -> void:
		_piece += 1
		var sl := "L" if s < 0.0 else "R"
		var h: float = b.h
		var ball: Vector3 = j[("HPaw" if hind else "Paw") + sl]
		var toe: Vector3 = j[("htoe" if hind else "toe") + sl]
		var bones_l: Array = B_LEGS[(2 if s < 0.0 else 3) if hind else (0 if s < 0.0 else 1)]
		var res: Array = PAW_RES[level]
		var rings: int = res[0]
		var around: int = res[1]
		var legr: float = b.leg * h
		var pl := ball.distance_to(Vector3(toe.x, ball.y, toe.z))
		var back := Vector3(ball.x, 0.0, ball.z + pl * 0.22)
		var base := verts.size()
		var along := 0.0
		for r in rings + 1:
			var t := float(r) / float(rings)
			var zc := lerpf(back.z, toe.z, t)
			var width := legr * (lerpf(0.95, 1.18, smoothstep(0.0, 0.6, t)) * sqrt(maxf(1.0 - pow(maxf(t - 0.55, 0.0) / 0.45, 2.0), 0.02)))
			var height := legr * 1.55 * lerpf(1.0, 0.45, smoothstep(0.1, 1.0, t)) * (0.35 + 0.65 * sqrt(maxf(1.0 - pow(maxf(t - 0.6, 0.0) / 0.4, 2.0), 0.0)))
			if r == rings:
				width = 0.0006
				height = legr * 0.25
			along = t * pl
			for k in around + 1:
				var th := TAU * float(k) / float(around)
				var ct := cos(th)
				var st := sin(th)
				var y := (ct * 0.5 + 0.5) * height
				var bottom := ct < -0.55
				if bottom:
					y = 0.0015
				var x := ball.x + st * width * (1.0 if ct > -0.2 else lerpf(1.0, 0.92, smoothstep(-0.2, -1.0, ct)))
				var p := Vector3(x, y, zc)
				var out := Vector3(st / maxf(width, 1e-4), ct / maxf(height * 0.5, 1e-4), 0.0)
				if t > 0.85:
					out.z -= 2.0 / maxf(legr, 1e-4)
				if t < 0.05:
					out.z += 1.0 / maxf(legr, 1e-4)
				var u := (th / PI) if th <= PI else (2.0 - th / PI)
				var uv := DogMesh._uv(DogMesh.R_PAW, u, t)
				var part := PART_PAD if bottom else PART_FUR
				if not bottom and t > 0.93 and ct < 0.2:
					part = PART_CLAW
				var wl := smoothstep(0.0, 0.3, t)
				var bw: Array = [[bones_l[3], wl], [bones_l[2], 1.0 - wl]]
				add(p, out, uv, Vector2(along, th * width), Vector3(0, -0.3, -1).normalized(), part, coat_len("leg") * 0.7 if part == PART_FUR else 0.0, 0.9 if not bottom else 0.6, bw)
		grid(base, rings + 1, around)
		var c0 := Vector3(ball.x, legr * 0.7, back.z + legr * 0.1)
		cap(base, around, c0, Vector3(0, 0, 1), DogMesh._uv(DogMesh.R_PAW, 0.5, 0.0), PART_FUR, coat_len("leg"), [[bones_l[2], 1.0]], Vector3(0, -1, 0))

	# --- tail --------------------------------------------------------------------------------

	func _tail() -> void:
		_piece += 1
		var kind: String = b.tail[0]
		var tl: float = b.tail[1]
		var r0: float = b.tail[2]
		var res: Array = TAIL_RES[level]
		var rings: int = res[0]
		var around: int = res[1]
		var tb: Vector3 = j["Tail0"]
		var base := verts.size()
		var start := tb + Vector3(0.0, -r0 * 0.3, -r0 * 1.2)
		for r in rings + 1:
			var t := float(r) / float(rings)
			var c := start.lerp(j["tail_tip"], t)
			var rad: float
			match kind:
				"otter":
					rad = r0 * lerpf(1.25, 0.32, pow(t, 0.8))
				"whip", "sickle_up":
					rad = r0 * lerpf(1.0, 0.22, pow(t, 0.7))
				"erect":
					rad = r0 * lerpf(1.1, 0.5, t)
				_:
					rad = r0 * lerpf(1.0, 0.45, t)
			if r == rings:
				rad *= 0.25
			for k in around + 1:
				var th := TAU * float(k) / float(around)
				var p := c + Vector3(sin(th) * rad, cos(th) * rad, 0.0)
				var out := Vector3(sin(th), cos(th), 0.0)
				if r == rings:
					out.z += 2.0
				if r == 0:
					out.z -= 1.0
				var u := (th / PI) if th <= PI else (2.0 - th / PI)
				var uv := DogMesh._uv(DogMesh.R_TAIL, u, t)
				# The bones: four along the tail, blended; the root on the pelvis too.
				var seg := t * 4.0
				var k0 := mini(int(seg), 3)
				var f := seg - float(k0)
				var bw: Array = [[B_TAIL[k0], 1.0 - smoothstep(0.6, 1.0, f) * 0.5]]
				if k0 < 3:
					bw.append([B_TAIL[k0 + 1], smoothstep(0.6, 1.0, f) * 0.5])
				if t < 0.1:
					bw.append([B_PELVIS, (0.1 - t) * 6.0])
				var fur := coat_len("tail") * (lerpf(0.75, 1.15, sin(t * PI)) if kind in ["plume", "sickle"] else lerpf(1.0, 0.7, t))
				add(p, out, uv, Vector2(t * tl, th * rad), Vector3(0, 0, 1), PART_FUR, fur, 1.0 - 0.2 * maxf(-cos(th), 0.0), bw)
		grid(base, rings + 1, around)
		var last := base + rings * (around + 1)
		cap(last, around, (j["tail_tip"] as Vector3) + Vector3(0, 0, r0 * 0.15), Vector3(0, 0, 1), DogMesh._uv(DogMesh.R_TAIL, 0.5, 1.0), PART_FUR, coat_len("tail") * 0.6, [[B_TAIL[3], 1.0]], Vector3(0, 0, 1))

	# --- normals and commit ------------------------------------------------------------------

	func _smooth_normals() -> void:
		var acc := PackedVector3Array()
		acc.resize(verts.size())
		for k in range(0, idx.size(), 3):
			var a := idx[k]
			var c := idx[k + 1]
			var d := idx[k + 2]
			var fn := (verts[d] - verts[a]).cross(verts[c] - verts[a])
			acc[a] += fn
			acc[c] += fn
			acc[d] += fn
		# Seams (the loft's first and last columns, caps): average by position within a piece.
		var by_pos := {}
		for i in verts.size():
			var key := Vector4i(roundi(verts[i].x * 20000.0), roundi(verts[i].y * 20000.0), roundi(verts[i].z * 20000.0), piece[i])
			if by_pos.has(key):
				(by_pos[key] as Array).append(i)
			else:
				by_pos[key] = [i]
		for key in by_pos:
			var ids: Array = by_pos[key]
			if ids.size() < 2:
				continue
			# Only merge across vertices facing roughly the same way (an ear's two faces don't).
			var sum := Vector3.ZERO
			for i: int in ids:
				sum += acc[i]
			for i: int in ids:
				if acc[i].dot(sum) > 0.0 and outs[i].dot(outs[ids[0]]) > 0.0:
					acc[i] = sum
		for i in verts.size():
			var n := acc[i]
			if n.length_squared() < 1e-16 or n.dot(outs[i]) < 0.0 and n.length_squared() < 1e-10:
				n = outs[i]
			norms[i] = n.normalized()

	func _arrays(layer_verts: PackedVector3Array, layer_col: PackedColorArray, custom: PackedFloat32Array, index: PackedInt32Array, src: PackedInt32Array) -> Array:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		var n := src.size()
		var vv := PackedVector3Array()
		var nn := PackedVector3Array()
		var tt := PackedFloat32Array()
		var u1 := PackedVector2Array()
		var u2 := PackedVector2Array()
		var bb := PackedInt32Array()
		var ww := PackedFloat32Array()
		vv.resize(n)
		nn.resize(n)
		tt.resize(n * 4)
		u1.resize(n)
		u2.resize(n)
		bb.resize(n * 4)
		ww.resize(n * 4)
		for i in n:
			var s := src[i]
			vv[i] = layer_verts[i]
			var nv := norms[s]
			nn[i] = nv
			var f := flows[s] - nv * nv.dot(flows[s])
			if f.length_squared() < 1e-10:
				f = nv.cross(Vector3.RIGHT if absf(nv.x) < 0.9 else Vector3.UP)
			f = f.normalized()
			tt[i * 4] = f.x
			tt[i * 4 + 1] = f.y
			tt[i * 4 + 2] = f.z
			tt[i * 4 + 3] = 1.0
			u1[i] = uvs[s]
			u2[i] = uv2s[s]
			for k in 4:
				bb[i * 4 + k] = bones[s * 4 + k]
				ww[i * 4 + k] = weights[s * 4 + k]
		arrays[Mesh.ARRAY_VERTEX] = vv
		arrays[Mesh.ARRAY_NORMAL] = nn
		arrays[Mesh.ARRAY_TANGENT] = tt
		arrays[Mesh.ARRAY_TEX_UV] = u1
		arrays[Mesh.ARRAY_TEX_UV2] = u2
		arrays[Mesh.ARRAY_COLOR] = layer_col
		arrays[Mesh.ARRAY_CUSTOM0] = custom
		arrays[Mesh.ARRAY_BONES] = bb
		arrays[Mesh.ARRAY_WEIGHTS] = ww
		arrays[Mesh.ARRAY_INDEX] = index
		return arrays

	func _bounds(m: ArrayMesh) -> void:
		var lo := Vector3(INF, INF, INF)
		var hi := -lo
		for v in verts:
			lo = lo.min(v)
			hi = hi.max(v)
		# Room for every pose (a sit, a stretch, the tail up, a leap): the rig moves bones about.
		var h: float = b.h
		m.custom_aabb = AABB(lo - Vector3(h * 0.6, h * 0.3, h * 0.8), (hi - lo) + Vector3(h * 1.2, h * 1.0, h * 1.6))

	func commit_skin() -> ArrayMesh:
		var src := PackedInt32Array()
		var custom := PackedFloat32Array()
		for i in verts.size():
			src.append(i)
			custom.append_array([0.0, 0.0, 0.0, 0.0])
		var arrays := _arrays(verts, cols, custom, idx, src)
		var fmt := Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, fmt)
		_bounds(m)
		return m

	## `layers` copies of the coat's triangles (anything with fur), each a layer further out.
	func commit_shells(layers: int) -> ArrayMesh:
		if layers <= 0:
			return null
		# The vertices the shells use: those with fur, compacted.
		var keep := PackedInt32Array()
		keep.resize(verts.size())
		var src := PackedInt32Array()
		for i in verts.size():
			var c := cols[i]
			if c.g > 0.0 and (c.r * 8.0 < 0.5 or absf(c.r * 8.0 - PART_EAR_IN) < 0.5):
				keep[i] = src.size()
				src.append(i)
			else:
				keep[i] = -1
		var tris := PackedInt32Array()
		for k in range(0, idx.size(), 3):
			var a := keep[idx[k]]
			var c := keep[idx[k + 1]]
			var d := keep[idx[k + 2]]
			if a >= 0 and c >= 0 and d >= 0:
				tris.append_array([a, c, d])
		var n := src.size()
		var all_src := PackedInt32Array()
		var all_v := PackedVector3Array()
		var all_c := PackedColorArray()
		var custom := PackedFloat32Array()
		var index := PackedInt32Array()
		for layer in layers:
			var l := float(layer + 1) / float(layers)
			for i in n:
				var s := src[i]
				all_src.append(s)
				all_v.append(verts[s])
				all_c.append(cols[s])
				custom.append_array([l, 0.0, 0.0, 0.0])
			var off := layer * n
			for t in tris:
				index.append(t + off)
		var arrays := _arrays(all_v, all_c, custom, index, all_src)
		var fmt := Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, fmt)
		_bounds(m)
		return m
