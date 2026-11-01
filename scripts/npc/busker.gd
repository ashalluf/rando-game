class_name Busker
extends Pedestrian
## A street performer (Buskers places them): a crowd rig at its pitch, playing. A Pedestrian like
## anyone - in the crowd cap and the "pedestrian" group, so shot, knocked, bled and ragdolled the
## same way, and gunfire sends them running with the rest; when it is over they walk back to the
## pitch and start again (the street vendors' way: StreetVendor).
##
## The acts are the crowd's clips (the "life" library, and a "busk" one of their own retargeted
## from the same CC0 Universal Animation Library by tools/crowd/busk_clips.gd: the dance, a
## crouch, a lantern-bearer's still pose) with the playing laid over them by hand, after the clip,
## near the camera only:
##   GUITAR    the guitar on the chest (Buskers.guitar_mesh, hung off Spine01), the right hand
##             strumming over the sound hole, the left on the neck changing chords;
##   DRUMS     seated on a bucket (the bench solve, Pedestrian._sit_pose()), sticks in both hands
##             striking the kit's buckets and cymbal (Buskers.DRUM_HITS) to a pattern of its own;
##   BREAK     toprock (the dance), a drop, a spin on the cardboard, a one-hand freeze, back up;
##   STATUE    silver all over on a plinth, frozen in a pose; now and then (or when somebody comes
##             close) a slow mechanical bow;
##   MARIACHI  a trio in black and silver under sombreros: the guitarron, the violin under the chin
##             with the bow across it, the trumpet at the lips.
## Arms are two-bone solves to points on the instrument; everything is worked out from the
## performance clock and a hash of the performer, nothing else rolled.

## Seconds a song lasts, and the pause between songs (the watchers clap, the performer nods).
@export var song_seconds: Vector2 = Vector2(32.0, 58.0)
@export var break_seconds: float = 4.0
## Strums a second (each a down and an up), drum steps a second (eighth notes).
@export var strum_rate: float = 1.7
@export var drum_rate: float = 3.4
## A living statue bows to anyone this close (m), at most this often (s).
@export var bow_reach: float = 3.2
@export var bow_every: float = 16.0

var kind: int = Buskers.Kind.GUITAR
## Which of a trio (0 guitarron, 1 violin, 2 trumpet); 0 for the rest.
var role: int = 0
var home := Vector2.ZERO
var home_yaw: float = 0.0
## Watchers clap while the physics clock (Pedestrian._life_now_ms) is before this.
var applause_until_ms: int = 0

var _kit_home := Vector2.ZERO
var _busk_ok: bool = false
var _gear: Dictionary = {}
var _gear_xf: Dictionary = {}
var _pw: float = 0.0
var _t: float = 0.0
var _song_end: float = 0.0
var _in_break: bool = false
var _frozen: bool = false
var _freeze_at: float = 0.0
var _bow_left: float = 0.0
var _bow_next: float = 0.0
var _lean_x: float = 0.0
var _beat: float = 0.0
var _pat: Array = []
var _hash: int = 0


func setup_busker(block_rect: Rect2, seed_value: int, at: Vector2, yaw: float, k: int, r: int) -> void:
	setup(block_rect, 4.0, seed_value)
	kind = k
	role = r
	home = at
	_kit_home = at
	home_yaw = yaw
	_hash = hash([seed_value, "busk"])


func _lives() -> bool:
	return true


func _roll_life(seed_value: int) -> void:
	super(seed_value)
	_carry = CrowdLife.Carry.NONE
	_jogger = false
	_dog_walker = false


## After the model and the life clips: the act's own clips, the costume, where to stand.
func _setup_life() -> void:
	super()
	# A performer at work is not part of the crowd's rain behaviour (RainCrowd): no umbrella.
	rain = null
	if not _life_ok:
		return
	_busk_ok = attach_clips(_anim, _model_path)
	_lean_x = _visual.rotation.x
	if _hat != Accessory.NONE and (kind == Buskers.Kind.MARIACHI or kind == Buskers.Kind.STATUE):
		_hide_hat()
	match kind:
		Buskers.Kind.STATUE:
			_paint_silver()
		Buskers.Kind.MARIACHI:
			_charro()
		Buskers.Kind.DRUMS:
			# The root stands where the clip's seated hips land on the kit's bucket.
			var info := _sit_clip_info()
			if not info.is_empty():
				var face := Vector2(-sin(home_yaw), -cos(home_yaw))
				home = _kit_home + face * (float(info.back) * _visual.scale.z - Buskers.SEAT_BACK)
				_seat_drop = float(info.hips) * _visual.scale.y - (Buskers.SEAT_H + CrowdLife.HIP_OVER_SEAT)
	_song_end = _song_len()


## Adds the performers' "busk" library to a rig's AnimationPlayer (False when the rig has none).
static func attach_clips(anim: AnimationPlayer, model_path: String) -> bool:
	if anim == null:
		return false
	if anim.has_animation_library("busk"):
		return true
	var path := "res://assets/models/crowd_busk/%s_busk.res" % model_path.get_file().get_basename()
	if not ResourceLoader.exists(path):
		return false
	anim.add_animation_library("busk", load(path))
	return true


func _ready() -> void:
	super()
	_work(true)


func _song_len() -> float:
	var r := float(absi(hash([_hash, int(_t)])) % 1000) / 1000.0
	return _t + lerpf(song_seconds.x, song_seconds.y, r)


# --- At the pitch ----------------------------------------------------------------------------

func _work(at_once: bool) -> void:
	_act = CrowdLife.Act.STAND
	_act_left = INF
	_act_face = home_yaw
	_act_beat = 3.0
	_life_base = _base_clip()
	if at_once:
		_stage = Stage.DOING
		_place_at(home, home_yaw)
		_life_clip = _life_base
		if kind == Buskers.Kind.STATUE or kind == Buskers.Kind.DRUMS:
			_kinematic = true
			collision_mask = 0
	else:
		_stage = Stage.GOING
		_go_to(home)


func _base_clip() -> String:
	if not _life_ok:
		return ""
	match kind:
		Buskers.Kind.DRUMS:
			return CrowdLife.SIT
		Buskers.Kind.STATUE:
			return "busk/spell" if _busk_ok and (_hash % 3) != 0 else ("busk/lantern" if _busk_ok else CrowdLife.IDLE)
		Buskers.Kind.BREAK:
			return "busk/dance" if _busk_ok else CrowdLife.IDLE
	return CrowdLife.IDLE


func _performing() -> bool:
	return _stage == Stage.DOING and _act == CrowdLife.Act.STAND and not _down and _panic_left <= 0.0


## On the plinth (or seated at the kit) a performer is placed, not dropped: the walkers' 0.1 m
## (which gravity takes up) is taken off, and the statue stands on the plinth's top.
func _ground_y(x: float, z: float, fallback: float) -> float:
	var at_work := _stage == Stage.DOING and _panic_left <= 0.0
	if at_work and kind == Buskers.Kind.STATUE:
		return super(x, z, fallback) - 0.1 + Buskers.PLINTH_H
	if at_work and kind == Buskers.Kind.DRUMS:
		return super(x, z, fallback) - 0.1
	return super(x, z, fallback)


func _life_range_changed(_near: bool) -> void:
	pass


func _update_lod() -> void:
	super()
	if _performing() and (kind == Buskers.Kind.STATUE or kind == Buskers.Kind.DRUMS):
		# On the plinth or the bucket: placed, never solved against what it stands on.
		_kinematic = true
		collision_mask = 0


func _scare(at: Vector3) -> void:
	_frozen = false
	_visual.rotation.x = _lean_x
	_visual.rotation.z = 0.0
	if _hip_bone >= 0 and _head_skel:
		_head_skel.reset_bone_pose(_hip_bone)
	if _kinematic:
		# Off the plinth or the bucket and into the physics (_update_lod puts a far one back).
		_kinematic = false
		collision_mask = 1
	super(at)


func _physics_process(delta: float) -> void:
	super(delta)
	if _down:
		return
	# The scare is over and they are walking about: back to the pitch.
	if _act == CrowdLife.Act.NONE and _panic_left <= 0.0 and _cross == Cross.NONE:
		_work(false)


## The clock of the act: songs and breaks, the dancer's routine, the statue's bows.
func _do_act(delta: float) -> void:
	super(delta)
	if _stage != Stage.DOING or not _life_ok:
		return
	_t += delta
	if _t >= _song_end:
		if not _in_break:
			_in_break = true
			_song_end = _t + break_seconds
			applause_until_ms = _life_now_ms() + int(break_seconds * 1000.0)
			if kind != Buskers.Kind.STATUE and kind != Buskers.Kind.BREAK and _one_shot_left <= 0.0:
				_one_shot(CrowdLife.NOD)
		else:
			_in_break = false
			_song_end = _song_len()
	match kind:
		Buskers.Kind.BREAK:
			_break_routine()
		Buskers.Kind.STATUE:
			_statue(delta)
	# Looking at whoever is watching now and then, else ahead.
	_beat -= delta
	if _beat <= 0.0:
		_beat = 2.5 + float(absi(hash([_hash, int(_t * 3.0)])) % 100) / 25.0
		_life_look = Vector3.INF
		if kind != Buskers.Kind.STATUE and _player != null and is_instance_valid(_player) \
				and _player.global_position.distance_to(global_position) < 9.0:
			_life_look = _player.global_position + Vector3.UP * 1.5


## The dancer's 18 s routine: toprock, drop, spin, freeze, up.
const BREAK_CYCLE := 18.0


func _break_phase() -> float:
	return fposmod(_t + float(_hash % 7), BREAK_CYCLE)


func _break_routine() -> void:
	if not _busk_ok:
		return
	var p := _break_phase()
	var want := "busk/dance"
	if p >= 8.0 and p < 15.0:
		want = "busk/crouch"
	if want != _life_clip and _one_shot_left <= 0.0:
		_life_clip = want
		_life_base = want
	var spin := 0.0
	if p >= 9.0 and p < 12.5:
		# A spin on the spot, quick in the middle, two and a half turns.
		var f := (p - 9.0) / 3.5
		spin = TAU * 2.5 * (f - sin(TAU * f) / TAU)
	_visual.rotation.y = home_yaw + spin
	var tilt := 0.0
	if p >= 12.5 and p < 14.6:
		tilt = smoothstep(12.5, 12.8, p) * (1.0 - smoothstep(14.3, 14.6, p))
		if p < 12.6 and _t > 3.0:
			applause_until_ms = _life_now_ms() + 3200
	_frozen = p >= 12.8 and p < 14.3
	# The freeze: down onto one hand, the body tipped over to the side.
	_visual.rotation.z = -1.0 * tilt
	_visual.rotation.x = _lean_x + 0.25 * tilt


func _statue(delta: float) -> void:
	_bow_next -= delta
	if _bow_left > 0.0:
		_bow_left -= delta
		_frozen = false
		if _bow_left <= 0.0:
			_life_clip = _life_base
		return
	# Frozen once the pose has blended in (frozen mid-blend it would hold half a walk).
	_frozen = _t > 1.2
	var near := _player != null and is_instance_valid(_player) and _player.global_position.distance_to(global_position) < bow_reach
	if _bow_next <= 0.0 and (near or _in_break):
		_bow_next = bow_every
		if _anim and _anim.has_animation(CrowdLife.NOD):
			_frozen = false
			_life_clip = CrowdLife.NOD
			_bow_left = _anim.get_animation(CrowdLife.NOD).length / 0.55 + 0.8


## A frozen pose holds the clip where it is; a statue's bow plays at half speed (mechanical).
func _animate_gait() -> void:
	super()
	if _anim == null or not _performing():
		return
	if _frozen:
		_anim.speed_scale = 0.0
		_rate = -1.0
	elif kind == Buskers.Kind.STATUE:
		_anim.speed_scale = 0.55
		_rate = -1.0
	elif kind == Buskers.Kind.BREAK and _life_clip == "busk/dance":
		_anim.speed_scale = 1.15
		_rate = -1.0


# --- The playing, after the clip ---------------------------------------------------------------

func _life_pose(delta: float) -> void:
	super(delta)
	if _head_skel == null:
		return
	var on := _performing() and _life_near
	_pw = move_toward(_pw, 1.0 if on else 0.0, delta * 2.0)
	_show_gear(_life_near and not _down)
	if _pw <= 0.001:
		return
	var w := smoothstep(0.0, 1.0, _pw)
	match kind:
		Buskers.Kind.GUITAR:
			_play_guitar(w, false)
		Buskers.Kind.DRUMS:
			_sit_pose()
			_play_drums(w)
		Buskers.Kind.BREAK:
			_freeze_hand(w)
		Buskers.Kind.MARIACHI:
			match role:
				0:
					_play_guitar(w, true)
				1:
					_play_violin(w)
				2:
					_play_trumpet(w)


## The instruments, made the first time they are wanted and shown while the act is near.
func _show_gear(want: bool) -> void:
	if want and _gear.is_empty():
		_make_gear()
	for k: String in _gear:
		var n: Node3D = _gear[k]
		if is_instance_valid(n):
			n.visible = want


func _make_gear() -> void:
	var s := _skel_unit
	match kind:
		Buskers.Kind.GUITAR:
			_gear["guitar"] = _hang(Buskers.guitar_mesh(false), "Spine01", _guitar_rest(false, s))
		Buskers.Kind.MARIACHI:
			match role:
				0:
					_gear["guitar"] = _hang(Buskers.guitar_mesh(true), "Spine01", _guitar_rest(true, s))
				1:
					_gear["violin"] = _hang(Buskers.violin_mesh(), "Spine", _violin_rest(s))
					_gear["bow"] = _loose(Buskers.bow_mesh())
				2:
					_gear["trumpet"] = _hang(Buskers.trumpet_mesh(), "Head", _trumpet_rest(s))
			_gear["sombrero"] = _sombrero()
		Buskers.Kind.DRUMS:
			_gear["stick_r"] = _loose(Buskers.stick_mesh())
			_gear["stick_l"] = _loose(Buskers.stick_mesh())


## The guitar in skeleton space at the rest pose: across the belly, the neck up to the left.
func _guitar_rest(big: bool, s: float) -> Transform3D:
	var hips := _head_skel.get_bone_global_rest(_head_skel.find_bone("Hips")).origin
	var x := Vector3(0.86, 0.46, 0.16).normalized()
	var z := (Vector3(0, 0, 1) - x * x.z).normalized()
	var y := z.cross(x)
	var at := hips + Vector3(-0.07, 0.17 if big else 0.2, 0.25 if big else 0.18) * s
	return Transform3D(Basis(x, y, z) * Basis.from_scale(Vector3.ONE * s), at)


## The violin on the left collarbone, the chin on its rest, the scroll out to the front left.
func _violin_rest(s: float) -> Transform3D:
	var neck := _head_skel.get_bone_global_rest(_head_skel.find_bone("neck")).origin
	var x := Vector3(0.62, 0.08, 0.78).normalized()
	var z := (Vector3(-0.45, 1.0, 0.0) - x * x.dot(Vector3(-0.45, 1.0, 0.0))).normalized()
	var y := z.cross(x)
	var chin := neck + Vector3(0.07, -0.02, 0.07) * s
	return Transform3D(Basis(x, y, z) * Basis.from_scale(Vector3.ONE * s), chin + x * 0.15 * s - z * 0.02 * s)


## The trumpet at the lips, pointing ahead and a little down, valves up.
func _trumpet_rest(s: float) -> Transform3D:
	var hb := _head_skel.find_bone("Head")
	var head := _head_skel.get_bone_global_rest(hb).origin
	var h := CrowdHat.head_for(_model_path)
	var mouth := head + Vector3(0.0, h.eye_y - 0.08, h.eye_z + 0.012) * s
	var x := Vector3(0.0, -0.22, 1.0).normalized()
	var y := (Vector3.UP - x * x.y).normalized()
	var z := x.cross(y)
	return Transform3D(Basis(x, y, z) * Basis.from_scale(Vector3.ONE * s), mouth)


## A mesh on a bone, placed where `rest` (skeleton space, rest pose) says.
func _hang(mesh: Mesh, bone: String, rest: Transform3D) -> Node3D:
	var b := _head_skel.find_bone(bone)
	var att := BoneAttachment3D.new()
	_head_skel.add_child(att)
	att.bone_name = bone
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.visibility_range_end = life_range
	mi.transform = _head_skel.get_bone_global_rest(b).affine_inverse() * rest
	att.add_child(mi)
	_gear_xf[bone] = mi
	return att


## A mesh placed in the world each tick (sticks, the bow).
func _loose(mesh: Mesh) -> Node3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.visibility_range_end = life_range
	mi.top_level = true
	add_child(mi)
	return mi


func _sombrero() -> Node3D:
	var skel := _head_skel
	var hb := skel.find_bone("Head")
	var rest := skel.get_bone_global_rest(hb)
	var att := BoneAttachment3D.new()
	skel.add_child(att)
	att.bone_name = "Head"
	var mi := MeshInstance3D.new()
	mi.mesh = Buskers.sombrero_mesh(_model_path)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.visibility_range_end = accessory_distance
	mi.transform = rest.affine_inverse() * Transform3D(Basis.from_scale(Vector3.ONE * _skel_unit), rest.origin)
	att.add_child(mi)
	for node in _visual.find_children("Hair*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).visible = false
		node.set_meta("under_hat", true)
	return att


## A point given in a hung instrument's own metres, in skeleton space now.
func _on(bone: String, p: Vector3) -> Vector3:
	var mi: MeshInstance3D = _gear_xf.get(bone)
	var b := _head_skel.find_bone(bone)
	if mi == null or b < 0:
		return Vector3.ZERO
	return _head_skel.get_bone_global_pose(b) * (mi.transform * p)


func _shoulder(side: String) -> Vector3:
	return _head_skel.get_bone_global_pose(_head_skel.find_bone(side + "Arm")).origin


func _play_guitar(w: float, big: bool) -> void:
	if not _gear_xf.has("Spine01"):
		return
	var s := 1.33 if big else 1.0
	var strum := 0.0 if _in_break else sin(_t * TAU * strum_rate)
	var r := _on("Spine01", Vector3(-0.05 * s, (-0.05 + 0.05 * strum) * s, 0.07))
	var chord := float(absi(hash([_hash, int(_t / 2.1)])) % 4) / 3.0
	var l := _on("Spine01", Vector3(lerpf(0.42, 0.56, chord) * s, -0.04 * s, 0.01))
	var u := _skel_unit
	two_bone(_head_skel, "Right", r, _shoulder("Right") + Vector3(-0.25, -0.25, -0.3) * u, w)
	two_bone(_head_skel, "Left", l, _shoulder("Left") + Vector3(0.2, -0.45, 0.05) * u, w)


func _play_violin(w: float) -> void:
	if not _gear_xf.has("Spine"):
		return
	var u := _skel_unit
	var l := _on("Spine", Vector3(0.26, -0.01, -0.005))
	two_bone(_head_skel, "Left", l, _shoulder("Left") + Vector3(0.05, -0.45, 0.1) * u, w)
	# The bow across the strings between the bridge and the fingerboard, drawn up and down.
	var contact := _on("Spine", Vector3(0.0, 0.0, 0.036))
	var across := (_on("Spine", Vector3(0.0, 1.0, 0.0)) - _on("Spine", Vector3.ZERO)).normalized()
	# The bow hand is on the player's right.
	var right := _head_skel.get_bone_global_pose(_head_skel.find_bone("Hips")).basis.x.normalized() * -1.0
	if across.dot(right) < 0.0:
		across = -across
	var stroke := 0.0 if _in_break else 0.5 + 0.5 * sin(_t * TAU * 0.55)
	var d := lerpf(0.12, 0.52, stroke) * u
	var hand := contact + across * d
	two_bone(_head_skel, "Right", hand, _shoulder("Right") + Vector3(-0.3, -0.3, -0.1) * u, w)
	var bow: Node3D = _gear.get("bow")
	if bow != null:
		var to_world := _head_skel.global_transform
		var hb := _head_skel.get_bone_global_pose(_head_skel.find_bone("RightHand")).origin
		var a := to_world * hb
		var dir := (to_world * contact - a).normalized()
		bow.global_transform = Transform3D(_basis_x(dir, Vector3.UP), a)


func _play_trumpet(w: float) -> void:
	if not _gear_xf.has("Head"):
		return
	var u := _skel_unit
	two_bone(_head_skel, "Right", _on("Head", Vector3(0.2, 0.065, 0.04)), _shoulder("Right") + Vector3(-0.35, -0.3, 0.0) * u, w)
	two_bone(_head_skel, "Left", _on("Head", Vector3(0.21, -0.03, -0.035)), _shoulder("Left") + Vector3(0.3, -0.35, 0.05) * u, w)


## The kit's strike points, the pattern, the sticks.
func _play_drums(w: float) -> void:
	if _pat.is_empty():
		var r := RandomNumberGenerator.new()
		r.seed = _hash
		for i in 8:
			# Right hand mostly on the cymbal and the pail, the left on the bass and the high
			# bucket; one bar of eight, its own for each drummer.
			_pat.append([[3, 3, 2, 3][r.randi() % 4] if i % 2 == 0 else [3, 2, 0][r.randi() % 3], [0, 1, 0, 1][r.randi() % 4] if i % 4 != 2 else 1])
	var kit := (get_parent() as Node3D).global_transform * Transform3D(Basis(Vector3.UP, home_yaw), Vector3(_kit_home.x, global_position.y - (get_parent() as Node3D).global_position.y, _kit_home.y))
	var to_skel := _head_skel.global_transform.affine_inverse()
	var step := _t * drum_rate
	var i0 := int(floor(step))
	var f := step - float(i0)
	var u := _skel_unit
	for side in 2:
		var a: int = _pat[i0 % 8][side]
		var b: int = _pat[(i0 + 1) % 8][side]
		var pa: Vector3 = Buskers.DRUM_HITS[a]
		var pb: Vector3 = Buskers.DRUM_HITS[b]
		var lift := 0.16 * sin(PI * f) if not _in_break else 0.12
		var tip := pa.lerp(pb, smoothstep(0.15, 0.85, f)) + Vector3(0.0, lift, 0.0)
		# The hand behind and above the tip, the stick sloping down to it.
		var hand := tip + Vector3(0.05 if side == 0 else -0.05, 0.1, 0.27)
		var hand_g := kit * hand
		var tip_g := kit * tip
		var pole := _shoulder("Right" if side == 0 else "Left") + Vector3(-0.45 if side == 0 else 0.45, -0.3, -0.05) * u
		two_bone(_head_skel, "Right" if side == 0 else "Left", to_skel * hand_g, pole, w)
		var stick: Node3D = _gear.get("stick_r" if side == 0 else "stick_l")
		if stick != null:
			var hb := _head_skel.get_bone_global_pose(_head_skel.find_bone("RightHand" if side == 0 else "LeftHand")).origin
			var at := _head_skel.global_transform * hb
			stick.global_transform = Transform3D(_basis_x((tip_g - at).normalized(), Vector3.UP), at)


## In the freeze one hand goes down flat to the cardboard under the shoulder it tipped toward.
func _freeze_hand(w: float) -> void:
	var p := _break_phase()
	var k := smoothstep(12.5, 12.8, p) * (1.0 - smoothstep(14.3, 14.6, p))
	if k <= 0.001:
		return
	var sh := _head_skel.global_transform * _shoulder("Right")
	var ground := Vector3(sh.x, global_position.y + 0.08, sh.z)
	two_bone(_head_skel, "Right", _head_skel.global_transform.affine_inverse() * ground, _shoulder("Right") + Vector3(-0.3, 0.2, -0.2) * _skel_unit, w * k)


static func _basis_x(x: Vector3, up: Vector3) -> Basis:
	var z := x.cross(up)
	if z.length_squared() < 1e-6:
		z = x.cross(Vector3.FORWARD)
	z = z.normalized()
	return Basis(x, z.cross(x).normalized(), z)


## A two-bone arm solve in skeleton space: the hand of `side` ("Left" / "Right") to `target`,
## the elbow toward `pole`, blended over the clip's pose by `w`.
static func two_bone(sk: Skeleton3D, side: String, target: Vector3, pole: Vector3, w: float) -> void:
	var up := sk.find_bone(side + "Arm")
	var fore := sk.find_bone(side + "ForeArm")
	var hand := sk.find_bone(side + "Hand")
	if up < 0 or fore < 0 or hand < 0 or w <= 0.0:
		return
	var q_up := sk.get_bone_pose_rotation(up)
	var q_fore := sk.get_bone_pose_rotation(fore)
	var a := sk.get_bone_global_pose(up)
	var k := sk.get_bone_global_pose(fore)
	var f := sk.get_bone_global_pose(hand)
	var l1 := a.origin.distance_to(k.origin)
	var l2 := k.origin.distance_to(f.origin)
	var to := target - a.origin
	if to.length_squared() < 1e-8 or l1 < 1e-5 or l2 < 1e-5:
		return
	var d := clampf(to.length(), absf(l1 - l2) + 0.01 * (l1 + l2), (l1 + l2) * 0.995)
	var dir := to.normalized()
	var pv := pole - a.origin
	pv = pv - dir * pv.dot(dir)
	if pv.length_squared() < 1e-8:
		pv = (k.origin - a.origin) - dir * (k.origin - a.origin).dot(dir)
	pv = pv.normalized()
	var cos_a := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var k_new := a.origin + (dir * cos_a + pv * sqrt(1.0 - cos_a * cos_a)) * l1
	_set_rot(sk, up, Basis(Quaternion((k.origin - a.origin).normalized(), (k_new - a.origin).normalized())) * a.basis)
	var k2 := sk.get_bone_global_pose(fore)
	var f2 := sk.get_bone_global_pose(hand)
	_set_rot(sk, fore, Basis(Quaternion((f2.origin - k2.origin).normalized(), (a.origin + dir * d - k2.origin).normalized())) * k2.basis)
	if w < 0.999:
		sk.set_bone_pose_rotation(up, q_up.slerp(sk.get_bone_pose_rotation(up), w))
		sk.set_bone_pose_rotation(fore, q_fore.slerp(sk.get_bone_pose_rotation(fore), w))


static func _set_rot(sk: Skeleton3D, bone: int, global_basis: Basis) -> void:
	var p := sk.get_bone_parent(bone)
	var pb := sk.get_bone_global_pose(p).basis if p >= 0 else Basis.IDENTITY
	sk.set_bone_pose_rotation(bone, (pb.orthonormalized().inverse() * global_basis.orthonormalized()).get_rotation_quaternion())


# --- Costumes --------------------------------------------------------------------------------

## A living statue: every surface of the body one coat of silver paint over the rig's own relief.
func _paint_silver() -> void:
	for mi in _meshes:
		if not is_instance_valid(mi):
			continue
		var src := mi.mesh.surface_get_material(0) as StandardMaterial3D if mi.mesh and mi.mesh.get_surface_count() > 0 else null
		mi.material_override = silver_material(src.albedo_texture if src else null, is_hair(mi))


static var _silver: Dictionary = {}


static func silver_material(albedo: Texture2D, hair: bool) -> StandardMaterial3D:
	var key := "%d_%d" % [albedo.get_instance_id() if albedo else 0, int(hair)]
	if _silver.has(key):
		return _silver[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.62, 0.63, 0.64)
	m.metallic = 0.85
	m.roughness = 0.38 if not hair else 0.5
	if albedo and not hair:
		var nrm := _normal_map_for(albedo)
		if nrm != null:
			m.normal_enabled = true
			m.normal_texture = nrm
			m.normal_scale = 0.6
	if hair:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
		m.albedo_texture = albedo
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_silver[key] = m
	return m


## A mariachi's charro suit: jacket and trousers black (the character shader's garment split),
## the rig's own face, skin and hair.
func _charro() -> void:
	for mi in _meshes:
		if not is_instance_valid(mi) or is_hair(mi):
			continue
		var src := mi.mesh.surface_get_material(0) as StandardMaterial3D if mi.mesh and mi.mesh.get_surface_count() > 0 else null
		if src and src.albedo_texture:
			var m := charro_material(src.albedo_texture)
			if m != null:
				mi.material_override = m


static var _charros: Dictionary = {}
const CHARRO := Color(0.05, 0.045, 0.05)


static func charro_material(albedo: Texture2D) -> ShaderMaterial:
	var key := albedo.get_instance_id()
	if _charros.has(key):
		return _charros[key]
	var base := character_material(albedo, 1)
	if base == null:
		return null
	var mat := base.duplicate() as ShaderMaterial
	mat.set_shader_parameter("cloth_hue", CHARRO.h)
	mat.set_shader_parameter("cloth_sat", CHARRO.s)
	mat.set_shader_parameter("cloth_value", CHARRO.v)
	mat.set_shader_parameter("cloth_strength", 0.97)
	mat.set_shader_parameter("pants_hue", CHARRO.h)
	mat.set_shader_parameter("pants_sat", CHARRO.s)
	mat.set_shader_parameter("pants_value", CHARRO.v)
	mat.set_shader_parameter("pants_strength", 0.97)
	mat.set_shader_parameter("cloth_roughness", 0.62)
	mat.set_shader_parameter("cloth_shade_keep", 0.55)
	_charros[key] = mat
	return mat


func _hide_hat() -> void:
	for n in _visual.find_children("*", "MeshInstance3D", true, false):
		if String(n.name).begins_with("Hat") or (n.get_parent() is BoneAttachment3D and not (n as MeshInstance3D) in _meshes):
			(n as Node3D).visible = false


## The body a knocked performer becomes keeps the costume (a fresh copy of the rig).
func _dress_doll(doll: Ragdoll) -> void:
	super(doll)
	if doll._rig == null or (kind != Buskers.Kind.STATUE and kind != Buskers.Kind.MARIACHI):
		return
	for node in doll._rig.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var src := mi.mesh.surface_get_material(0) as StandardMaterial3D if mi.mesh and mi.mesh.get_surface_count() > 0 else null
		if kind == Buskers.Kind.STATUE:
			mi.material_override = silver_material(src.albedo_texture if src else null, is_hair(mi))
		elif src and src.albedo_texture and not is_hair(mi):
			var m := charro_material(src.albedo_texture)
			if m != null:
				mi.material_override = m
