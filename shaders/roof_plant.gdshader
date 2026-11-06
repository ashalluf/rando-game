shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// A building's roof plant merged into one mesh (Building._commit_roof()): every box and cylinder
// that used to be a MeshInstance3D with its own flat StandardMaterial3D - a draw call each, and
// one more in every shadow pass - is now one draw. Each vertex carries what its material said:
// CUSTOM0 (32-bit floats) is the albedo exactly as the renderer would have handed the material's
// albedo_color to its shader (Building._roof_albedo(): linear on Forward+ and Mobile, the sRGB
// value verbatim on Compatibility, which does not convert source_color uniforms) and the
// roughness; UV.x is the metallic. The rest is StandardMaterial3D's own generated shader for a
// plain opaque material, line for line, down to the unset textures it samples (white, and the
// roughness hint's default), so a merged prop shades to the bit as its old node did.
uniform sampler2D texture_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D texture_metallic : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D texture_roughness : hint_roughness_r, filter_linear_mipmap, repeat_enable;

varying flat vec4 plant;
varying flat float plant_metal;

void vertex() {
	plant = CUSTOM0;
	plant_metal = UV.x;
}

void fragment() {
	vec2 base_uv = UV;
	vec4 albedo_tex = texture(texture_albedo, base_uv);
	ALBEDO = plant.rgb * albedo_tex.rgb;
	float metallic_tex = dot(texture(texture_metallic, base_uv), vec4(1.0, 0.0, 0.0, 0.0));
	METALLIC = metallic_tex * plant_metal;
	SPECULAR = 0.5;
	vec4 roughness_texture_channel = vec4(1.0, 0.0, 0.0, 0.0);
	float roughness_tex = dot(texture(texture_roughness, base_uv), roughness_texture_channel);
	ROUGHNESS = roughness_tex * plant.a;
}
