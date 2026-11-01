shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// The red mist round a gunshot wound (WeaponFX._blood_mist_material()). It was a lit billboard,
// and a camera-facing card lit like a surface catches almost none of the sun: in a still at twelve
// metres it came out as a puff of dark grey-brown dust (96, 94, 87 against a 172, 159, 145 road),
// with no red in it at all. Unshaded like the fire and smoke, it follows the time of day itself
// through the night_factor global instead, so it reads as blood by day and does not glow at night.

global uniform float night_factor;

uniform sampler2D puff_tex : source_color, filter_linear_mipmap, repeat_disable;
// Fine blood droplets in the air scatter more light than blood lying on the ground: a lighter,
// redder colour than the splats', still dark enough not to read as paint.
uniform vec3 blood : source_color = vec3(0.46, 0.04, 0.03);
// Brightness at full night, against the day's 1.0.
uniform float night_level = 0.14;


void vertex() {
	// Particle billboard that keeps the particle's scale and spins it by its own angle, the same
	// transform StandardMaterial3D's BILLBOARD_PARTICLES + billboard_keep_scale builds (and the
	// one fire_puff.gdshader uses).
	mat4 world = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	float a = INSTANCE_CUSTOM.x;
	world = world * mat4(vec4(cos(a), -sin(a), 0.0, 0.0), vec4(sin(a), cos(a), 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * world;
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}


void fragment() {
	vec4 tex = texture(puff_tex, UV);
	// The billow's own shade gives each puff darker and lighter lumps.
	float light = mix(1.0, night_level, clamp(night_factor, 0.0, 1.0));
	ALBEDO = blood * COLOR.rgb * mix(0.7, 1.15, tex.r) * light;
	ALPHA = COLOR.a * tex.a;
}
