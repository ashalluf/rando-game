shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

// Ocean: Gerstner waves in the vertex shader (three swells plus one long tsunami-scale wave),
// foam on the crests, fresnel toward the horizon. Runs on the web renderer too (no depth or
// screen textures). wave_scale is a shader global the Weather node drives (1 calm, 6 storm);
// tsunami_scale is a second global for the big one (0 off, 1 a 30 m wall).
global uniform float wave_scale;
global uniform float tsunami_scale;
uniform vec3 deep_color : source_color = vec3(0.02, 0.12, 0.22);
uniform vec3 shallow_color : source_color = vec3(0.08, 0.36, 0.42);
uniform vec3 foam_color : source_color = vec3(0.92, 0.96, 0.98);
uniform float base_height = 1.2;
uniform float tsunami_height = 30.0;
uniform float tsunami_length = 420.0;
uniform vec2 tsunami_dir = vec2(1.0, 0.15);
uniform float speed = 1.0;

varying float crest;
varying vec3 world_pos;


// One Gerstner wave: moves the vertex in place, returns the height it added.
vec3 gerstner(vec2 p, vec2 dir, float length, float amp, float steep, float t, inout float h_sum) {
	float k = 6.28318 / length;
	float c = sqrt(9.8 / k);
	float f = k * (dot(dir, p) - c * t);
	float a = amp;
	float q = steep / (k * a + 0.001);
	h_sum += a * cos(f);
	return vec3(q * a * dir.x * sin(f) * -1.0, a * cos(f), q * a * dir.y * sin(f) * -1.0);
}


void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 p = wp.xz;
	float t = TIME * speed;
	float amp = base_height * max(wave_scale, 0.05);
	float h = 0.0;
	vec3 d = vec3(0.0);
	d += gerstner(p, normalize(vec2(1.0, 0.3)), 38.0, amp * 0.55, 0.35, t, h);
	d += gerstner(p, normalize(vec2(0.7, -0.6)), 23.0, amp * 0.3, 0.3, t, h);
	d += gerstner(p, normalize(vec2(-0.2, 1.0)), 11.0, amp * 0.15, 0.25, t, h);
	if (tsunami_scale > 0.001) {
		d += gerstner(p, normalize(tsunami_dir), tsunami_length, tsunami_height * tsunami_scale, 0.6, t * 0.9, h);
	}
	VERTEX += d;
	crest = clamp(h / max(amp + tsunami_height * tsunami_scale * 0.6, 0.2), -1.0, 1.0);
	world_pos = wp + d;
}


void fragment() {
	vec3 n = normalize(NORMAL);
	float fres = pow(1.0 - clamp(dot(n, VIEW), 0.0, 1.0), 3.0);
	vec3 col = mix(deep_color, shallow_color, 0.5 + 0.5 * crest);
	float foam = smoothstep(0.55, 0.9, crest) * (0.6 + 0.4 * wave_scale / 6.0);
	// Ripple detail: two moving noise-ish sines so calm water is not flat-shaded.
	float rip = sin(world_pos.x * 1.7 + TIME * 1.3) * sin(world_pos.z * 1.3 - TIME * 0.9);
	foam += 0.08 * smoothstep(0.6, 1.0, rip) * wave_scale;
	col = mix(col, foam_color, clamp(foam, 0.0, 1.0));
	ALBEDO = col;
	ROUGHNESS = mix(0.12, 0.6, clamp(foam, 0.0, 1.0));
	METALLIC = 0.0;
	SPECULAR = 0.7 + 0.3 * fres;
	NORMAL_MAP = vec3(0.5 + 0.08 * sin(world_pos.x * 2.1 + TIME * 1.7), 0.5 + 0.08 * cos(world_pos.z * 1.9 - TIME * 1.2), 1.0);
	NORMAL_MAP_DEPTH = 0.4;
}
