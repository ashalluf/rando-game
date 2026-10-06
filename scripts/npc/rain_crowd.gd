class_name RainCrowd
extends RefCounted
## The crowd in the rain, built on crowd life (Pedestrian's "Life" section, CrowdLife): when
## Weather rains, people near the camera put up umbrellas (RainGear: code-built, opened in the
## hand by CrowdLife's grip frame, held over the head on a raised arm, a few colourways), pull up
## their jacket's hood (the windbreaker and hoodie rigs), hurry (a faster walk, the head down
## for anyone with nothing over it), and shelter: under the bus shelters (the stops' benches,
## CrowdLife's seats with a "bus_stop" record) and in the doorways and under the awnings along
## the building line (the wall a ray finds, as a lean does). Under a downpour the street empties
## out: a share of the walkers walk into a doorway and go in (hidden, their collision off) until
## it eases. When it stops the umbrellas fold - each person at their own moment - and are
## carried furled; hoods go down; the sheltering step back out.
##
## Who does what is rolled from the person's seed (hash(seed, "rain")), never a chunk or block
## rng, and only for the plain crowd that lives (Pedestrian._lives()). Everything is near the
## camera only (Pedestrian.life_range, _life_near): far people walk as before. Dry, nothing
## runs but one float compare a tick. The rain is Weather's `rain_level` (0.7 rain, 1.0 storm),
## pushed into `level` by Weather each frame. `RAIN_CROWD=0` in the environment turns it off.
##
## Pedestrian keeps one of these per person (`rain`) and calls it from four lines: `indoors()`
## at the top of its physics tick, `pace()` for the walking speed, `on_walk_end()` where a walk
## ends, `pose()` after the life pose.

enum Gear { NONE, UMBRELLA, HOOD }

## On or off (the A/B: RAIN_CROWD=0).
static var enabled: bool = OS.get_environment("RAIN_CROWD") != "0"
## Weather's rain level (0 dry, 0.7 rain, 1 storm), set by Weather every frame.
static var level: float = 0.0
## A level forced by tests and stills (-1: Weather's).
static var forced: float = -1.0

## Share of the crowd who carry an umbrella, and of the rest wearing a hooded jacket who pull
## the hood up.
const UMBRELLA_SHARE := 0.56
const HOOD_SHARE := 0.85
## The rigs whose top is a jacket with a hood in its collar or a windbreaker (crowd_config.json:
## m windbreaker, n cardigan, o hoodie).
const HOOD_RIGS := ["crowd_m.glb", "crowd_o.glb"]
## Each person reacts at their own rain level in this range (the light rain at the start of a
## shower has some up and some not), and folds again below it less HYSTERESIS.
const REACT_LEVEL := Vector2(0.06, 0.45)
const HYSTERESIS := 0.04
## How long opening or folding an umbrella takes (seconds), and pulling a hood up or down.
const OPEN_SECONDS := 0.55
const HOOD_SECONDS := 0.7
## Walking pace in the rain: under an umbrella, under a hood, with nothing over the head.
const PACE := Vector3(1.1, 1.22, 1.38)
## Above this level the unprotected look for shelter at the end of a walk (and the protected
## now and then); a stop lasts until the rain drops back under it.
const SHELTER_LEVEL := 0.5
const SHELTER_CHANCE := Vector2(0.75, 0.12)   # without, with an umbrella or hood
## How far they look for a bus shelter (m).
const SHELTER_REACH := 35.0
## Under a downpour this share of the walkers near the camera go indoors (a doorway, then out of
## sight), from LEAVE_LEVEL up to all of it at the storm's level; they come back out once it
## drops under LEAVE_LEVEL - HYSTERESIS (or they are out of the camera's range).
const LEAVE_LEVEL := 0.6
const LEAVE_SHARE := Vector2(0.18, 0.55)
## How often each person thinks about the weather (seconds).
const THINK_SECONDS := 0.5
## The arm that holds an umbrella up: the upper arm and forearm aimed along these (skeleton
## space: +Z forward, +X the rig's left, mirrored for the right arm), so the hand is in front of
## the chest a little toward the middle whatever the walk does.
const UPPER_ARM := Vector3(0.18, -0.86, 0.36)
const FOREARM := Vector3(-0.55, 0.6, 0.58)
## Where the canopy's apex is held: over the Head bone (the base of the skull) by this much, so
## the rim clears the crown, and this far forward of it.
const APEX_OVER_HEAD := 0.62
const APEX_FORWARD := 0.06
## The grip point in the hand's grip frame (CrowdLife.grip_basis(): x thumb, y fingers, z palm).
const GRIP := Vector3(0.0, 0.085, 0.032)

var ped: Pedestrian
var gear: int = Gear.NONE
var react: float = 0.3
var leave_roll: float = 1.0
var kind: int = RainGear.Kind.STICK
var pick: int = 0
var hand: String = "RightHand"
var hood_color: Color = RainGear.HOOD_DEFAULT
## 0 furled .. 1 open, and where it is going.
var open: float = 0.0
var open_to: float = 0.0
var carried: bool = false
var hood: float = 0.0
var hood_to: float = 0.0
var sheltering: bool = false
var going_in: bool = false
var inside: bool = false
var _think: float = 0.0
var _seen: bool = false
var _umbrella: MeshInstance3D
var _step: int = -1
## Where the umbrella was last put (world): read when it is dropped, as the person leaves the tree.
var _last_xf := Transform3D.IDENTITY
var _hood_mi: MeshInstance3D
var _hood_base := Transform3D.IDENTITY
var _hood_pivot := Vector3.ZERO
var _hair_hidden: Array = []
var _pitch0: float = 0.0
var _pitch_set: bool = false
var _layer: int = 0
var _bones := PackedInt32Array()


## The rain state of `p` (a plain walker that lives), or null when it never takes part.
static func make(p: Pedestrian, seed_value: int) -> RainCrowd:
	if not enabled or p == null:
		return null
	var r := RainCrowd.new()
	r.ped = p
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "rain"])
	var rig := String(p._model_path).get_file()
	var u := rng.randf()
	if u < UMBRELLA_SHARE:
		r.gear = Gear.UMBRELLA
	elif rig in HOOD_RIGS and rng.randf() < HOOD_SHARE:
		r.gear = Gear.HOOD
	r.react = rng.randf_range(REACT_LEVEL.x, REACT_LEVEL.y)
	r.leave_roll = rng.randf()
	r.kind = RainGear.Kind.STICK if rng.randf() < 0.45 else RainGear.Kind.COMPACT
	r.pick = rng.randi()
	r._think = rng.randf() * THINK_SECONDS
	# A hat stays on: no hood over a cap.
	if r.gear == Gear.HOOD and p._hat != Pedestrian.Accessory.NONE:
		r.gear = Gear.NONE
	# The phone and the bag are in the right hand: the umbrella goes in the left.
	if p._carry == CrowdLife.Carry.CALL or p._carry == CrowdLife.Carry.BAG or p._carry == CrowdLife.Carry.TEXT:
		r.hand = "LeftHand"
	if p._jogger:
		r.gear = Gear.NONE
	if r.gear == Gear.HOOD:
		r.hood_color = _top_color(p)
	p.tree_exiting.connect(r._on_exit)
	return r


## Knocked down (shot, run over, blown up) with the umbrella in hand: it is let go and tumbles
## away as a light physics body (PhysicsBudget debris), open or furled as it was.
func _on_exit() -> void:
	if not ped._down or _umbrella == null or not _umbrella.visible or not ped.is_inside_tree():
		return
	var tree := ped.get_tree()
	var parent: Node = tree.current_scene if tree.current_scene else tree.root
	if not PhysicsBudget.make_room(1):
		return
	var body := RigidBody3D.new()
	body.name = "DroppedUmbrella"
	body.collision_layer = 0
	body.collision_mask = 1
	body.mass = 0.45
	body.linear_damp = 1.2 if open > 0.5 else 0.2
	body.angular_damp = 0.8
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var r := RainGear.canopy_radius(kind) if open > 0.5 else 0.05
	box.size = Vector3(r * 1.6, 0.35 if open > 0.5 else 0.9, r * 1.6)
	shape.shape = box
	shape.position = Vector3(0.0, RainGear.apex_height(kind) * (0.75 if open > 0.5 else 0.4), 0.0)
	body.add_child(shape)
	var mi := MeshInstance3D.new()
	mi.mesh = _umbrella.mesh
	mi.material_override = _umbrella.material_override
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mi)
	var at := _last_xf
	parent.add_child(body)
	body.global_transform = at
	body.linear_velocity = Vector3(randf_range(-1.5, 1.5), randf_range(1.0, 2.5), randf_range(-1.5, 1.5))
	body.angular_velocity = Vector3(randf_range(-3.0, 3.0), randf_range(-2.0, 2.0), randf_range(-3.0, 3.0))
	PhysicsBudget.register_debris(body, 25.0)


## The colour of the top this person's look wears (the hood is the jacket's), linear.
static func _top_color(p: Pedestrian) -> Color:
	for mi in p._meshes:
		if not is_instance_valid(mi) or Pedestrian.is_hair(mi) or mi.skin == null:
			continue
		var m := mi.material_override as ShaderMaterial
		if m == null:
			m = mi.get_surface_override_material(0) as ShaderMaterial
		if m == null or m.get_shader_parameter("cloth_strength") == null:
			continue
		if float(m.get_shader_parameter("cloth_strength")) < 0.1:
			return RainGear.HOOD_DEFAULT
		var c := Color.from_hsv(float(m.get_shader_parameter("cloth_hue")), float(m.get_shader_parameter("cloth_sat")),
			float(m.get_shader_parameter("cloth_value")))
		return c.srgb_to_linear()
	return RainGear.HOOD_DEFAULT


## The rain level the crowd sees now.
static func rain_now() -> float:
	return forced if forced >= 0.0 else level


## Whether this person is out of sight indoors (Pedestrian skips its whole tick while so).
func indoors(delta: float) -> bool:
	if not inside:
		return false
	_think -= delta
	if _think > 0.0:
		return true
	_think = THINK_SECONDS
	if rain_now() < LEAVE_LEVEL - HYSTERESIS or not ped._life_near or not enabled:
		_come_out()
		return false
	# _update_lod still runs (it says when the camera has gone) and may turn the hit zone back on.
	if ped._hit_shape and not ped._hit_shape.disabled:
		ped._hit_shape.set_deferred("disabled", true)
	return true


## The walking pace's factor in the rain (1 dry, panicking or a jogger).
func pace(panicking: bool) -> float:
	var r := rain_now()
	if r < react or panicking or not ped._life_near:
		return 1.0
	var k := smoothstep(react, react + 0.2, r)
	var p: float = PACE.x if gear == Gear.UMBRELLA else (PACE.y if gear == Gear.HOOD else PACE.z)
	return lerpf(1.0, p, k)


## At the end of a walk near the camera: go in out of a downpour, or find shelter. True when
## the person has somewhere to go (Pedestrian then leaves its own choice alone).
func on_walk_end() -> bool:
	var r := rain_now()
	if r < SHELTER_LEVEL or not ped._life_free():
		return false
	if _wants_in(r):
		return _plan_door(true, false)
	var chance: float = SHELTER_CHANCE.x if gear == Gear.NONE else SHELTER_CHANCE.y
	if ped._life.randf() > chance:
		return false
	return _plan_bus_shelter(false) or _plan_door(false, false)


## Someone who comes into the camera's range while it is already raining (their chunk streamed
## in, the player arrived) is already as the rain has left them: umbrella up, hood up, in a
## doorway or a shelter, or gone in. Also what the stills stage (tools/rain_crowd/stage.gd).
func settle_now() -> void:
	var r := rain_now()
	if not enabled or r < react or not ped._life_near or ped._down:
		return
	if gear == Gear.UMBRELLA:
		open = 1.0
		open_to = 1.0
		carried = true
	elif gear == Gear.HOOD:
		hood = 1.0
		hood_to = 1.0
	if r < SHELTER_LEVEL or sheltering or inside:
		return
	if ped._act != CrowdLife.Act.NONE and gear == Gear.NONE:
		ped._end_act(true)
	if not ped._life_free():
		return
	if _wants_in(r):
		_go_in()
		return
	var chance: float = SHELTER_CHANCE.x if gear == Gear.NONE else SHELTER_CHANCE.y
	if ped._life.randf() < chance:
		var _ok := _plan_bus_shelter(true) or _plan_door(false, true)


func _wants_in(r: float) -> bool:
	if r < LEAVE_LEVEL:
		return false
	var share := lerpf(LEAVE_SHARE.x, LEAVE_SHARE.y, smoothstep(LEAVE_LEVEL, 1.0, r))
	return leave_roll < share


## After the life pose: the umbrella or the hood, the head down, and now and then a thought about
## the weather (end an exposed stop, go in, come out).
func pose(delta: float) -> void:
	var r := rain_now() if enabled else 0.0
	if r <= 0.0 and open <= 0.0 and hood <= 0.0 and not carried and not sheltering and not _pitch_set:
		return
	var near := ped._life_near and not ped._down
	if near and not _seen:
		_seen = true
		if Pedestrian._life_now_ms() - ped._born_ms < 4000:
			settle_now()
	var wet := r >= react
	var dry := r < react - HYSTERESIS
	if gear == Gear.UMBRELLA:
		if wet and near:
			open_to = 1.0
			carried = true
		elif dry or not near:
			open_to = 0.0
		var running := ped._clip == Pedestrian.RUN_CLIP or ped._panic_left > 0.0
		# Folded to run, and under a shelter's roof or in a doorway.
		var covered := (sheltering or (ped._act == CrowdLife.Act.SIT and _bus_seat(ped._seat))) \
			and ped._stage != Pedestrian.Stage.GOING
		if running or covered:
			open_to = 0.0
		open = move_toward(open, open_to, delta / OPEN_SECONDS)
		if not near:
			carried = false
	elif gear == Gear.HOOD:
		hood_to = 1.0 if wet and near else (0.0 if dry or not near else hood_to)
		hood = move_toward(hood, hood_to, delta / HOOD_SECONDS)
	_head_down(near and wet and gear == Gear.NONE)
	_think -= delta
	if _think <= 0.0:
		_think = THINK_SECONDS
		_weather_thought(r, near)
	_show(near)


func _weather_thought(r: float, near: bool) -> void:
	if sheltering:
		# Back out once it eases (or the stop was ended by something else).
		if ped._act == CrowdLife.Act.NONE:
			sheltering = false
			going_in = false
		elif r < SHELTER_LEVEL - HYSTERESIS or not near:
			sheltering = false
			going_in = false
			ped._end_act()
		else:
			ped._act_left = maxf(ped._act_left, 6.0)
			if going_in and ped._stage == Pedestrian.Stage.DOING:
				_go_in()
		return
	if not near or r < SHELTER_LEVEL:
		return
	# Out in it with no cover: whatever they had stopped for ends (a talk, an open bench). The
	# umbrella holders and the hooded carry on.
	if gear == Gear.NONE and ped._act != CrowdLife.Act.NONE and ped._seat.is_empty() == false \
			and not _bus_seat(ped._seat):
		ped._end_act()
	elif gear == Gear.NONE and (ped._act == CrowdLife.Act.TALK or ped._act == CrowdLife.Act.STAND) \
			and ped._life.randf() < 0.5:
		ped._end_act()
	elif ped._act == CrowdLife.Act.SIT and not _bus_seat(ped._seat):
		ped._end_act()


## The head down and the shoulders in, for someone with nothing over their head.
func _head_down(on: bool) -> void:
	if on and not _pitch_set:
		_pitch0 = ped._posture_pitch
		_pitch_set = true
		ped._posture_pitch = minf(_pitch0, -0.38)
	elif not on and _pitch_set:
		_pitch_set = false
		ped._posture_pitch = _pitch0


static func _bus_seat(seat: Dictionary) -> bool:
	if seat.is_empty():
		return false
	var rec: Variant = seat.get("record")
	return rec is Dictionary and String((rec as Dictionary).get("kind", "")) == "bus_stop"


## The nearest free seat under a bus shelter within SHELTER_REACH: sit on it (a seat a life stop
## would take, CrowdLife.add_seat()).
func _plan_bus_shelter(at_once: bool) -> bool:
	var parent := ped.get_parent()
	if parent == null or not parent.has_meta("life_seats"):
		return false
	var from := Vector2(ped.position.x, ped.position.z)
	var best := {}
	var best_d := SHELTER_REACH * SHELTER_REACH
	for seat: Dictionary in parent.get_meta("life_seats"):
		if not _bus_seat(seat):
			continue
		if seat.taken != null and is_instance_valid(seat.taken):
			continue
		if bool((seat.record as Dictionary).get("dead", false)):
			continue
		var d := (seat.p as Vector2).distance_squared_to(from)
		if d < best_d:
			best_d = d
			best = seat
	if best.is_empty():
		return false
	var info := ped._sit_clip_info()
	if info.is_empty():
		return false
	ped._act = CrowdLife.Act.SIT
	ped._seat = best
	best.taken = ped
	var face := Vector2(-sin(float(best.yaw)), -cos(float(best.yaw)))
	ped._act_spot = (best.p as Vector2) + face * float(info.back) * ped._visual.scale.z
	ped._act_face = float(best.yaw)
	ped._seat_drop = float(info.hips) * ped._visual.scale.y - (CrowdLife.SEAT_HEIGHT + CrowdLife.HIP_OVER_SEAT)
	ped._act_left = 60.0
	ped._act_beat = ped._life.randf_range(4.0, 10.0)
	if at_once:
		ped._place_at(ped._act_spot, ped._act_face)
		ped._stage = Pedestrian.Stage.DOING
		ped._life_base = CrowdLife.SIT
		ped._life_clip = CrowdLife.SIT
	else:
		ped._stage = Pedestrian.Stage.GOING
		ped._go_to(ped._act_spot)
	sheltering = true
	return true


## A doorway or an awning along the building line (the wall a ray finds, as a lean does): stand
## in it with the back to the wall, or - `inside` - walk into it and go in.
func _plan_door(go_inside: bool, at_once: bool) -> bool:
	var kind_act := CrowdLife.Act.WINDOW if go_inside else CrowdLife.Act.LEAN
	if not ped._plan_wall(kind_act, at_once):
		return false
	if go_inside:
		# Into the door, not in front of the window: right up to the wall.
		var inward := ped._inward(ped._act_spot)
		ped._act_spot += inward * 0.45
		ped._go_to(ped._act_spot)
	else:
		# Sheltering stands rather than leans on a wet wall, with the phone out or arms folded.
		ped._life_base = CrowdLife.PHONE if ped._carry == CrowdLife.Carry.CALL else \
			(CrowdLife.FOLD if ped._life.randf() < 0.5 else CrowdLife.IDLE)
		if at_once:
			ped._life_clip = ped._life_base
		ped._act_left = 60.0
	sheltering = true
	going_in = go_inside
	return true


## Through the door: out of sight with no collision until the rain eases.
func _go_in() -> void:
	going_in = false
	sheltering = false
	ped._end_act(true)
	inside = true
	ped.visible = false
	_layer = ped.collision_layer
	ped.collision_layer = 0
	if ped._hit_shape:
		ped._hit_shape.set_deferred("disabled", true)
	ped.velocity = Vector3.ZERO
	_show(false)


func _come_out() -> void:
	inside = false
	ped.visible = true
	ped.collision_layer = _layer if _layer != 0 else ped.collision_layer
	if ped._hit_shape:
		ped._hit_shape.set_deferred("disabled", ped._kinematic)
	ped._go_to(ped._random_ring_point(ped._sidewalk))


## Shows, hides and places what they wear and hold.
func _show(near: bool) -> void:
	# The umbrella: open over the head, furled in the hand, or nothing.
	var want_umbrella := near and gear == Gear.UMBRELLA and (open > 0.0 or carried) and not ped._down
	if want_umbrella:
		if _umbrella == null:
			_umbrella = MeshInstance3D.new()
			_umbrella.name = "Umbrella"
			_umbrella.top_level = true
			_umbrella.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_umbrella.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			_umbrella.material_override = RainGear.canopy_material(pick)
			_umbrella.visibility_range_end = ped.life_range
			ped.add_child(_umbrella)
		var step := roundi(open * float(RainGear.OPEN_STEPS - 1))
		if step != _step:
			_step = step
			_umbrella.mesh = RainGear.umbrella(kind, step)
		_umbrella.visible = true
		_place_umbrella()
	elif _umbrella != null:
		_umbrella.visible = false
	# The hood.
	var want_hood := near and gear == Gear.HOOD and hood > 0.0 and not ped._down
	if want_hood and _hood_mi == null:
		_make_hood()
	if _hood_mi != null:
		_hood_mi.visible = want_hood
		if want_hood:
			# Pulled up from behind the neck: turned back about the nape until it is up.
			var t := smoothstep(0.0, 1.0, hood)
			var turn := Transform3D(Basis(Vector3.RIGHT, -1.9 * (1.0 - t)), Vector3.ZERO)
			var piv := Transform3D(Basis.IDENTITY, _hood_pivot)
			_hood_mi.transform = _hood_base * piv * turn * piv.affine_inverse()
		_hide_hair(want_hood and hood > 0.6)


## The umbrella in the hand. Open, the holding arm is raised (upper arm and forearm aimed in
## skeleton space, as the coffee's forearm is) and the shaft leans from the hand to over the head;
## furled, it hangs from the hand like a cane, tip down and a little forward.
func _place_umbrella() -> void:
	var sk: Skeleton3D = ped._head_skel
	if sk == null:
		return
	if _bones.is_empty():
		var pre := "Left" if hand == "LeftHand" else "Right"
		for b in [pre + "Arm", pre + "ForeArm", pre + "Hand", sk.find_bone("Head")]:
			_bones.append(b if b is int else sk.find_bone(b))
		if -1 in _bones:
			_bones = PackedInt32Array([-1])
	if _bones.size() < 4:
		return
	var side := 1.0 if hand == "LeftHand" else -1.0
	var raise := smoothstep(0.0, 0.35, open)
	if raise > 0.001:
		_aim(_bones[0], _bones[1], Vector3(UPPER_ARM.x * side, UPPER_ARM.y, UPPER_ARM.z), raise)
		_aim(_bones[1], _bones[2], Vector3(FOREARM.x * side, FOREARM.y, FOREARM.z), raise)
	var to_world := sk.global_transform
	var hx := to_world * sk.get_bone_global_pose(_bones[2])
	var grip := hx * (CrowdLife.grip_basis(hand) * GRIP * ped._skel_unit)
	var head := to_world * sk.get_bone_global_pose(_bones[3]).origin
	var yaw := ped._visual.global_rotation.y
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var s := ped._visual.scale.y
	# Open: the shaft from the grip to over the head (the canopy centred on the walker).
	var apex := head + Vector3.UP * (APEX_OVER_HEAD * s) + fwd * APEX_FORWARD
	var up_dir := (apex - grip).normalized()
	up_dir = up_dir.lerp(Vector3.UP, 0.12).normalized()
	# Furled: down and forward from the hand.
	var cane := (-Vector3.UP + fwd * 0.25).normalized()
	var dir := cane.lerp(up_dir, raise).normalized()
	var yv := dir
	var xv := fwd.cross(yv)
	if xv.length_squared() < 1e-6:
		xv = Vector3.RIGHT
	xv = xv.normalized()
	var zv := xv.cross(yv).normalized()
	# A furled one hangs from the crook / top of the grip, so it sits a little lower in the hand.
	var at := grip if raise > 0.5 else grip - yv * 0.02
	_last_xf = Transform3D(Basis(xv, yv, zv), at)
	_umbrella.global_transform = _last_xf


## Turns `bone` in skeleton space so its child lies along `dir`, by `w`.
func _aim(bone: int, child: int, dir: Vector3, w: float) -> void:
	var sk: Skeleton3D = ped._head_skel
	var b := sk.get_bone_global_pose(bone)
	var now := (sk.get_bone_global_pose(child).origin - b.origin).normalized()
	if now.length_squared() < 1e-8:
		return
	var turn := Quaternion(now, dir.normalized())
	ped._set_global_rot(bone, Basis(Quaternion.IDENTITY.slerp(turn, w)) * b.basis)


func _make_hood() -> void:
	var sk: Skeleton3D = ped._head_skel
	if sk == null:
		return
	var hb := sk.find_bone("Head")
	if hb < 0:
		return
	var unit := 1.0 / maxf(ped._skel_unit, 1e-6)
	var rest := sk.get_bone_global_rest(hb)
	var att := BoneAttachment3D.new()
	att.name = "HoodMount"
	sk.add_child(att)
	att.bone_name = "Head"
	_hood_mi = MeshInstance3D.new()
	_hood_mi.name = "Hood"
	_hood_mi.mesh = RainGear.hood(ped._model_path)
	_hood_mi.material_override = RainGear.hood_material(hood_color)
	_hood_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hood_mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_hood_mi.visibility_range_end = ped.life_range
	_hood_base = rest.affine_inverse() * Transform3D(Basis.IDENTITY.scaled(Vector3.ONE / maxf(unit, 1e-6)), rest.origin)
	var h := CrowdHat.head_for(ped._model_path)
	_hood_pivot = Vector3(0.0, h.c.y - 0.06, h.c.z - 0.09)
	att.add_child(_hood_mi)


## The hair cards go under the hood (and come back out with it down); a hat's own hiding is left
## as it is (Pedestrian._update_lod reads the same "under_hat" meta).
func _hide_hair(on: bool) -> void:
	if on and _hair_hidden.is_empty():
		for mi in ped._meshes:
			if is_instance_valid(mi) and Pedestrian.is_hair(mi) and not mi.has_meta("under_hat"):
				mi.set_meta("under_hat", true)
				mi.visible = false
				_hair_hidden.append(mi)
	elif not on and not _hair_hidden.is_empty():
		for mi in _hair_hidden:
			if is_instance_valid(mi):
				mi.remove_meta("under_hat")
				mi.visible = ped._draw_tier < 2
		_hair_hidden.clear()
