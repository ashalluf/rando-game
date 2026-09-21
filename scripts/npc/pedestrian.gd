class_name Pedestrian
extends CharacterBody3D
## Wandering pedestrian. Walks between random points on its block's sidewalk ring, bobs a bit,
## and turns into a ragdoll when something fast hits it (cars, crates, explosions, bullets,
## a boosting player). Collides with the world only, so cars never get stuck on it.

const SHIRTS := [Color(0.9, 0.3, 0.3), Color(0.3, 0.5, 0.9), Color(0.95, 0.85, 0.3), Color(0.4, 0.75, 0.45), Color(0.9, 0.9, 0.9), Color(0.6, 0.35, 0.7), Color(0.95, 0.55, 0.2)]
const PANTS := [Color(0.2, 0.25, 0.4), Color(0.15, 0.15, 0.17), Color(0.5, 0.4, 0.3), Color(0.35, 0.35, 0.38)]
const SKINS := [Color(0.95, 0.8, 0.65), Color(0.85, 0.65, 0.5), Color(0.6, 0.42, 0.3), Color(0.4, 0.28, 0.2)]
## Generated rigged characters (see docs/ASSETS.md). Each has Idle, Casual_Walk_inplace and
## run_fast_3_inplace clips. Missing files fall back to the box person.
## pedestrian_b is deliberately not in this list. Its texture is entirely skin tones - the
## generator returned an unclothed figure - so the garment recolour below has nothing to work
## on and it walks the city as a naked orange mannequin, and its rig does not take the walk
## clip properly either (it stands with its arms over its head). The file is kept so the
## decision is visible, not because anything loads it.
const MODELS := [
	"res://assets/models/pedestrian_a_anim.glb",
	"res://assets/models/pedestrian_c_anim.glb",
]
## Walking speed (m/s) at which the walk clip plays at its natural pace.
const WALK_CLIP_SPEED := 1.3
const WALK_CLIP := "Casual_Walk_inplace"
const IDLE_CLIP := "Idle"

@export var walk_speed: float = 1.8
## Anything moving faster than this that touches us knocks us over (m/s).
@export var knock_speed: float = 4.0
## A boosting player has to be at least this fast to tackle us (m/s).
@export var tackle_speed: float = 14.0
## Odds that a pedestrian stands still for a while when it reaches a spot instead of turning
## straight round. A crowd where nobody ever stops reads as a conveyor belt, not a street.
@export var pause_chance: float = 0.28
## How long a pause lasts (seconds, min and max).
@export var pause_seconds: Vector2 = Vector2(1.4, 5.5)
## Spread of the walk cadence: the clip plays between these multiples of the rate its speed asks
## for, so two people walking at the same speed do not step in the same rhythm.
@export var gait_spread: Vector2 = Vector2(0.84, 1.20)
## How far the torso leans, in degrees. Positive stoops forward. Rolled per character.
@export var lean_spread: Vector2 = Vector2(-1.5, 4.5)
## Fraction of the crowd wearing a cap, a beanie or a backpack. Each is one extra draw call and
## only within `accessory_distance`, and a changed silhouette separates two people far harder
## than another shirt colour does.
@export var accessory_chance: float = 0.42
## Metres past which a pedestrian's accessory stops drawing.
@export var accessory_distance: float = 60.0

var ring: Rect2
var shirt: Color
var pants: Color
var skin: Color
var _target: Vector2
var _rng := RandomNumberGenerator.new()
var _visual: Node3D
var _bob: float = 0.0
var _down: bool = false
var _anim: AnimationPlayer
## Which rig this pedestrian wears ("" for the box person); the ragdoll keeps the same one.
var _model_path: String = ""
## Clothing look index, so the ragdoll that replaces this pedestrian keeps the same outfit.
var _look: int = 0
## Update LOD: far pedestrians move and animate every Nth physics frame (see _update_lod).
var _lod_stride: int = 1
var _lod_tick: int = 0
var _lod_timer: float = 0.0
## Cadence multiplier on the walk clip for this character.
var _gait: float = 1.0
## Seconds left standing still; 0 means walking.
var _pause_left: float = 0.0
## Everything cosmetic (look, gait, lean, accessory, pauses) rolls on its own stream, so adding
## or removing one of them never shifts where the crowd walks. Same seed, same city.
var _style := RandomNumberGenerator.new()
static var _player: Node3D


func setup(block_rect: Rect2, sidewalk: float, seed_value: int) -> void:
	ring = block_rect
	_rng.seed = seed_value
	_style.seed = hash([seed_value, "style"])
	shirt = SHIRTS[_rng.randi() % SHIRTS.size()]
	pants = PANTS[_rng.randi() % PANTS.size()]
	skin = SKINS[_rng.randi() % SKINS.size()]
	walk_speed = _rng.randf_range(1.4, 2.6)
	_target = _random_ring_point(sidewalk)
	_sidewalk = sidewalk


var _sidewalk: float = 4.0


func _ready() -> void:
	add_to_group("pedestrian")
	collision_layer = 8 # the npc layer: bullets, blasts and bumpers look for it
	collision_mask = 1
	floor_snap_length = 0.4
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.7
	shape.shape = capsule
	shape.position = Vector3(0.0, 0.85, 0.0)
	add_child(shape)
	_visual = Node3D.new()
	add_child(_visual)
	if _add_model():
		_add_hit_area()
		return
	_part(Vector3(0.5, 0.65, 0.3), Vector3(0.0, 1.05, 0.0), shirt)
	_part(Vector3(0.2, 0.7, 0.2), Vector3(-0.14, 0.38, 0.0), pants)
	_part(Vector3(0.2, 0.7, 0.2), Vector3(0.14, 0.38, 0.0), pants)
	_part(Vector3(0.16, 0.6, 0.16), Vector3(-0.36, 1.05, 0.0), skin)
	_part(Vector3(0.16, 0.6, 0.16), Vector3(0.36, 1.05, 0.0), skin)
	var head := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.15
	sphere.height = 0.3
	sphere.radial_segments = 8
	sphere.rings = 4
	head.mesh = sphere
	head.material_override = PropFactory.material(skin, 0.8)
	head.position = Vector3(0.0, 1.55, 0.0)
	_visual.add_child(head)
	_add_hit_area()


## Picks one of the generated characters (seeded) and starts its walk cycle. False if none exist.
func _add_model() -> bool:
	var available: Array[String] = []
	for path in MODELS:
		if ResourceLoader.exists(path):
			available.append(path)
	if available.is_empty():
		return false
	var path: String = available[_style.randi() % available.size()]
	var scene: PackedScene = load(path)
	if scene == null:
		return false
	var inst := scene.instantiate() as Node3D
	inst.rotation.y = PI # Meshy rigs face +Z; our visuals face -Z
	_look = _style.randi() % CHARACTER_LOOKS
	prepare_rig(inst, _look)
	_visual.add_child(inst)
	_model_path = path
	# Build variation: nobody in a crowd is the same height or width as the person next to them.
	var tall := _style.randf_range(0.90, 1.10)
	_visual.scale = Vector3(_style.randf_range(0.94, 1.07), tall, _style.randf_range(0.94, 1.07))
	# A fixed stoop or a chest-out posture, held for this character's whole life. Forward is -Z,
	# so a negative X rotation tips the head forward.
	_visual.rotation.x = -deg_to_rad(_style.randf_range(lean_spread.x, lean_spread.y))
	_gait = _style.randf_range(gait_spread.x, gait_spread.y)
	_anim = inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim:
		fix_arm_pose(_anim, path)
		for clip in _anim.get_animation_list():
			_anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		# Advanced by hand in _physics_process so far pedestrians can animate less often.
		_anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		if _anim.has_animation(WALK_CLIP):
			_play_walk(0.0)
			# Pose the rig at the top of the walk before hanging anything off its bones. The
			# clip holds the spine seven degrees off the bind pose the whole way round, so a
			# backpack lined up against the bind pose rides tilted back and floating off the
			# spine. Lining it up against a walking frame puts it on the back.
			_anim.seek(0.0, true)
	_add_accessory(inst)
	if _anim and _anim.has_animation(WALK_CLIP):
		# Start everyone at a different point in the cycle. A crowd stepping in perfect
		# unison is the most obvious tell that they are all the same model.
		_anim.seek(_style.randf() * _anim.get_animation(WALK_CLIP).length, true)
	return true


## Starts (or returns to) the walk cycle at this character's own cadence.
func _play_walk(blend: float = 0.25) -> void:
	if _anim == null or not _anim.has_animation(WALK_CLIP):
		return
	_anim.play(WALK_CLIP, blend)
	_anim.speed_scale = walk_speed / WALK_CLIP_SPEED * _gait


func _play_idle() -> void:
	if _anim == null or not _anim.has_animation(IDLE_CLIP):
		return
	_anim.play(IDLE_CLIP, 0.3)
	_anim.speed_scale = _gait


## Caps, beanies and backpacks, built in code the way the street props are and hung off the rig's
## own bones so they ride the head and the back. The mesh is built once per kind and shared, the
## material is cached per colour, so a wearer costs one draw call, and nothing draws past
## `accessory_distance`. A changed silhouette separates two people at fifty metres; a fourth
## shirt colour does not.
enum Accessory {NONE, CAP, BEANIE, PACK}
const ACC_BONE := {Accessory.CAP: "Head", Accessory.BEANIE: "Head", Accessory.PACK: "Spine01"}
## Where the accessory sits relative to that bone, in metres, in skeleton space (Y up, the rig
## facing +Z). Measured out from the bone rather than from the model origin, so the same numbers
## land on both rigs even though their heads sit 2 cm apart.
const ACC_OFFSET := {
	Accessory.CAP: Vector3(0.0, 0.0, -0.012),
	Accessory.BEANIE: Vector3(0.0, 0.0, -0.012),
	Accessory.PACK: Vector3(0.0, 0.0, 0.0),
}
const HAT_COLORS := [
	Color(0.10, 0.11, 0.14), Color(0.60, 0.15, 0.14), Color(0.14, 0.24, 0.46),
	Color(0.86, 0.86, 0.83), Color(0.20, 0.36, 0.24), Color(0.56, 0.43, 0.23),
	Color(0.34, 0.34, 0.37), Color(0.80, 0.55, 0.15),
]
const PACK_COLORS := [
	Color(0.13, 0.14, 0.16), Color(0.19, 0.27, 0.40), Color(0.36, 0.27, 0.18),
	Color(0.45, 0.16, 0.16), Color(0.22, 0.34, 0.26), Color(0.55, 0.53, 0.50),
]
static var _acc_meshes: Dictionary = {}


func _add_accessory(inst: Node3D) -> void:
	if _style.randf() >= accessory_chance:
		return
	var roll := _style.randf()
	var kind: int = Accessory.PACK if roll < 0.38 else (Accessory.BEANIE if roll < 0.60 else Accessory.CAP)
	var skel := inst.find_child("Skeleton3D", true, false) as Skeleton3D
	if skel == null:
		return
	var bone: String = ACC_BONE[kind]
	var idx := skel.find_bone(bone)
	if idx < 0:
		return
	# The rig's skeleton works in centimetres under a 0.01 armature, so anything hung off a bone
	# has to be scaled back up by that chain to be built in metres. Read it off the nodes rather
	# than hard-coding 100, in case a rig is ever exported at a different scale.
	var unit := 1.0
	var node: Node3D = skel
	while node != null and node != inst:
		unit *= node.transform.basis.get_scale().y
		node = node.get_parent() as Node3D
	unit = 1.0 / maxf(unit, 0.0001)
	var att := BoneAttachment3D.new()
	skel.add_child(att)
	att.bone_name = bone
	var mi := MeshInstance3D.new()
	mi.mesh = _accessory_mesh(kind)
	var palette: Array = PACK_COLORS if kind == Accessory.PACK else HAT_COLORS
	mi.material_override = PropFactory.material(palette[_style.randi() % palette.size()], 0.72)
	mi.visibility_range_end = accessory_distance * (0.6 if OS.has_feature("web") else 1.0)
	# No shadow pass and no global illumination: a cap's own shadow falls on a head that is
	# already under it, and paying a second draw call per wearer for that is not worth it.
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	# The bone as it stands in the walk clip, not as it stands in the bind pose (see _add_model).
	var pose := skel.get_bone_global_pose(idx)
	var at: Vector3 = pose.origin + (ACC_OFFSET[kind] as Vector3) * unit
	# Built level in skeleton space and then pushed back through that pose, so a cap sits flat
	# on the skull whatever angle the head bone happens to hold (the two rigs differ by ten
	# degrees there), and still rides the head once the clip moves on.
	mi.transform = pose.affine_inverse() * Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * unit), at)
	att.add_child(mi)


## One shared mesh per accessory kind, built in metres about the bone it hangs from. Part
## colours go in the vertex colour and the per-character colour multiplies them, so one mesh
## covers every colourway.
static func _accessory_mesh(kind: int) -> Mesh:
	if _acc_meshes.has(kind):
		return _acc_meshes[kind]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var white := Color(1.0, 1.0, 1.0)
	match kind:
		Accessory.CAP:
			# A tall band from just above the brow with a shallow dome on top: the skull is
			# still 10 cm wide two centimetres from its crown (it is carrying hair), so a plain
			# hemisphere the height of a cap pinches in and lets the head through its sides.
			st.set_smooth_group(0)
			_acc_tube(st, 0.095, 0.150, 0.108, 0.124, white, 20)
			_acc_dome(st, Vector3(0.0, 0.150, 0.0), Vector3(0.108, 0.062, 0.124), white, 20, 4)
			st.set_smooth_group(0xFFFFFFFF)
			_acc_brim(st, 0.100, 0.185, 0.104, 0.018, 0.012, Color(0.84, 0.84, 0.84), 12)
			_acc_box(st, Vector3(0.0, 0.211, 0.0), Vector3(0.022, 0.012, 0.022), Color(0.84, 0.84, 0.84))
		Accessory.BEANIE:
			st.set_smooth_group(0)
			_acc_dome(st, Vector3(0.0, 0.132, 0.0), Vector3(0.110, 0.084, 0.126), white, 20, 5)
			_acc_tube(st, 0.082, 0.132, 0.112, 0.128, Color(0.82, 0.82, 0.82), 20)
		Accessory.PACK:
			# Sunk a centimetre into the back rather than floated off it: the front face is
			# never seen, and a gap between a pack and a spine is.
			st.set_smooth_group(0xFFFFFFFF)
			_acc_box(st, Vector3(0.0, -0.020, -0.218), Vector3(0.285, 0.390, 0.160), white)
			_acc_box(st, Vector3(0.0, 0.168, -0.226), Vector3(0.270, 0.050, 0.146), Color(0.86, 0.86, 0.86))
			_acc_box(st, Vector3(0.0, -0.112, -0.303), Vector3(0.185, 0.125, 0.030), Color(0.74, 0.74, 0.74))
			for side: float in [-1.0, 1.0]:
				_acc_beam(st, Vector3(side * 0.086, 0.135, -0.148), Vector3(side * 0.103, 0.222, -0.020),
						0.048, 0.026, Color(0.72, 0.72, 0.72))
	st.generate_normals()
	var mesh := st.commit()
	_acc_meshes[kind] = mesh
	return mesh


## Winding matches the rest of the project: vertices clockwise seen from outside, so
## generate_normals() points them out of the solid.
static func _acc_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, colour: Color) -> void:
	for v: Vector3 in [a, b, c, a, c, d]:
		st.set_color(colour)
		st.set_uv(Vector2.ZERO)
		st.add_vertex(v)


static func _acc_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, colour: Color) -> void:
	for v: Vector3 in [a, b, c]:
		st.set_color(colour)
		st.set_uv(Vector2.ZERO)
		st.add_vertex(v)


## A box with its own axes: `ex`, `ey`, `ez` are half-extent vectors and must be right-handed.
static func _acc_prism(st: SurfaceTool, centre: Vector3, ex: Vector3, ey: Vector3, ez: Vector3, colour: Color) -> void:
	var p := [
		centre - ex - ey - ez, centre + ex - ey - ez, centre + ex + ey - ez, centre - ex + ey - ez,
		centre - ex - ey + ez, centre + ex - ey + ez, centre + ex + ey + ez, centre - ex + ey + ez,
	]
	for f: Array in [[0, 1, 2, 3], [5, 4, 7, 6], [4, 0, 3, 7], [1, 5, 6, 2], [3, 2, 6, 7], [4, 5, 1, 0]]:
		_acc_quad(st, p[f[0]], p[f[1]], p[f[2]], p[f[3]], colour)


static func _acc_box(st: SurfaceTool, centre: Vector3, size: Vector3, colour: Color) -> void:
	_acc_prism(st, centre, Vector3(size.x * 0.5, 0.0, 0.0), Vector3(0.0, size.y * 0.5, 0.0),
			Vector3(0.0, 0.0, size.z * 0.5), colour)


## A strap: a thin box running from `a` to `b`.
static func _acc_beam(st: SurfaceTool, a: Vector3, b: Vector3, width: float, thick: float, colour: Color) -> void:
	var axis := b - a
	var length := axis.length()
	if length < 0.001:
		return
	var forward := axis / length
	var side := forward.cross(Vector3.UP)
	if side.length() < 0.001:
		side = forward.cross(Vector3.FORWARD)
	side = side.normalized()
	# Right-handed: ex cross ey has to come out along ez.
	_acc_prism(st, (a + b) * 0.5, side * (width * 0.5), forward.cross(side) * (thick * 0.5),
			forward * (length * 0.5), colour)


## An open elliptical band (the side wall of a hat). No caps: the head fills one end and the
## crown the other.
static func _acc_tube(st: SurfaceTool, y0: float, y1: float, rx: float, rz: float, colour: Color, seg: int) -> void:
	for s in seg:
		var u0 := TAU * float(s) / float(seg)
		var u1 := TAU * float(s + 1) / float(seg)
		var a := Vector3(sin(u0) * rx, 0.0, cos(u0) * rz)
		var b := Vector3(sin(u1) * rx, 0.0, cos(u1) * rz)
		_acc_quad(st, a + Vector3(0.0, y0, 0.0), a + Vector3(0.0, y1, 0.0),
				b + Vector3(0.0, y1, 0.0), b + Vector3(0.0, y0, 0.0), colour)


static func _acc_dome_at(centre: Vector3, r: Vector3, u: float, v: float) -> Vector3:
	return centre + Vector3(sin(u) * cos(v) * r.x, sin(v) * r.y, cos(u) * cos(v) * r.z)


## The top half of an ellipsoid, equator to pole. The last ring is a fan so there are no
## zero-area triangles at the pole for generate_normals() to choke on.
static func _acc_dome(st: SurfaceTool, centre: Vector3, r: Vector3, colour: Color, seg: int, rings: int) -> void:
	var top := centre + Vector3(0.0, r.y, 0.0)
	for ring in rings:
		var v0 := PI * 0.5 * float(ring) / float(rings)
		var v1 := PI * 0.5 * float(ring + 1) / float(rings)
		for s in seg:
			var u0 := TAU * float(s) / float(seg)
			var u1 := TAU * float(s + 1) / float(seg)
			var p00 := _acc_dome_at(centre, r, u0, v0)
			var p10 := _acc_dome_at(centre, r, u1, v0)
			if ring == rings - 1:
				_acc_tri(st, p00, top, p10, colour)
			else:
				_acc_quad(st, p00, _acc_dome_at(centre, r, u0, v1), _acc_dome_at(centre, r, u1, v1), p10, colour)


## A cap peak: half an ellipse reaching forward (+Z) from the band, drooping by `drop` at the tip.
static func _acc_brim(st: SurfaceTool, y: float, reach: float, half_width: float, drop: float,
		thick: float, colour: Color, seg: int) -> void:
	var down := Vector3(0.0, -thick, 0.0)
	var hub := Vector3(0.0, y, 0.0)
	var pts: Array[Vector3] = []
	for i in seg + 1:
		var a := -PI * 0.5 + PI * float(i) / float(seg)
		pts.append(Vector3(sin(a) * half_width, y - drop * cos(a), cos(a) * reach))
	for i in seg:
		_acc_tri(st, hub, pts[i + 1], pts[i], colour)
		_acc_tri(st, hub + down, pts[i] + down, pts[i + 1] + down, colour)
		_acc_quad(st, pts[i], pts[i + 1], pts[i + 1] + down, pts[i] + down, colour)


## The generated walk and idle clips hold the arms out from the body like a scarecrow: the
## retarget put the shoulders in an A-pose and animated the swing on top of that, so every
## person in the city walks around with their arms at 45 degrees. The clips animate the
## shoulders as well, so a pose override would be overwritten every frame; instead the
## shoulder rotation keys are rotated once, on the shared animation resource, which costs
## nothing at runtime and fixes every instance of the model at the same time.
##
## `ARM_DROP_DEG` is how far the arms come down toward the body, `ARM_TUCK_DEG` how far they
## come in toward the chest. Both are tuned by eye against a render.
## Per model, because the two rigs do not share a rest pose: the same correction that puts A's
## arms by its sides leaves C's still held out. Negative brings the arms down.
const ARM_DROP := {"pedestrian_a_anim.glb": -46.0, "pedestrian_c_anim.glb": -76.0}
const ARM_DROP_DEFAULT := -46.0
const ARM_BONES := ["LeftShoulder", "RightShoulder"]
static var _arms_fixed: Dictionary = {}


static func fix_arm_pose(anim: AnimationPlayer, model_path: String) -> void:
	if anim == null or _arms_fixed.has(model_path):
		return
	_arms_fixed[model_path] = true
	var drop: float = ARM_DROP.get(model_path.get_file(), ARM_DROP_DEFAULT)
	var override := OS.get_environment("ARM_DROP_" + model_path.get_file().get_basename())
	if override != "":
		drop = float(override)
	for clip in anim.get_animation_list():
		var a := anim.get_animation(clip)
		for t in a.get_track_count():
			if a.track_get_type(t) != Animation.TYPE_ROTATION_3D:
				continue
			var bone := str(a.track_get_path(t)).get_slice(":", 1)
			var index := ARM_BONES.find(bone)
			if index < 0:
				continue
			# Mirror the correction for the right side.
			var sign_ := 1.0 if index == 0 else -1.0
			var fix := Quaternion(Vector3(0.0, 0.0, 1.0), deg_to_rad(drop) * sign_)
			for k in a.track_get_key_count(t):
				var q: Quaternion = a.track_get_key_value(t, k)
				a.track_set_key_value(t, k, (fix * q).normalized())


## Fixes an instantiated rig so it renders right (shared by pedestrians, ragdolls and the
## player's avatar). The rig's skeleton is in centimeters under a 0.01 armature while the mesh
## bounds are in meters, so the imported AABB is 2 cm tall and the renderer culls the character:
## give the skinned mesh a generous box in skeleton units. Meshy's animated export also keeps
## only the base color and leaves the glTF defaults of metallic 1 plus a full emission of the
## same texture (a shiny, self-lit mannequin): make it plain skin and cloth. The material is
## shared by every instance of the model.
static func prepare_rig(inst: Node3D, look: int = -1) -> void:
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).custom_aabb = AABB(Vector3(-150.0, -10.0, -150.0), Vector3(300.0, 260.0, 300.0))
		var mat := (mi as MeshInstance3D).mesh.surface_get_material(0) as StandardMaterial3D
		if mat and mat.metallic_texture == null:
			mat.metallic = 0.0
			mat.roughness = 0.85
			mat.emission_enabled = false
		if look >= 0 and mat:
			(mi as MeshInstance3D).material_override = character_material(mat.albedo_texture, look)


## Character materials, shared by look so a crowd of hundreds still uses a handful of materials.
## `look` picks a clothing hue and brightness; see shaders/character.gdshader.
## Skin tones, as multipliers on the model's own complexion (see shaders/character.gdshader).
## Spread across the looks so a crowd is not three people copied a thousand times.
const SKIN_TINTS := [
	Color(1.03, 0.99, 0.95), Color(0.97, 0.91, 0.84), Color(0.88, 0.78, 0.67),
	Color(0.79, 0.67, 0.56), Color(0.68, 0.56, 0.46), Color(0.56, 0.44, 0.36),
	Color(0.93, 0.86, 0.79),
]
## Hair, beards and eyebrows. Taken outright rather than tinted (see the shader): the source
## hair is nearly black on every model, so a tint of it stays nearly black and a whole city
## walks around with the same head. Weighted the way a street looks - mostly dark, a few fair,
## the odd grey head.
const HAIR_COLORS := [
	Color(0.045, 0.038, 0.035), Color(0.075, 0.058, 0.048), Color(0.13, 0.090, 0.060),
	Color(0.20, 0.135, 0.085), Color(0.30, 0.190, 0.105), Color(0.42, 0.285, 0.145),
	Color(0.36, 0.150, 0.075), Color(0.55, 0.425, 0.225), Color(0.72, 0.600, 0.380),
	Color(0.52, 0.505, 0.485), Color(0.78, 0.770, 0.745),
]
const CHARACTER_LOOKS := 24
## Texture-value bands the character shader splits skin, hair and cloth on, written in gamma
## (sRGB) space - the numbers you read straight off the texture file in an image viewer.
## Measured over triangle-interior samples of both rigs: garments and hair top out near value
## 0.40 and lit skin starts near 0.65, so SKIN_VALUE_BAND sits in the gap with room either side.
## Brightness is the only test that separates them on pedestrian_c, whose jacket and trousers are
## the same warm brown as its skin.
const SKIN_VALUE_BAND := Vector2(0.44, 0.62)
## Hair is the dark half of the head band, the face the bright half. Hair sits at 0.19-0.40 and a
## face at 0.65-0.95 on both rigs.
const HAIR_VALUE_BAND := Vector2(0.32, 0.55)
## Below the first number a pixel is a seam, a deep fold or the shadow under a hem: hue means
## nothing there and recolouring it makes fabric look printed on. Above the second it is cloth
## and takes the garment colour in full. The band used to be 0.045..0.13, which put the rigs'
## own near-black trousers (about 0.10) only halfway up it, so trousers took barely half the
## recolour and stayed black however they were rolled.
const CLOTH_VALUE_BAND := Vector2(0.030, 0.075)
## The source hair's own shading is mapped from this value band onto this brightness range, so a
## recoloured head still shows strands and roots instead of going flat. Applied in gamma space
## inside the shader, so unlike the bands above this one is not converted per renderer.
const HAIR_SHADE_BAND := Vector2(0.18, 0.45)
const HAIR_SHADE_RANGE := Vector2(0.55, 1.0)
static var _looks: Dictionary = {}


## Moves a texture-value threshold from gamma (sRGB) space into whichever space this renderer
## hands `source_color` textures back in.
##
## Forward+ and Mobile sample such a texture through an sRGB view, so the shader sees a LINEAR
## value; the Compatibility renderer (the web build) hands back the raw sRGB texels. The picture
## on screen is the same either way, but the numbers the shader compares against are not, and
## every threshold in character.gdshader was written against the sRGB ones. On desktop that put
## every threshold in the wrong place: a garment at sRGB 0.35 arrives as 0.10, its saturation
## arrives much higher, and the shader called the whole body skin - so no pedestrian's clothes
## were ever recoloured in the Mac build at all. Verified by rendering a known grey through a
## source_color sampler under both renderers.
static func _texture_is_linear() -> bool:
	return RenderingServer.get_current_rendering_method() != "gl_compatibility"


static func _texture_value(v: float) -> float:
	if not _texture_is_linear():
		return v
	return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)


static func character_material(albedo: Texture2D, look: int) -> ShaderMaterial:
	if albedo == null:
		return null
	var key := "%d_%d" % [albedo.get_instance_id(), look % CHARACTER_LOOKS]
	if _looks.has(key):
		return _looks[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 4200 + (look % CHARACTER_LOOKS)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/character.gdshader")
	mat.set_shader_parameter("albedo_tex", albedo)
	# One look in five keeps the original outfit, so the source clothes still appear.
	var plain := look % 5 == 0
	# The top, rolled as a wardrobe rather than as one range. `cloth_value` is the garment's own
	# brightness, 0 black to 1 white; the shader keeps the source texture's value as shading
	# around it. It used to be a multiplier on that source value, which is why the whole city
	# wore black: the rigs' garments are dark in the texture and their trousers nearly so, and
	# no multiplier lifts a dark texel to a white shirt.
	var top := rng.randf()
	mat.set_shader_parameter("cloth_hue", rng.randf())
	if top < 0.30:
		# White, cream, pale grey - the commonest thing anybody actually wears.
		mat.set_shader_parameter("cloth_sat", rng.randf_range(0.0, 0.09))
		mat.set_shader_parameter("cloth_value", rng.randf_range(0.80, 0.96))
	elif top < 0.56:
		# Mid tones: navy, olive, burgundy, tan.
		mat.set_shader_parameter("cloth_sat", rng.randf_range(0.18, 0.42))
		mat.set_shader_parameter("cloth_value", rng.randf_range(0.30, 0.58))
	elif top < 0.80:
		# Dark: black, charcoal, deep navy. Still a quarter of the street, just not all of it.
		mat.set_shader_parameter("cloth_hue", rng.randf_range(0.55, 0.72))
		mat.set_shader_parameter("cloth_sat", rng.randf_range(0.0, 0.20))
		mat.set_shader_parameter("cloth_value", rng.randf_range(0.07, 0.22))
	else:
		# Something bright.
		mat.set_shader_parameter("cloth_sat", rng.randf_range(0.45, 0.80))
		mat.set_shader_parameter("cloth_value", rng.randf_range(0.45, 0.78))
	# High, because what it mixes AWAY from is the source garment, which is near-black: at 0.7
	# a white shirt still came out mid-grey once Forward+ had linearised the base underneath it.
	mat.set_shader_parameter("cloth_strength", 0.0 if plain else rng.randf_range(0.80, 0.95))
	# Trousers are rolled apart from the top, and weighted the way a pavement actually looks:
	# denim, black and grey, khaki, and only occasionally something bright. Matching the top to
	# the bottom is what made every recoloured character read as wearing a boiler suit.
	var lower := rng.randf()
	if lower < 0.40:
		mat.set_shader_parameter("pants_hue", rng.randf_range(0.55, 0.68)) # denim
		mat.set_shader_parameter("pants_sat", rng.randf_range(0.10, 0.34))
		mat.set_shader_parameter("pants_value", rng.randf_range(0.16, 0.38))
	elif lower < 0.70:
		mat.set_shader_parameter("pants_hue", rng.randf()) # black through to pale grey
		mat.set_shader_parameter("pants_sat", rng.randf_range(0.0, 0.07))
		mat.set_shader_parameter("pants_value", rng.randf_range(0.06, 0.72))
	elif lower < 0.90:
		mat.set_shader_parameter("pants_hue", rng.randf_range(0.07, 0.20)) # khaki, sand, olive
		mat.set_shader_parameter("pants_sat", rng.randf_range(0.12, 0.32))
		mat.set_shader_parameter("pants_value", rng.randf_range(0.40, 0.66))
	else:
		mat.set_shader_parameter("pants_hue", rng.randf())
		mat.set_shader_parameter("pants_sat", rng.randf_range(0.30, 0.55))
		mat.set_shader_parameter("pants_value", rng.randf_range(0.28, 0.58))
	mat.set_shader_parameter("pants_strength", 0.0 if plain else rng.randf_range(0.82, 0.96))
	mat.set_shader_parameter("hair_color", HAIR_COLORS[rng.randi() % HAIR_COLORS.size()])
	mat.set_shader_parameter("hair_strength", rng.randf_range(0.75, 1.0))
	mat.set_shader_parameter("skin_tint", SKIN_TINTS[look % SKIN_TINTS.size()])
	# Every threshold the shader compares a texture value against, moved into this renderer's
	# colour space (see _texture_value). Cheaper than converting the sample per pixel, and the
	# two renderers then classify identically.
	mat.set_shader_parameter("skin_value_lo", _texture_value(SKIN_VALUE_BAND.x))
	mat.set_shader_parameter("skin_value_hi", _texture_value(SKIN_VALUE_BAND.y))
	mat.set_shader_parameter("hair_value_lo", _texture_value(HAIR_VALUE_BAND.x))
	mat.set_shader_parameter("hair_value_hi", _texture_value(HAIR_VALUE_BAND.y))
	mat.set_shader_parameter("cloth_value_lo", _texture_value(CLOTH_VALUE_BAND.x))
	mat.set_shader_parameter("cloth_value_hi", _texture_value(CLOTH_VALUE_BAND.y))
	# The garment colours and the hair shading ramp are built in gamma space inside the shader,
	# so they only need to know which space the texture arrived in.
	mat.set_shader_parameter("value_is_linear", 1.0 if _texture_is_linear() else 0.0)
	# Straight-line fit of the hair shading ramp across its band.
	var shade_gain := (HAIR_SHADE_RANGE.y - HAIR_SHADE_RANGE.x) / maxf(HAIR_SHADE_BAND.y - HAIR_SHADE_BAND.x, 0.0001)
	mat.set_shader_parameter("hair_shade_gain", shade_gain)
	mat.set_shader_parameter("hair_shade_bias", HAIR_SHADE_RANGE.x - shade_gain * HAIR_SHADE_BAND.x)
	_looks[key] = mat
	return mat


func _add_hit_area() -> void:
	# Hit detector: anything fast on the props layer, or a fast player.
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 2 | 4
	var ashape := CollisionShape3D.new()
	var abox := BoxShape3D.new()
	abox.size = Vector3(1.0, 1.8, 1.0)
	ashape.shape = abox
	ashape.position = Vector3(0.0, 0.9, 0.0)
	area.add_child(ashape)
	area.body_entered.connect(_on_body_entered)
	add_child(area)


func _part(size: Vector3, pos: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = PropFactory.material(color, 0.8)
	mesh.position = pos
	_visual.add_child(mesh)


func _physics_process(delta: float) -> void:
	if _down:
		return
	_lod_timer += delta
	if _lod_timer >= 0.5:
		_lod_timer = 0.0
		_update_lod()
	_lod_tick += 1
	if _lod_stride > 1 and _lod_tick % _lod_stride != 0:
		return
	delta *= _lod_stride
	if _anim:
		_anim.advance(delta)
	# Standing still: waiting at a kerb, looking in a window, checking a phone. A crowd where
	# every single person walks without ever stopping reads as a conveyor belt.
	if _pause_left > 0.0:
		_pause_left -= delta
		velocity.x = 0.0
		velocity.z = 0.0
		velocity.y = 0.0 if is_on_floor() else velocity.y - 30.0 * delta
		move_and_slide()
		if _pause_left <= 0.0:
			_play_walk()
		return
	var here := Vector2(global_position.x, global_position.z) - _ring_origin()
	var to_target := _target - here
	if to_target.length() < 1.0:
		_target = _random_ring_point(_sidewalk)
		to_target = _target - here
		if _anim and _anim.has_animation(IDLE_CLIP) and _style.randf() < pause_chance:
			_pause_left = _style.randf_range(pause_seconds.x, pause_seconds.y)
			_play_idle()
	var dir := to_target.normalized()
	velocity.x = dir.x * walk_speed
	velocity.z = dir.y * walk_speed
	if not is_on_floor():
		velocity.y -= 30.0 * delta
	else:
		velocity.y = 0.0
	move_and_slide()
	_visual.rotation.y = lerp_angle(_visual.rotation.y, atan2(-dir.x, -dir.y), 1.0 - exp(-8.0 * delta))
	if _anim == null:
		_bob += delta * walk_speed * 4.0
		_visual.position.y = absf(sin(_bob)) * 0.06


## Far pedestrians move and animate every 3rd (past lod_mid) or 6th (past lod_far) physics
## frame with a matching delta, so a crowd of hundreds costs what a few dozen used to.
static var lod_mid: float = 60.0
static var lod_far: float = 140.0


func _update_lod() -> void:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player == null:
			_lod_stride = 1
			return
	var d := global_position.distance_to(_player.global_position)
	_lod_stride = 1 if d < lod_mid else (3 if d < lod_far else 6)


## Ring points are stored relative to the chunk's world offset so re-centering does not matter.
func _ring_origin() -> Vector2:
	return Vector2.ZERO


func _random_ring_point(sidewalk: float) -> Vector2:
	# A point on the sidewalk ring: pick an edge, then a spot 1..(sidewalk-1) m in from the curb.
	var inset := _rng.randf_range(1.0, maxf(sidewalk - 1.0, 1.2))
	var edge := _rng.randi() % 4
	match edge:
		0:
			return Vector2(_rng.randf_range(ring.position.x + 1.0, ring.end.x - 1.0), ring.position.y + inset)
		1:
			return Vector2(_rng.randf_range(ring.position.x + 1.0, ring.end.x - 1.0), ring.end.y - inset)
		2:
			return Vector2(ring.position.x + inset, _rng.randf_range(ring.position.y + 1.0, ring.end.y - 1.0))
		_:
			return Vector2(ring.end.x - inset, _rng.randf_range(ring.position.y + 1.0, ring.end.y - 1.0))


func _on_body_entered(body: Node3D) -> void:
	if _down:
		return
	var speed := 0.0
	var dir := Vector3.UP
	if body is RigidBody3D:
		speed = (body as RigidBody3D).linear_velocity.length()
		dir = (body as RigidBody3D).linear_velocity.normalized()
		if body is Vehicle and (body as Vehicle).is_traffic():
			speed = (body as Vehicle).traffic_speed
			dir = -(body as Vehicle).global_basis.z
	elif body is Player:
		speed = (body as Player).velocity.length()
		dir = (body as Player).velocity.normalized()
		if speed < tackle_speed:
			return
	if speed >= knock_speed:
		knock(dir * (8.0 + speed * 0.6) + Vector3.UP * 6.0)


## Turns into a ragdoll flung by `impulse`.
func knock(impulse: Vector3) -> void:
	if _down:
		return
	_down = true
	Sfx.play("yelp", global_position, 0.0, _rng.randf_range(0.8, 1.3))
	var doll := Ragdoll.new()
	doll.position = position
	doll.rotation.y = _visual.rotation.y
	get_parent().add_child(doll)
	if _model_path == "" or not doll.build_from_rig(_model_path, _look):
		doll.build(shirt, pants, skin)
	PhysicsBudget.register_debris(doll)
	doll.fling(impulse)
	queue_free()
