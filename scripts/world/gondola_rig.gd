class_name GondolaRig
extends Node3D
## One window-washing cradle at a TowerGondolas site (the `site` dictionary, in this node's
## parent's frame; this node itself stays at identity under it, so origin shifts and chunk
## unloads carry it). Nothing is built until the camera comes within TowerGondolas.BUILD_RANGE
## (the cradle, its four wire ropes, the davits for a davit site, the water on the glass) and
## WORKER_RANGE (the two workers, their lanyards and squeegees); it is all freed again past them.
##
## Where the cradle hangs comes from TowerGondolas.pose_at() on the shared clock; on top of that
## it swings: a long pendulum out from the glass and along it (period from the rope length), a
## quicker twist and a roll between the two hoists, the rollers stopping it at the glass. A round
## or a blast (take_hit() on its AnimatableBody3D, props layer) kicks it, and the workers drop to
## a crouch with both hands on the front rail until it settles.

## The site (TowerGondolas._site()).
var site: Dictionary = {}
## Built (cradle live), and the workers' state.
var built: bool = false
var has_workers: bool = false
## Rounds and blasts taken (the checks read it).
var hits: int = 0
## Build regardless of the camera (tests, stills).
var force: bool = false

var _body: AnimatableBody3D
var _ropes: Array[MeshInstance3D] = []
var _lanyards: Array[MeshInstance3D] = []
var _davits: Array[Node3D] = []
var _streak: MeshInstance3D
var _streak_mat: ShaderMaterial
var _workers: Array = []
var _lane: float = INF
# The swing: out from the glass (m) and along it, the twist and the roll (rad), and their rates.
var _xo := 0.0
var _vo := 0.0
var _xa := 0.0
var _va := 0.0
var _yaw := 0.0
var _vyaw := 0.0
var _roll := 0.0
var _vroll := 0.0
var _brace := 0.0
var _brace_w := 0.0
var _scream_cd := 0.0
var _tick := 0
var _rng := RandomNumberGenerator.new()
var _pose: Dictionary = {}


## The cradle's collision: forwards hits to the rig.
class GondolaBody:
	extends AnimatableBody3D
	var rig: GondolaRig

	func take_hit(shape: int = -1, damage: float = 0.0, dir: Vector3 = Vector3.ZERO, _at: Vector3 = Vector3.INF, _kind: int = 0) -> void:
		if rig != null and is_instance_valid(rig):
			rig.hit(shape, damage, dir)


func _ready() -> void:
	add_to_group("tower_gondola")
	_rng.seed = int(site.get("seed", 0))
	_tick = _rng.randi() % 20


func _exit_tree() -> void:
	_drop()


func _physics_process(delta: float) -> void:
	if site.is_empty():
		return
	_tick += 1
	if _tick % 15 == 0 or force:
		_manage()
	if built:
		_update(delta)


## Builds or frees by the camera's distance (a few times a second).
func _manage() -> void:
	var d := 0.0
	if not force:
		var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
		if cam == null:
			return
		d = cam.global_position.distance_to(global_transform * (site.m as Vector3))
	if not built and d < TowerGondolas.BUILD_RANGE and (force or TowerGondolas.live < TowerGondolas.MAX_LIVE):
		_build()
	elif built and d > TowerGondolas.BUILD_RANGE + 60.0:
		_drop()
		return
	if built and not has_workers and d < TowerGondolas.WORKER_RANGE and (force or TowerGondolas.workers_live < TowerGondolas.MAX_WORKERS):
		_add_workers()
	elif has_workers and d > TowerGondolas.WORKER_RANGE + 30.0:
		_drop_workers()


func _frame(lane: float, y: float) -> Transform3D:
	var n: Vector3 = site.n
	var t: Vector3 = site.t
	var m: Vector3 = site.m
	var o := m + t * lane + n * TowerGondolas.GAP
	o.y = y
	return Transform3D(Basis(t, Vector3.UP, n), o)


func _build() -> void:
	built = true
	TowerGondolas.live += 1
	_pose = TowerGondolas.pose_at(site, TowerGondolas.clock())
	_body = GondolaBody.new()
	_body.rig = self
	_body.name = "Cradle"
	_body.collision_layer = 4
	_body.collision_mask = 0
	_body.add_to_group("rail_vehicle")
	# Placed BEFORE it enters the tree (a kinematic body's first move would read as a velocity).
	_body.transform = _frame(_pose.lane, _pose.y)
	var mi := MeshInstance3D.new()
	mi.name = "CradleMesh"
	mi.mesh = TowerGondolas.cradle_mesh(int(site.paint))
	_body.add_child(mi)
	var hl := TowerGondolas.CRADLE_LEN * 0.5
	var hd := TowerGondolas.HALF_DEPTH
	_shape(Vector3(TowerGondolas.CRADLE_LEN, 0.1, hd * 2.0), Vector3(0, 0.0, 0))
	_shape(Vector3(TowerGondolas.CRADLE_LEN, 1.0, 0.06), Vector3(0, 0.6, hd))
	_shape(Vector3(TowerGondolas.CRADLE_LEN, 0.12, 0.06), Vector3(0, TowerGondolas.RAIL_Y, -hd))
	for sx in [-1.0, 1.0]:
		_shape(Vector3(0.3, 1.9, 0.5), Vector3(sx * (hl + 0.1), 1.0, 0))
	add_child(_body)
	# Wire ropes: two from each stirrup (the working rope and the safety rope).
	for k in 4:
		var r := MeshInstance3D.new()
		r.name = "Rope%d" % k
		r.mesh = TowerGondolas.unit_cylinder()
		r.material_override = TowerGondolas.rope_material(Color(0.32, 0.33, 0.34))
		r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(r)
		_ropes.append(r)
	if int(site.support) == 0:
		for k in 2:
			var dv := MeshInstance3D.new()
			dv.name = "Davit%d" % k
			dv.mesh = TowerGondolas.davit_mesh()
			add_child(dv)
			_davits.append(dv)
	# The water on the glass.
	_streak = MeshInstance3D.new()
	_streak.name = "Wet"
	var q := QuadMesh.new()
	q.size = Vector2(hl * 2.0 + 0.4, 22.0)
	q.center_offset = Vector3(0, 4.0, 0)
	_streak.mesh = q
	_streak_mat = TowerGondolas.streak_material().duplicate() as ShaderMaterial
	_streak_mat.set_shader_parameter("half_width", hl + 0.2)
	_streak_mat.set_shader_parameter("seed", float(int(site.seed) % 997))
	_streak.material_override = _streak_mat
	_streak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_streak)
	_update(0.0)


func _shape(size: Vector3, at: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = at
	_body.add_child(cs)


func _drop() -> void:
	_drop_workers()
	if not built:
		return
	built = false
	TowerGondolas.live = maxi(TowerGondolas.live - 1, 0)
	var nodes: Array = [_body, _streak]
	nodes.append_array(_ropes)
	nodes.append_array(_davits)
	for n in nodes:
		if n != null and is_instance_valid(n):
			n.queue_free()
	_body = null
	_streak = null
	_ropes.clear()
	_davits.clear()
	_lane = INF


# --- Workers -------------------------------------------------------------------------------

func _add_workers() -> void:
	var avail: Array[String] = []
	for p: String in TowerGondolas.WORKER_MODELS:
		if ResourceLoader.exists(p):
			avail.append(p)
	if avail.is_empty() or _body == null:
		return
	has_workers = true
	TowerGondolas.workers_live += 1
	var s := int(site.seed)
	for i in 2:
		var path := avail[absi(hash([s, "worker", i])) % avail.size()]
		var scene: PackedScene = load(path)
		if scene == null:
			continue
		var wx := -1.05 if i == 0 else 1.0
		var root := Node3D.new()
		root.name = "Worker%d" % i
		# Facing the glass (-z of the cradle); the rigs face +Z.
		root.transform = Transform3D(Basis(Vector3.UP, PI), Vector3(wx, 0.04, 0.02))
		var inst := scene.instantiate() as Node3D
		Pedestrian.prepare_rig(inst, 1)
		root.add_child(inst)
		var shirt := absi(hash([s, "shirt", i])) % TowerGondolas.SHIRTS.size()
		for node in inst.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			var src := mi.mesh.surface_get_material(0) as StandardMaterial3D if mi.mesh else null
			if src and src.albedo_texture and not Pedestrian.is_hair(mi) and not path.ends_with("crowd_s.glb"):
				mi.material_override = TowerGondolas.uniform_material(src.albedo_texture, shirt)
		Pedestrian.plain_hair(inst)
		_body.add_child(root)
		var anim := inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if anim and anim.has_animation(Pedestrian.IDLE_CLIP):
			anim.get_animation(Pedestrian.IDLE_CLIP).loop_mode = Animation.LOOP_LINEAR
			# Held near the idle's start, square to the glass: the clip itself swings the shoulders
			# round 60 degrees, and the IK does the moving.
			anim.play(Pedestrian.IDLE_CLIP)
			anim.seek(0.4 + _rng.randf() * 0.4, true)
			anim.speed_scale = 0.0
		TowerGondolas.dress_hat(inst, path, absi(hash([s, "hat", i])) % TowerGondolas.HATS.size())
		var w := {"root": root, "inst": inst, "x": wx, "phase": _rng.randf() * TAU, "rate": 0.8 + _rng.randf() * 0.4}
		_rig_ik(w)
		_workers.append(w)
		# The worker's own collision (a round at them swings the cradle too).
		_shape(Vector3(0.5, 1.7, 0.4), Vector3(wx, 0.9, 0.02))
		var lan := MeshInstance3D.new()
		lan.name = "Lanyard%d" % i
		lan.mesh = TowerGondolas.unit_cylinder()
		lan.material_override = TowerGondolas.rope_material(TowerGondolas.ROPE_ORANGE)
		lan.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(lan)
		_lanyards.append(lan)
		w.lanyard = lan


## Two-bone IK on both arms (onto the rail, the squeegee) and both legs (feet planted on the
## floor while the hips drop into a crouch), on the rig's own skeleton.
func _rig_ik(w: Dictionary) -> void:
	var inst: Node3D = w.inst
	var skel := inst.find_child("Skeleton3D", true, false) as Skeleton3D
	if skel == null:
		return
	w.skel = skel
	var root: Node3D = w.root
	var targets := {}
	for side in ["Left", "Right"]:
		var hand := Node3D.new()
		hand.name = side + "HandTarget"
		_body.add_child(hand)
		targets[side + "Hand"] = hand
		var foot := Node3D.new()
		foot.name = side + "FootTarget"
		_body.add_child(foot)
		var fb := skel.find_bone(side + "Foot")
		if fb >= 0:
			foot.position = _body.to_local(skel.global_transform * skel.get_bone_global_rest(fb).origin) if skel.is_inside_tree() else \
				root.transform * (inst.transform * (skel.transform * skel.get_bone_global_rest(fb).origin))
		targets[side + "Foot"] = foot
		var sh := skel.find_bone(side + "Arm")
		# In the root's frame the rig faces +Z, so its left is +X.
		var sgn := 1.0 if side == "Left" else -1.0
		var elbow := Node3D.new()
		elbow.name = side + "ElbowPole"
		root.add_child(elbow)
		if sh >= 0:
			elbow.position = inst.transform * (skel.transform * skel.get_bone_global_rest(sh).origin) + Vector3(sgn * 0.45, -0.6, -0.45)
		var knee := Node3D.new()
		knee.name = side + "KneePole"
		root.add_child(knee)
		knee.position = Vector3(sgn * 0.12, 0.6, 1.0)
		_ik(skel, side + "ArmIK", side + "Arm", side + "ForeArm", side + "Hand", hand, elbow)
		_ik(skel, side + "LegIK", side + "UpLeg", side + "Leg", side + "Foot", foot, knee)
	w.targets = targets
	# The squeegee rides the right hand's target.
	var tool := MeshInstance3D.new()
	tool.name = "Squeegee"
	tool.mesh = TowerGondolas.tool_mesh()
	(targets["RightHand"] as Node3D).add_child(tool)
	w.tool = tool


func _ik(skel: Skeleton3D, node_name: String, a: String, b: String, c: String, target: Node3D, pole: Node3D) -> void:
	if skel.find_bone(a) < 0 or skel.find_bone(c) < 0:
		return
	var ik := TwoBoneIK3D.new()
	ik.name = node_name
	skel.add_child(ik)
	ik.setting_count = 1
	ik.set_root_bone_name(0, a)
	ik.set_middle_bone_name(0, b)
	ik.set_end_bone_name(0, c)
	ik.set_target_node(0, ik.get_path_to(target))
	ik.set_pole_node(0, ik.get_path_to(pole))
	ik.set_pole_direction(0, SkeletonModifier3D.SECONDARY_DIRECTION_PLUS_Z)
	ik.active = true


func _drop_workers() -> void:
	if not has_workers:
		return
	has_workers = false
	TowerGondolas.workers_live = maxi(TowerGondolas.workers_live - 1, 0)
	for w: Dictionary in _workers:
		for key in ["root", "lanyard"]:
			var n: Node = w.get(key)
			if n != null and is_instance_valid(n):
				n.queue_free()
		var tg: Dictionary = w.get("targets", {})
		for n: Node in tg.values():
			if is_instance_valid(n):
				n.queue_free()
	_workers.clear()
	_lanyards.clear()
	# Their collision boxes: everything past the cradle's own five shapes.
	if _body != null and is_instance_valid(_body):
		var shapes := 0
		for c in _body.get_children():
			if c is CollisionShape3D:
				shapes += 1
				if shapes > 5:
					c.queue_free()


# --- Hits ----------------------------------------------------------------------------------

## A round, a pellet or a blast at the cradle (GondolaBody.take_hit): the kick, the brace, a yell.
func hit(shape: int, damage: float, dir: Vector3) -> void:
	hits += 1
	var n: Vector3 = site.n
	var t: Vector3 = site.t
	var k := clampf(damage * 0.03, 0.15, 2.4)
	_vo += dir.dot(n) * k
	_va += dir.dot(t) * k * 0.8
	var side := 1.0 if _rng.randf() < 0.5 else -1.0
	_vyaw += side * k * 0.35
	_vroll += -side * k * 0.25
	_brace = maxf(_brace, 3.5 + k * 2.0)
	if has_workers and _scream_cd <= 0.0 and _body != null:
		_scream_cd = 4.0
		Sfx.play("scream", _body.global_position + Vector3.UP * 1.5, -8.0 if shape <= 4 else -3.0)


# --- Per frame -----------------------------------------------------------------------------

func _update(dt: float) -> void:
	var now := TowerGondolas.clock()
	_pose = TowerGondolas.pose_at(site, now)
	var lane: float = _pose.lane
	var y: float = _pose.y
	var hl := TowerGondolas.CRADLE_LEN * 0.5
	var n: Vector3 = site.n
	var t: Vector3 = site.t
	var m: Vector3 = site.m
	# The heads the ropes hang from.
	var heads: Array[Vector3] = []
	if int(site.support) == 1:
		heads = [site.heads[0], site.heads[1]]
	else:
		for sx in [-1.0, 1.0]:
			heads.append(m + t * (lane + sx * (hl + 0.12)) + n * TowerGondolas.DAVIT_OUT + Vector3.UP * (TowerGondolas.DAVIT_RISE - 0.12))
	# The swing.
	var rope := maxf((heads[0].y + heads[1].y) * 0.5 - (y + 1.97), 2.0)
	var w := sqrt(9.8 / rope)
	if dt > 0.0:
		_vo += (-w * w * _xo - 2.0 * 0.04 * w * _vo) * dt
		_va += (-w * w * _xa - 2.0 * 0.04 * w * _va) * dt
		var wy := 1.5
		_vyaw += (-wy * wy * _yaw - 2.0 * 0.12 * wy * _vyaw) * dt
		var wr := 2.3
		_vroll += (-wr * wr * _roll - 2.0 * 0.16 * wr * _vroll) * dt
		# The cradle walking down a floor bobs on its hoists.
		if int(_pose.moving) == 1:
			_vroll += sin(now * 2.1) * 0.02 * dt
		_xo += _vo * dt
		_xa += _va * dt
		_yaw += _vyaw * dt
		_roll += _vroll * dt
		# The rollers against the glass.
		if _xo < 0.0:
			_xo = 0.0
			if _vo < 0.0:
				_vo = -_vo * 0.25
		var lim := (_xo + 0.02) / hl
		if absf(_yaw) > lim:
			_yaw = clampf(_yaw, -lim, lim)
			_vyaw *= -0.3
		_roll = clampf(_roll, -0.3, 0.3)
		_xa = clampf(_xa, -3.0, 3.0)
		_xo = minf(_xo, 6.0)
		_brace = maxf(_brace - dt, 0.0)
		_scream_cd = maxf(_scream_cd - dt, 0.0)
	var shaken := clampf(absf(_vo) + absf(_va) + absf(_vyaw) * 2.0 + absf(_roll) * 3.0, 0.0, 1.0)
	var want := 1.0 if _brace > 0.0 or shaken > 0.35 else 0.0
	_brace_w = move_toward(_brace_w, want, (dt if dt > 0.0 else 1.0) * 2.5)
	# Placed: the frame, the swing out and along, the twist about the middle and the roll about
	# the rope entries' height (the cradle hangs from both ends).
	var f := _frame(lane, y)
	var pivot := Vector3(0, 1.97, 0)
	var swing := Transform3D(Basis(Vector3.UP, _yaw) * Basis(Vector3(0, 0, 1), _roll), Vector3.ZERO)
	var local := Transform3D(Basis.IDENTITY, Vector3(_xa, 0.0, _xo) + pivot) * swing * Transform3D(Basis.IDENTITY, -pivot)
	if _body != null:
		_body.transform = f * local
	# Ropes from the stirrup tops to the heads.
	for i in 4:
		var sx := -1.0 if i < 2 else 1.0
		var zo := -0.04 if i % 2 == 0 else 0.04
		var a := _body.transform * Vector3(sx * (hl + 0.12), 2.06, zo)
		var b: Vector3 = heads[0 if sx < 0.0 else 1] + t * zo
		_set_rope(_ropes[i], a, b, 0.0055 if i % 2 == 0 else 0.0045)
	# Davits move lane to lane (the crew carries them; done before the next drop).
	if not _davits.is_empty() and lane != _lane:
		_lane = lane
		for k in 2:
			var sx := -1.0 if k == 0 else 1.0
			var base := m + t * (lane + sx * (hl + 0.12)) - n * TowerGondolas.DAVIT_IN
			base.y = float(site.roof)
			(_davits[k] as Node3D).transform = Transform3D(Basis(t, Vector3.UP, n), base)
	# The water: on the glass, at the cradle's height, washed glass above it.
	if _streak != null:
		var wall := m + t * lane - n * 0.0 + n * 0.04
		wall.y = y
		_streak.transform = Transform3D(Basis(t, Vector3.UP, n), wall)
		var washed: float = _pose.washed
		_streak_mat.set_shader_parameter("wet_top", clampf(washed + 1.0, 0.6, 12.0))
		_streak_mat.set_shader_parameter("soap", (1.0 - float(_pose.step)) if int(_pose.moving) == 0 else 0.0)
		_streak_mat.set_shader_parameter("drip_len", 7.0 if int(_pose.moving) != 2 else 2.0)
	if has_workers:
		_pose_workers(now, f * local)


## The hands: the left on the front rail, the right working the squeegee across the pane in
## overlapping S strokes while they wash, both on the rail while it moves or swings; the hips
## drop into a crouch when it is shaken. Lanyards from the roof anchor to each worker's back.
func _pose_workers(now: float, cradle: Transform3D) -> void:
	var hd := TowerGondolas.HALF_DEPTH
	var washing := int(_pose.moving) == 0
	for i in _workers.size():
		var w: Dictionary = _workers[i]
		var wx: float = w.x
		var tg: Dictionary = w.get("targets", {})
		var crouch := 0.22 * _brace_w
		(w.root as Node3D).position = Vector3(wx, 0.04 - crouch, 0.02 + crouch * 0.4)
		if tg.is_empty():
			continue
		var lh: Node3D = tg.LeftHand
		var rh: Node3D = tg.RightHand
		var rail := TowerGondolas.RAIL_Y - 0.02
		lh.transform = Transform3D(Basis(), Vector3(wx - 0.32, rail, -hd))
		var ph: float = now * float(w.rate) + float(w.phase)
		var work := 0.0 if not washing else 1.0 - _brace_w
		var stroke := Vector3(wx + 0.1 + 0.3 * sin(ph), 1.3 + 0.22 * sin(ph * 0.5), -hd - 0.06)
		var hold := Vector3(wx + 0.3, rail, -hd)
		var p := hold.lerp(stroke, work)
		# The squeegee leans up and in to the glass from the hand.
		var up := Vector3(0.15 * cos(ph), 1.0, -0.55).normalized().lerp(Vector3(0.0, -1.0, 0.25).normalized(), 1.0 - work).normalized()
		var zb := Vector3(1, 0, 0).cross(up).normalized()
		var xb := up.cross(zb).normalized()
		rh.transform = Transform3D(Basis(xb, up, zb), p)
		if w.has("tool"):
			(w.tool as Node3D).visible = work > 0.05
		var lf: Node3D = tg.LeftFoot
		var rf: Node3D = tg.RightFoot
		if not w.has("feet"):
			w.feet = [lf.position, rf.position]
		lf.position = w.feet[0]
		rf.position = w.feet[1]
		if w.has("lanyard"):
			var t: Vector3 = site.t
			var n: Vector3 = site.n
			var anchor: Vector3 = (site.m as Vector3) + t * (float(_pose.lane) + wx * 0.8) - n * 0.4 + Vector3.UP * 0.25
			_set_rope(w.lanyard, anchor, cradle * Vector3(wx, 1.32, 0.16), 0.008)


static func _set_rope(mi: MeshInstance3D, a: Vector3, b: Vector3, r: float) -> void:
	var d := b - a
	var len := d.length()
	if len < 0.01:
		mi.visible = false
		return
	mi.visible = true
	var yv := d
	var xv := yv.cross(Vector3.FORWARD if absf(d.normalized().dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized() * r
	var zv := xv.cross(yv).normalized() * r
	mi.transform = Transform3D(Basis(xv, yv, zv), (a + b) * 0.5)

