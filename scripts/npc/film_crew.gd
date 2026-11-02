class_name FilmCrew
extends StreetVendor
## A film crew member on location (FilmShootBuild.spawn_crew()): a crowd rig in black top and
## black trousers (the character shader's garment split, ApronCrew's way), standing at their post -
## the camera operator and focus puller at the dolly, the dolly grip, the crane operator, the
## director and script supervisor at video village, the gaffer by an HMI, the boom operator, a
## production assistant at each end of the closure, the caterer at the tent. An ordinary
## pedestrian otherwise: shot, knocked, bled and ragdolled like anyone, in the crowd cap; gunfire
## sends them running and they walk back to their post after (StreetVendor).

const BLACK := Color(0.035, 0.035, 0.04)

## Their job on the set (FilmShoot.layout()'s crew roles); a PA holds a walkie to the face.
var role: String = ""

static var _black_mats: Dictionary = {}


func _init() -> void:
	# Nobody wears the crowd's cap or pack on set; the roll is still made (Pedestrian).
	accessory_chance = 0.0


func _ready() -> void:
	add_to_group("film_crew")
	super._ready()


func _roll_life(seed_value: int) -> void:
	super(seed_value)
	# A PA is always on the walkie, the caterer and the crew mostly idle at their posts.
	if role == "pa":
		_carry = CrowdLife.Carry.CALL


func _add_model() -> bool:
	if not super._add_model():
		return false
	for node in _visual.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or is_hair(mi):
			continue
		var src := mi.mesh.surface_get_material(0) as StandardMaterial3D
		if src and src.albedo_texture:
			var mat := black_material(src.albedo_texture)
			if mat:
				mi.material_override = mat
	return true


## The model's own face, skin and hair, top and trousers dyed black.
static func black_material(albedo: Texture2D) -> ShaderMaterial:
	var key := albedo.get_instance_id()
	if _black_mats.has(key):
		return _black_mats[key]
	var base := character_material(albedo, 1)
	if base == null:
		return null
	var mat := base.duplicate() as ShaderMaterial
	mat.set_shader_parameter("cloth_hue", BLACK.h)
	mat.set_shader_parameter("cloth_sat", BLACK.s)
	mat.set_shader_parameter("cloth_value", BLACK.v)
	mat.set_shader_parameter("cloth_strength", 0.97)
	mat.set_shader_parameter("pants_hue", BLACK.h)
	mat.set_shader_parameter("pants_sat", BLACK.s)
	mat.set_shader_parameter("pants_value", BLACK.v)
	mat.set_shader_parameter("pants_strength", 0.95)
	mat.set_shader_parameter("cloth_roughness", 0.85)
	mat.set_shader_parameter("cloth_shade_keep", 0.75)
	_black_mats[key] = mat
	return mat
