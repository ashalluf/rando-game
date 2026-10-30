class_name Golfer
extends Pedestrian
## Somebody playing the golf course (GolfCourse, GolfLife): a crowd rig in golf clothes (a polo
## shirt in a club colour over chinos, through the character shader's garment split) with a club
## in the right hand. A Pedestrian, so shot, knocked, bled and ragdolled like anyone, counted in
## the crowd cap, a witness for the police; frightened, they drop the stance and run like anyone.
##
## The rigs carry only idle, walk and run clips, so the golf poses are written into the skeleton
## (RoughSleeper's method): each pose is a table of bone segment directions in rig space (+Z
## forward, +X the rig's left), solved once per rig over the idle clip's frame, plus a twist of the
## spine round the vertical (the shoulder turn a swing is made of). A swing is a timeline through
## them - stand, address (with a waggle), the top of the backswing, impact, the finish, held, then
## back to standing - eased between poses bone by bone; a putt is address and a short pendulum.
##
##   DRIVE / IRON  a full swing on the tee or the fairway, every `period` seconds (30-50 s on the
##                 course, so a group takes turns; 9-14 s on the range's tee line)
##   PUTT          on a green
##   WAIT          standing by with a club (the idle clip, playing)
##   RIDE          seated in a golf cart (GolfLife's carts)

enum Role { DRIVE, IRON, PUTT, WAIT, RIDE }
enum Club { DRIVER, IRON, PUTTER }

## Polo shirts and trousers (display numbers): club whites and pastels, navy, a bright one.
const POLOS := [Color(0.95, 0.95, 0.93), Color(0.14, 0.20, 0.38), Color(0.55, 0.72, 0.88), Color(0.90, 0.62, 0.66),
	Color(0.32, 0.55, 0.36), Color(0.92, 0.86, 0.55), Color(0.62, 0.15, 0.16), Color(0.20, 0.20, 0.22), Color(0.95, 0.55, 0.20)]
const SLACKS := [Color(0.76, 0.68, 0.52), Color(0.55, 0.56, 0.58), Color(0.14, 0.17, 0.27), Color(0.88, 0.86, 0.80), Color(0.30, 0.30, 0.32)]

const POSES := {
	# Address: bent from the hips, knees flexed, both arms hanging to a point in front of the
	# belt buckle, eyes on the ball.
	"address": {
		"hips_drop": 0.045,
		"aim": {
			"Spine": Vector3(0.0, 0.86, 0.50), "Spine01": Vector3(0.0, 0.84, 0.54), "Spine02": Vector3(0.0, 0.82, 0.57),
			"neck": Vector3(0.0, 0.55, 0.83), "Head": Vector3(0.0, 0.20, 0.98),
			"LeftUpLeg": Vector3(0.10, -0.95, 0.28), "LeftLeg": Vector3(0.05, -0.97, -0.24),
			"RightUpLeg": Vector3(-0.10, -0.95, 0.28), "RightLeg": Vector3(-0.05, -0.97, -0.24),
			"LeftArm": Vector3(-0.22, -0.82, 0.52), "LeftForeArm": Vector3(-0.20, -0.86, 0.47),
			"RightArm": Vector3(0.12, -0.85, 0.51), "RightForeArm": Vector3(0.24, -0.84, 0.48),
		},
		"keep": ["LeftFoot", "RightFoot"],
	},
	# The top of the backswing: shoulders turned 90 degrees away from the target (the target is to
	# the golfer's left, +X), the left arm across the chest, both hands up over the right shoulder.
	"top": {
		"hips_drop": 0.04,
		"twist": {"Spine": -25.0, "Spine01": -30.0, "Spine02": -30.0, "neck": 40.0, "Head": 40.0},
		"aim": {
			"Spine": Vector3(0.0, 0.88, 0.47), "Spine01": Vector3(0.0, 0.86, 0.51), "Spine02": Vector3(0.0, 0.85, 0.52),
			"neck": Vector3(0.10, 0.55, 0.83), "Head": Vector3(0.22, 0.18, 0.96),
			"LeftUpLeg": Vector3(0.04, -0.95, 0.31), "LeftLeg": Vector3(-0.08, -0.96, -0.24),
			"RightUpLeg": Vector3(-0.10, -0.96, 0.26), "RightLeg": Vector3(-0.05, -0.98, -0.18),
			"LeftArm": Vector3(-0.28, 0.56, -0.79), "LeftForeArm": Vector3(-0.28, 0.56, -0.79),
			"RightArm": Vector3(-0.41, -0.62, -0.69), "RightForeArm": Vector3(-0.11, 0.97, 0.22),
		},
		"keep": ["LeftFoot", "RightFoot"],
	},
	# The finish: weight on the left, belt and chest to the target, right heel up and the right
	# knee in toward the left, the hands high over the left shoulder.
	"finish": {
		"hips_drop": 0.01,
		"twist": {"Spine": 40.0, "Spine01": 25.0, "Spine02": 20.0, "neck": -30.0, "Head": -25.0},
		"aim": {
			"Spine": Vector3(-0.06, 0.97, 0.22), "Spine01": Vector3(-0.08, 0.97, 0.20), "Spine02": Vector3(-0.10, 0.97, 0.20),
			"neck": Vector3(0.10, 0.92, 0.38), "Head": Vector3(0.25, 0.85, 0.46),
			"LeftUpLeg": Vector3(0.08, -0.99, 0.08), "LeftLeg": Vector3(0.04, -0.99, -0.05),
			"RightUpLeg": Vector3(0.18, -0.92, 0.35), "RightLeg": Vector3(0.10, -0.80, -0.59),
			"RightFoot": Vector3(0.05, -0.85, 0.52),
			"LeftArm": Vector3(0.43, -0.54, -0.72), "LeftForeArm": Vector3(0.09, 0.89, 0.45),
			"RightArm": Vector3(0.74, 0.0, -0.68), "RightForeArm": Vector3(-0.37, 0.56, -0.74),
		},
		"keep": ["LeftFoot"],
	},
	# Putting: bent further over, the arms straight down from the shoulders, the head over the ball.
	"putt": {
		"hips_drop": 0.03,
		"aim": {
			"Spine": Vector3(0.0, 0.80, 0.60), "Spine01": Vector3(0.0, 0.76, 0.65), "Spine02": Vector3(0.0, 0.72, 0.69),
			"neck": Vector3(0.0, 0.38, 0.92), "Head": Vector3(0.0, 0.0, 1.0),
			"LeftUpLeg": Vector3(0.07, -0.96, 0.26), "LeftLeg": Vector3(0.04, -0.98, -0.18),
			"RightUpLeg": Vector3(-0.07, -0.96, 0.26), "RightLeg": Vector3(-0.04, -0.98, -0.18),
			"LeftArm": Vector3(-0.16, -0.88, 0.45), "LeftForeArm": Vector3(-0.12, -0.92, 0.37),
			"RightArm": Vector3(0.08, -0.90, 0.43), "RightForeArm": Vector3(0.16, -0.90, 0.40),
		},
		"keep": ["LeftFoot", "RightFoot"],
	},
	# The putter's back and through: the putt pose with the arm triangle rocked by the shoulders.
	"putt_back": {
		"hips_drop": 0.03,
		"twist": {"Spine02": -9.0},
		"aim": {
			"Spine": Vector3(0.0, 0.80, 0.60), "Spine01": Vector3(0.0, 0.76, 0.65), "Spine02": Vector3(0.0, 0.72, 0.69),
			"neck": Vector3(0.0, 0.38, 0.92), "Head": Vector3(0.0, 0.0, 1.0),
			"LeftUpLeg": Vector3(0.07, -0.96, 0.26), "LeftLeg": Vector3(0.04, -0.98, -0.18),
			"RightUpLeg": Vector3(-0.07, -0.96, 0.26), "RightLeg": Vector3(-0.04, -0.98, -0.18),
			"LeftArm": Vector3(-0.30, -0.84, 0.45), "LeftForeArm": Vector3(-0.26, -0.88, 0.39),
			"RightArm": Vector3(-0.06, -0.89, 0.45), "RightForeArm": Vector3(0.02, -0.92, 0.39),
		},
		"keep": ["LeftFoot", "RightFoot"],
	},
	"putt_through": {
		"hips_drop": 0.03,
		"twist": {"Spine02": 9.0},
		"aim": {
			"Spine": Vector3(0.0, 0.80, 0.60), "Spine01": Vector3(0.0, 0.76, 0.65), "Spine02": Vector3(0.0, 0.72, 0.69),
			"neck": Vector3(0.0, 0.38, 0.92), "Head": Vector3(0.0, 0.0, 1.0),
			"LeftUpLeg": Vector3(0.07, -0.96, 0.26), "LeftLeg": Vector3(0.04, -0.98, -0.18),
			"RightUpLeg": Vector3(-0.07, -0.96, 0.26), "RightLeg": Vector3(-0.04, -0.98, -0.18),
			"LeftArm": Vector3(-0.02, -0.88, 0.47), "LeftForeArm": Vector3(0.02, -0.92, 0.39),
			"RightArm": Vector3(0.22, -0.86, 0.46), "RightForeArm": Vector3(0.30, -0.86, 0.41),
		},
		"keep": ["LeftFoot", "RightFoot"],
	},
	# Seated in a cart: thighs forward, shins down, hands on the knees (or the wheel).
	"ride": {
		"hips_drop": 0.43,
		"aim": {
			"Spine": Vector3(0.0, 0.98, -0.12), "Spine01": Vector3(0.0, 0.98, -0.10), "Spine02": Vector3(0.0, 0.99, -0.06),
			"neck": Vector3(0.0, 0.97, 0.20), "Head": Vector3(0.0, 0.95, 0.30),
			"LeftUpLeg": Vector3(0.10, -0.05, 0.99), "LeftLeg": Vector3(0.03, -0.99, 0.10),
			"RightUpLeg": Vector3(-0.10, -0.05, 0.99), "RightLeg": Vector3(-0.03, -0.99, 0.10),
			"LeftFoot": Vector3(0.0, -0.45, 0.89), "RightFoot": Vector3(0.0, -0.45, 0.89),
			"LeftArm": Vector3(0.18, -0.75, 0.64), "LeftForeArm": Vector3(0.02, -0.30, 0.95),
			"RightArm": Vector3(-0.18, -0.75, 0.64), "RightForeArm": Vector3(-0.02, -0.30, 0.95),
		},
	},
}
## The swing's timeline: [seconds into the cycle, pose] (eased between; "" is the idle frame).
const SWING := [[0.0, ""], [1.3, "address"], [3.4, "address"], [4.3, "top"], [4.58, "address"], [4.95, "finish"], [6.6, "finish"], [7.8, ""]]
const PUTT := [[0.0, ""], [1.6, "putt"], [3.3, "putt"], [3.95, "putt_back"], [4.3, "putt_through"], [5.6, "putt_through"], [6.6, ""]]
## Which way the club points from the hands in each pose, in the golfer's own space (facing -Z, the
## target to the left, -X); "ball" means at the ball on the ground.
const CLUB_DIRS := {"": Vector3(-0.15, -0.97, -0.2), "address": "ball", "putt": "ball", "putt_back": "ball", "putt_through": "ball",
	"top": Vector3(-0.85, -0.15, 0.5), "finish": Vector3(0.7, -0.4, 0.6), "ride": Vector3(0.0, -1.0, 0.0)}
## When in the cycle the ball leaves (impact).
const IMPACT := {"swing": 4.58, "putt": 4.12}
## Range of the ball flight drawn after impact (m) and how long it flies (s).
const FLIGHT_SECONDS := 4.2
## Within this distance of the player a golfer is posed every tick, beyond it every few.
const POSE_RANGE := 70.0

var role: int = Role.WAIT
var club: int = Club.IRON
## Seconds per cycle, and where in it this golfer starts.
var period: float = 36.0
var phase: float = 0.0
## Which way the shot goes (unit XZ): the golfer stands side-on to it, the target to their left.
var target_dir := Vector2(0.0, -1.0)
var _home := Vector2.ZERO
var _home_y: float = 0.0
var _skel: Skeleton3D
var _order := PackedInt32Array()
var _base_rot: Array[Quaternion] = []
var _base_pos: Array[Vector3] = []
var _hips: int = -1
var _poses: Dictionary = {}
var _clock: float = 0.0
var _ball: MeshInstance3D
var _flight_t: float = -1.0
var _flight_v := Vector3.ZERO
var _fled := false
var _club_node: Node3D
var _rhand: int = -1
var _lhand: int = -1
static var _club_meshes: Dictionary = {}
static var _attire_mats: Dictionary = {}
static var _ball_mesh: Mesh


func setup_golfer(home: Vector2, y: float, target: Vector2, r: int, seed_value: int) -> void:
	setup(Rect2(home - Vector2(14.0, 14.0), Vector2(28.0, 28.0)), 10.0, seed_value)
	role = r
	_home = home
	_home_y = y
	target_dir = target.normalized() if target.length() > 0.01 else Vector2(0.0, -1.0)
	var hs := absi(hash([seed_value, "golfer"]))
	period = 36.0 + float(hs % 1700) / 100.0
	phase = float(hs % 997) / 997.0 * period
	match r:
		Role.DRIVE:
			club = Club.DRIVER
		Role.PUTT:
			club = Club.PUTTER
		Role.WAIT:
			club = [Club.DRIVER, Club.IRON, Club.PUTTER][hs % 3]
		_:
			club = Club.IRON
	cross_chance = 0.0
	# (No `life_enabled = false` here: it is Pedestrian's STATIC switch, and set from a golfer it
	# turned crowd life off for the whole city. A golfer never lives anyway: _lives() is false.)
	position = Vector3(home.x, y, home.y)


## The range's tee line: a shorter cycle, and a driver one time in three.
func range_cycle(seed_value: int) -> void:
	var hs := absi(hash([seed_value, "range"]))
	period = 9.0 + float(hs % 500) / 100.0
	phase = float(hs % 991) / 991.0 * period
	club = Club.DRIVER if hs % 3 == 0 else Club.IRON


func _ready() -> void:
	super._ready()
	# Side-on to the shot: the golfer's left (node -X) points down `target_dir`.
	var yaw := atan2(target_dir.y, -target_dir.x)
	rotation = Vector3(0.0, yaw, 0.0)
	_visual.rotation.x = 0.0
	_dress()
	_skel = _visual.find_child("Skeleton3D", true, false) as Skeleton3D
	if _skel == null or _anim == null or not _has_idle:
		return
	_anim.play(IDLE_CLIP, 0.0)
	_anim.seek(0.6, true)
	_clip = IDLE_CLIP
	_speed = 0.0
	var n := _skel.get_bone_count()
	_base_rot.resize(n)
	_base_pos.resize(n)
	for b in n:
		_base_rot[b] = _skel.get_bone_pose_rotation(b)
		_base_pos[b] = _skel.get_bone_pose_position(b)
	_order = RoughSleeper._bone_order(_skel)
	_hips = _skel.find_bone("Hips")
	for key: String in POSES:
		_poses[key] = _solve(POSES[key])
	_poses[""] = [_base_rot.duplicate(), _base_pos[_hips] if _hips >= 0 else Vector3.ZERO]
	_add_club()
	if role == Role.DRIVE or role == Role.IRON or role == Role.PUTT:
		_add_ball()
	if role == Role.RIDE:
		_apply_pose("ride", "ride", 0.0)
	if role == Role.WAIT:
		_anim.speed_scale = _style.randf_range(0.8, 1.05)
		_anim.seek(_style.randf() * _anim.get_animation(IDLE_CLIP).length, true)


## Golf clothes: the top garment a polo colour, the trousers chinos or slacks (per texture, cached).
func _dress() -> void:
	var pi := absi(hash([_rng.seed, "polo"])) % POLOS.size()
	var si := absi(hash([_rng.seed, "slacks"])) % SLACKS.size()
	for mi in _meshes:
		if not is_instance_valid(mi) or mi.mesh == null or is_hair(mi):
			continue
		var src := mi.mesh.surface_get_material(0) as StandardMaterial3D
		if src == null or src.albedo_texture == null:
			continue
		var key := "%d_%d_%d" % [src.albedo_texture.get_instance_id(), pi, si]
		if not _attire_mats.has(key):
			var base := character_material(src.albedo_texture, 1)
			if base == null:
				continue
			var mat := base.duplicate() as ShaderMaterial
			var top: Color = POLOS[pi]
			var low: Color = SLACKS[si]
			mat.set_shader_parameter("cloth_hue", top.h)
			mat.set_shader_parameter("cloth_sat", top.s)
			mat.set_shader_parameter("cloth_value", top.v)
			mat.set_shader_parameter("cloth_strength", 0.95)
			mat.set_shader_parameter("pants_hue", low.h)
			mat.set_shader_parameter("pants_sat", low.s)
			mat.set_shader_parameter("pants_value", low.v)
			mat.set_shader_parameter("pants_strength", 0.95)
			mat.set_shader_parameter("cloth_roughness", 0.72)
			mat.set_shader_parameter("cloth_shade_keep", 0.7)
			_attire_mats[key] = mat
		mi.material_override = _attire_mats[key]


## Not a pavement walker: swings in place, unless frightened (then they run like anyone).
func _physics_process(delta: float) -> void:
	if _down:
		return
	if _fled:
		super._physics_process(delta)
		return
	_lod_timer += delta
	if _lod_timer >= 0.5:
		_lod_timer = 0.0
		_update_lod()
	_clock += delta
	if role == Role.RIDE:
		return
	if role == Role.WAIT:
		_lod_tick += 1
		if _anim and (_lod_stride <= 1 or _lod_tick % _lod_stride == 0):
			_anim.advance(delta * _lod_stride)
			_place_club("", "", 0.0)
		return
	_flight(delta)
	_lod_tick += 1
	if _lod_stride > 1 and _lod_tick % _lod_stride != 0:
		return
	_pose_at(fposmod(_clock + phase, period))


func _scare(at: Vector3) -> void:
	if role == Role.RIDE:
		return
	if not _fled and _skel:
		_fled = true
		_apply_pose("", "", 0.0)
		if _ball:
			_ball.visible = false
		_set_clip(WALK_CLIP, 0.2)
	super._scare(at)


func _head_look_ok() -> bool:
	return _fled


## Where the timeline is at `t` seconds into the cycle.
func _pose_at(t: float) -> void:
	if _skel == null:
		return
	var line: Array = PUTT if role == Role.PUTT else SWING
	var impact: float = IMPACT.putt if role == Role.PUTT else IMPACT.swing
	var a: Array = line[line.size() - 1]
	var b: Array = line[line.size() - 1]
	for k in line.size() - 1:
		if t >= float(line[k][0]) and t < float(line[k + 1][0]):
			a = line[k]
			b = line[k + 1]
			break
	var w := 0.0
	if b != a:
		w = (t - float(a[0])) / maxf(float(b[0]) - float(a[0]), 1e-3)
		w = w * w * (3.0 - 2.0 * w)
	_apply_pose(String(a[1]), String(b[1]), w)
	# The waggle at address, and the ball: on the tee at address, away at impact.
	if _ball:
		var before := t < impact
		if before and not _ball.visible and _flight_t < 0.0:
			_ball.position = _ball_spot()
			_ball.visible = true
		if not before and _ball.visible and _flight_t < 0.0 and t < impact + 0.5:
			_launch()


func _apply_pose(ka: String, kb: String, w: float) -> void:
	if not _poses.has(ka) or not _poses.has(kb):
		return
	var pa: Array = _poses[ka]
	var pb: Array = _poses[kb]
	var ra: Array = pa[0]
	var rb: Array = pb[0]
	var n := mini(ra.size(), _skel.get_bone_count())
	for bi in n:
		var q: Quaternion = (ra[bi] as Quaternion).slerp(rb[bi], w) if ka != kb else ra[bi]
		_skel.set_bone_pose_rotation(bi, q)
	if _hips >= 0:
		_skel.set_bone_pose_position(_hips, (pa[1] as Vector3).lerp(pb[1], w))
	_place_club(ka, kb, w)


## RoughSleeper's solve, plus a twist of named bones round the vertical before they are aimed.
func _solve(spec: Dictionary) -> Array:
	var n := _skel.get_bone_count()
	var local: Array[Quaternion] = _base_rot.duplicate()
	var glob: Array[Transform3D] = []
	glob.resize(n)
	var base_glob: Array[Transform3D] = []
	base_glob.resize(n)
	var aims: Dictionary = spec.get("aim", {})
	var twists: Dictionary = spec.get("twist", {})
	var keep: Array = spec.get("keep", [])
	for b in _order:
		var p := _skel.get_bone_parent(b)
		var bl := Transform3D(Basis(_base_rot[b]), _base_pos[b])
		base_glob[b] = base_glob[p] * bl if p >= 0 else bl
		var g := glob[p] * bl if p >= 0 else bl
		var bone_name := _skel.get_bone_name(b)
		if twists.has(bone_name):
			g.basis = Basis(Vector3.UP, deg_to_rad(float(twists[bone_name]))) * g.basis
		var aim: Variant = aims.get(bone_name)
		if aim != null and RoughSleeper.AIM_CHILD.has(bone_name):
			var c := _skel.find_bone(RoughSleeper.AIM_CHILD[bone_name])
			if c >= 0:
				var cur := (g.basis * _base_pos[c]).normalized()
				var want := (aim as Vector3).normalized()
				if cur.length() > 0.5 and absf(cur.dot(want)) < 0.9999:
					g.basis = Basis(Quaternion(cur, want)) * g.basis
		elif keep.has(bone_name):
			g.basis = base_glob[b].basis
		glob[b] = g
		local[b] = ((glob[p].basis.inverse() * g.basis) if p >= 0 else g.basis).get_rotation_quaternion()
	var hips := _base_pos[_hips] if _hips >= 0 else Vector3.ZERO
	hips.y -= float(spec.get("hips_drop", 0.0)) * _skel_unit
	return [local, hips]


# --- Club and ball -------------------------------------------------------------------------------

func _add_club() -> void:
	_rhand = _skel.find_bone("RightHand")
	_lhand = _skel.find_bone("LeftHand")
	if _rhand < 0:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = club_mesh(club)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 90.0
	add_child(mi)
	_club_node = mi
	mi.visible = role != Role.RIDE


## The club in the hands: its grip between them, its shaft along the pose's direction (eased).
func _place_club(ka: String, kb: String, w: float) -> void:
	if _club_node == null or _skel == null:
		return
	var sk := _skel.global_transform
	var hand := to_local(sk * _skel.get_bone_global_pose(_rhand).origin)
	if _lhand >= 0:
		hand = hand.lerp(to_local(sk * _skel.get_bone_global_pose(_lhand).origin), 0.5)
	var da := _club_dir(ka, hand)
	var db := _club_dir(kb, hand)
	var d := da.lerp(db, w).normalized()
	var up := Vector3.UP if absf(d.y) < 0.95 else Vector3.FORWARD
	var x := d
	var z := x.cross(up).normalized()
	var y := z.cross(x)
	_club_node.transform = Transform3D(Basis(x, y, z), hand - d * 0.06)


func _club_dir(key: String, hand: Vector3) -> Vector3:
	var v: Variant = CLUB_DIRS.get(key, CLUB_DIRS[""])
	if v is String:
		return (_ball_spot() + Vector3(0.0, 0.02, 0.0) - hand).normalized()
	return (v as Vector3).normalized()


## A club along +X from the butt (x -0.1) to the head (x ~0.9-1.05): grip, steel shaft, head.
static func club_mesh(kind: int) -> Mesh:
	if _club_meshes.has(kind):
		return _club_meshes[kind]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var length := 1.04 if kind == Club.DRIVER else (0.86 if kind == Club.IRON else 0.80)
	_tube(st, -0.1, 0.17, 0.0125, 0.0105, Color(0.06, 0.06, 0.06))
	_tube(st, 0.17, length, 0.0068, 0.0045, Color(0.72, 0.73, 0.75))
	var head_c := Vector3(length + 0.01, 0.0, 0.0)
	match kind:
		Club.DRIVER:
			_box(st, head_c + Vector3(0.025, -0.0, 0.035), Vector3(0.07, 0.05, 0.11), Color(0.08, 0.08, 0.09))
		Club.IRON:
			_box(st, head_c + Vector3(0.022, 0.0, 0.03), Vector3(0.05, 0.012, 0.075), Color(0.70, 0.71, 0.73))
		_:
			_box(st, head_c + Vector3(0.015, 0.0, 0.04), Vector3(0.025, 0.022, 0.1), Color(0.55, 0.56, 0.58))
	st.generate_normals()
	var mesh := st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.metallic = 0.6
	m.roughness = 0.35
	mesh.surface_set_material(0, m)
	_club_meshes[kind] = mesh
	return mesh


static func _tube(st: SurfaceTool, x0: float, x1: float, r0: float, r1: float, c: Color) -> void:
	var segs := 8
	for i in segs:
		var a0 := TAU * float(i) / segs
		var a1 := TAU * float(i + 1) / segs
		var p := [Vector3(x0, cos(a0) * r0, sin(a0) * r0), Vector3(x1, cos(a0) * r1, sin(a0) * r1),
			Vector3(x1, cos(a1) * r1, sin(a1) * r1), Vector3(x0, cos(a1) * r0, sin(a1) * r0)]
		for k: int in [0, 2, 1, 0, 3, 2]:
			st.set_color(c)
			st.add_vertex(p[k])


static func _box(st: SurfaceTool, c: Vector3, s: Vector3, col: Color) -> void:
	var h := s * 0.5
	var corners := []
	for k in 8:
		corners.append(c + Vector3(h.x if k & 1 else -h.x, h.y if k & 2 else -h.y, h.z if k & 4 else -h.z))
	for f: Array in [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]:
		for k: int in [0, 1, 2, 0, 2, 3]:
			st.set_color(col)
			st.add_vertex(corners[f[k]])


func _ball_spot() -> Vector3:
	# In front of the feet (node -Z is the way the golfer faces), a little toward the target.
	return Vector3(-0.08 if club == Club.DRIVER else 0.0, 0.025, -(0.72 if club != Club.PUTTER else 0.42))


func _add_ball() -> void:
	if _ball_mesh == null:
		var sm := SphereMesh.new()
		sm.radius = 0.0214
		sm.height = 0.0428
		sm.radial_segments = 10
		sm.rings = 5
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.97, 0.97, 0.95)
		m.roughness = 0.35
		sm.material = m
		_ball_mesh = sm
	_ball = MeshInstance3D.new()
	_ball.mesh = _ball_mesh
	_ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ball.visibility_range_end = 60.0
	_ball.position = _ball_spot()
	add_child(_ball)


## The shot: the ball leaves toward the target (node -X), climbing for a full swing, rolling for a putt.
func _launch() -> void:
	if role == Role.PUTT:
		_flight_v = Vector3(-1.6 - _style.randf() * 0.8, 0.0, _style.randf_range(-0.05, 0.05))
	else:
		var speed := 62.0 if club == Club.DRIVER else 44.0
		var launch := deg_to_rad(11.0 if club == Club.DRIVER else 19.0)
		_flight_v = Vector3(-cos(launch), sin(launch), _style.randf_range(-0.04, 0.04)) * speed
	_flight_t = 0.0


func _flight(delta: float) -> void:
	if _flight_t < 0.0 or _ball == null:
		return
	_flight_t += delta
	if role == Role.PUTT:
		_flight_v *= exp(-delta * 1.1)
	else:
		_flight_v.y -= 9.8 * delta * 0.82
		_flight_v *= exp(-delta * 0.12)
	_ball.position += _flight_v * delta
	if _ball.position.y < 0.02:
		_ball.position.y = 0.02
		_flight_v.y = absf(_flight_v.y) * 0.3
		_flight_v.x *= 0.7
		_flight_v.z *= 0.7
	if _flight_t > FLIGHT_SECONDS:
		_flight_t = -1.0
		_ball.visible = false
