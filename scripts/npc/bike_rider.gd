class_name BikeRider
extends Pedestrian
## Somebody riding a bike or a shared e-scooter down a bike lane (Cyclists drives them; this is
## the body). A Pedestrian, so a round, a blast, a bumper or a boosting player knocks them off
## like anyone (Pedestrian.knock: the ragdoll, the crime, the blood) - and the bike goes too, as a
## PhysicsProp debris body of the same mesh (EncampmentItem.throw).
##
## The body is a crowd rig posed on the vehicle every frame by its own solve, not a clip: the
## hips on the saddle (or standing on the scooter's deck), the chest leaned toward the bars as
## far as the kind of bike asks (a road bike's 50 degrees, a cruiser's upright 9), and each limb
## a two-bone solve in skeleton space - the legs to the pedals going round, the arms to the
## grips, the knees and elbows bent in the plane a pole gives them (knees forward, elbows out
## and down), the feet along the pedal, the head brought back up to look down the road. The
## base it is worked from is the rig's own idle at a fixed moment (RoughSleeper's method), so it
## fits any of the crowd's twelve rigs. The bike is sized to the rider (a frame size: the saddle
## at the height that leaves the knee 25-30 degrees bent at the bottom of the stroke).
##
## Vehicles: MicroMesh's parts - the frame, the wheels spinning at the road speed, the crank and
## pedals at the cadence its gear gives (coasting, the cranks level, when it slows). The lamps
## are lit (MicroMesh.rider_material). A helmet on some (BikeHelmet, built round the rig's own
## head like the fire helmet), never over a hat they already wear.

## Seconds of panic after a shot or a blast nearby (they ride away flat out).
@export var rider_panic: Vector2 = Vector2(5.0, 9.0)
## Share of riders in a helmet: road bikes, the others.
@export var helmet_share: Vector2 = Vector2(0.85, 0.3)

var kind: int = MicroMesh.Kind.ROAD
var paint := Color(0.5, 0.5, 0.5)
## The crank's angle (radians, 0 = the drive-side arm straight up); the pedals follow it.
var crank_angle: float = 0.0
## Road speed (m/s), set by Cyclists each step; the wheels and the cadence follow it.
var ride_speed: float = 0.0
## How far the rider leans the bike into a turn (radians, + to the right).
var bank: float = 0.0

var _bike: Node3D
var _front: MeshInstance3D
var _rear: MeshInstance3D
var _crank: MeshInstance3D
var _pedals: Array[MeshInstance3D] = []
var _wheel_angle: float = 0.0
var _coast_t: float = 0.0
var _bike_scale: float = 1.0
var _mat: ShaderMaterial
var _sk: Skeleton3D
var _order := PackedInt32Array()
var _parent_of := PackedInt32Array()
## Each bone and everything under it, in solve order (a turn re-runs only that subtree).
var _subtree: Array[PackedInt32Array] = []
var _base_rot: Array[Quaternion] = []
var _base_pos: Array[Vector3] = []
var _rot: Array[Quaternion] = []
var _glob: Array[Transform3D] = []
var _hips_pos := Vector3.ZERO
var _to_skel := Transform3D.IDENTITY
var _b := {}
var _leg_len: float = 0.9
var _foot_len: float = 0.15
var _posed: bool = false
var _pose_tick: int = 0
var _rig_override: int = -1
## Extra lean (radians) found for this rider so the hands reach the bars (_fit_reach()), and how
## far the wrists fell short in the last pose (m).
var _lean_extra: float = 0.0
var _reach_miss: float = 0.0
## Held still (stills): no rolling, the pose only.
var frozen: bool = false


## Picks the vehicle, the seed (the rig and the look) and the frame paint. `rig` >= 0 forces one
## crowd rig (stills).
func setup_rider(vehicle: int, seed_value: int, frame_paint: Color, rig: int = -1) -> void:
	kind = vehicle
	paint = frame_paint
	_rig_override = rig
	if rig >= 0:
		seed_value = seed_for_rig(seed_value, rig)
	setup(Rect2(-1.0, -1.0, 2.0, 2.0), 1.0, seed_value)
	crank_angle = float(absi(seed_value) % 628) * 0.01


## A seed near `seed_value` whose look picks crowd rig `rig` (Pedestrian._add_model's first roll).
static func seed_for_rig(seed_value: int, rig: int) -> int:
	var n := 0
	for path: String in Pedestrian.MODELS:
		if ResourceLoader.exists(path):
			n += 1
	if n == 0:
		return seed_value
	for k in 4000:
		var s := seed_value + k
		var r := RandomNumberGenerator.new()
		r.seed = hash([s, "style"])
		if r.randi() % n == rig % n:
			return s
	return seed_value


func _ready() -> void:
	super._ready()
	add_to_group("bike_rider")
	# Placed, not simulated: the manager sets the position every step.
	collision_mask = 0
	_build_bike()
	_prepare_pose()
	_dress()


func _lives() -> bool:
	return false


func _head_look_ok() -> bool:
	return false


# --- The vehicle -------------------------------------------------------------------------------

func _build_bike() -> void:
	_mat = MicroMesh.rider_material(paint)
	_mat.set_shader_parameter("wear", float(absi(hash([_life_seed, "wear"])) % 100) / 200.0)
	_bike = Node3D.new()
	_bike.name = "Bike"
	add_child(_bike)
	var g: Dictionary = MicroMesh.GEO[kind]
	var frame := _bike_part("frame")
	frame.name = "Frame"
	_front = _bike_part("front")
	_front.position = g.front
	_rear = _bike_part("rear")
	_rear.position = g.rear
	# The lamp's throw on the road ahead and the tail lamp's glow behind, after dark (the pool
	# shader reads lamp_factor itself: nothing by day).
	for k in 2:
		var pool := MeshInstance3D.new()
		pool.mesh = PropFactory.light_pool(Color(1.0, 0.95, 0.86) if k == 0 else Color(1.0, 0.12, 0.06), 0.55 if k == 0 else 0.35)
		pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pool.visibility_range_end = 90.0
		var size := Vector3(1.5, 1.0, 3.4) if k == 0 else Vector3(0.9, 1.0, 0.9)
		pool.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(size), Vector3(0.0, 0.03, -2.7 if k == 0 else 0.9))
		pool.name = "LampPool" if k == 0 else "TailPool"
		add_child(pool)
	if g.has("crank"):
		_crank = _bike_part("crank")
		_crank.position = Vector3(0.0, float(g.bb), 0.0)
		for s in 2:
			var p := _bike_part("pedal")
			if s == 1:
				p.scale = Vector3(-1.0, 1.0, 1.0)
			_pedals.append(p)


func _bike_part(which: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = MicroMesh.part(kind, which)
	mi.material_override = _mat
	mi.visibility_range_end = 160.0
	_bike.add_child(mi)
	return mi


func _scooter() -> bool:
	return kind >= MicroMesh.Kind.SCOOTER_A


## Turns the wheels and the cranks for `delta` seconds at ride_speed.
func _roll(delta: float) -> void:
	var g: Dictionary = MicroMesh.GEO[kind]
	var r: float = float(g.r) * _bike_scale
	_wheel_angle -= ride_speed / maxf(r, 0.05) * delta
	_front.rotation.x = _wheel_angle
	_rear.rotation.x = _wheel_angle
	if _crank == null:
		return
	# Pedalling at the gear's cadence while holding speed or speeding up; coasting with the
	# cranks brought level when slowing or stopped.
	var coasting := _coast_t > 0.0 or ride_speed < 0.4
	if not coasting:
		var circ := TAU * r * float(g.ratio)
		crank_angle -= ride_speed / circ * TAU * delta
	else:
		var level := roundf((crank_angle - PI * 0.5) / PI) * PI + PI * 0.5
		crank_angle = move_toward(crank_angle, level, delta * 1.5)
	_coast_t = maxf(_coast_t - delta, 0.0)
	_place_cranks()


func _place_cranks() -> void:
	if _crank == null:
		return
	_crank.rotation.x = crank_angle
	for s in 2:
		_pedals[s].position = pedal_at(s)


## Where pedal `side` (0 the drive side, +x; 1 the left) is, in the bike's frame (unscaled).
func pedal_at(side: int) -> Vector3:
	var g: Dictionary = MicroMesh.GEO[kind]
	var a := crank_angle + (0.0 if side == 0 else PI)
	var sx := 1.0 if side == 0 else -1.0
	return Vector3(sx * float(g.q), float(g.bb) + cos(a) * float(g.crank), sin(a) * float(g.crank))


## Asks the rider to coast for a moment (Cyclists, when it brakes).
func coast(seconds: float) -> void:
	_coast_t = maxf(_coast_t, seconds)


# --- Dressing ----------------------------------------------------------------------------------

func _dress() -> void:
	if _visual == null:
		return
	# Nobody rides with a stoop held from their walk.
	_visual.rotation.x = 0.0
	# The backpack hangs off the walking spine (Pedestrian._add_accessory) and floats off a
	# leaning one: riders leave it at home.
	for att in _visual.find_children("*", "BoneAttachment3D", true, false):
		if (att as BoneAttachment3D).bone_name == "Spine01":
			att.queue_free()
	var inst := _visual.get_child(0) as Node3D if _visual.get_child_count() > 0 else null
	if inst == null or _model_path == "" or _hat != Accessory.NONE:
		return
	# A head already covered (Pedestrian.NO_HAT_MODELS: a headscarf) takes no helmet either.
	if _model_path in Pedestrian.NO_HAT_MODELS:
		return
	var share := helmet_share.x if kind == MicroMesh.Kind.ROAD else helmet_share.y
	if kind >= MicroMesh.Kind.SCOOTER_A:
		share *= 0.35
	var roll := float(absi(hash([_life_seed, "helmet"])) % 1000) / 1000.0
	if roll < share:
		BikeHelmet.dress(inst, _model_path, absi(hash([_life_seed, "helmet_c"])), _accessory_reach(), kind == MicroMesh.Kind.ROAD)


# --- The pose ----------------------------------------------------------------------------------

## The rig's idle at a fixed moment is the base (as EmergencyCrew's poses), and the bones the
## solve works on are found.
func _prepare_pose() -> void:
	if _visual == null:
		return
	_sk = _visual.find_child("Skeleton3D", true, false) as Skeleton3D
	if _sk == null or _anim == null or not _has_idle:
		_sk = null
		return
	_anim.play(IDLE_CLIP, 0.0)
	_anim.seek(0.6, true)
	_anim.pause()
	var n := _sk.get_bone_count()
	_base_rot.resize(n)
	_base_pos.resize(n)
	_glob.resize(n)
	_parent_of.resize(n)
	for b in n:
		_base_rot[b] = _sk.get_bone_pose_rotation(b)
		_base_pos[b] = _sk.get_bone_pose_position(b)
		_parent_of[b] = _sk.get_bone_parent(b)
	_order = RoughSleeper._bone_order(_sk)
	_subtree.resize(n)
	for b in n:
		var sub := PackedInt32Array()
		for o in _order:
			var x := o
			while x >= 0 and x != b:
				x = _parent_of[x]
			if x == b:
				sub.append(o)
		_subtree[b] = sub
	for bone: String in ["Hips", "Spine02", "Spine01", "Spine", "neck", "Head", "headfront",
			"LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase", "RightUpLeg", "RightLeg", "RightFoot", "RightToeBase",
			"LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand", "RightShoulder", "RightArm", "RightForeArm", "RightHand"]:
		_b[bone] = _sk.find_bone(bone)
	for bone: String in _b:
		if int(_b[bone]) < 0 and bone != "headfront":
			_sk = null
			return
	# The chain from the rider's frame (metres, -z forward) into skeleton space.
	var m := Transform3D.IDENTITY
	var node: Node = _sk
	while node != null and node != self:
		if node is Node3D:
			m = (node as Node3D).transform * m
		node = node.get_parent()
	_to_skel = m.affine_inverse()
	_rot = _base_rot.duplicate()
	_hips_pos = _base_pos[_b.Hips]
	_fk()
	var unit := 1.0 / _to_skel.basis.get_scale().y
	_leg_len = (_glob[_b.LeftUpLeg].origin.distance_to(_glob[_b.LeftLeg].origin) + _glob[_b.LeftLeg].origin.distance_to(_glob[_b.LeftFoot].origin)) * unit
	_foot_len = _glob[_b.LeftFoot].origin.distance_to(_glob[_b.LeftToeBase].origin) * unit
	_fit_bike()
	_fit_reach()


## Leans this rider further over the bars until the hands reach them (a short-armed rider on a
## road bike folds lower), at most half a radian more than the bike asks.
func _fit_reach() -> void:
	for i in 4:
		_pose()
		if _reach_miss < 0.02 or _lean_extra >= 0.5:
			break
		_lean_extra = minf(_lean_extra + clampf(_reach_miss / 0.45, 0.04, 0.3), 0.5)


## The bike's size for this rider: the saddle at the height that leaves the knee bent 25-30
## degrees at the bottom of the stroke (the leg at 93 % of its length).
func _fit_bike() -> void:
	var g: Dictionary = MicroMesh.GEO[kind]
	if _scooter():
		_bike_scale = 1.0
		return
	var s := 1.0
	for i in 6:
		var hip := _hip_target(s)
		var bottom := Vector3(float(g.q), float(g.bb) - float(g.crank), 0.0) * s
		var ankle := _ankle_for(bottom, Vector3(0.0, -0.12, -1.0).normalized())
		var d := hip.distance_to(ankle)
		s *= clampf(_leg_len * 0.93 / maxf(d, 0.1), 0.9, 1.1)
	_bike_scale = clampf(s, 0.86, 1.14)
	_bike.scale = Vector3.ONE * _bike_scale


func _hip_target(s: float) -> Vector3:
	var g: Dictionary = MicroMesh.GEO[kind]
	if _scooter():
		return Vector3(0.0, float(g.deck) + _leg_len * 0.955 + 0.075, 0.03)
	var saddle: Vector3 = g.saddle
	# The hip joints sit over the saddle's middle, a hand above its top.
	return saddle * s + Vector3(0.0, 0.085, -0.035)


## The ankle over a pedal (or a spot on the deck): the ball of the foot on it, the sole's
## thickness under the ankle, the foot pointing along `toe`.
func _ankle_for(ball: Vector3, toe: Vector3) -> Vector3:
	return ball + Vector3(0.0, 0.075, 0.0) - toe * (_foot_len * 0.82)


## Forward kinematics over the working arrays (skeleton space).
func _fk() -> void:
	for b in _order:
		var p := _parent_of[b]
		var local := Transform3D(Basis(_rot[b]), _hips_pos if b == _b.Hips else _base_pos[b])
		_glob[b] = _glob[p] * local if p >= 0 else local


func _set_glob_basis(b: int, basis: Basis) -> void:
	var p := _parent_of[b]
	var pb := _glob[p].basis if p >= 0 else Basis.IDENTITY
	_rot[b] = (pb.orthonormalized().inverse() * basis.orthonormalized()).get_rotation_quaternion()


## Rotates bone `b` (and with it everything under it) by `q` in skeleton space.
func _turn(b: int, q: Quaternion) -> void:
	_set_glob_basis(b, Basis(q) * _glob[b].basis)
	for o in _subtree[b]:
		var p := _parent_of[o]
		var local := Transform3D(Basis(_rot[o]), _hips_pos if o == _b.Hips else _base_pos[o])
		_glob[o] = _glob[p] * local if p >= 0 else local


## Two-bone solve: bones a -> b -> c, the end of c's parent... c's origin to `target`, the middle
## joint bent toward `pole` (skeleton space).
func _ik(a: int, b: int, c: int, target: Vector3, pole: Vector3) -> void:
	var pa := _glob[a].origin
	var pb := _glob[b].origin
	var pc := _glob[c].origin
	var l1 := pa.distance_to(pb)
	var l2 := pb.distance_to(pc)
	var to := target - pa
	var d := clampf(to.length(), absf(l1 - l2) + 0.01, (l1 + l2) * 0.999)
	var dir := to.normalized()
	var pl := pole - dir * dir.dot(pole)
	if pl.length_squared() < 1e-8:
		pl = Vector3.UP - dir * dir.dot(Vector3.UP)
	pl = pl.normalized()
	var cos_a := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var pb_new := pa + (dir * cos_a + pl * sqrt(1.0 - cos_a * cos_a)) * l1
	var end_new := pa + dir * d
	# The upper bone: its direction to the new joint, its hinge to the new bend plane's normal.
	var d_old := (pb - pa).normalized()
	var d_new := (pb_new - pa).normalized()
	var n_new := d_new.cross((end_new - pb_new).normalized())
	if n_new.length_squared() < 1e-8:
		n_new = d_new.cross(pl)
	n_new = n_new.normalized()
	var n_old := d_old.cross((pc - pb).normalized())
	if n_old.length_squared() < 0.02 or n_old.dot(n_new) < 0.0:
		n_old = n_new - d_old * d_old.dot(n_new)
	n_old = n_old.normalized()
	var f_old := Basis(d_old, n_old, d_old.cross(n_old).normalized())
	var f_new := Basis(d_new, n_new, d_new.cross(n_new).normalized())
	_turn(a, (f_new * f_old.transposed()).get_rotation_quaternion())
	# The lower bone: swung in that plane onto the target.
	var cur := (_glob[c].origin - _glob[b].origin).normalized()
	var want := (end_new - _glob[b].origin).normalized()
	if cur.dot(want) < 0.99999:
		_turn(b, Quaternion(cur, want))


## Points bone `b`'s child direction (to `child`) along `want`, the least turn.
func _aim(b: int, child: int, want: Vector3, weight: float = 1.0) -> void:
	var cur := (_glob[child].origin - _glob[b].origin).normalized()
	var w := want.normalized()
	if cur.dot(w) > 0.99999:
		return
	_turn(b, Quaternion.IDENTITY.slerp(Quaternion(cur, w), weight))


## The whole pose for this frame, written over the rig.
func _pose() -> void:
	if _sk == null:
		return
	var g: Dictionary = MicroMesh.GEO[kind]
	var t := _to_skel
	var unit := t.basis.get_scale().y
	var right := (t.basis * Vector3.RIGHT).normalized()
	var up := (t.basis * Vector3.UP).normalized()
	var fwd := (t.basis * Vector3.FORWARD).normalized()
	_rot = _base_rot.duplicate()
	_hips_pos = _base_pos[_b.Hips]
	_fk()
	# The pelvis and the chest lean forward toward the bars (about the rider's right axis).
	var lean := deg_to_rad(float(g.lean)) + _lean_extra
	var axis := up.cross(fwd).normalized()
	_turn(_b.Hips, Quaternion(axis, lean * 0.42))
	for k in 3:
		var bone: int = [_b.Spine02, _b.Spine01, _b.Spine][k]
		_turn(bone, Quaternion(axis, lean * [0.2, 0.2, 0.18][k]))
	# The hips' joints on the saddle.
	var mid := (_glob[_b.LeftUpLeg].origin + _glob[_b.RightUpLeg].origin) * 0.5
	var want := t * _hip_target(_bike_scale)
	_hips_pos += (want - mid)
	_fk()
	# Legs: to the pedals (or the deck), knees forward and a touch out.
	for side in 2:
		var sx := -1.0 if side == 0 else 1.0
		var ball: Vector3
		var toe: Vector3
		if _scooter():
			var deck := float(g.deck) + 0.01
			ball = Vector3(0.03 * sx, deck, -0.12) if side == 0 else Vector3(0.04, deck, 0.22)
			toe = Vector3(0.12 * sx, -0.08, -1.0).normalized() if side == 0 else Vector3(0.55, -0.1, -0.83).normalized()
		else:
			# The left leg (the rig's LeftUpLeg is the rider's left: -x) on pedal 1.
			var p := pedal_at(1 if side == 0 else 0)
			p.x = (float(g.q) + 0.05) * sx
			ball = p * _bike_scale
			# Ankling: the toe drops through the back of the stroke.
			var a := crank_angle + (PI if side == 0 else 0.0)
			toe = Vector3(0.0, -0.1 - 0.22 * maxf(sin(a), 0.0), -1.0).normalized()
		var ankle := _ankle_for(ball, toe)
		var up_b: int = _b.LeftUpLeg if side == 0 else _b.RightUpLeg
		var leg_b: int = _b.LeftLeg if side == 0 else _b.RightLeg
		var foot_b: int = _b.LeftFoot if side == 0 else _b.RightFoot
		var toe_b: int = _b.LeftToeBase if side == 0 else _b.RightToeBase
		var knee_pole := fwd + up * 0.15 + right * (sx * 0.12)
		_ik(up_b, leg_b, foot_b, t * ankle, knee_pole)
		_aim(foot_b, toe_b, t.basis * toe)
	# Arms: the shoulders reach a little, then each arm to its grip, elbows out and down.
	var grip: Vector3 = g.grip
	_reach_miss = 0.0
	for side in 2:
		var sx := -1.0 if side == 0 else 1.0
		var gp := Vector3(grip.x * sx, grip.y, grip.z) * (_bike_scale if not _scooter() else 1.0)
		var sh_b: int = _b.LeftShoulder if side == 0 else _b.RightShoulder
		var arm_b: int = _b.LeftArm if side == 0 else _b.RightArm
		var fore_b: int = _b.LeftForeArm if side == 0 else _b.RightForeArm
		var hand_b: int = _b.LeftHand if side == 0 else _b.RightHand
		var reach := (t * gp - _glob[arm_b].origin).normalized()
		_aim(sh_b, arm_b, (_glob[arm_b].origin - _glob[sh_b].origin).normalized().slerp(reach, 0.25), 1.0)
		# The wrist sits a palm short of the grip, the hand wrapped over it.
		var hand_dir := (fwd * 0.7 - up * 0.45 + right * (sx * 0.25)).normalized()
		if kind == MicroMesh.Kind.ROAD:
			hand_dir = (fwd * 0.85 - up * 0.2 + right * (sx * 0.1)).normalized()
		var wrist := t * gp - hand_dir * (0.075 * unit) + up * (0.02 * unit)
		var elbow_pole := -up * 0.7 + right * (sx * 0.65) - fwd * 0.25
		_ik(arm_b, fore_b, hand_b, wrist, elbow_pole)
		_reach_miss = maxf(_reach_miss, _glob[hand_b].origin.distance_to(wrist) / unit)
		var fingers := _glob[hand_b].origin + _glob[hand_b].basis.y.normalized() * 10.0
		var cur := (fingers - _glob[hand_b].origin).normalized()
		if cur.dot(hand_dir) < 0.99999:
			_turn(hand_b, Quaternion(cur, hand_dir))
	# The head back up: looking down the road a few metres ahead.
	if int(_b.headfront) >= 0:
		var look := (fwd * cos(0.2) - up * sin(0.2)).normalized()
		_aim(_b.neck, _b.headfront, look, 0.5)
		_aim(_b.Head, _b.headfront, look, 1.0)
	# Write it.
	for b in _rot.size():
		_sk.set_bone_pose_rotation(b, _rot[b])
	_sk.set_bone_pose_position(_b.Hips, _hips_pos)
	_posed = true


func _physics_process(delta: float) -> void:
	if _down:
		return
	_lod_timer += delta
	if _lod_timer >= 0.5:
		_lod_timer = 0.0
		_update_lod()
	_panic_left = maxf(_panic_left - delta, 0.0)
	if frozen:
		_place_cranks()
	else:
		_roll(delta)
	# The pose every step near the player, less often further out (the cycle is what reads).
	_pose_tick += 1
	var stride := 1 if _lod_stride <= 1 else (2 if _lod_stride == 2 else 4)
	if not _posed or (_pose_tick % stride == 0 and _in_view()):
		_pose()


## Whether the camera can see this rider (checked every few ticks: a rider behind the camera
## keeps its last pose).
var _view_t: int = 0
var _view_ok: bool = true


func _in_view() -> bool:
	_view_t -= 1
	if _view_t <= 0:
		_view_t = 6
		var cam := get_viewport().get_camera_3d()
		var p := global_position + Vector3.UP
		_view_ok = cam == null or p.distance_to(cam.global_position) < 4.0 or (not cam.is_position_behind(p) and cam.is_position_in_frustum(p))
	return _view_ok


## Poses the rig at once (stills, tests: no physics step needed).
func pose_now() -> void:
	_place_cranks()
	_pose()


## A shot, a blast: ride away flat out for a few seconds (Cyclists reads `panicking()`).
func _scare(_at: Vector3) -> void:
	_panic_left = _rng.randf_range(rider_panic.x, rider_panic.y)


func panicking() -> bool:
	return _panic_left > 0.0


## Off the bike: the rider is a ragdoll (Pedestrian.knock) and the bike a thrown debris body.
func knock(impulse: Vector3, gibs: int = 0) -> void:
	if _down:
		return
	var parent := get_parent()
	if parent != null and _bike != null:
		var g: Dictionary = MicroMesh.GEO[kind]
		var length := absf((g.front as Vector3).z - (g.rear as Vector3).z) + float(g.r) * 2.0
		var box := Vector3(0.5 if _scooter() else 0.45, 0.9 if not _scooter() else 0.6, length) * _bike_scale
		var xf := transform * Transform3D(Basis().scaled(Vector3.ONE * _bike_scale), Vector3.ZERO)
		var mass := 14.0 if _scooter() else (24.0 if kind == MicroMesh.Kind.CARGO or kind == MicroMesh.Kind.SHARE else 10.0)
		EncampmentItem.throw(parent, MicroMesh.whole(kind), box, box.y * 0.5, mass, Color.WHITE,
			Color(paint.r, paint.g, paint.b, 0.3), xf, impulse * 0.8 + Vector3.UP * 1.5)
		_bike.visible = false
	super.knock(impulse, gibs)
