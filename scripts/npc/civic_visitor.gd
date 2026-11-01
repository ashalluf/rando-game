class_name CivicVisitor
extends Pedestrian
## Someone at a civic building (CivicBuildings): a library patron, a customer at the post office,
## somebody with a form at city services - an ordinary pedestrian (shot, knocked, bled and
## ragdolled like anyone, in the crowd cap) on a small ring in the forecourt who stops often and
## never crosses a road. `worker`: a postal carrier by the dock, in the service's blue-grey shirt
## and navy trousers (the character shader's garment split, as ApronCrew's hi-vis).

const SHIRT := Color(0.46, 0.55, 0.66)
const TROUSERS := Color(0.07, 0.09, 0.18)

var worker := false

static var _mats: Dictionary = {}


func _ready() -> void:
	cross_chance = 0.0
	pause_chance = 0.6
	super._ready()


func _add_model() -> bool:
	if not super._add_model():
		return false
	if not worker:
		return true
	for node in _visual.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or is_hair(mi):
			continue
		var src := mi.mesh.surface_get_material(0) as StandardMaterial3D
		if src and src.albedo_texture:
			var mat := carrier_material(src.albedo_texture)
			if mat:
				mi.material_override = mat
	return true


## The model's own face, skin and hair with the carrier's shirt and trousers.
static func carrier_material(albedo: Texture2D) -> ShaderMaterial:
	var key := albedo.get_instance_id()
	if _mats.has(key):
		return _mats[key]
	var base := character_material(albedo, 1)
	if base == null:
		return null
	var mat := base.duplicate() as ShaderMaterial
	mat.set_shader_parameter("cloth_hue", SHIRT.h)
	mat.set_shader_parameter("cloth_sat", SHIRT.s)
	mat.set_shader_parameter("cloth_value", SHIRT.v)
	mat.set_shader_parameter("cloth_strength", 0.95)
	mat.set_shader_parameter("pants_hue", TROUSERS.h)
	mat.set_shader_parameter("pants_sat", TROUSERS.s)
	mat.set_shader_parameter("pants_value", TROUSERS.v)
	mat.set_shader_parameter("pants_strength", 0.95)
	mat.set_shader_parameter("cloth_roughness", 0.75)
	mat.set_shader_parameter("cloth_shade_keep", 0.7)
	_mats[key] = mat
	return mat
