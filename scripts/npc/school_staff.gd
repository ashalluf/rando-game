class_name SchoolStaff
extends StreetVendor
## An adult at a school's front at drop-off (RcSchoolMorning): a crossing guard at the kerb in a
## lime hi-vis top with a STOP paddle, a yard supervisor at the gate in hi-vis, or a parent
## standing on the pavement (plain clothes: `hivis` false). A crowd rig like anyone - shot,
## knocked, ragdolled, in the crowd cap - standing at its spot (StreetVendor); a fright sends them
## off and they walk back. Never a child: adult crowd rigs only.

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

## The hi-vis top (crossing guard, supervisor) and the paddle (the guard).
var hivis: bool = true
var paddle: bool = false


func _add_model() -> bool:
	if not super._add_model():
		return false
	if not hivis:
		return true
	for node in _visual.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or is_hair(mi):
			continue
		var src := mi.mesh.surface_get_material(0) as StandardMaterial3D
		if src and src.albedo_texture:
			# Lime (ApronCrew.HIVIS[1]): the crossing guards' and yard staff's colour.
			var mat := ApronCrew.hivis_material(src.albedo_texture, 1)
			if mat:
				mi.material_override = mat
	if paddle:
		_hold_paddle()
	return true


## The STOP paddle in the right hand, its pole down (ConstructionWorker's, the same grip).
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
	var grip := CrowdLife.grip_basis("RightHand")
	var turn := Basis(Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1))
	mi.transform = Transform3D(grip * turn * Basis.from_scale(Vector3.ONE * unit), grip * Vector3(-1.0 * unit, 0.0, 0.0))
	att.add_child(mi)
