class_name ConstructionWorker
extends StreetVendor
## A worker on a building site or at road works (Construction): a crowd rig in a hi-vis top and
## dark work trousers (ApronCrew's garment split) under a hard hat built round the rig's head
## (HardHat), standing at their spot - on the tower's top deck, at the site's gate, at the trench,
## or flagging the traffic with a STOP / SLOW paddle. An ordinary pedestrian otherwise: shot,
## knocked, bled and ragdolled like anyone, in the crowd cap and the "pedestrian" group. They play
## the crowd's standing clips (StreetVendor). They do not run from gunfire (they are up a building
## or in the road); they turn and look.

## Holds the flagger's paddle.
var paddle: bool = false


func _init() -> void:
	# The old crowd roll is made either way (Pedestrian._add_accessory's first roll), but nobody
	# wears a cap or a pack under the hard hat.
	accessory_chance = 0.0


func _add_model() -> bool:
	if not super._add_model():
		return false
	var inst: Node3D = null
	for c in _visual.get_children():
		if c is Node3D:
			inst = c
			break
	if inst == null:
		return true
	var which := _style.randi() % ApronCrew.HIVIS.size()
	for node in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or is_hair(mi):
			continue
		var src := mi.mesh.surface_get_material(0) as StandardMaterial3D
		if src and src.albedo_texture:
			var mat := ApronCrew.hivis_material(src.albedo_texture, which)
			if mat:
				mi.material_override = mat
	HardHat.dress(inst, _model_path, _style.randi())
	if paddle:
		_hold_paddle()
	return true


## The paddle in the right hand, its pole down to the road.
func _hold_paddle() -> void:
	if _head_skel == null:
		var found := _visual.find_children("*", "Skeleton3D", true, false)
		if found.is_empty():
			return
		_head_skel = found[0]
	if _head_skel.find_bone("RightHand") < 0:
		return
	var unit := 1.0
	var node: Node3D = _head_skel
	while node != null and node != _visual:
		unit *= node.transform.basis.get_scale().y
		node = node.get_parent() as Node3D
	unit = 1.0 / maxf(unit, 1e-5)
	var att := BoneAttachment3D.new()
	_head_skel.add_child(att)
	att.bone_name = "RightHand"
	var mi := MeshInstance3D.new()
	mi.name = "Paddle"
	mi.mesh = Construction.paddle_mesh()
	mi.material_override = ConstructionKit.material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.visibility_range_end = 90.0
	# The grip frame (CrowdLife.grip_basis: x the thumb, y the fingers, z out of the palm): the pole
	# runs along the fist (x), the hand a little under its middle.
	var grip := CrowdLife.grip_basis("RightHand")
	var turn := Basis(Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1))
	mi.transform = Transform3D(grip * turn * Basis.from_scale(Vector3.ONE * unit), grip * Vector3(-1.0 * unit, 0.0, 0.0))
	att.add_child(mi)


## Working: they turn to look at trouble, they do not run.
func _scare(at: Vector3) -> void:
	_look_threat = at
	_look_hold = look_threat_seconds


## A worker in the road (at the trench, flagging) is placed, not walked, like a truck's cook.
func _physics_process(delta: float) -> void:
	super(delta)
	if in_truck and _visual:
		_visual.position.y = 0.0
