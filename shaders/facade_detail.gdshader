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
// The street level up close (FacadeStreet): the TRUE world height of the building's foot. The
// plinth band and anything else this low takes the splash-back, the damp and the contact shade the
// walls behind it take (facade_street.gdshaderinc's fs_plinth()); far under, it is off.
uniform float street_foot = -100000.0;
varying vec3 true_pos;

void vertex() {
	true_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz + origin_shift;
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
	float up = true_pos.y - street_foot;
	if (up < 1.2) {
		vec2 q = true_pos.xz + vec2(true_pos.z * 0.37, 0.0);
		float along = q.x * 0.55 + q.y * 0.55;
		float n = fract(sin(dot(floor(vec2(along, 3.0)), vec2(12.9898, 78.233))) * 43758.5453);
		float n2 = fract(sin(dot(floor(vec2(along * 6.0, 1.0)), vec2(39.3468, 11.135))) * 24634.6345);
		float hs = 0.18 + 0.22 * n + 0.06 * n2;
		float damp = 1.0 - smoothstep(hs - 0.06, hs + 0.01, up);
		float foot = 1.0 - smoothstep(0.0, 0.22, up);
		vec3 c = ALBEDO;
		c = mix(c, mix(c, vec3(dot(c, vec3(0.3, 0.55, 0.15))), 0.35) * 0.64, damp * 0.75);
		c *= 1.0 - 0.38 * foot;
		ALBEDO = c;
		ROUGHNESS = mix(ROUGHNESS, min(ROUGHNESS, 0.8), damp);
	}
}
