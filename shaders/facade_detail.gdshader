shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// A building's facade detail MultiMeshes - window frames, bands and cornices, parapets, bay
// cheeks - one per building instead of one per box part (Building._commit_details()). The
// shading is the StandardMaterial3D each one used before (PropFactory.material(): the instance
// colour as albedo), its generated shader line for line, down to the unset textures it samples;
// Building copies that material's albedo, roughness, metallic and specular into the uniforms.
//
// What the merge would have changed is WHERE each part's details stop drawing. A node's
// visibility range is measured from the camera to the centre of its bounds, and one node for
// the whole building has a different centre from each part's, so the frames on a podium would
// have gone out at the tower's distance. So every instance says which part it belongs to
// (INSTANCE_CUSTOM.x) and part_ref holds that part's old node: the centre of its bounds in TRUE
// world space (origin_shift, WorldState.world_offset, brings it into the shifted scene: nothing
// per instance could carry it exactly, the Compatibility renderer packs INSTANCE_CUSTOM into
// half floats) and its range (0 for none). An instance past it collapses to a point - in the
// shadow passes too, measured from the main camera exactly as the culling did. The node's own
// range only drops the whole building once every part is past its own. The SDFGI voxeliser runs
// with an identity main camera and ignored visibility ranges before, so it is left alone here.
global uniform vec3 origin_shift;
uniform vec4 part_ref[16];
uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D texture_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform float roughness : hint_range(0.0, 1.0) = 1.0;
uniform sampler2D texture_metallic : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D texture_roughness : hint_roughness_r, filter_linear_mipmap, repeat_enable;
uniform float specular : hint_range(0.0, 1.0, 0.01) = 0.5;
uniform float metallic : hint_range(0.0, 1.0, 0.01) = 0.0;

void vertex() {
	vec4 ref = part_ref[clamp(int(INSTANCE_CUSTOM.x + 0.5), 0, 15)];
	if (ref.w > 0.0 && MAIN_CAM_INV_VIEW_MATRIX != mat4(1.0)) {
		if (distance(MAIN_CAM_INV_VIEW_MATRIX[3].xyz, ref.xyz - origin_shift) > ref.w) {
			VERTEX = vec3(0.0);
		}
	}
}

void fragment() {
	vec2 base_uv = UV;
	vec4 albedo_tex = texture(texture_albedo, base_uv);
	albedo_tex *= COLOR;
	ALBEDO = albedo.rgb * albedo_tex.rgb;
	float metallic_tex = dot(texture(texture_metallic, base_uv), vec4(1.0, 0.0, 0.0, 0.0));
	METALLIC = metallic_tex * metallic;
	SPECULAR = specular;
	vec4 roughness_texture_channel = vec4(1.0, 0.0, 0.0, 0.0);
	float roughness_tex = dot(texture(texture_roughness, base_uv), roughness_texture_channel);
	ROUGHNESS = roughness_tex * roughness;
}
