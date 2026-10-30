class_name CrowdLife
## The crowd's everyday life (GAME_PLAN G5): the data and the shared pieces behind what a
## Pedestrian does when it is not just walking - the "life" clip library each rig gets
## (tools/crowd/life_clips.gd: Quaternius' Universal Animation Library 1 and 2, CC0, retargeted
## onto every crowd rig), the arm poses a walker carries a phone, a cup or a bag in, the props
## they hold (built in code, hung off the hand bone), and the seats a chunk's benches offer.
## The behaviour itself (who stops to talk, sits down, leans on a wall, ...) is Pedestrian's
## "Life" section; everything here is static and shared by the whole crowd.

## What somebody is doing while stopped (Pedestrian._act).
enum Act { NONE, STAND, LEAN, WINDOW, TALK, SIT, WATCH }
## What a person carries (rolled once per person; walking, near the camera only, and standing).
enum Carry { NONE, CALL, TEXT, CUP, BAG, SMOKE }
## Props held in a hand.
enum Prop { PHONE, CUP, BAG, CIGARETTE }

const LIB_DIR := "res://assets/models/crowd_life/"
## Clip names in the "life" library (CLIPS in tools/crowd/life_clips.gd).
const IDLE := "life/idle"
const TALK := "life/talk"
const PHONE := "life/phone"
const FOLD := "life/fold"
const DRINK := "life/drink"
const NOD := "life/nod"
const SHAKE := "life/shake"
const RAIL := "life/rail"
const SIT_DOWN := "life/sit_down"
const SIT := "life/sit"
const SIT_TALK := "life/sit_talk"
const STAND_UP := "life/stand_up"
const JOG := "life/jog"
## One-shots: started from their first frame and timed by the walker (never looped).
const ONE_SHOTS := [DRINK, NOD, SIT_DOWN, STAND_UP]
## The jog's ground speed at speed_scale 1 (clip_probe.tscn on all twelve rigs: 2.3-3.7 per
## foot; the legs' swing was scaled to a jogger's stride in life_clips.gd).
const JOG_CLIP_SPEED := 3.0

## The arm poses a walker carries something in, laid over the walk (Pedestrian._carry_overlay):
## [clip, time (fraction), bones]. Taken from the library's own frames, so they are a real
## animator's arm on each rig: the phone held to the right ear, both hands in front at the
## chest (texting, the head tipped down on top), the left forearm raised in front as the
## torch-bearer's is (a coffee cup).
const CARRY_POSES := {
	Carry.CALL: [PHONE, 0.5, ["RightShoulder", "RightArm", "RightForeArm", "RightHand"]],
	Carry.TEXT: [TALK, 0.0, ["LeftArm", "LeftForeArm", "LeftHand", "RightArm", "RightForeArm", "RightHand"]],
}
## The coffee is carried the way people do, upper arm down and forearm forward: aimed (not
## sampled), along this direction in skeleton space (+Z forward, +X the rig's left), so the cup
## stays in front whatever the walk does with the upper arm.
const CUP_FOREARM := Vector3(-0.3, 0.12, 1.0)
## Which hand holds what (a carry's prop, and the standing activities').
const PROP_HAND := {Prop.PHONE: "RightHand", Prop.CUP: "LeftHand", Prop.BAG: "RightHand", Prop.CIGARETTE: "LeftHand"}

## Seats on a bench: two, either side of the middle (a bench is 2.45 m long).
const SEAT_OFFSETS := [-0.55, 0.55]
## Height of a bench seat above the pavement, and how far in front of the bench's origin its
## middle is (prop_bench_kit, faced -Z by PropFactory.model_bench()).
const SEAT_HEIGHT := 0.45
const SEAT_DEPTH := 0.06
## A hip joint sits this far above whatever its owner sits on.
const HIP_OVER_SEAT := 0.1

static var _libs: Dictionary = {}
static var _poses: Dictionary = {}
static var _meshes: Dictionary = {}
static var _material: ShaderMaterial


## Adds the rig's "life" library to its AnimationPlayer. False when the rig has none (an old
## or new model nobody ran tools/crowd/life_clips.gd for): that person just walks.
static func attach(anim: AnimationPlayer, model_path: String) -> bool:
	if anim == null:
		return false
	if anim.has_animation_library("life"):
		return true
	var lib := library(model_path)
	if lib == null:
		return false
	anim.add_animation_library("life", lib)
	return true


static func library(model_path: String) -> AnimationLibrary:
	if _libs.has(model_path):
		return _libs[model_path]
	var path := LIB_DIR + model_path.get_file().get_basename() + "_life.res"
	var lib: AnimationLibrary = load(path) if ResourceLoader.exists(path) else null
	_libs[model_path] = lib
	return lib


## {bone index: local rotation} for a carry pose on this rig (cached per model).
static func carry_pose(model_path: String, skel: Skeleton3D, carry: int) -> Dictionary:
	var key := "%s|%d" % [model_path, carry]
	if _poses.has(key):
		return _poses[key]
	var out := {}
	var lib := library(model_path)
	if lib != null and CARRY_POSES.has(carry):
		var spec: Array = CARRY_POSES[carry]
		var clip := String(spec[0]).trim_prefix("life/")
		if lib.has_animation(clip):
			var a := lib.get_animation(clip)
			for bone: String in spec[2]:
				var t := a.find_track(NodePath("Armature/Skeleton3D:" + bone), Animation.TYPE_ROTATION_3D)
				var b := skel.find_bone(bone)
				if t >= 0 and b >= 0:
					out[b] = a.rotation_track_interpolate(t, a.length * float(spec[1]))
	_poses[key] = out
	return out


## A chunk's bench (CityChunk._add_bench, the bus stops' benches) offers its seats to the
## chunk's walkers. `at` is in the chunk's own space (the walkers' too), `yaw` the way the
## bench faces (forward is -Z). `record` is the bench's prop record: a broken bench seats nobody.
static func add_seat(chunk: Node, at: Vector3, yaw: float, record: Variant = null) -> void:
	if chunk == null:
		return
	var seats: Array = chunk.get_meta("life_seats", [])
	var face := Vector2(-sin(yaw), -cos(yaw))
	var side := Vector2(face.y, -face.x)
	for off: float in SEAT_OFFSETS:
		var p := Vector2(at.x, at.z) + face * SEAT_DEPTH + side * off
		seats.append({"p": p, "yaw": yaw, "taken": null, "record": record})
	chunk.set_meta("life_seats", seats)


## The free seat nearest `from` (chunk space) within `reach`, or {}.
static func free_seat(chunk: Node, from: Vector2, reach: float) -> Dictionary:
	if chunk == null or not chunk.has_meta("life_seats"):
		return {}
	var best := {}
	var best_d := reach * reach
	for seat: Dictionary in chunk.get_meta("life_seats"):
		if seat.taken != null and is_instance_valid(seat.taken):
			continue
		var rec: Variant = seat.record
		if rec is Dictionary and bool((rec as Dictionary).get("dead", false)):
			continue
		var d := (seat.p as Vector2).distance_squared_to(from)
		if d < best_d:
			best_d = d
			best = seat
	return best


## Whether somebody is sitting in the place beside `seat` on the same bench.
static func neighbour(chunk: Node, seat: Dictionary) -> Node:
	for other: Dictionary in chunk.get_meta("life_seats", []):
		if other != seat and other.record == seat.record and other.yaw == seat.yaw \
				and (other.p as Vector2).distance_to(seat.p) < 1.3 and other.taken != null and is_instance_valid(other.taken):
			return other.taken
	return null


## One shared mesh per prop, built in metres in the GRIP frame: x along the thumb, y along the
## fingers from the wrist, z out of the palm (grip_basis() turns it into the hand bone's frame).
## Colours in the vertex colour; the shader's emission comes from UV.x (1: the phone's screen,
## 2: a cigarette's ember).
static func prop_mesh(kind: int) -> Mesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	match kind:
		Prop.PHONE:
			# 7 x 14.6 x 0.8 cm flat on the palm, the screen away from it (to the ear on a call,
			# up when texting).
			_box(st, Vector3(0.0, 0.075, 0.022), Vector3(0.071, 0.146, 0.008), Color(0.07, 0.07, 0.08), 0.0)
			_box(st, Vector3(0.0, 0.075, 0.0265), Vector3(0.064, 0.134, 0.0012), Color(0.25, 0.42, 0.6), 1.0)
		Prop.CUP:
			# A 12 oz paper cup with a sleeve and a lid, upright along the thumb, in the curl of
			# the fingers.
			_tube(st, Vector3(0.0, 0.07, 0.05), Vector3.RIGHT, -0.075, 0.03, 0.042, 0.13, Color(0.93, 0.92, 0.88), 14)
			_tube(st, Vector3(0.0, 0.07, 0.05), Vector3.RIGHT, -0.055, 0.0365, 0.0405, 0.05, Color(0.55, 0.40, 0.25), 14)
			_tube(st, Vector3(0.0, 0.07, 0.05), Vector3.RIGHT, 0.055, 0.043, 0.041, 0.016, Color(0.95, 0.95, 0.94), 14)
		Prop.BAG:
			# A paper shopping bag hanging from the fist by its cord handles, its width along the
			# thumb (fore and aft of a hanging arm).
			_box(st, Vector3(0.0, 0.28, 0.03), Vector3(0.26, 0.30, 0.11), Color(0.62, 0.47, 0.30), 0.0)
			_box(st, Vector3(0.06, 0.08, 0.03), Vector3(0.008, 0.10, 0.008), Color(0.15, 0.13, 0.12), 0.0)
			_box(st, Vector3(-0.06, 0.08, 0.03), Vector3(0.008, 0.10, 0.008), Color(0.15, 0.13, 0.12), 0.0)
		Prop.CIGARETTE:
			# Between the first two fingers, out past the thumb side, the filter in the hand and
			# an ember at the far end.
			_box(st, Vector3(0.045, 0.1, 0.005), Vector3(0.06, 0.007, 0.007), Color(0.93, 0.93, 0.9), 0.0)
			_box(st, Vector3(0.008, 0.1, 0.005), Vector3(0.016, 0.0072, 0.0072), Color(0.78, 0.55, 0.3), 0.0)
			_box(st, Vector3(0.077, 0.1, 0.005), Vector3(0.005, 0.0074, 0.0074), Color(1.0, 0.35, 0.08), 2.0)
	st.generate_normals()
	var mesh := st.commit()
	_meshes[kind] = mesh
	return mesh


## The grip frame (see prop_mesh()) in a hand bone's own frame. Measured on the crowd's rest
## pose and the same on all twelve rigs (to a hundredth): the bone's +Y runs along the fingers,
## and the palm faces the thigh with the thumb forward.
static func grip_basis(hand: String) -> Basis:
	var palm := Vector3(-0.75, -0.32, 0.58) if hand == "RightHand" else Vector3(0.6, -0.36, 0.72)
	var thumb := Vector3(0.5, 0.31, 0.81) if hand == "RightHand" else Vector3(-0.67, 0.28, 0.69)
	var y := Vector3.UP
	var z := (palm - y * palm.dot(y)).normalized()
	var x := y.cross(z)
	if x.dot(thumb) < 0.0:
		x = -x
	return Basis(x, y, z)


static func prop_material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/crowd_prop.gdshader")
	return _material


static func _box(st: SurfaceTool, c: Vector3, s: Vector3, colour: Color, glow: float) -> void:
	var h := s * 0.5
	var faces := [
		[Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)], [Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
		[Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0)], [Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
		[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)], [Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0)],
	]
	for f: Array in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var o := c + n * h
		var du := u * h
		var dv := v * h
		var q := [o - du - dv, o + du - dv, o + du + dv, o - du + dv]
		for i in [0, 1, 2, 0, 2, 3]:
			st.set_color(colour)
			st.set_uv(Vector2(glow, 0.0))
			st.add_vertex(q[i])


## A tube (cone frustum) along `axis` through `centre`, from `start` for `height`, capped.
static func _tube(st: SurfaceTool, centre: Vector3, axis: Vector3, start: float, r0: float, r1: float,
		height: float, colour: Color, seg: int) -> void:
	var u := axis.cross(Vector3.FORWARD if absf(axis.z) < 0.9 else Vector3.UP).normalized()
	var v := axis.cross(u)
	var base := centre + axis * start
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var p0 := base + (u * cos(a0) + v * sin(a0)) * r0
		var p1 := base + (u * cos(a1) + v * sin(a1)) * r0
		var q0 := base + axis * height + (u * cos(a0) + v * sin(a0)) * r1
		var q1 := base + axis * height + (u * cos(a1) + v * sin(a1)) * r1
		var top := base + axis * height
		for p in [p0, q0, q1, p0, q1, p1, top, q1, q0]:
			st.set_color(colour)
			st.set_uv(Vector2.ZERO)
			st.add_vertex(p)
