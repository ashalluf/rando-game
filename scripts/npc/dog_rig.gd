class_name DogRig
extends Node3D
## One dog's body (DogMesh): the breed's skeleton, its skin and fur-shell meshes at three levels
## of detail, and a procedural pose worked out every tick from a handful of numbers a brain sets
## (CrowdDog on a lead, YardDog behind a fence):
##   speed      metres a second along the dog's own -Z (the gait picks walk, trot or gallop by it,
##              each leg's paw placed by its phase - planted, then lifted and swung forward - and
##              the legs solved by two-bone IK with the pastern / hock at its own angle)
##   sit        0..1: the haunches drop and the hind legs fold under, the hocks on the ground
##   sniff      0..1: the nose down to the pavement
##   look_at    a point (this node's local space; INF for none) the head turns to, the neck taking
##              part of it
##   wag, fear  the tail's wag; ears back, the tail tucked, the body low
##   bark       a pulse (set to 1 on a bark, it decays): the jaw snaps open, the head thrusts
##   pant       the jaw hangs a little open
## The body bobs, rolls and flexes with the gait, the head nods at a walk, drop ears swing.
## The node's origin is on the ground under the dog's middle and it faces -Z, like the mesh.

## Distances (metres to the camera) where the shells thin to the MID level and where the FAR
## level (no shells) takes over; the whole dog stops drawing at `draw_range`.
@export var near_range: float = 9.0
@export var mid_range: float = 26.0
@export var draw_range: float = 75.0
## Gait: Froude-style walk-trot and trot-gallop speeds (multiplied by sqrt of the withers height).
@export var trot_at: float = 2.05
@export var gallop_at: float = 5.2
## How fast the head turns to its target and the body settles into a sit (per second).
@export var look_rate: float = 5.0
@export var sit_rate: float = 2.5

var breed: String = "labrador"
var look: String = "lab_yellow"
var speed: float = 0.0
var sit: float = 0.0
var sniff: float = 0.0
var look_at := Vector3.INF
var wag: float = 0.3
var fear: float = 0.0
var bark: float = 0.0
var pant: float = 0.0
## Yaw rate (radians a second) the brain is turning at; the body leans into it.
var turn: float = 0.0

var skeleton: Skeleton3D
var _levels: Array = [] # per level: [skin MeshInstance3D, shells MeshInstance3D or null]
var _level: int = -1
var _b: Dictionary
var _rest := PackedVector3Array()
var _phase: float = 0.0
var _moving: float = 0.0
var _trot: float = 0.0
var _gallop: float = 0.0
var _sit_now: float = 0.0
var _sniff_now: float = 0.0
var _look_yaw: float = 0.0
var _look_pitch: float = 0.0
var _wag_t: float = 0.0
var _ear_swing: float = 0.0
var _ear_vel: float = 0.0
var _lod_check: float = 0.0
var _time: float = 0.0
var _g: Array = [] # bone globals (Transform3D), skeleton space
var _seed: int = 0

static var _mats: Dictionary = {}

## Tail carriage per kind: [base pitch up from straight back, curl per segment] (degrees).
const TAIL_POSE := {
	"otter": [-28.0, 7.0], "sickle": [-60.0, 9.0], "plume": [62.0, 42.0], "whip": [-22.0, 4.0],
	"erect": [58.0, 2.0], "sickle_up": [40.0, 30.0],
}


static func make(breed_name: String, look_name: String, seed_value: int) -> DogRig:
	var r := DogRig.new()
	r.breed = breed_name
	r.look = look_name
	r._seed = seed_value
	return r


## The look's three materials: [skin under shells, skin alone (FAR), shells].
static func materials(breed_name: String, look_name: String) -> Array:
	var key := breed_name + "/" + look_name
	if _mats.has(key):
		return _mats[key]
	var b := DogMesh.breed(breed_name)
	var tex_path := DogMesh.TEXTURE_DIR + look_name + ".jpg"
	var tex: Texture2D = load(tex_path) if ResourceLoader.exists(tex_path) else null
	var out: Array = []
	for k in 3:
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/dog_fur.gdshader" if k == 2 else "res://shaders/dog.gdshader")
		if tex:
			m.set_shader_parameter("coat_tex", tex)
		m.set_shader_parameter("coat_len", float(b.coat))
		m.set_shader_parameter("strand_cell", float(b.cell))
		var ec: Color = b.eye
		m.set_shader_parameter("eye_color", Vector3(ec.r, ec.g, ec.b))
		if k < 2:
			m.set_shader_parameter("shells", 1.0 if k == 0 else 0.0)
		out.append(m)
	_mats[key] = out
	return out


func _ready() -> void:
	_b = DogMesh.breed(breed)
	_rest = DogMesh.rest_positions(breed)
	skeleton = DogMesh.make_skeleton(breed)
	skeleton.name = "Skeleton"
	add_child(skeleton)
	var mats := materials(breed, look)
	var sk := DogMesh.skin(breed)
	for lv in 3:
		var ms: Array = DogMesh.meshes(breed, lv)
		var skin_mi := MeshInstance3D.new()
		skin_mi.mesh = ms[0]
		skin_mi.skin = sk
		skin_mi.material_override = mats[0] if ms[1] != null else mats[1]
		skin_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		skin_mi.visible = false
		skeleton.add_child(skin_mi)
		skin_mi.skeleton = NodePath("..")
		var shell_mi: MeshInstance3D = null
		if ms[1] != null:
			shell_mi = MeshInstance3D.new()
			shell_mi.mesh = ms[1]
			shell_mi.skin = sk
			shell_mi.material_override = mats[2]
			shell_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			shell_mi.visible = false
			skeleton.add_child(shell_mi)
			shell_mi.skeleton = NodePath("..")
		_levels.append([skin_mi, shell_mi])
	_g.resize(DogMesh.BONES.size())
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed
	_phase = rng.randf()
	_wag_t = rng.randf() * 10.0
	_set_level(0)
	advance(0.0)


func _set_level(lv: int) -> void:
	if lv == _level:
		return
	_level = lv
	for i in _levels.size():
		var pair: Array = _levels[i]
		(pair[0] as MeshInstance3D).visible = i == lv
		if pair[1] != null:
			(pair[1] as MeshInstance3D).visible = i == lv


## The level shown now (DogMesh.Level), or -1 when hidden.
func level() -> int:
	return _level if visible else -1


func _update_lod() -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return
	var d := cam.global_position.distance_to(global_position)
	# A small dog's shells matter at a shorter range.
	var k := clampf(float(_b.h) / 0.5, 0.45, 1.2)
	if d > draw_range:
		visible = false
		return
	visible = true
	_set_level(0 if d < near_range * k else (1 if d < mid_range * k else 2))


## Forces a level (stills and tests).
func force_level(lv: int) -> void:
	visible = true
	_set_level(lv)
	_lod_check = 1e9


## Steps the pose by `delta` seconds.
func advance(delta: float) -> void:
	_time += delta
	if _lod_check < 1e8:
		_lod_check -= delta
		if _lod_check <= 0.0:
			_lod_check = 0.25
			_update_lod()
	if not visible:
		return
	_pose(delta)


# --- the pose ----------------------------------------------------------------------------------

static func _rx(a: float) -> Basis:
	return Basis(Vector3.RIGHT, a)


static func _ry(a: float) -> Basis:
	return Basis(Vector3.UP, a)


static func _rz(a: float) -> Basis:
	return Basis(Vector3.BACK, a)


## The basis that turns the rest direction `d0` onto `d1`, keeping the bone's x axis as near
## `side` as it can (rest bases are identity).
static func _aim(d0: Vector3, d1: Vector3, side: Vector3) -> Basis:
	var y0 := d0.normalized()
	var x0 := (Vector3.RIGHT - y0 * y0.dot(Vector3.RIGHT))
	if x0.length_squared() < 1e-6:
		x0 = Vector3.BACK - y0 * y0.z
	x0 = x0.normalized()
	var b0 := Basis(x0, y0, x0.cross(y0))
	var y1 := d1.normalized()
	var x1 := side - y1 * y1.dot(side)
	if x1.length_squared() < 1e-6:
		x1 = Vector3.BACK - y1 * y1.z
	x1 = x1.normalized()
	var b1 := Basis(x1, y1, x1.cross(y1))
	return b1 * b0.inverse()


## Two-bone IK: [middle joint, end] from root `a` toward `t`, bending toward `pole`.
static func _ik(a: Vector3, t: Vector3, l1: float, l2: float, pole: Vector3) -> Array:
	var d := t - a
	var dist := d.length()
	var dn := d / maxf(dist, 1e-5)
	dist = clampf(dist, absf(l1 - l2) + 1e-4, (l1 + l2) * 0.9995)
	var end := a + dn * dist
	var along := (l1 * l1 - l2 * l2 + dist * dist) / (2.0 * dist)
	var h := sqrt(maxf(l1 * l1 - along * along, 0.0))
	var p := pole - dn * dn.dot(pole)
	if p.length_squared() < 1e-8:
		p = Vector3.FORWARD
	return [a + dn * along + p.normalized() * h, end]


func _pose(delta: float) -> void:
	var h: float = _b.h
	var sh := sqrt(h)
	var r := _rest
	var dt := clampf(delta, 0.0, 0.1)
	# Gait blend and phase.
	var v := absf(speed)
	_moving = move_toward(_moving, 1.0 if v > 0.06 else 0.0, dt * 3.0)
	_trot = move_toward(_trot, 1.0 if v > trot_at * sh * 0.75 else 0.0, dt * 2.5)
	_gallop = move_toward(_gallop, 1.0 if v > gallop_at * sh * 0.75 else 0.0, dt * 2.0)
	var stride := h * lerpf(lerpf(1.55, 2.3, _trot), 3.2, _gallop)
	var freq := clampf(v / maxf(stride, 1e-3), 0.0, 4.8 / maxf(sh, 0.3))
	_phase = fposmod(_phase + freq * dt, 1.0)
	_sit_now = move_toward(_sit_now, sit, dt * sit_rate)
	_sniff_now = move_toward(_sniff_now, sniff, dt * 2.0)
	var s_sit := smoothstep(0.0, 1.0, _sit_now)
	var s_sniff := smoothstep(0.0, 1.0, _sniff_now) * (1.0 - s_sit)
	var ph := _phase
	var bobw := _moving * (0.6 + 0.4 * _trot)
	# The body: anchored between the hips and the chest when standing, at the chest when sitting.
	var bob := (-cos(ph * TAU * 2.0) * h * lerpf(0.008, 0.016, _trot) - 0.012 * h * _gallop * cos(ph * TAU)) * bobw
	var pitch := s_sit * deg_to_rad(36.0) - s_sniff * 0.08 + _gallop * 0.06 * sin(ph * TAU) * _moving
	var low := fear * 0.06 * h + s_sniff * 0.05 * h
	var flex := (sin(ph * TAU) * 0.05 * (1.0 - _trot) + turn * 0.05) * _moving
	var roll := sin(ph * TAU) * 0.03 * _moving * (1.0 - _gallop) - clampf(turn * v * 0.02, -0.12, 0.12)
	var body := _ry(clampf(turn * 0.04, -0.2, 0.2)) * _rx(pitch) * _rz(roll)
	var k := lerpf(0.5, 1.0, s_sit)
	var anchor_rest := r[DogMesh.B_PELVIS].lerp(r[DogMesh.B_CHEST], k)
	var anchor := anchor_rest + Vector3(0.0, bob - low + s_sit * 0.02 * h, s_sit * 0.03 * h)
	var pel_pos := anchor - body * (anchor_rest - r[DogMesh.B_PELVIS])
	var rp := body * _ry(flex)
	var rs := body
	var rc := body * _ry(-flex)
	_g[DogMesh.B_PELVIS] = Transform3D(rp, pel_pos)
	var spine_pos := pel_pos + rp * (r[DogMesh.B_SPINE] - r[DogMesh.B_PELVIS])
	_g[DogMesh.B_SPINE] = Transform3D(rs, spine_pos)
	var chest_pos := spine_pos + rs * (r[DogMesh.B_CHEST] - r[DogMesh.B_SPINE])
	_g[DogMesh.B_CHEST] = Transform3D(rc, chest_pos)
	# The head: looks at its target, the neck taking part of the turn.
	var neck_pos := chest_pos + rc * (r[DogMesh.B_NECK] - r[DogMesh.B_CHEST])
	var want_yaw := 0.0
	var want_pitch := 0.0
	if look_at != Vector3.INF:
		var head_guess := neck_pos + rc * (r[DogMesh.B_HEAD] - r[DogMesh.B_NECK])
		var d := rc.inverse() * (look_at - head_guess)
		want_yaw = clampf(atan2(-d.x, -d.z), -1.1, 1.1)
		want_pitch = clampf(atan2(d.y, Vector2(d.x, d.z).length()), -0.7, 0.9)
	var lr := 1.0 - exp(-look_rate * dt)
	_look_yaw = lerpf(_look_yaw, want_yaw, lr)
	_look_pitch = lerpf(_look_pitch, want_pitch, lr)
	var nod := sin(ph * TAU * 2.0) * 0.06 * _moving * (1.0 - _trot)
	var neck_pitch := -s_sniff * 0.95 + s_sit * -0.25 - fear * 0.25 + _gallop * -0.3 * _moving + bark * 0.15
	var rn := rc * _ry(_look_yaw * 0.4) * _rx(neck_pitch + _look_pitch * 0.35 + nod)
	_g[DogMesh.B_NECK] = Transform3D(rn, neck_pos)
	var head_pos := neck_pos + rn * (r[DogMesh.B_HEAD] - r[DogMesh.B_NECK])
	var rh := rn * _ry(_look_yaw * 0.6) * _rx(_look_pitch * 0.65 - s_sniff * 0.45 - nod * 0.5 - bark * 0.12)
	_g[DogMesh.B_HEAD] = Transform3D(rh, head_pos)
	var jaw_open := pant * 0.1 + bark * 0.5
	_g[DogMesh.B_JAW] = Transform3D(rh * _rx(-jaw_open), head_pos + rh * (r[DogMesh.B_JAW] - r[DogMesh.B_HEAD]))
	# Ears: drop ears swing with the bob; any ear goes back with fear and forward when alert.
	var ear_kind: String = _b.ear[0]
	var spring := -bob / maxf(h, 0.1) * 60.0
	_ear_vel += (spring - _ear_swing * 40.0 - _ear_vel * 6.0) * dt
	_ear_swing += _ear_vel * dt
	for e in 2:
		var side := -1.0 if e == 0 else 1.0
		var back := fear * (0.9 if ear_kind != "drop" else 0.35)
		var perk := (0.12 if look_at != Vector3.INF else 0.0) + bark * 0.1
		var swing := _ear_swing if ear_kind in ["drop", "button", "rose"] else _ear_swing * 0.15
		var re := rh * _rx(back - perk) * _rz(side * (swing * 0.6 - back * 0.3))
		var bi: int = DogMesh.B_EAR[e]
		_g[bi] = Transform3D(re, head_pos + rh * (r[bi] - r[DogMesh.B_HEAD]))
	# Tail: the breed's carriage, curled, wagging; tucked in fear, swaying with the gait.
	var tp: Array = TAIL_POSE.get(_b.tail[0], [-20.0, 5.0])
	var base_pitch := deg_to_rad(lerpf(float(tp[0]), -80.0, fear))
	var curl := deg_to_rad(float(tp[1]) * (1.0 - fear))
	_wag_t += dt
	var wag_a := wag * (1.0 - fear) * 0.55
	var parent_b := rp
	var parent_p := pel_pos
	var parent_rest := r[DogMesh.B_PELVIS]
	for i in 4:
		var bi: int = DogMesh.B_TAIL[i]
		var pos := parent_p + parent_b * (r[bi] - parent_rest)
		var wagi := sin(_wag_t * TAU * 2.6 - float(i) * 0.7) * wag_a * (0.5 + 0.25 * float(i))
		wagi += sin(ph * TAU) * 0.12 * _moving
		var rel := _rx(-(base_pitch if i == 0 else curl)) * _ry(wagi)
		var rb := parent_b * rel if i > 0 else rp * _rx(-pitch * 0.6) * rel
		_g[bi] = Transform3D(rb, pos)
		parent_b = rb
		parent_p = pos
		parent_rest = r[bi]
	# Legs.
	_legs(dt, stride, s_sit, s_sniff)
	# Hand the globals to the skeleton as local poses.
	for i in DogMesh.BONES.size():
		var p: int = DogMesh.BONES[i][1]
		var g: Transform3D = _g[i]
		var loc := g if p < 0 else (_g[p] as Transform3D).affine_inverse() * g
		skeleton.set_bone_pose_position(i, loc.origin)
		skeleton.set_bone_pose_rotation(i, loc.basis.get_rotation_quaternion())
	bark = maxf(bark - dt * 3.0, 0.0)


## Where one paw goes this tick: [ball position, flex of the pastern (radians, + folds it back)].
func _paw_target(li: int, stride: float) -> Array:
	var r := _rest
	var leg: Array = DogMesh.B_LEGS[li]
	var neutral := r[leg[3]]
	var h: float = _b.h
	# Phase offsets: walk (lateral sequence), trot (diagonal pairs), gallop (rotary).
	var walk := [0.25, 0.75, 0.0, 0.5]
	var trot := [0.0, 0.5, 0.5, 0.0]
	var gal := [0.5, 0.6, 0.0, 0.1]
	var out := Vector3.ZERO
	var flex := 0.0
	var weights := [(1.0 - _trot) * (1.0 - _gallop), _trot * (1.0 - _gallop), _gallop]
	var duties := [0.62, 0.48, 0.34]
	var offs := [walk, trot, gal]
	for g in 3:
		var w: float = weights[g]
		if w <= 0.0:
			continue
		var phi := fposmod(_phase + float(offs[g][li]), 1.0)
		var duty: float = duties[g]
		var z := 0.0
		var y := 0.0
		var f := 0.0
		if phi < duty:
			z = -stride * 0.5 + stride * (phi / duty)
		else:
			var u := (phi - duty) / (1.0 - duty)
			z = stride * 0.5 - stride * smoothstep(0.0, 1.0, u)
			y = sin(u * PI) * h * (0.09 + 0.04 * float(g))
			f = sin(minf(u * 1.4, 1.0) * PI) * (1.25 if li < 2 else 0.6)
		out += Vector3(0.0, y, z) * w
		flex += f * w
	out *= _moving
	flex *= _moving
	return [neutral + out, flex]


func _legs(_dt: float, stride: float, s_sit: float, s_sniff: float) -> void:
	var r := _rest
	var h: float = _b.h
	for li in 4:
		var leg: Array = DogMesh.B_LEGS[li]
		var front := li < 2
		var parent: Transform3D = _g[DogMesh.B_CHEST] if front else _g[DogMesh.B_PELVIS]
		var parent_rest := r[DogMesh.B_CHEST] if front else r[DogMesh.B_PELVIS]
		var root := parent.origin + parent.basis * (r[leg[0]] - parent_rest)
		var tgt: Array = _paw_target(li, stride)
		var ball: Vector3 = tgt[0]
		var flex: float = tgt[1]
		var l1 := r[leg[0]].distance_to(r[leg[1]])
		var l2 := r[leg[1]].distance_to(r[leg[2]])
		var meta0 := r[leg[2]] - r[leg[3]] # from the ball up to the carpus / hock
		var meta := _rx(-flex if front else flex * 0.4) * meta0
		if not front and s_sit > 0.0:
			# Sitting: the hind paws come forward under the body, the hocks down on the ground.
			var sit_ball := Vector3(r[leg[3]].x * 1.2, r[leg[3]].y, r[DogMesh.B_LEGS[li - 2][3]].z + h * 0.32)
			ball = ball.lerp(sit_ball, s_sit)
			var lying := Vector3(0.0, h * 0.02, meta0.length())
			meta = meta.lerp(lying.normalized() * meta0.length(), s_sit)
		if front and s_sniff > 0.0:
			ball += Vector3(0.0, 0.0, -h * 0.03 * s_sniff)
		var pole := (Vector3.BACK if front else Vector3.FORWARD) * 1.0 + Vector3(signf(r[leg[0]].x) * 0.15, 0.0, 0.0)
		pole = parent.basis * pole
		var want_mid_end := ball + meta
		var sol: Array = _ik(root, want_mid_end, l1, l2, pole)
		var mid: Vector3 = sol[0]
		var end: Vector3 = sol[1]
		ball = end - meta
		var side := parent.basis.x
		_g[leg[0]] = Transform3D(_aim(r[leg[1]] - r[leg[0]], mid - root, side), root)
		_g[leg[1]] = Transform3D(_aim(r[leg[2]] - r[leg[1]], end - mid, side), mid)
		_g[leg[2]] = Transform3D(_aim(r[leg[3]] - r[leg[2]], ball - end, side), end)
		# The paw: flat on the ground in stance, curled under in the swing.
		var toe_name := ("toe" if front else "htoe") + ("L" if r[leg[0]].x < 0.0 else "R")
		var toe_rest: Vector3 = DogMesh.joints(breed)[toe_name]
		var curl := flex * (0.55 if front else 0.35)
		var toe_dir := _rx(-curl) * (toe_rest - r[leg[3]])
		_g[leg[3]] = Transform3D(_aim(toe_rest - r[leg[3]], toe_dir, side), ball)
