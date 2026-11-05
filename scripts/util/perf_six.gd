class_name PerfSix
## Perf audit 6 (docs/HANDOFF.md "Perf audit 6"): the cuts found by measuring every refcam after
## wave 7, each behind its own switch. Every cut here changes what the GPU is fed, never what a
## camera sees (each was proved with a DIFF=1 / --strict pair against an A/A run).

## The rooftop air-conditioning units (Building's RoofUnits MultiMeshes: the 4.7k-triangle
## condenser model, 1.7x) cast from a lighter twin: the model's shadow proxy at the shadow LOD
## scale the car bodies use. They used to cast the full model into every cascade - downtown has
## hundreds on the roofs round any camera, and none had a lighter caster. ROOF_UNIT_SHADOW=0 the A/B.
static var roof_units_lite := OS.get_environment("ROOF_UNIT_SHADOW") != "0"
const ROOF_UNIT_SHADOW_BIAS := 0.3


## Called by Building._commit_roof() for each RoofUnits node, already in the tree.
static func roof_units(units: MultiMeshInstance3D, mesh: Mesh, xforms: Array) -> void:
	if not roof_units_lite or xforms.is_empty():
		return
	var proxy: Mesh = PropFactory.shadow_proxy(mesh)
	if proxy == null:
		proxy = mesh
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = proxy
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var twin := MultiMeshInstance3D.new()
	twin.name = String(units.name) + "Shadow"
	twin.multimesh = mm
	twin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	twin.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	twin.lod_bias = ROOF_UNIT_SHADOW_BIAS
	units.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	units.add_sibling(twin)


## Every other batch's shadow twin (street props' shadow proxies, and a batch's own mesh cast within
## a shadow reach) picks its LOD at the trees' shadow LOD scale too: a bench, a hydrant or a lamp's
## shadow at a cascade's texels does not need the camera pass's triangles. PROP_SHADOW_LOD=0 the A/B.
static var prop_shadow_lod := OS.get_environment("PROP_SHADOW_LOD") != "0"


static func prop_twin_bias() -> float:
	return FoliageLod.SHADOW_LOD_SCALE if prop_shadow_lod else 1.0
