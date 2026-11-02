class_name MotoRider
extends BikeRider
## Whoever rides a traffic motorcycle (Motorcycle makes one for a bike with an NPC at the
## controls, Vehicle's cabin rule). A BikeRider - so a Pedestrian: shot, knocked, bled and
## ragdolled like anyone - without a bike of its own: the motorcycle is the bike. It is a child of
## the bike's model frame and posed in it every frame by RideSolver (seat, grips, pegs, a boot
## down when the bike stands, tucked in at speed, hanging off into turns), so it leans with the
## drawn bike. Knocked, it leaves the bike first (the ragdoll goes into the world, not the bike).
## Always in a full-face helmet (MotoHelmet), hair under it.

var bike: Motorcycle
## What the bike tells the pose this frame (Motorcycle.ride_state()).
var ride_state: Dictionary = {}
var _solver: RideSolver
var _fit: bool = false


func setup_moto(m: Motorcycle, seed_value: int) -> void:
	bike = m
	kind = -1
	setup(Rect2(-1.0, -1.0, 2.0, 2.0), 1.0, seed_value)


func _ready() -> void:
	super._ready()
	# Not a walker: the crowd's cap, its trim and the street's life leave riders alone.
	remove_from_group("pedestrian")
	remove_from_group("bike_rider")
	add_to_group("moto_rider")
	set_meta("no_trim", true)


func _build_bike() -> void:
	_bike = null


func _scooter() -> bool:
	return false


func _roll(_delta: float) -> void:
	pass


func _dress() -> void:
	if _visual == null:
		return
	_visual.rotation.x = 0.0
	for att in _visual.find_children("*", "BoneAttachment3D", true, false):
		if (att as BoneAttachment3D).bone_name == "Spine01":
			att.queue_free()
	var inst := _visual.get_child(0) as Node3D if _visual.get_child_count() > 0 else null
	if inst == null or _model_path == "":
		return
	# Whatever they had on their head comes off for the helmet.
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		if String(mi.name).begins_with("Hat") or String(mi.get_parent().name).begins_with("Hat"):
			(mi as Node3D).visible = false
	MotoHelmet.dress(inst, _model_path, absi(hash([_life_seed, "moto_helmet"])))


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
	var rot: Array = []
	var pos: Array = []
	for b in n:
		rot.append(_sk.get_bone_pose_rotation(b))
		pos.append(_sk.get_bone_pose_position(b))
	_solver = RideSolver.new()
	if not _solver.setup(_sk, rot, pos):
		_solver = null
		_sk = null
		return
	var t := _skel_frame()
	_solver.measure(t.basis.get_scale().y)
	if bike != null:
		_solver.fit(t, bike.geo())
		_fit = true


## The bike's model frame (this node's own: the rider stands at its origin) into skeleton space.
func _skel_frame() -> Transform3D:
	var m := Transform3D.IDENTITY
	var node: Node = _sk
	while node != null and node != self:
		if node is Node3D:
			m = (node as Node3D).transform * m
		node = node.get_parent()
	return m.affine_inverse()


func _pose() -> void:
	if _solver == null or bike == null or not is_instance_valid(bike):
		return
	_solver.solve(_skel_frame(), bike.geo(), ride_state)
	_posed = true


func pose_now() -> void:
	_pose()


## Its own bike rides inside its hit zone: only something else knocks it off.
func _on_body_entered(body: Node3D) -> void:
	if body == bike:
		return
	super._on_body_entered(body)


## Off the bike: out into the world first, so the ragdoll is not a passenger. Deferred: a knock
## often comes from a physics callback (a bumper, a hit zone), where a body may not change parent.
var _knocking: bool = false


func knock(impulse: Vector3, gibs: int = 0) -> void:
	if _down or _knocking:
		return
	_knocking = true
	if bike != null and is_instance_valid(bike) and bike._rider == self:
		bike._rider = null
		bike.fallen = true
	_knock_now.call_deferred(impulse, gibs)


func _knock_now(impulse: Vector3, gibs: int) -> void:
	if _down or not is_inside_tree():
		return
	var world := bike.get_parent() if bike != null and is_instance_valid(bike) else null
	if world != null:
		var g := global_transform
		var yaw := g.basis.get_euler().y
		reparent(world, false)
		global_position = g.origin
		rotation = Vector3.ZERO
		if _visual:
			_visual.rotation.y = yaw
	super.knock(impulse, gibs)
