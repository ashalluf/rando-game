class_name BeachGoer
extends RoughSleeper
## Somebody at the beach on a warm afternoon (BeachLife, scripts/world/beach_life.gd): lying on a
## towel on their back or front, sitting on it, in a low beach chair, standing about, playing
## volleyball. Most of them are never this node: a beach's people are static figures
## (BeachFigure, the camps' CampFigure trick: posed once, baked, merged into one mesh a chunk) and
## one only turns into a BeachGoer when it is shot, knocked or near gunfire - then it gets up and
## runs like anyone (RoughSleeper's FLEE and RETURN), bleeds, ragdolls.
##
## **Swimwear.** The crowd rigs (tools/crowd) wear street clothes, and every vertex says what it
## is in its colour (R top garment, G bottom garment, B hair, A skin). swim_mesh() rewrites a
## copy of the body per style, triangle by triangle, from the rest pose's height: a garment
## triangle inside the swimsuit's band stays a garment (the top or the bottom region, which the
## material colours as the swimsuit), everything else - the rest of the shirt, the trouser legs,
## the shoes - becomes skin: the skin region, on one texel of the person's own skin (UV2, the
## metres the pores tile on, is kept). Border vertices are split, so the suit's edge is a clean
## line and no triangle interpolates across the atlas. Trunks for the men, a bikini or a one-piece
## for the women (STYLE_OF). The garment shells stand a little off the body they covered, which
## nobody sees past a few metres; up close it reads as a bare torso. No new bones, no new surface:
## the welded middle and far bodies, the baked figures, the ragdolls and the limb cuts all work on
## it as on any rig.

enum Style { TRUNKS, BIKINI, ONE_PIECE }

## The crowd rigs that come to the beach (indices into Pedestrian.MODELS) and what each wears:
## the younger ones in our own garments (tools/crowd/garments.py), and two older ones.
const BEACH_MODELS := [0, 3, 4, 7, 8, 10, 11]
const STYLE_OF := {0: Style.TRUNKS, 3: Style.BIKINI, 4: Style.ONE_PIECE, 7: Style.TRUNKS,
	8: Style.BIKINI, 10: Style.ONE_PIECE, 11: Style.TRUNKS}
## Swimsuit colours as (hue, saturation, value), the way the character shader takes a garment:
## black, navy, red, coral, teal, royal blue, a sun yellow, white, a print-dark olive, hot pink.
const SUITS: Array[Vector3] = [
	Vector3(0.62, 0.05, 0.08), Vector3(0.62, 0.55, 0.22), Vector3(0.99, 0.78, 0.62),
	Vector3(0.03, 0.62, 0.86), Vector3(0.49, 0.72, 0.52), Vector3(0.61, 0.78, 0.58),
	Vector3(0.13, 0.75, 0.88), Vector3(0.0, 0.0, 0.93), Vector3(0.22, 0.45, 0.34),
	Vector3(0.93, 0.62, 0.82),
]
## Height bands of the suit, as fractions of the rig's standing height (rest pose): trunks from
## just above the knee to the waist; a bikini's bottom over the hips and its top across the bust
## (inside TOP_HALF_WIDTH of the body's height either side of the middle, so not the sleeves); a
## one-piece from the hips to the bust.
const TRUNKS_BAND := Vector2(0.335, 0.565)
const BOTTOM_BAND := Vector2(0.455, 0.535)
const TOP_BAND := Vector2(0.705, 0.775)
const TOP_HALF_WIDTH := 0.098
## Below this share of the height a shoe is a bare foot.
const FOOT_TOP := 0.075

## Extra poses (RoughSleeper.POSES' format, solved the same way per rig). The body's front faces
## +Z in rig space; lying on the back is the pelvis pitched back a quarter turn (its legs follow
## it), on the front pitched forward.
const BEACH_POSES := {
	"lie_back": {
		"hips_pitch": -90.0, "hips_y": 10.0,
		"aim": {
			"Spine02": Vector3(0.0, 0.08, -1.0), "Spine01": Vector3(0.0, 0.05, -1.0),
			"Spine": Vector3(0.0, 0.03, -1.0), "neck": Vector3(0.0, 0.3, -0.95),
			"Head": Vector3(0.0, 0.22, -0.97),
			"LeftUpLeg": Vector3(0.09, 0.0, 1.0), "LeftLeg": Vector3(0.05, 0.0, 1.0),
			"LeftFoot": Vector3(0.18, 0.86, 0.47),
			"LeftArm": Vector3(0.3, 0.0, 0.95), "LeftForeArm": Vector3(0.2, 0.0, 0.98),
		},
		"keep": [],
	},
	# Hands behind the head, one knee up.
	"lie_back_relax": {
		"hips_pitch": -90.0, "hips_y": 10.0,
		"aim": {
			"Spine02": Vector3(0.0, 0.08, -1.0), "Spine01": Vector3(0.0, 0.06, -1.0),
			"Spine": Vector3(0.0, 0.05, -1.0), "neck": Vector3(0.0, 0.38, -0.92),
			"Head": Vector3(0.0, 0.3, -0.95),
			"LeftUpLeg": Vector3(0.1, 0.62, 0.78), "LeftLeg": Vector3(0.04, -0.66, 0.75),
			"RightUpLeg": Vector3(-0.08, 0.0, 1.0), "RightLeg": Vector3(-0.05, 0.0, 1.0),
			"LeftFoot": Vector3(0.1, -0.2, 0.97), "RightFoot": Vector3(-0.18, 0.86, 0.47),
			"LeftArm": Vector3(0.8, 0.22, -0.56), "LeftForeArm": Vector3(-0.9, 0.2, -0.38),
		},
		"keep": [],
	},
	"lie_front": {
		"hips_pitch": 90.0, "hips_y": 11.0,
		"aim": {
			"Spine02": Vector3(0.0, 0.03, 1.0), "Spine01": Vector3(0.0, 0.05, 1.0),
			"Spine": Vector3(0.0, 0.08, 1.0), "neck": Vector3(0.0, 0.12, 1.0),
			"Head": Vector3(0.0, 0.1, 1.0),
			"LeftFoot": Vector3(0.12, -0.25, -0.96),
			"LeftArm": Vector3(0.86, 0.02, 0.5), "LeftForeArm": Vector3(-0.78, 0.04, 0.62),
		},
		"keep": [],
	},
	# Sitting on a towel leaning back on the hands, legs out.
	"sit_lean": {
		"hips_pitch": -14.0, "hips_y": 11.0,
		"aim": {
			"Spine02": Vector3(0.0, 0.88, -0.48), "Spine01": Vector3(0.0, 0.9, -0.43),
			"Spine": Vector3(0.0, 0.94, -0.33), "neck": Vector3(0.0, 0.96, 0.27),
			"Head": Vector3(0.0, 0.86, 0.5),
			"LeftUpLeg": Vector3(0.12, -0.04, 0.99), "LeftLeg": Vector3(0.08, -0.1, 0.99),
			"LeftFoot": Vector3(0.18, 0.7, 0.69),
			"LeftArm": Vector3(0.28, -0.7, -0.66), "LeftForeArm": Vector3(0.12, -0.86, -0.5),
		},
		"keep": [],
	},
	# A low beach chair: seat 0.28 m up, the back leaning, legs out to the sand.
	"beach_chair": {
		"hips_pitch": -26.0, "hips_y": 34.0,
		"aim": {
			"Spine02": Vector3(0.0, 0.82, -0.57), "Spine01": Vector3(0.0, 0.85, -0.52),
			"Spine": Vector3(0.0, 0.9, -0.43), "neck": Vector3(0.0, 0.94, 0.33),
			"Head": Vector3(0.0, 0.84, 0.54),
			"LeftUpLeg": Vector3(0.16, 0.05, 0.99), "LeftLeg": Vector3(0.06, -0.62, 0.78),
			"LeftArm": Vector3(0.36, -0.86, -0.1), "LeftForeArm": Vector3(0.1, -0.25, 0.96),
		},
		"keep": ["LeftFoot", "RightFoot"],
	},
	# Sitting astride a surfboard, waiting for a set: legs down in the water.
	"surf_sit": {
		"hips_pitch": -4.0, "hips_y": 2.0,
		"aim": {
			"Spine02": Vector3(0.0, 0.97, 0.12), "Spine01": Vector3(0.0, 0.98, 0.1),
			"Spine": Vector3(0.0, 0.99, 0.08), "neck": Vector3(0.0, 0.92, 0.38),
			"Head": Vector3(0.0, 0.88, 0.47),
			"LeftUpLeg": Vector3(0.42, -0.4, 0.81), "LeftLeg": Vector3(0.1, -0.96, 0.25),
			"LeftArm": Vector3(0.24, -0.95, 0.18), "LeftForeArm": Vector3(0.05, -0.4, 0.92),
		},
		"keep": [],
	},
	# Riding a wave: a low crouch, sideways to the way the board runs (the board runs along the
	# rig's x), arms out for balance.
	"surf_ride": {
		"hips_pitch": 18.0, "stand": true,
		"aim": {
			"Spine02": Vector3(0.0, 0.86, 0.5), "Spine01": Vector3(0.0, 0.9, 0.44),
			"Spine": Vector3(0.0, 0.95, 0.3), "neck": Vector3(0.12, 0.94, 0.3),
			"Head": Vector3(0.3, 0.88, 0.36),
			"LeftUpLeg": Vector3(0.42, -0.72, 0.55), "LeftLeg": Vector3(0.32, -0.92, -0.2),
			"RightUpLeg": Vector3(-0.42, -0.72, 0.55), "RightLeg": Vector3(-0.32, -0.92, -0.2),
			"LeftArm": Vector3(0.94, 0.05, 0.33), "LeftForeArm": Vector3(0.9, -0.3, 0.3),
			"RightArm": Vector3(-0.9, -0.2, 0.38), "RightForeArm": Vector3(-0.8, -0.5, 0.3),
		},
		"keep": ["LeftFoot", "RightFoot"],
	},
	# Prone on a board, paddling: chest up, arms down into the water.
	"paddle": {
		"hips_pitch": 90.0, "hips_y": 8.0,
		"aim": {
			"Spine02": Vector3(0.0, 0.08, 1.0), "Spine01": Vector3(0.0, 0.22, 0.97),
			"Spine": Vector3(0.0, 0.32, 0.95), "neck": Vector3(0.0, 0.52, 0.85),
			"Head": Vector3(0.0, 0.62, 0.78),
			"LeftFoot": Vector3(0.1, 0.0, -1.0),
			"LeftArm": Vector3(0.36, -0.62, 0.7), "LeftForeArm": Vector3(0.05, -0.92, 0.38),
		},
		"keep": [],
	},
	# Volleyball: forearms together in a platform (a pass), and both arms up (a set or a block).
	"bump": {"aim": {"LeftArm": Vector3(0.18, -0.55, 0.82), "LeftForeArm": Vector3(-0.3, -0.42, 0.86)}, "keep": []},
	"reach": {"aim": {"LeftArm": Vector3(0.22, 0.92, 0.32), "LeftForeArm": Vector3(0.0, 0.96, 0.28)}, "keep": []},
	# Skateboarding: a glide on a board, a little crouched, side-on.
	"skate": {
		"hips_pitch": 8.0, "stand": true,
		"aim": {
			"Spine02": Vector3(0.0, 0.95, 0.3), "Spine01": Vector3(0.0, 0.97, 0.24),
			"Spine": Vector3(0.0, 0.98, 0.18), "neck": Vector3(0.18, 0.96, 0.2),
			"Head": Vector3(0.4, 0.88, 0.25),
			"LeftUpLeg": Vector3(0.3, -0.9, 0.3), "LeftLeg": Vector3(0.18, -0.97, -0.12),
			"RightUpLeg": Vector3(-0.3, -0.9, 0.3), "RightLeg": Vector3(-0.18, -0.97, -0.12),
			"LeftArm": Vector3(0.6, -0.75, 0.25), "LeftForeArm": Vector3(0.55, -0.7, 0.45),
			"RightArm": Vector3(-0.5, -0.8, 0.3), "RightForeArm": Vector3(-0.3, -0.75, 0.6),
		},
		"keep": ["LeftFoot", "RightFoot"],
	},
}

## Who rides the bike path (the younger rigs) and how many bike colours each has (rider_paint()).
const RIDER_MODELS := [0, 3, 7, 8]
const RIDER_PAINTS := 2


## Bike colour `k` of a rider of crowd rig `model` (an index into BeachLife.BIKES).
static func rider_paint(model: int, k: int) -> int:
	return (model * 2 + k * 3) % 6


## Seated on a beach cruiser (BeachLife.bike_mesh()): the saddle's height over the ground in
## metres per metre of the rider's leg (hip joint to ankle), the bottom bracket's height and how far
## ahead of the saddle it is, the crank's length, the pedals' half spread, the bars' grip (height
## over the ground, ahead of the saddle, half width) and the torso's lean.
const RIDE := {
	"saddle_k": 1.13, "bb_y": 0.28, "bb_ahead": 0.3, "crank": 0.17, "pedal_x": 0.115,
	"bars_y": 1.06, "bars_ahead": 0.5, "bars_x": 0.29,
}
## Crank positions baked per rider (BeachFigure.ride_mesh()): the pedalling is a flipbook.
const RIDE_FRAMES := 12

## Which extra pose (BEACH_POSES) this person holds, "" for the base pose's own.
var beach_pose: String = ""
## Which of SUITS they wear.
var suit: int = 0
## Volleyball (BeachLife's court, BeachActivity drives it): the spot they play from (parent
## space), where they are going now, and how long the hit lasts.
var volley_home := Vector2.INF
var volley_goal := Vector2.INF
var volley_face: float = 0.0
var _volley_hit: float = 0.0
var _volley_kind: String = ""
var _volley_hop: float = 0.0
var _arm_bones2 := PackedInt32Array()
var _arm_rot: Dictionary = {}

## Swim meshes by "mesh id|style", the skin texel per mesh, and the swim looks by
## "albedo id|suit|look".
static var _swim: Dictionary = {}
static var _swim_looks: Dictionary = {}


func _init() -> void:
	# Nothing on the head or the back at the beach (and so no seed search for a bare head).
	accessory_chance = 0.0


func _ready() -> void:
	super._ready()
	if _down:
		return
	dress(_visual, _model_path, suit)
	if beach_pose != "" and BEACH_POSES.has(beach_pose) and _skel != null and not _base_rot.is_empty():
		var p := _solve(BEACH_POSES[beach_pose])
		_posed_rot = p[0]
		_posed_hips = p[1]
		_apply(1.0)
	if volley_home != Vector2.INF and _skel != null and not _base_rot.is_empty():
		for key: String in ["bump", "reach"]:
			var arms: Array = _solve(BEACH_POSES[key])[0]
			var rots := {}
			for bone_name: String in ["LeftArm", "LeftForeArm", "RightArm", "RightForeArm"]:
				var bi := _skel.find_bone(bone_name)
				if bi >= 0:
					rots[bi] = arms[bi]
			_arm_rot[key] = rots
		volley_goal = volley_home


## The collision capsule for `beach_pose` (BEACH_POSES) facing `yaw`, like RoughSleeper's
## pose_capsule() (whose base pose it falls back to): a body lying on its back or front is laid
## along the way it faces, the hips at the origin, the head behind on its back, ahead on its front.
static func beach_capsule(pose_key: String, base_pose: int, yaw: float) -> Dictionary:
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var cap := CapsuleShape3D.new()
	cap.radius = 0.26
	match pose_key:
		"lie_back", "lie_back_relax", "lie_front", "paddle":
			cap.height = 1.75
			var along := 0.1 if pose_key.begins_with("lie_back") else -0.1
			return {"shape": cap, "position": Vector3(0.0, 0.2, 0.0) + fwd * along, "rotation": Vector3(PI * 0.5, yaw, 0.0)}
		"sit_lean":
			cap.height = 1.0
			return {"shape": cap, "position": Vector3(0.0, 0.42, 0.0) - fwd * 0.05, "rotation": Vector3.ZERO}
		"beach_chair":
			cap.height = 1.2
			return {"shape": cap, "position": Vector3(0.0, 0.6, 0.0), "rotation": Vector3.ZERO}
	return RoughSleeper.pose_capsule(base_pose, yaw)


func _fit_shape() -> void:
	var fit := beach_capsule(beach_pose, pose, _home_yaw)
	if fit.is_empty():
		return
	for c in get_children():
		var cs := c as CollisionShape3D
		if cs == null or not (cs.shape is CapsuleShape3D):
			continue
		cs.shape = fit.shape
		cs.position = fit.position
		cs.rotation = fit.rotation
		break


## A seed whose person is crowd rig `model` (an index into Pedestrian.MODELS), found once and kept:
## the figure and the live person it wakes into are then the same person. `salt` picks among
## several such seeds (a beach has many people of each model).
static func seed_for(model: int, salt: int) -> int:
	var models := 0
	for path: String in Pedestrian.MODELS:
		if ResourceLoader.exists(path):
			models += 1
	if models == 0:
		return salt
	var s := absi(hash([model, salt, "beach_goer"])) % 100000 + 1
	for k in 4000:
		var style := RandomNumberGenerator.new()
		style.seed = hash([s, "style"])
		if style.randi() % models == model % models:
			return s
		s += 1
	return s


## Dresses every body mesh under `rig` (a crowd rig instance) in swimsuit `suit_index`: the swim
## mesh in place of the body and its swim look, the hair in its own colour.
static func dress(rig: Node, model_path: String, suit_index: int) -> void:
	if rig == null:
		return
	var model := Pedestrian.MODELS.find(model_path)
	var style: int = STYLE_OF.get(model, Style.TRUNKS)
	for node in rig.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or not mi.skin or Pedestrian.is_hair(mi):
			continue
		var src_mesh: Mesh = mi.get_meta("near_mesh") if mi.has_meta("near_mesh") else mi.mesh
		var src := src_mesh.surface_get_material(0) as StandardMaterial3D
		var swim := swim_mesh(src_mesh, style)
		if swim != src_mesh:
			mi.mesh = swim
			if mi.has_meta("near_mesh"):
				mi.set_meta("near_mesh", swim)
		if src and src.albedo_texture:
			var mat := swim_material(src.albedo_texture, suit_index, (model * 7 + 3) % Pedestrian.CHARACTER_LOOKS)
			if mat:
				mi.material_override = mat
	Pedestrian.plain_hair(rig)


## The body of `mesh` in swimwear of `style` (see the header). The mesh itself when it carries no
## region colours or there is no mesh data (the headless check).
static func swim_mesh(mesh: Mesh, style: int) -> Mesh:
	if mesh == null or mesh.get_surface_count() == 0:
		return mesh
	var key := "%d|%d" % [mesh.get_instance_id(), style]
	if _swim.has(key):
		return _swim[key]
	_swim[key] = mesh
	if mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_COLOR == 0:
		return mesh
	var arrays := mesh.surface_get_arrays(0)
	if arrays.is_empty() or arrays[Mesh.ARRAY_INDEX] == null or arrays[Mesh.ARRAY_COLOR] == null \
			or arrays[Mesh.ARRAY_TEX_UV] == null:
		return mesh
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var lo := INF
	var hi := -INF
	for v in verts:
		lo = minf(lo, v.y)
		hi = maxf(hi, v.y)
	var height := maxf(hi - lo, 0.001)
	# One texel of this person's own skin: the front of the neck (skin, not eye, not hair).
	var anchor := -1
	var best := -INF
	for v in verts.size():
		var c := colors[v]
		if c.a < 0.9 or c.b > 0.1 or c.r > 0.1 or c.g > 0.1:
			continue
		var h := (verts[v].y - lo) / height
		if h < 0.8 or h > 0.86:
			continue
		var score := verts[v].z - absf(verts[v].x) * 2.0
		if score > best:
			best = score
			anchor = v
	if anchor < 0:
		return mesh
	var skin_uv := uvs[anchor]
	# Each triangle: what it becomes (0 itself, 1 skin, 2 the suit's top, 3 its bottom).
	var tri_kind := PackedByteArray()
	tri_kind.resize(index.size() / 3)
	for t in index.size() / 3:
		var a := index[t * 3]
		var b := index[t * 3 + 1]
		var c := index[t * 3 + 2]
		var cc := (colors[a] + colors[b] + colors[c]) / 3.0
		var p := (verts[a] + verts[b] + verts[c]) / 3.0
		var h := (p.y - lo) / height
		var eye := cc.b + cc.a > 1.5
		var garment := cc.r + cc.g > 0.12
		var other := not garment and cc.a < 0.5 and cc.b < 0.5
		var kind := 0
		if garment or (other and not eye):
			kind = 1
			match style:
				Style.TRUNKS:
					if garment and h >= TRUNKS_BAND.x and h <= TRUNKS_BAND.y:
						kind = 3
				Style.BIKINI:
					if garment and h >= BOTTOM_BAND.x and h <= BOTTOM_BAND.y:
						kind = 3
					elif garment and h >= TOP_BAND.x and h <= TOP_BAND.y and absf(p.x) < TOP_HALF_WIDTH * height:
						kind = 2
				Style.ONE_PIECE:
					if garment and h >= BOTTOM_BAND.x and h <= TOP_BAND.y and absf(p.x) < TOP_HALF_WIDTH * height * (1.0 if h > 0.6 else 1.25):
						kind = 2 if h > 0.6 else 3
			if other and h > FOOT_TOP * 1.6:
				# A button or a zip pull above the feet: the skin it sits on.
				kind = 1
		tri_kind[t] = kind
	# New vertices: each source vertex once per kind its triangles give it.
	var remap := {}
	var order := PackedInt32Array()
	var kinds := PackedByteArray()
	var new_index := PackedInt32Array()
	new_index.resize(index.size())
	for t in index.size() / 3:
		var kind := tri_kind[t]
		for k in 3:
			var v := index[t * 3 + k]
			var key2 := v * 4 + kind
			if not remap.has(key2):
				remap[key2] = order.size()
				order.append(v)
				kinds.append(kind)
			new_index[t * 3 + k] = remap[key2]
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	var per := 0
	if arrays[Mesh.ARRAY_BONES] != null:
		per = (arrays[Mesh.ARRAY_BONES] as PackedInt32Array).size() / maxi(verts.size(), 1)
	for a in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_COLOR]:
		if arrays[a] == null:
			continue
		var s = arrays[a]
		var d = s.duplicate()
		d.resize(order.size())
		for i in order.size():
			d[i] = s[order[i]]
		out[a] = d
	for a in [Mesh.ARRAY_TANGENT, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS]:
		if arrays[a] == null:
			continue
		var n := 4 if a == Mesh.ARRAY_TANGENT else per
		var s = arrays[a]
		var d = s.duplicate()
		d.resize(order.size() * n)
		for i in order.size():
			for k in n:
				d[i * n + k] = s[order[i] * n + k]
		out[a] = d
	var col: PackedColorArray = out[Mesh.ARRAY_COLOR]
	var uv: PackedVector2Array = out[Mesh.ARRAY_TEX_UV]
	for i in order.size():
		match kinds[i]:
			1:
				col[i] = Color(0.0, 0.0, 0.0, 1.0)
				uv[i] = skin_uv
			2:
				# Jersey (level 1.0): lycra reads like a knit.
				col[i] = Color(1.0, 0.0, 0.0, 0.0)
			3:
				col[i] = Color(0.0, 1.0, 0.0, 0.0)
	out[Mesh.ARRAY_COLOR] = col
	out[Mesh.ARRAY_TEX_UV] = uv
	out[Mesh.ARRAY_INDEX] = new_index
	var flags: int = mesh.surface_get_format(0) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out, [], {}, flags)
	result.surface_set_material(0, mesh.surface_get_material(0))
	_swim[key] = result
	return result


## The swim look on the rig of `albedo`: the crowd look `look` with both garment regions in suit
## `suit_index`'s colour, fully (a swimsuit is not its source garment).
static func swim_material(albedo: Texture2D, suit_index: int, look: int) -> ShaderMaterial:
	var key := "%d|%d|%d" % [albedo.get_instance_id(), suit_index, look]
	if _swim_looks.has(key):
		return _swim_looks[key]
	var base := Pedestrian.character_material(albedo, look)
	if base == null:
		return null
	var mat := base.duplicate() as ShaderMaterial
	var c: Vector3 = SUITS[posmod(suit_index, SUITS.size())]
	for part: String in ["cloth", "pants"]:
		mat.set_shader_parameter(part + "_hue", c.x)
		mat.set_shader_parameter(part + "_sat", c.y)
		mat.set_shader_parameter(part + "_value", c.z)
		mat.set_shader_parameter(part + "_strength", 1.0)
	# The suit keeps a little of the garment's folds, not its pattern.
	mat.set_shader_parameter("cloth_shade_keep", 0.45)
	mat.set_shader_parameter("hair_strength", 0.0)
	_swim_looks[key] = mat
	return mat


## Seats this person on a beach cruiser with the crank at `angle` (0 = the left pedal at the bottom,
## turning forward) and holds the pose: an upright cruiser seat, hands on swept-back bars, and each
## leg solved by two-bone IK onto its pedal (the knee kept forward). The saddle is set to this rider's
## leg (RIDE.saddle_k). Returns where the bike's parts must be in this node's space (metres,
## forward -z): {saddle, bb, pedal_l, pedal_r, grip_l, grip_r}; {} if the rig cannot be posed.
func ride_pose(angle: float) -> Dictionary:
	if _skel == null or _base_rot.is_empty() or _hips < 0:
		return {}
	var names := ["LeftUpLeg", "LeftLeg", "LeftFoot", "RightUpLeg", "RightLeg", "RightFoot", "LeftHand", "RightHand"]
	var ids := {}
	for n: String in names:
		ids[n] = _skel.find_bone(n)
		if int(ids[n]) < 0:
			return {}
	# Skeleton space (this rig: +Y up, +Z forward, +X its left; centimetres) and the way to metres
	# in this node's space.
	var to_local := global_transform.affine_inverse() * _skel.global_transform
	var unit := to_local.basis.get_scale().x
	var s := 1.0 / maxf(unit, 1e-6)
	var bg := _base_globals()
	var pitch := deg_to_rad(10.0)
	var rot := Basis(Vector3.RIGHT, pitch)
	var hips_base: Vector3 = (bg[_hips] as Transform3D).origin
	var thigh := _base_pos[ids.LeftLeg].length()
	var shin := _base_pos[ids.LeftFoot].length()
	var leg := thigh + shin
	var bb := Vector3(hips_base.x, float(RIDE.bb_y) * s, hips_base.z + float(RIDE.bb_ahead) * s)
	var crank := float(RIDE.crank) * s
	# The ankle rides 7 cm over the pedal's spindle and 4 cm behind it (the ball of the foot on it).
	var ankle_off := Vector3(0.0, 0.07 * s, -0.04 * s)
	var off := {}
	for side: String in ["Left", "Right"]:
		var up: int = ids[side + "UpLeg"]
		off[side] = rot * ((bg[up] as Transform3D).origin - hips_base)
	# Hip height from the leg's reach to the pedal at the bottom of its stroke.
	var low := bb + Vector3(0.0, -crank, 0.0) + ankle_off
	var reach := 0.94 * leg
	var lo: Vector3 = off.Left
	var dz := low.z - (hips_base.z + lo.z)
	var dy := sqrt(maxf(reach * reach - dz * dz, 1.0))
	var hips_y := low.y + dy - lo.y
	var spec := {"hips_pitch": rad_to_deg(pitch), "hips_y": hips_y, "aim": {
		"Spine02": Vector3(0.0, 0.94, 0.33), "Spine01": Vector3(0.0, 0.95, 0.3),
		"Spine": Vector3(0.0, 0.97, 0.24), "neck": Vector3(0.0, 0.92, 0.38),
		"Head": Vector3(0.0, 0.94, 0.33),
		"LeftArm": Vector3(0.24, -0.58, 0.78), "LeftForeArm": Vector3(0.08, -0.26, 0.96),
	}, "keep": []}
	var pedals := {}
	for side: String in ["Left", "Right"]:
		var sg := 1.0 if side == "Left" else -1.0
		var phi := angle + (0.0 if side == "Left" else PI)
		var pedal := bb + Vector3(sg * float(RIDE.pedal_x) * s, -crank * cos(phi), crank * sin(phi))
		pedals[side] = pedal
		var hip := Vector3(hips_base.x, hips_y, hips_base.z) + (off[side] as Vector3)
		var target := pedal + ankle_off
		var to_t := target - hip
		var d := clampf(to_t.length(), absf(thigh - shin) + 0.01, leg * 0.999)
		var dir := to_t.normalized()
		var pole := (Vector3(sg * 0.08, 0.0, 1.0) - dir * dir.dot(Vector3(sg * 0.08, 0.0, 1.0))).normalized()
		var cos_a := clampf((thigh * thigh + d * d - shin * shin) / (2.0 * thigh * d), -1.0, 1.0)
		var knee := hip + dir * thigh * cos_a + pole * thigh * sqrt(1.0 - cos_a * cos_a)
		spec.aim[side + "UpLeg"] = (knee - hip).normalized()
		spec.aim[side + "Leg"] = (hip + dir * d - knee).normalized()
		# Ankling: the toe drops a little through the down stroke.
		spec.aim[side + "Foot"] = Vector3(sg * 0.06, -0.18 - 0.16 * sin(phi), 1.0).normalized()
	var p := _solve(spec)
	_posed_rot = p[0]
	_posed_hips = p[1]
	_state = State.POSED
	_weight = 1.0
	_apply(1.0)
	_skel.force_update_all_bone_transforms()
	var gl := _skel.get_bone_global_pose(ids.LeftHand).origin
	var gr := _skel.get_bone_global_pose(ids.RightHand).origin
	var saddle := Vector3(hips_base.x, hips_y + lo.y - 0.085 * s, hips_base.z - 0.02 * s)
	return {"saddle": to_local * saddle, "bb": to_local * bb, "pedal_l": to_local * (pedals.Left as Vector3),
		"pedal_r": to_local * (pedals.Right as Vector3), "grip_l": to_local * (gl + Vector3(0.0, -0.02 * s, 0.05 * s)),
		"grip_r": to_local * (gr + Vector3(0.0, -0.02 * s, 0.05 * s))}


## Each bone's global transform in the base (idle) pose, from _base_rot / _base_pos.
func _base_globals() -> Array:
	var out: Array = []
	out.resize(_skel.get_bone_count())
	for b in _order:
		var parent := _skel.get_bone_parent(b)
		var bl := Transform3D(Basis(_base_rot[b]), _base_pos[b])
		out[b] = (out[parent] as Transform3D) * bl if parent >= 0 else bl
	return out


## The sand (or the sea) under (x, z) in the parent chunk's space.
func _ground_y(x: float, z: float, fallback: float) -> float:
	return BeachLife.ground_at(get_parent(), x, z, fallback)


func _pose_ground() -> float:
	return BeachLife.ground_at(get_parent(), _home.x, _home.y, position.y) + lift


## The beach is open sand: straight there, no ring corners.
func _ring_route(_from: Vector2, _to: Vector2) -> PackedVector2Array:
	return PackedVector2Array()


## A spot on the dry sand of this chunk's beach (`ring` is it).
func _random_ring_point(_sidewalk: float) -> Vector2:
	return Vector2(_rng.randf_range(ring.position.x, ring.end.x), _rng.randf_range(ring.position.y, ring.end.y))


## Away from the threat and up the beach toward the town: people run off the sand, not into the
## sea.
func _flee_point() -> Vector2:
	var best := _random_ring_point(_sidewalk)
	for i in 6:
		var p := _random_ring_point(_sidewalk)
		if p.distance_squared_to(_threat) + p.x * 4.0 > best.distance_squared_to(_threat) + best.x * 4.0:
			best = p
	return best


func _physics_process(delta: float) -> void:
	if volley_home != Vector2.INF and not _down and _state == State.POSED:
		_volley_tick(delta)
		return
	super._physics_process(delta)


## A volleyball player between rallies and in one: shuffles to `volley_goal` (the walk clip, or the
## run clip when it is far), faces the net, and while a hit is on (hit()) holds the platform or
## the arms up over the clip, hopping on a spike.
func _volley_tick(delta: float) -> void:
	_lod_timer += delta
	if _lod_timer >= 0.5:
		_lod_timer = 0.0
		_update_lod()
	var here := Vector2(position.x, position.z)
	var to_goal := volley_goal - here
	var d := to_goal.length()
	var want := 0.0 if d < 0.15 else clampf(d * 2.2, 0.0, 4.2)
	_speed = move_toward(_speed, want, 9.0 * delta)
	if d > 0.01:
		here += to_goal / d * minf(_speed * delta, d)
	position = Vector3(here.x, _ground_y(here.x, here.y, position.y), here.y)
	_visual.rotation = Vector3(0.0, lerp_angle(_visual.rotation.y, volley_face, minf(delta * 8.0, 1.0)), 0.0)
	if _anim:
		var clip := IDLE_CLIP if _speed < 0.3 else (RUN_CLIP if _speed > 2.4 and _has_run else WALK_CLIP)
		_set_clip(clip, 0.15)
		_anim.speed_scale = 1.0 if clip == IDLE_CLIP else _speed / ((RUN_CLIP_SPEED if clip == RUN_CLIP else WALK_CLIP_SPEED) * maxf(_stride, 0.5))
		_anim.advance(delta)
	_volley_hit = maxf(_volley_hit - delta, 0.0)
	_volley_hop = maxf(_volley_hop - delta, 0.0)
	if _skel and _volley_hit > 0.0 and _arm_rot.has(_volley_kind):
		var rots: Dictionary = _arm_rot[_volley_kind]
		var w := clampf(_volley_hit / 0.12, 0.0, 1.0)
		for bi: int in rots:
			_skel.set_bone_pose_rotation(bi, _skel.get_bone_pose_rotation(bi).slerp(rots[bi], w))
	_visual.position.y = sin(clampf(_volley_hop / 0.55, 0.0, 1.0) * PI) * 0.55


## The ball reaches them: a pass ("bump") or a set / spike ("reach"), `hop` for a jump.
func hit(kind: String, hop: bool) -> void:
	_volley_kind = kind
	_volley_hit = 0.45
	if hop:
		_volley_hop = 0.55


## Volleyball players run off like anyone, and walk back to their spot after.
func _scare(at: Vector3) -> void:
	if volley_home != Vector2.INF:
		_home = volley_home
		_visual.position.y = 0.0
	super._scare(at)


func _settle() -> void:
	super._settle()
	if volley_home != Vector2.INF:
		_visual.rotation = Vector3(0.0, volley_face, 0.0)
		volley_goal = volley_home


## Knocked down: the ragdoll they become is a fresh copy of the rig, in street clothes and with
## RoughSleeper's worn look - so it is dressed again, in the same suit.
func knock(impulse: Vector3, gibs: int = 0) -> void:
	if _down:
		return
	var parent := get_parent()
	var before := parent.get_child_count() if parent else 0
	super.knock(impulse, gibs)
	if parent == null:
		return
	for i in range(before, parent.get_child_count()):
		var doll := parent.get_child(i) as Ragdoll
		if doll and doll._rig:
			dress(doll._rig, _model_path, suit)
