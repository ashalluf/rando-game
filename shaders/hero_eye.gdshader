shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// The hero's eyes (hero.glb, material hero_eyes; HeroLook puts it on, HeroFace drives it).
// The rig has no face bones, so the living face is done here:
//  - the gaze: each eyeball turns about its own centre (eye_l / eye_r: centre xyz in WORLD space,
//    radius in w; the skinned VERTEX's space differs between the renderers' skinning paths, the
//    world does not) by its own rotation (rot_l / rot_r), so the eyes dart between
//    fixation points (saccades) and follow the camera's view
//  - the blink: there is no lid that closes, so the lid is drawn ON the eyeball - every fragment
//    above the upper lid's edge (and below the lower's), measured in the head's frame from the
//    eye's centre, is skin (lid_color), a dark lash line along the edge. The eyeball is hidden by
//    the face mesh everywhere outside the opening, so the painted lid shows only in the opening.
//    The upper lashes are swung down with it (hero_lash.gdshader, the same `blink`).
//  - the socket's shade: the upper lid and the brow shadow the top of the eyeball, and the
//    corners are darker than its middle (eye_shadow). Lit evenly, a CG eye stares.
// The rest is the glTF material's: the iris texture, a wet clear coat over the cornea.

#include "res://shaders/color_space.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 eye_l = vec4(0.03, 1.6887, 0.1335, 0.012);
uniform vec4 eye_r = vec4(-0.03, 1.6887, 0.1335, 0.012);
// Head frame in world space (columns: right, up, forward), from HeroFace.
uniform mat3 head_basis = mat3(1.0);
uniform mat3 rot_l = mat3(1.0);
uniform mat3 rot_r = mat3(1.0);
// 0 open .. 1 shut.
uniform float blink = 0.0;
// The upper lid raised (negative, radii) when the eyes look up.
uniform float lid_lift = 0.0;
// The lids' edges in eye radii from the centre, along the head's up: open and shut.
uniform vec2 upper_lid = vec2(0.62, -0.26);
uniform vec2 lower_lid = vec2(-0.85, -0.3);
// Linear albedo of the lid's skin.
uniform vec3 lid_color = vec3(0.25, 0.135, 0.095);
uniform float eye_shadow = 0.55;
uniform float roughness = 0.3;

varying vec3 head_local; // the fragment relative to its eye's centre, head frame, in radii

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	bool left = distance(w, eye_l.xyz) < distance(w, eye_r.xyz);
	vec4 e = left ? eye_l : eye_r;
	mat3 r = left ? rot_l : rot_r;
	vec3 o = r * (w - e.xyz);
	VERTEX = (inverse(MODEL_MATRIX) * vec4(e.xyz + o, 1.0)).xyz;
	mat3 m = mat3(MODEL_MATRIX);
	NORMAL = normalize(inverse(m) * (r * (m * NORMAL)));
	head_local = (transpose(head_basis) * o) / e.w;
}

void fragment() {
	vec3 alb = cs_in(texture(albedo_tex, UV).rgb); // linear on both renderers
	// The atlas' blue swatch (bottom right) lands on the tear line under the iris and drew a blue
	// band along every lower lid: it is the wet, pink waterline.
	float blue = smoothstep(0.04, 0.12, alb.b - alb.r);
	alb = mix(alb, vec3(0.30, 0.15, 0.13), blue);
	float up = head_local.y;
	float pw = fwidth(up) + 0.02;
	float top = mix(upper_lid.x - lid_lift, upper_lid.y, blink);
	float bottom = mix(lower_lid.x, lower_lid.y, blink);
	// 1 where the lid covers the eyeball.
	float lid = max(smoothstep(top - pw, top + pw, up), 1.0 - smoothstep(bottom - pw, bottom + pw, up));
	// The lash line along the upper lid's edge, and the lid's own shade on the eyeball under it.
	float lash = exp(-pow((up - top) / 0.09, 2.0)) * (1.0 - lid);
	float shade = mix(1.0, 1.0 - eye_shadow, smoothstep(top - 0.75, top, up));
	// The corners (far from the eye's forward axis sideways) are in the socket's shade.
	shade *= mix(1.0, 0.72, smoothstep(0.35, 0.95, abs(head_local.x)));
	vec3 col = alb * shade * (1.0 - 0.75 * lash);
	ALBEDO = cs_out(mix(col, lid_color, lid));
	ROUGHNESS = mix(roughness, 0.62, lid);
	SPECULAR = mix(0.5, 0.35, lid);
	// The wet cornea; none on the lid's skin, less in the shade of the upper lid.
	CLEARCOAT = (1.0 - lid) * mix(1.0, 0.45, 1.0 - shade);
	CLEARCOAT_ROUGHNESS = 0.03;
}
