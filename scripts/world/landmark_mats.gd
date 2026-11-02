class_name LandmarkMats
extends RefCounted
## Cached materials for the downtown civic landmarks, on the landmark shaders (see
## shaders/landmark_facade, curtain_glass, brushed_steel, clay_roof, fountain_water, fountain_jet
## and led_screen). One material per look, shared by every landmark that wears it, keyed by a
## name the builder chooses, so the near and far copies of a building also share them.

static var _cache: Dictionary = {}


## A facade material. `set_key` picks a CC0 wall texture (PropFactory.TEXTURE_SETS; "" for none,
## then it is flat `tint` with the other layers on top); `params` are shader uniforms by name.
static func facade(key: String, set_key: String, tex_scale: float, params: Dictionary = {}) -> ShaderMaterial:
	var k := "facade_" + key
	if _cache.has(k):
		return _cache[k]
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/landmark_facade.gdshader")
	if set_key != "":
		var albedo := PropFactory.texture(set_key, "Color")
		if albedo:
			mat.set_shader_parameter("use_texture", true)
			mat.set_shader_parameter("wall_albedo", albedo)
			mat.set_shader_parameter("wall_normal", PropFactory.texture(set_key, "NormalGL"))
			mat.set_shader_parameter("wall_roughness", PropFactory.texture(set_key, "Roughness"))
			mat.set_shader_parameter("tex_scale", tex_scale)
			var means: Array = Building.WALL_TEXTURE_MEAN.get(set_key, [Color(0.3, 0.3, 0.3)])
			var m: Color = means[0]
			mat.set_shader_parameter("wall_texture_mean", Vector3(m.r, m.g, m.b))
	for p: String in params:
		mat.set_shader_parameter(p, params[p])
	_cache[k] = mat
	return mat


## Curtain-wall glass (curved, leaning, tilted), `params` shader uniforms by name.
static func glass(key: String, params: Dictionary = {}) -> ShaderMaterial:
	return _shader_mat("glass_" + key, "res://shaders/curtain_glass.gdshader", params)


## Brushed stainless steel (the concert hall's sails).
static func steel(key: String, params: Dictionary = {}) -> ShaderMaterial:
	return _shader_mat("steel_" + key, "res://shaders/brushed_steel.gdshader", params)


## Mission barrel-tile roof.
static func clay(key: String, params: Dictionary = {}) -> ShaderMaterial:
	return _shader_mat("clay_" + key, "res://shaders/clay_roof.gdshader", params)


static func water(key: String, params: Dictionary = {}) -> ShaderMaterial:
	return _shader_mat("water_" + key, "res://shaders/fountain_water.gdshader", params)


static func jet() -> ShaderMaterial:
	return _shader_mat("jet", "res://shaders/fountain_jet.gdshader", {})


static func _shader_mat(k: String, path: String, params: Dictionary) -> ShaderMaterial:
	if _cache.has(k):
		return _cache[k]
	var mat := ShaderMaterial.new()
	mat.shader = load(path)
	for p: String in params:
		mat.set_shader_parameter(p, params[p])
	_cache[k] = mat
	return mat


## A plain lit material taking the vertex colour (metal trim, dark steel, bronze, soil).
static func plain(key: String, color: Color, roughness: float = 0.7, metallic: float = 0.0) -> StandardMaterial3D:
	var k := "plain_" + key
	if _cache.has(k):
		return _cache[k]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	mat.vertex_color_use_as_albedo = true
	_cache[k] = mat
	return mat


## An unshaded glowing material (beacons, clock faces, lamp heads), vertex colour times `color`.
static func glow(key: String, color: Color) -> StandardMaterial3D:
	var k := "glow_" + key
	if _cache.has(k):
		return _cache[k]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	_cache[k] = mat
	return mat


## Paving through the road wear shader (joints, patches, no visible tile grid), per landmark.
static func paving(set_key: String, scale_m: float, tint: Color, seed_value: int, joints: float = 1.5, wear: float = 0.3) -> ShaderMaterial:
	return PropFactory.road(set_key, scale_m, tint, seed_value, joints, wear)
