class_name HeroFace
extends RefCounted
## The hero's living face (wave 3, "hero-closeup"): his rig has no face bones, so a still idle
## face read as a mannequin's. HeroFace drives the eye shader (shaders/hero_eye.gdshader) and the
## lash shader (shaders/hero_lash.gdshader) from the head bone every frame:
##  - gaze: the eyes fixate a point and jump to the next in fast saccades, a fixation every
##    `fixation` seconds (a short hold now and then), a small drift and a micro-tremor between.
##    The point is ahead of him along the camera's view (where the player is looking), or the
##    camera itself when it stands in front of his face close up (a photo, a close-up) - the
##    eyes find the lens now and then and look away again. Each eye aims at the point from its
##    own centre, so near points converge. Clamped to the eye's real range (`max_yaw`, `max_pitch`).
##  - blinks: every 2-6 s, sometimes a double, and with a big saccade (people blink as their eyes
##    jump). A blink closes in 70 ms and opens in 130. The upper lid follows the eye down a little.
## Every roll is on its own RandomNumberGenerator with a fixed seed: nothing else's stream moves.

## Skinned-space eye centres (metres, the hero.glb mesh's own space) and radius, from the mesh
## (tools/hero_closeup/mesh_probe.gd: the eyeballs' bounds, the centre 12.5 mm behind the cornea).
const EYE_L := Vector3(0.0300, 1.6887, 0.1332)
const EYE_R := Vector3(-0.0300, 1.6887, 0.1332)
const EYE_RADIUS := 0.0122
## Seconds a blink takes to close, stay shut and open.
const BLINK_CLOSE := 0.07
const BLINK_HOLD := 0.03
const BLINK_OPEN := 0.13
## How far the upper lashes swing down (radians) when the lid is shut.
const LASH_SWING := 0.72

@export var fixation: Vector2 = Vector2(0.35, 2.4)
@export var blink_every: Vector2 = Vector2(2.0, 6.0)
@export var max_yaw: float = deg_to_rad(32.0)
@export var max_pitch: float = deg_to_rad(24.0)

var eye: ShaderMaterial
var lash: ShaderMaterial
## 0 open .. 1 shut (read by the checks).
var blink := 0.0
## The current and the target gaze of the left and right eye: (yaw, pitch_down) in the head frame.
var gaze_l := Vector2.ZERO
var gaze_r := Vector2.ZERO
var target_l := Vector2.ZERO
var target_r := Vector2.ZERO
## Counters for the checks.
var saccades := 0
var blinks := 0

var _rng := RandomNumberGenerator.new()
var _skeleton: Skeleton3D
var _mesh: MeshInstance3D
var _head := -1
var _bind := Transform3D.IDENTITY
var _next_fix := 0.6
var _next_blink := 1.5
var _blink_t := -1.0
var _double := false
var _gap := 0.0
var _offset := Vector2.ZERO
var _at_camera := false
var _last_us := 0
var _tremor := 0.0


static func enabled() -> bool:
	return closeup() and OS.get_environment("HERO_FACE") != "0"


## The whole close-up pass (the face, the clip speeds, the hair roots, the skin's backlight):
## HERO_CLOSEUP=0 is the A/B.
static func closeup() -> bool:
	return OS.get_environment("HERO_CLOSEUP") != "0"


## Stills: HERO_FACE_BLINK=0..1 holds the lids, HERO_FACE_GAZE=yaw,pitch (degrees, + his left
## and down) holds the eyes.
var _force_blink := -1.0
var _force_gaze := Vector2(INF, INF)


func _init() -> void:
	_rng.seed = 0x6e7e5ace
	if OS.get_environment("HERO_FACE_BLINK") != "":
		_force_blink = float(OS.get_environment("HERO_FACE_BLINK"))
	var g := OS.get_environment("HERO_FACE_GAZE").split(",")
	if g.size() == 2:
		_force_gaze = Vector2(deg_to_rad(float(g[0])), deg_to_rad(float(g[1])))


func attach(skeleton: Skeleton3D, mesh: MeshInstance3D) -> void:
	_skeleton = skeleton
	_mesh = mesh
	_head = skeleton.find_bone("Head")
	if mesh and mesh.skin:
		for i in mesh.skin.get_bind_count():
			if mesh.skin.get_bind_bone(i) == _head or mesh.skin.get_bind_name(i) == &"Head":
				_bind = mesh.skin.get_bind_pose(i)
				break
	_next_blink = _rng.randf_range(blink_every.x, blink_every.y)


## The head's deformation in the mesh's own space (a rest-pose point of the head -> where it is now).
func head_xform() -> Transform3D:
	if _skeleton == null or _head < 0 or _mesh == null or not _mesh.is_inside_tree():
		return Transform3D.IDENTITY
	# Not orthonormalised: the bind carries the rig's 100x (metres in the mesh, centimetres in
	# the skeleton the mesh node sits in).
	return _mesh.global_transform.affine_inverse() * _skeleton.global_transform * _skeleton.get_bone_global_pose(_head) * _bind


## Called on the skeleton's skeleton_updated (HeroLook.update()): advances by the real time since
## the last call, scaled by the game's time scale (slow motion slows the blinks; a pause holds them).
func update() -> void:
	var now := Time.get_ticks_usec()
	var dt := 0.0 if _last_us == 0 else clampf((now - _last_us) * 1e-6, 0.0, 0.1) * Engine.time_scale
	_last_us = now
	step(dt)


func step(dt: float) -> void:
	var h := head_xform()
	_choose(dt, h)
	_move(dt)
	_blink(dt)
	if _force_blink >= 0.0:
		blink = _force_blink
	if _force_gaze.x != INF:
		gaze_l = _force_gaze
		gaze_r = _force_gaze
	_apply(h)


## Picks the next fixation: the look point plus a random offset, at the camera when it is close in
## front of the face (and then only some of the time).
func _choose(dt: float, h: Transform3D) -> void:
	_next_fix -= dt
	var cam: Camera3D = _mesh.get_viewport().get_camera_3d() if _mesh and _mesh.is_inside_tree() else null
	var point := Vector3.ZERO
	var have := false
	var cam_close := false
	if cam:
		var to_local := _mesh.global_transform.affine_inverse()
		var c := to_local * cam.global_position
		# The camera in the head's rest frame (metres), from between the eyes.
		var rel := h.affine_inverse() * c - (EYE_L + EYE_R) * 0.5
		cam_close = rel.z > 0.2 and rel.length() < 4.0 and absf(atan2(rel.x, rel.z)) < max_yaw * 1.4
		if cam_close and _at_camera:
			point = c
			have = true
		else:
			# Where the player is looking: 20 m along the camera's view, unless that is behind
			# his head (the camera looks at his face): then straight ahead.
			point = to_local * (cam.global_position - cam.global_basis.z * 20.0)
			var p := h.affine_inverse() * point - (EYE_L + EYE_R) * 0.5
			have = p.z > 0.3 * p.length()
	if _next_fix <= 0.0:
		_next_fix = _rng.randf_range(fixation.x, fixation.y)
		if _rng.randf() < 0.18:
			_next_fix *= 2.2 # a longer hold
		_at_camera = cam_close and _rng.randf() < 0.45
		_offset = Vector2.ZERO if _at_camera else Vector2(_rng.randfn(0.0, deg_to_rad(9.0)), _rng.randfn(deg_to_rad(2.0), deg_to_rad(5.0)))
		var before := target_l
		target_l = _aim(h, EYE_L, point, have) + _offset
		target_r = _aim(h, EYE_R, point, have) + _offset
		target_l = _clamp(target_l)
		target_r = _clamp(target_r)
		var jump := (target_l - before).length()
		if jump > deg_to_rad(1.5):
			saccades += 1
		if jump > deg_to_rad(14.0) and _blink_t < 0.0 and _rng.randf() < 0.35:
			_start_blink()
	elif have and not _at_camera:
		# Between saccades the eyes stay on the point as the head moves (the vestibular reflex).
		target_l = _clamp(_aim(h, EYE_L, point, have) + _offset)
		target_r = _clamp(_aim(h, EYE_R, point, have) + _offset)


func _aim(h: Transform3D, eye_at: Vector3, point: Vector3, have: bool) -> Vector2:
	if not have:
		return Vector2.ZERO
	var d := h.basis.inverse() * (point - h * eye_at)
	if d.z < 0.05:
		d.z = 0.05 # never behind the head
	return Vector2(atan2(d.x, d.z), atan2(-d.y, Vector2(d.x, d.z).length()))


func _clamp(g: Vector2) -> Vector2:
	return Vector2(clampf(g.x, -max_yaw, max_yaw), clampf(g.y, -max_pitch, max_pitch))


func _move(dt: float) -> void:
	# A saccade is fast (about 30 ms for a large jump): a stiff ease, plus the tremor.
	var k := 1.0 - exp(-38.0 * dt)
	gaze_l = gaze_l.lerp(target_l, k)
	gaze_r = gaze_r.lerp(target_r, k)
	_tremor += dt


func _start_blink() -> void:
	_blink_t = 0.0
	blinks += 1


func _blink(dt: float) -> void:
	_next_blink -= dt
	if _gap > 0.0:
		_gap -= dt
		if _gap <= 0.0:
			_start_blink()
	elif _next_blink <= 0.0 and _blink_t < 0.0:
		_start_blink()
		_double = _rng.randf() < 0.15
		_next_blink = _rng.randf_range(blink_every.x, blink_every.y)
	if _blink_t >= 0.0:
		_blink_t += dt
		if _blink_t > BLINK_CLOSE + BLINK_HOLD + BLINK_OPEN:
			_blink_t = -1.0
			if _double:
				_double = false
				_gap = 0.12 # a short gap, then the second
	blink = blink_amount(_blink_t)


## How shut the lid is `t` seconds into a blink.
static func blink_amount(t: float) -> float:
	if t < 0.0:
		return 0.0
	if t < BLINK_CLOSE:
		return smoothstep(0.0, 1.0, t / BLINK_CLOSE)
	if t < BLINK_CLOSE + BLINK_HOLD:
		return 1.0
	return 1.0 - smoothstep(0.0, 1.0, (t - BLINK_CLOSE - BLINK_HOLD) / BLINK_OPEN)


static func eye_rotation(g: Vector2) -> Basis:
	# Yaw about the head's up (+ toward his left, +X), then pitch about its right (+ down).
	return Basis(Vector3.UP, g.x) * Basis(Vector3.RIGHT, g.y)


func _apply(h: Transform3D) -> void:
	if eye == null:
		return
	var tremor := Vector2(sin(_tremor * 83.0), cos(_tremor * 71.0)) * deg_to_rad(0.12)
	# Everything goes to the shaders in world space (see hero_eye.gdshader).
	var g := _mesh.global_transform if _mesh and _mesh.is_inside_tree() else Transform3D.IDENTITY
	var gh := g * h
	var hb := gh.basis.orthonormalized()
	var rl := hb * eye_rotation(gaze_l + tremor) * hb.inverse()
	var rr := hb * eye_rotation(gaze_r + tremor) * hb.inverse()
	var cl := gh * EYE_L
	var cr := gh * EYE_R
	var rad := EYE_RADIUS * gh.basis.get_scale().x
	eye.set_shader_parameter("eye_l", Vector4(cl.x, cl.y, cl.z, rad))
	eye.set_shader_parameter("eye_r", Vector4(cr.x, cr.y, cr.z, rad))
	eye.set_shader_parameter("head_basis", hb)
	eye.set_shader_parameter("rot_l", rl)
	eye.set_shader_parameter("rot_r", rr)
	# The upper lid follows the eye: down with a downward look, up a little with an upward one.
	var follow := clampf((gaze_l.y + gaze_r.y) * 0.5, -0.3, 0.4) * 0.7
	var shut := clampf(blink + maxf(follow, 0.0) * 0.5, 0.0, 1.0)
	eye.set_shader_parameter("blink", shut)
	eye.set_shader_parameter("lid_lift", minf(follow, 0.0))
	if lash:
		var swing := Basis(Vector3.RIGHT, LASH_SWING * shut + minf(follow, 0.0) * 0.4)
		lash.set_shader_parameter("eye_l", Vector4(cl.x, cl.y, cl.z, rad))
		lash.set_shader_parameter("eye_r", Vector4(cr.x, cr.y, cr.z, rad))
		lash.set_shader_parameter("head_basis", hb)
		lash.set_shader_parameter("lid_rot", hb * swing * hb.inverse())
