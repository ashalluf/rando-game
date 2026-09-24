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
## These are the second generation (2026-09-22, owner: "we need entirely new assets for the
## humans"), made at twice the first set's polycount. The first set - a, b and c - is no longer
## loaded: b came back unclothed, and a and c are visibly lower-detail than the people walking
## next to them, which reads worse in a crowd than having fewer faces. Their files stay so the
## decision is visible.
const MODELS := [
	"res://assets/models/pedestrian_d_anim.glb",
	"res://assets/models/pedestrian_e_anim.glb",
	"res://assets/models/pedestrian_f_anim.glb",
	"res://assets/models/pedestrian_g_anim.glb",
	"res://assets/models/pedestrian_h_anim.glb",
	"res://assets/models/pedestrian_i_anim.glb",
	"res://assets/models/pedestrian_j_anim.glb",
	"res://assets/models/pedestrian_k_anim.glb",
	"res://assets/models/pedestrian_l_anim.glb",
]
## Walking speed (m/s) at which the walk clip plays at its natural pace.
const WALK_CLIP_SPEED := 1.3
const WALK_CLIP := "Casual_Walk_inplace"
const IDLE_CLIP := "Idle"
## The run cycle the player's avatar uses too, and the speed it plays at its natural pace.
const RUN_CLIP := "run_fast_3_inplace"
const RUN_CLIP_SPEED := 5.0

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
## Running pace when frightened (m/s).
@export var run_speed: float = 5.2
## How long a scare lasts (seconds, min and max). Another shot while running starts it again.
@export var panic_seconds: Vector2 = Vector2(7.0, 12.0)

## Seconds of panic left; above zero the pedestrian runs away from `_threat` and never pauses.
var _panic_left: float = 0.0
## Where the scare came from (the same XZ space as `ring`).
var _threat := Vector2.ZERO
## Counts down to this pedestrian's scream; below zero, no scream is due.
var _scream_in: float = -1.0
## When and where the last alarm went off, so an automatic rifle does not re-scan the crowd ten
## times a second from the same spot.
static var _last_alarm_ms: int = -100000
static var _last_alarm_at := Vector3.INF
## When the last scream started. Screams are spaced out across the whole crowd: a hundred people
## screaming in the same frame is one loud noise, a few overlapping voices is a panicking street.
static var _last_scream_ms: int = -100000
## Shortest gap between two screams anywhere (milliseconds).
static var scream_gap_ms: int = 140

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
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		_meshes.append(mi as MeshInstance3D)
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


## Arm retarget. The generated clips were authored for a skeleton whose arms hang straight, but
## every generated rig is bound in whatever pose its mesh came out in - an A-pose for the first
## two, a palms-up shrug with the forearms raised for the newer ones - and the clips drive the
## arm bones as if that rest pose were the canonical one. So the arms came out held out like a
## scarecrow, or with the hands up by the ears. Rotating fixed amounts off the keys (the old
## ARM_DROP) had to be tuned per rig by eye and still left the forearms and wrists wrong.
##
## Instead the arm keys are rebuilt from the rig's own rest pose: the upper arm hangs from the
## shoulder with a little spread, swings opposite the same-side thigh (the phase is read from
## the clip's own legs, so the arms stay in step with the feet), the elbow bends forward and
## bends more as the arm comes forward, the forearm and wrist turn the palm to face the thigh,
## and the wrist is straightened. All of it is in the chest's frame, so the shoulders' twist
## and the torso's lean carry the arms with them. The clips animate these bones, so a pose
## override would be overwritten every frame; this runs once per model on the shared animation
## resource, so it costs nothing at runtime and fixes every instance at the same time.
## Judge a change with tools/glshot/character_shot.gd, front AND side.
##
## Per clip kind (matched against the clip name): swing amplitude, forward bias of the swing,
## elbow bend, extra elbow bend at the front of the swing, spread of the upper arm from the
## body, and how far the forearm comes back in from that spread. Degrees.
## The last two are a pair: the upper arm has to clear the ribs and the jacket, but carried on
## down the forearm the same angle leaves the hand a hand's width off the thigh, and a crowd of
## people walking with their hands held out from their sides reads as gunslingers.
const ARM_GAIT := {
	"run": [34.0, 8.0, 78.0, 14.0, 12.0, 4.0],
	"walk": [15.0, 4.0, 15.0, 15.0, 9.0, 7.0],
	"idle": [0.0, 3.0, 12.0, 0.0, 8.0, 7.0],
}
## Extra spread per model file (degrees), for a bulky jacket the arms would pass through.
const ARM_SPREAD := {}
## Palm turn (degrees) carried by the forearm and by the wrist. Split, because linear skinning
## puts all of a single bone's twist at one joint and a whole quarter turn there pinches it.
## Measured, not assumed: 60 in total puts the palm on the thigh with the hand edge-on from the
## front; 85 left the hands as open fans, and past that the palms turn to face forward.
const FOREARM_TWIST := 32.0
const WRIST_TWIST := 28.0
static var _arms_fixed: Dictionary = {}


static func fix_arm_pose(anim: AnimationPlayer, model_path: String) -> void:
	if anim == null or _arms_fixed.has(model_path):
		return
	var root := anim.get_node_or_null(anim.root_node)
	if root == null:
		return
	var found := root.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		return
	var skel: Skeleton3D = found[0]
	_arms_fixed[model_path] = true
	var spread_extra: float = ARM_SPREAD.get(model_path.get_file(), 0.0)
	for clip in anim.get_animation_list():
		var a := anim.get_animation(clip)
		var gait: Array = ARM_GAIT["idle"]
		for kind in ARM_GAIT:
			if String(clip).to_lower().contains(kind):
				gait = ARM_GAIT[kind]
				break
		var tracks := {}
		for t in a.get_track_count():
			if a.track_get_type(t) == Animation.TYPE_ROTATION_3D:
				var bi := skel.find_bone(String(a.track_get_path(t).get_concatenated_subnames()))
				if bi >= 0:
					tracks[bi] = t
		_retarget_arm(a, skel, tracks, 1.0, gait, spread_extra)
		_retarget_arm(a, skel, tracks, -1.0, gait, spread_extra)


## Rebuilds one arm's keys in `a`. `side` is +1 for the left arm (the rigs face +Z, so their
## left is +X) and -1 for the right.
static func _retarget_arm(a: Animation, skel: Skeleton3D, tracks: Dictionary, side: float,
		gait: Array, spread_extra: float) -> void:
	var pre := "Left" if side > 0.0 else "Right"
	var arm := skel.find_bone(pre + "Arm")
	var fore := skel.find_bone(pre + "ForeArm")
	var hand := skel.find_bone(pre + "Hand")
	if arm < 0 or fore < 0 or hand < 0 or not tracks.has(arm) or not tracks.has(fore):
		return
	var shoulder := skel.get_bone_parent(arm)
	var chest := skel.get_bone_parent(shoulder)
	# The collarbone first, because the arm keys are written relative to it. The clips hold it
	# 8 to 20 degrees below level the whole way round - the same retarget mismatch as the arms -
	# which slumps the shoulders and squares them off. Every rig's own rest collarbone is level,
	# so the keys are turned until their average lies on it: the shoulders' bob through the
	# stride stays, the slump goes.
	if tracks.has(shoulder):
		var t_sh: int = tracks[shoulder]
		var reach := skel.get_bone_rest(arm).origin.normalized()
		var mean := Vector3.ZERO
		for k in a.track_get_key_count(t_sh):
			mean += (a.track_get_key_value(t_sh, k) as Quaternion) * reach
		if mean.length() > 0.001:
			var level := Quaternion(mean.normalized(), skel.get_bone_rest(shoulder).basis.get_rotation_quaternion() * reach)
			for k in a.track_get_key_count(t_sh):
				a.track_set_key_value(t_sh, k, (level * (a.track_get_key_value(t_sh, k) as Quaternion)).normalized())
	var arm_rest := _rest_rot(skel, arm)
	var fore_rest := _rest_rot(skel, fore)
	var chest_rest_inv := _rest_rot(skel, chest).inverse()
	# The rest pose's upper arm and forearm directions and the elbow's hinge axis between them.
	var u0 := (arm_rest * skel.get_bone_rest(fore).origin).normalized()
	var f0 := (fore_rest * skel.get_bone_rest(hand).origin).normalized()
	var h0 := u0.cross(f0)
	if h0.length() < 0.1:
		h0 = u0.cross(Vector3.BACK)
	h0 = h0.normalized()
	var rest_u := Basis(u0, h0, u0.cross(h0)).transposed()
	var rest_f := Basis(f0, h0, f0.cross(h0)).transposed()

	# Arm swing phase from the same-side thigh: the arm is forward while that leg is back.
	var thigh := skel.find_bone(pre + "UpLeg")
	var knee := skel.find_bone(pre + "Leg")
	var leg_mid := 0.0
	var leg_amp := 0.0
	if thigh >= 0 and knee >= 0 and gait[0] > 0.0:
		var lo := INF
		var hi := -INF
		for i in 48:
			var ang := _thigh_angle(a, skel, tracks, thigh, knee, a.length * float(i) / 48.0)
			lo = minf(lo, ang)
			hi = maxf(hi, ang)
		leg_mid = (lo + hi) * 0.5
		leg_amp = (hi - lo) * 0.5
	var spread := deg_to_rad(gait[4] + spread_extra) * side

	var target := func(time: float) -> Array:
		var swing := 0.0
		if leg_amp > deg_to_rad(2.0):
			swing = -(_thigh_angle(a, skel, tracks, thigh, knee, time) - leg_mid) / leg_amp
		var elbow := deg_to_rad(gait[2] + gait[3] * clampf(swing, 0.0, 1.0))
		# Hanging straight down with the elbow hinge along -X, then spread out from the body,
		# swung about the shoulders' lateral axis, then turned with the chest. Only its turn,
		# not its lean: the clips tip the torso about seven degrees forward, and arms carried
		# by that pitch trail behind the body instead of hanging under gravity.
		var chest_fwd := (_pose_rot(a, skel, tracks, chest, time) * chest_rest_inv) * Vector3.BACK
		var turn := Quaternion(Vector3.UP, atan2(chest_fwd.x, chest_fwd.z))
		var frame := turn * Quaternion(Vector3.LEFT, deg_to_rad(gait[1] + gait[0] * swing)) \
				* Quaternion(Vector3.BACK, spread)
		var u1 := frame * Vector3.DOWN
		var h1 := frame * Vector3.LEFT
		var f1 := Quaternion(turn * Vector3.BACK, -deg_to_rad(gait[5]) * side) * (Quaternion(h1, elbow) * u1)
		var hf := (h1 - f1 * h1.dot(f1)).normalized()
		var g_arm := Quaternion(Basis(u1, h1, u1.cross(h1)) * rest_u) * arm_rest
		var g_fore := Quaternion(f1, deg_to_rad(FOREARM_TWIST) * side) \
				* Quaternion(Basis(f1, hf, f1.cross(hf)) * rest_f) * fore_rest
		return [g_arm.normalized(), g_fore.normalized()]

	var t_arm: int = tracks[arm]
	for k in a.track_get_key_count(t_arm):
		var time := a.track_get_key_time(t_arm, k)
		var g: Array = target.call(time)
		var parent := _pose_rot(a, skel, tracks, shoulder, time)
		a.track_set_key_value(t_arm, k, (parent.inverse() * (g[0] as Quaternion)).normalized())
	var t_fore: int = tracks[fore]
	for k in a.track_get_key_count(t_fore):
		var g: Array = target.call(a.track_get_key_time(t_fore, k))
		a.track_set_key_value(t_fore, k, ((g[0] as Quaternion).inverse() * (g[1] as Quaternion)).normalized())
	# The wrist: straightened onto the forearm's axis, then the rest of the palm turn.
	if tracks.has(hand):
		var hand_rest := skel.get_bone_rest(hand).basis.get_rotation_quaternion()
		var axis := skel.get_bone_rest(hand).origin.normalized()
		var q := Quaternion(axis, deg_to_rad(WRIST_TWIST) * side) * Quaternion(hand_rest * Vector3.UP, axis) * hand_rest
		var t_hand: int = tracks[hand]
		for k in a.track_get_key_count(t_hand):
			a.track_set_key_value(t_hand, k, q.normalized())


static func _rest_rot(skel: Skeleton3D, bone: int) -> Quaternion:
	return skel.get_bone_global_rest(bone).basis.get_rotation_quaternion()


## A bone's skeleton-space rotation at `time` in `a`, walking up the chain from the clip's keys
## (the rest rotation where a bone has no track).
static func _pose_rot(a: Animation, skel: Skeleton3D, tracks: Dictionary, bone: int, time: float) -> Quaternion:
	var q := Quaternion.IDENTITY
	var b := bone
	while b >= 0:
		var local: Quaternion
		if tracks.has(b):
			local = a.rotation_track_interpolate(tracks[b], time)
		else:
			local = skel.get_bone_rest(b).basis.get_rotation_quaternion()
		q = local * q
		b = skel.get_bone_parent(b)
	return q


## Forward pitch of the thigh at `time` (radians, positive is the knee forward).
static func _thigh_angle(a: Animation, skel: Skeleton3D, tracks: Dictionary, thigh: int, knee: int, time: float) -> float:
	var d := _pose_rot(a, skel, tracks, thigh, time) * skel.get_bone_rest(knee).origin
	return atan2(d.z, -d.y)


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
## Small on purpose. With two models these went down to 0.56, to stand in for a range of
## complexions the models did not have - and multiplying a pale face that far gives grey mud,
## not a darker person. The range of people now comes from the models themselves; this only
## keeps two copies of one model from being the same colour.
const SKIN_TINTS := [
	Color(1.02, 0.99, 0.96), Color(0.97, 0.93, 0.88), Color(1.0, 1.0, 1.0),
	Color(0.93, 0.88, 0.82), Color(1.03, 1.0, 0.98), Color(0.95, 0.91, 0.86),
	Color(0.99, 0.95, 0.91),
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


## How hard the baked relief reads. The maps carry a tangent slope of about 8 degrees, which is
## fabric weave and skin, not armour plate, so this wants to stay near 1.
const NORMAL_STRENGTH := 1.0


## The relief map that goes with a rig's colour texture, or null if that rig has none.
static func _normal_map_for(albedo: Texture2D) -> Texture2D:
	var path := albedo.resource_path
	var cut := path.find("_anim_texture")
	if cut < 0:
		return null
	var nrm := path.substr(0, cut) + "_nrm.png"
	if not ResourceLoader.exists(nrm):
		return null
	return load(nrm) as Texture2D


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
	# The rig's baked relief map, named after the rig the albedo came from
	# (pedestrian_a_anim_texture_0.jpg -> pedestrian_a_nrm.png). Rigs without one keep
	# normal_strength at the shader's 0.0 and render off the mesh normal exactly as before.
	var nrm := _normal_map_for(albedo)
	if nrm != null:
		mat.set_shader_parameter("normal_tex", nrm)
		mat.set_shader_parameter("normal_strength", NORMAL_STRENGTH)
	# Half the looks keep the model's own outfit. The recolour was the only source of variety
	# when there were two models; with a real wardrobe of them, a photographed jacket beats a
	# repainted one, so it now only has to stop two copies of a model dressing alike.
	var plain := look % 2 == 0
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
	# A look that keeps the model's own clothes keeps its own hair too. The hair swap was rolled
	# for every look, so a Black woman in her own blazer came out blonde and a grey-haired man
	# came out black-haired - a recolour on a photographed person reads as a wig.
	mat.set_shader_parameter("hair_strength", 0.0 if plain else rng.randf_range(0.75, 1.0))
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


## The player's tracksuit: jacket and trousers in one velour colour with white piping down the
## sleeves and legs (shaders/character.gdshader). Its own material rather than a crowd look, so
## nobody on the street is dressed like the hero. Pair it with add_piping() on the same rig, or
## the stripes have no data to draw from.
static func tracksuit_material(albedo: Texture2D, color: Color) -> ShaderMaterial:
	var look := character_material(albedo, 1)
	if look == null:
		return null
	var mat := look.duplicate() as ShaderMaterial
	for part in ["cloth", "pants"]:
		mat.set_shader_parameter(part + "_hue", color.h)
		mat.set_shader_parameter(part + "_sat", color.s)
		mat.set_shader_parameter(part + "_value", color.v)
		mat.set_shader_parameter(part + "_strength", 0.97)
	# The rig's own hair and complexion: it is still the same person, just changed.
	mat.set_shader_parameter("hair_strength", 0.0)
	mat.set_shader_parameter("skin_tint", Color(1, 1, 1))
	mat.set_shader_parameter("cloth_roughness", 0.92)
	mat.set_shader_parameter("velour", TRACKSUIT_SHEEN)
	mat.set_shader_parameter("piping", 1.0)
	mat.set_shader_parameter("cloth_shade_keep", 0.5)
	return mat


## Rim sheen of the tracksuit's velour (0 flat cotton, 1 satin-bright edges).
const TRACKSUIT_SHEEN := 0.45
## Arm and leg bones that carry the piping, each with the bone its axis points at.
const PIPING_BONES := {
	"LeftArm": "LeftForeArm", "LeftForeArm": "LeftHand",
	"RightArm": "RightForeArm", "RightForeArm": "RightHand",
	"LeftUpLeg": "LeftLeg", "LeftLeg": "LeftFoot",
	"RightUpLeg": "RightLeg", "RightLeg": "RightFoot",
}


## Bakes where the tracksuit piping runs into every skinned mesh of a rig, as CUSTOM0: for each
## vertex, its signed distance in metres round its arm or leg from the limb's outer line, how
## much of it follows arm and leg bones and how squarely it faces outward; and as CUSTOM1 how
## much of it follows the head and the hands (the only places skin can be) and the feet (the
## shoes, which keep their own colour). Measured on the
## rest pose, so the stripes are part of the cloth and move with it rather than being painted
## on in screen or model space, where they would slide over the sleeve as the arm swings.
## The outer line of a leg is its side away from the body's midline; an arm's is taken from
## "out and a little up", which on an A-posed or T-posed rest arm is its top - the side that
## faces out once it hangs. Needs mesh data, which the headless dummy renderer does not keep:
## there it changes nothing.
static func add_piping(inst: Node3D) -> void:
	var skel := inst.find_child("Skeleton3D", true, false) as Skeleton3D
	if skel == null:
		return
	var rig_xf := Ragdoll._rig_space_of_skel(skel)
	var hips := skel.find_bone("Hips")
	var mid_x := (rig_xf * skel.get_bone_global_rest(hips).origin).x if hips >= 0 else 0.0
	for node in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.skin == null or mi.mesh == null or mi.mesh.get_surface_count() != 1:
			continue
		var arrays := mi.mesh.surface_get_arrays(0)
		if arrays.is_empty() or arrays[Mesh.ARRAY_BONES] == null or arrays[Mesh.ARRAY_WEIGHTS] == null:
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		if verts.is_empty() or bones.size() % verts.size() != 0:
			continue
		var per := bones.size() / verts.size()
		# Per skin bind: its rest transform into model space, and for a limb bone its axis
		# (origin, direction) and the frame round it (outer line, and the line 90 degrees on).
		var bind_xf: Array[Transform3D] = []
		var limb: Array = []
		for i in mi.skin.get_bind_count():
			var bname := String(mi.skin.get_bind_name(i))
			var bone := skel.find_bone(bname)
			var rest := skel.get_bone_global_rest(bone) if bone >= 0 else Transform3D.IDENTITY
			bind_xf.append(rig_xf * rest * mi.skin.get_bind_pose(i))
			var child := skel.find_bone(PIPING_BONES.get(bname, ""))
			if bone < 0 or child < 0:
				limb.append(null)
				continue
			var o := rig_xf * rest.origin
			var axis := (rig_xf * skel.get_bone_global_rest(child).origin - o).normalized()
			var side := signf(o.x - mid_x)
			var hint := Vector3(side, 0.6 if bname.ends_with("Arm") else 0.0, 0.0)
			var out := (hint - axis * hint.dot(axis)).normalized()
			limb.append([o, axis, out, axis.cross(out) * side])
		# 1 the head, 2 a hand, 3 a foot.
		var skin_bind := PackedByteArray()
		skin_bind.resize(mi.skin.get_bind_count())
		for i in mi.skin.get_bind_count():
			var bn := String(mi.skin.get_bind_name(i))
			skin_bind[i] = 1 if bn.begins_with("head") or bn == "Head" else (2 if bn.ends_with("Hand") else (3 if bn.ends_with("Foot") or bn.ends_with("ToeBase") else 0))
		var custom := PackedFloat32Array()
		custom.resize(verts.size() * 3)
		var custom1 := PackedFloat32Array()
		custom1.resize(verts.size() * 3)
		for v in verts.size():
			var pos := Vector3.ZERO
			var total := 0.0
			var on_limb := 0.0
			var on_head := 0.0
			var on_hand := 0.0
			var on_foot := 0.0
			var best := -1
			var best_w := 0.0
			for k in per:
				var w := weights[v * per + k]
				var bi := bones[v * per + k]
				if w <= 0.0 or bi < 0 or bi >= bind_xf.size():
					continue
				pos += bind_xf[bi] * verts[v] * w
				total += w
				if skin_bind[bi] == 1:
					on_head += w
				elif skin_bind[bi] == 2:
					on_hand += w
				elif skin_bind[bi] == 3:
					on_foot += w
				if limb[bi] != null:
					on_limb += w
					if w > best_w:
						best_w = w
						best = bi
			pos /= maxf(total, 0.0001)
			var arc := 0.0
			var facing := -1.0
			if best >= 0:
				var l: Array = limb[best]
				var radial: Vector3 = pos - l[0]
				radial -= (l[1] as Vector3) * radial.dot(l[1])
				var r := radial.length()
				if r > 0.0001:
					var c := radial.dot(l[2]) / r
					arc = atan2(radial.dot(l[3]) / r, c) * r
					facing = c
			custom[v * 3] = arc
			custom[v * 3 + 1] = on_limb / maxf(total, 0.0001)
			custom[v * 3 + 2] = facing
			custom1[v * 3] = on_head / maxf(total, 0.0001)
			custom1[v * 3 + 1] = on_hand / maxf(total, 0.0001)
			custom1[v * 3 + 2] = on_foot / maxf(total, 0.0001)
		arrays[Mesh.ARRAY_CUSTOM0] = custom
		arrays[Mesh.ARRAY_CUSTOM1] = custom1
		var flags := (Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
		if per == 8:
			flags |= Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
		mesh.surface_set_material(0, mi.mesh.surface_get_material(0))
		mi.mesh = mesh


func _add_hit_area() -> void:
	# Hit detector: anything fast on the props layer, or a fast player.
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 2 | 4
	# Nothing looks for this zone, and a monitorable area sits in the broadphase's dynamic tree,
	# where every step it moves it is tested against the whole city's static geometry.
	area.monitorable = false
	var ashape := CollisionShape3D.new()
	_hit_shape = ashape
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
	var panicking := _panic_left > 0.0
	if panicking:
		_panic_left -= delta
		if _scream_in >= 0.0:
			_scream_in -= delta
			if _scream_in < 0.0:
				_scream()
		if _panic_left <= 0.0:
			_scream_in = -1.0
			_target = _random_ring_point(_sidewalk)
			_play_walk()
	# Standing still: waiting at a kerb, looking in a window, checking a phone. A crowd where
	# every single person walks without ever stopping reads as a conveyor belt.
	if _pause_left > 0.0:
		_pause_left -= delta
		velocity.x = 0.0
		velocity.z = 0.0
		# Someone standing on the pavement does not need a collision solve every step: only a
		# body that is still falling (just spawned, or knocked off a kerb) does.
		if not _kinematic and not is_on_floor():
			velocity.y -= 30.0 * delta
			move_and_slide()
		if _pause_left <= 0.0:
			_play_walk()
		return
	var here := Vector2(global_position.x, global_position.z) - _ring_origin()
	var to_target := _target - here
	if to_target.length() < 1.0:
		if panicking:
			_target = _flee_point()
		else:
			_target = _random_ring_point(_sidewalk)
		to_target = _target - here
		if not panicking and _anim and _anim.has_animation(IDLE_CLIP) and _style.randf() < pause_chance:
			_pause_left = _style.randf_range(pause_seconds.x, pause_seconds.y)
			_play_idle()
	var dir := to_target.normalized()
	var speed := run_speed if panicking else walk_speed
	velocity.x = dir.x * speed
	velocity.z = dir.y * speed
	if _kinematic:
		# Out of reach of the player: walk the pavement directly, on the chunk's own ground
		# height, with no collision solve. The ring is open pavement, so the path is the same
		# one move_and_slide would have taken.
		var at := position + Vector3(velocity.x, 0.0, velocity.z) * delta
		at.y = _ground_y(at.x, at.z, position.y)
		position = at
	else:
		if not is_on_floor():
			velocity.y -= 30.0 * delta
		else:
			velocity.y = 0.0
		move_and_slide()
	_visual.rotation.y = lerp_angle(_visual.rotation.y, atan2(-dir.x, -dir.y), 1.0 - exp(-(14.0 if panicking else 8.0) * delta))
	if _anim == null:
		_bob += delta * speed * 4.0
		_visual.position.y = absf(sin(_bob)) * 0.06


## Far pedestrians move and animate every 2nd (past physics_range), 4th (past lod_mid) or 8th
## (past lod_far) physics frame with a matching delta, so a crowd of hundreds costs what a few
## dozen used to.
static var lod_mid: float = 60.0
static var lod_far: float = 140.0
## Pedestrians cast shadows only inside this range (metres). Measured on a downtown street, the
## crowd was 6.4 of the frame's 15.7 million triangles, because all 650 of them - 16k-triangle
## rigs since 2026-09-22 - were drawn once for the camera and again into up to four shadow
## cascades. A person's shadow past this is a few pixels, and the one cast by the building behind
## them is what the eye reads anyway.
static var shadow_range: float = 45.0
## Mesh LOD bias per distance tier (near, mid, far): below 1 the renderer drops to the coarser
## generated LODs sooner. Nobody can see 16k triangles on a figure forty pixels tall.
const LOD_BIAS := [1.0, 0.45, 0.2]
## Most triangles a far body (past lod_far) may have. The models' own LODs stop at about 4,150
## of their 16,600: they are unwelded - nearly every triangle is its own UV island - and the
## importer will not simplify across a seam. So a crowd past 140 m, a third or more of it,
## still cost 4k triangles a figure eleven pixels tall.
static var far_triangles: int = 1100
## Far bodies, keyed by the model mesh they stand in for (see far_mesh()).
static var _far_meshes: Dictionary = {}
var _meshes: Array[MeshInstance3D] = []
var _draw_tier: int = -1
## Past this distance from the player (metres) a pedestrian walks without physics: no
## move_and_slide, no hit detector. Measured headless on a downtown block, the 625-strong crowd was
## 46 of 101 ms of physics a frame - a collision solve and an overlap test per person per step, to
## walk along flat pavement. Inside it everything is as before, so the ones you can reach still
## stumble, get knocked flying and stand on what they stand on.
static var physics_range: float = 35.0
var _kinematic: bool = false
var _hit_shape: CollisionShape3D


func _update_lod() -> void:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player == null:
			_lod_stride = 1
			return
	var d := global_position.distance_to(_player.global_position)
	# Every step only inside physics_range, where they can be touched; then 30, 15 and 7.5 Hz.
	# A figure forty metres off moves 6 cm between updates at walking pace, which nobody can see,
	# and the crowd's scripts were 12 ms of every physics step at every-step-to-60-metres.
	_lod_stride = 1 if d < physics_range else (2 if d < lod_mid else (4 if d < lod_far else 8))
	var kinematic := d > physics_range and not _down
	if kinematic != _kinematic:
		_kinematic = kinematic
		# Out of range the body keeps its layer (bullets, blasts and car bumpers still find it)
		# but drops its mask, and the hit zone leaves the broadphase: otherwise each of several
		# hundred walkers is paired with every kerb, slab and wall it passes, and re-paired every
		# time it moves, for collisions that can never happen.
		collision_mask = 0 if kinematic else 1
		if _hit_shape:
			_hit_shape.disabled = kinematic
		if kinematic:
			velocity = Vector3.ZERO
	var tier := 0 if d < shadow_range else (1 if d < lod_far else 2)
	if tier != _draw_tier:
		_draw_tier = tier
		for mi in _meshes:
			if is_instance_valid(mi):
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if tier == 0 \
					else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mi.lod_bias = LOD_BIAS[tier]
				if mi.skin:
					if not mi.has_meta("near_mesh"):
						mi.set_meta("near_mesh", mi.mesh)
					var near: Mesh = mi.get_meta("near_mesh")
					mi.mesh = far_mesh(near) if tier == 2 else near


## A coarse body for people past lod_far: the model welded to one vertex per position, so the
## simplifier can go all the way down, capped at far_triangles with its own LODs below that.
## Welding smears the texture across the seams, which at eleven pixels tall nobody can see.
## Built once per model (the loading screen does all nine); the original mesh when there is no
## mesh data to weld (the headless check).
static func far_mesh(mesh: Mesh) -> Mesh:
	if mesh == null:
		return mesh
	if _far_meshes.has(mesh):
		return _far_meshes[mesh]
	_far_meshes[mesh] = mesh
	var arrays := mesh.surface_get_arrays(0)
	if arrays.is_empty() or arrays[Mesh.ARRAY_INDEX] == null or arrays[Mesh.ARRAY_BONES] == null:
		return mesh
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if verts.is_empty():
		return mesh
	var per: int = (arrays[Mesh.ARRAY_BONES] as PackedInt32Array).size() / verts.size()
	var first := {}
	var order := PackedInt32Array()
	var weld := PackedInt32Array()
	weld.resize(verts.size())
	for v in verts.size():
		var key := Vector3i(roundi(verts[v].x * 2000.0), roundi(verts[v].y * 2000.0), roundi(verts[v].z * 2000.0))
		if not first.has(key):
			first[key] = order.size()
			order.append(v)
		weld[v] = first[key]
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	for a in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV]:
		if arrays[a] == null:
			continue
		var src = arrays[a]
		var dst = src.duplicate()
		dst.resize(order.size())
		for i in order.size():
			dst[i] = src[order[i]]
		out[a] = dst
	for a in [Mesh.ARRAY_TANGENT, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS]:
		if arrays[a] == null:
			continue
		var n := 4 if a == Mesh.ARRAY_TANGENT else per
		var src = arrays[a]
		var dst = src.duplicate()
		dst.resize(order.size() * n)
		for i in order.size():
			for k in n:
				dst[i * n + k] = src[order[i] * n + k]
		out[a] = dst
	var idx := PackedInt32Array()
	idx.resize(index.size())
	for i in index.size():
		idx[i] = weld[index[i]]
	out[Mesh.ARRAY_INDEX] = idx
	var material := mesh.surface_get_material(0)
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, out, [], {}, material)
	im.generate_lods(25.0, 60.0, [])
	var base: PackedInt32Array = idx
	for l in im.get_surface_lod_count(0):
		var lod := im.get_surface_lod_indices(0, l)
		if lod.size() / 3 <= far_triangles:
			base = lod
			break
	out[Mesh.ARRAY_INDEX] = base
	var far := ImporterMesh.new()
	far.add_surface(Mesh.PRIMITIVE_TRIANGLES, out, [], {}, material)
	far.generate_lods(25.0, 60.0, [])
	var result: Mesh = far.get_mesh()
	if result == null:
		return mesh
	_far_meshes[mesh] = result
	return result


## Makes the far body of a model now (the loading screen), so no pedestrian walking out past
## lod_far stalls the frame building it.
static func warm_far_mesh(path: String, host: Node) -> void:
	if not ResourceLoader.exists(path):
		return
	var inst := (load(path) as PackedScene).instantiate() as Node3D
	host.add_child(inst)
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).skin:
			far_mesh((mi as MeshInstance3D).mesh)
	inst.queue_free()


## Where the pavement is under (x, z) in the parent's space: the chunk's own ground height (the
## same one it placed this pedestrian with). `fallback` when the parent is not a chunk.
func _ground_y(x: float, z: float, fallback: float) -> float:
	var chunk := get_parent()
	if chunk and chunk.has_method("ground_y"):
		return chunk.ground_y(x, z) + 0.1
	return fallback


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
		# A cruiser that runs somebody down is the police's doing, not the player's crime.
		Police.innocent = body.has_meta("police")
		knock(dir * (8.0 + speed * 0.6) + Vector3.UP * 6.0)
		Police.innocent = false


## Frightens everyone within `radius` of `at` (a gunshot, a blast): they run from it, and the
## `screams` nearest of the ones who were calm scream, each after their own short delay.
## One pass over the crowd group, and at most one pass per quarter second per spot.
## `force` skips the rate limit (a blast is bigger news than the shot that caused it).
## The same pass counts who heard it and reports the crime to the police (Police.on_alarm):
## `crime` "auto" is a gunshot, or an explosion when forced; "" reports nothing (police fire).
static func alarm(tree: SceneTree, at: Vector3, radius: float, screams: int, force: bool = false, crime: String = "auto") -> void:
	if tree == null or radius <= 0.0:
		return
	var now := Time.get_ticks_msec()
	if not force and now - _last_alarm_ms < 250 and at.distance_to(_last_alarm_at) < 10.0:
		return
	_last_alarm_ms = now
	_last_alarm_at = at
	var r2 := radius * radius
	var fresh: Array = []
	var heard := 0
	for n in tree.get_nodes_in_group("pedestrian"):
		var p := n as Pedestrian
		if p == null or p._down or not p.is_inside_tree():
			continue
		var d2 := p.global_position.distance_squared_to(at)
		if d2 > r2:
			continue
		heard += 1
		if p._panic_left <= 0.0:
			fresh.append([d2, p])
		p._scare(at)
	fresh.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for i in mini(screams, fresh.size()):
		var p: Pedestrian = fresh[i][1]
		p._scream_in = p._rng.randf_range(0.05, 0.45) + 0.25 * float(i)
	if crime != "":
		Police.on_alarm(tree, at, radius, heard, ("explosion" if force else "gunfire") if crime == "auto" else crime)


func _scare(at: Vector3) -> void:
	var calm := _panic_left <= 0.0
	_panic_left = _rng.randf_range(panic_seconds.x, panic_seconds.y)
	_threat = Vector2(at.x, at.z)
	_pause_left = 0.0
	if calm:
		_target = _flee_point()
		_play_run()


## The spot on this block's pavement ring farthest from the threat, out of a handful: fleeing
## along the pavement keeps them out of the traffic, and away from it is all a scare needs.
func _flee_point() -> Vector2:
	var best := _random_ring_point(_sidewalk)
	for i in 5:
		var p := _random_ring_point(_sidewalk)
		if p.distance_squared_to(_threat) > best.distance_squared_to(_threat):
			best = p
	return best


func _play_run() -> void:
	if _anim == null:
		return
	if _anim.has_animation(RUN_CLIP):
		_anim.play(RUN_CLIP, 0.2)
		_anim.speed_scale = run_speed / RUN_CLIP_SPEED * _gait
	elif _anim.has_animation(WALK_CLIP):
		_anim.play(WALK_CLIP, 0.2)
		_anim.speed_scale = run_speed / WALK_CLIP_SPEED * _gait


## Screams now if nobody else in the crowd has just started one, else a moment later.
func _scream() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_scream_ms < scream_gap_ms:
		_scream_in = _rng.randf_range(0.08, 0.3)
		return
	_last_scream_ms = now
	_scream_in = -1.0
	Sfx.play("scream", global_position + Vector3.UP * 1.6, 0.0, _rng.randf_range(0.94, 1.08))


## Turns into a ragdoll flung by `impulse`, with `gibs` limbs torn off (a close blast).
func knock(impulse: Vector3, gibs: int = 0) -> void:
	if _down:
		return
	_down = true
	# A crime if anybody saw it, unless the police did it themselves (Police.innocent).
	Police.person_down(self)
	Sfx.play("yelp", global_position, 0.0, _rng.randf_range(0.8, 1.3))
	var doll := Ragdoll.new()
	doll.position = position
	doll.rotation.y = _visual.rotation.y
	get_parent().add_child(doll)
	if _model_path == "" or not doll.build_from_rig(_model_path, _look):
		doll.build(shirt, pants, skin)
	PhysicsBudget.register_debris(doll)
	doll.fling(impulse)
	if gibs > 0:
		doll.dismember(gibs, impulse)
	queue_free()
