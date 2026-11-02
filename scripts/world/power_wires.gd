class_name PowerWires
extends MeshInstance3D
## The power plant's wires (PowerPlantBuild.landmark()): power_wire.gdshader needs the viewport's
## size pushed to it (VIEWPORT_SIZE does not reach its vertex stage), as RidgeSystem does for its own.

var _vp := Vector2.ZERO


func _process(_delta: float) -> void:
	var mat := PowerPlantBuild.wire_material()
	var vp := get_viewport()
	var size := vp.get_visible_rect().size if vp else Vector2(1920.0, 1080.0)
	if vp and vp.scaling_3d_scale > 0.0:
		size *= vp.scaling_3d_scale
	if size.distance_to(_vp) > 0.5:
		_vp = size
		mat.set_shader_parameter("viewport_px", size)
