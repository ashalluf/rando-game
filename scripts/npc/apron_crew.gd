class_name ApronCrew
extends Pedestrian
## Ground crew round a parked airliner (Airport._crew()): an ordinary pedestrian - shot, knocked,
## bled and ragdolled like anyone, counted in the crowd cap - on a small ring by the jet's
## forward hold and baggage train, in a hi-vis top (safety orange or lime) and dark work
## trousers. The colours go through the character shader's garment split, the way the police
## uniform does (PoliceOfficer.uniform_material()). Never crosses a road: the apron has none.

const HIVIS := [Color(0.98, 0.42, 0.04), Color(0.80, 0.92, 0.10)]
const TROUSERS := Color(0.07, 0.08, 0.12)

static var _hivis_mats: Dictionary = {}


func _ready() -> void:
	cross_chance = 0.0
	pause_chance = 0.55
	super._ready()


func _add_model() -> bool:
	if not super._add_model():
		return false
	var which := _style.randi() % HIVIS.size()
	for node in _visual.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or is_hair(mi):
			continue
		var src := mi.mesh.surface_get_material(0) as StandardMaterial3D
		if src and src.albedo_texture:
			var mat := hivis_material(src.albedo_texture, which)
			if mat:
				mi.material_override = mat
	return true


## The model's own face, skin and hair, with the top repainted hi-vis and the trousers dark.
static func hivis_material(albedo: Texture2D, which: int) -> ShaderMaterial:
	var key := "%d_%d" % [albedo.get_instance_id(), which]
	if _hivis_mats.has(key):
		return _hivis_mats[key]
	var base := character_material(albedo, 1)
	if base == null:
		return null
	var mat := base.duplicate() as ShaderMaterial
	var top: Color = HIVIS[which % HIVIS.size()]
	mat.set_shader_parameter("cloth_hue", top.h)
	mat.set_shader_parameter("cloth_sat", top.s)
	mat.set_shader_parameter("cloth_value", top.v)
	mat.set_shader_parameter("cloth_strength", 0.97)
	mat.set_shader_parameter("pants_hue", TROUSERS.h)
	mat.set_shader_parameter("pants_sat", TROUSERS.s)
	mat.set_shader_parameter("pants_value", TROUSERS.v)
	mat.set_shader_parameter("pants_strength", 0.95)
	mat.set_shader_parameter("cloth_roughness", 0.7)
	mat.set_shader_parameter("cloth_shade_keep", 0.7)
	_hivis_mats[key] = mat
	return mat
