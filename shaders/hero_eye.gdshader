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
// hero-closeup-2 (HERO_CLOSEUP_2=0 sets 0): the eye as a wet organ - the tear meniscus, a thin
// bright line of water along the lower lid; the pink caruncle and a warmer, veined white in the
// inner corners; the white glossier (a film of tears), the cornea's coat sharper.
uniform float closeup2 = 0.0;
uniform float meniscus = 1.0;
// Linear colour of the caruncle and of the white's warm corners.
uniform vec3 caruncle_color = vec3(0.42, 0.16, 0.14);
uniform vec3 sclera_warm = vec3(0.62, 0.40, 0.34);

varying vec3 head_local; // the fragment relative to its eye's centre, head frame, in radii
varying float eye_side; // +1 the left eye, -1 the right: which way along x the nose is

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
	eye_side = left ? 1.0 : -1.0;
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
	// hero-closeup-2: toward the nose (inner) the caruncle, the whites warm and veined toward
	// both corners, the tear meniscus on the lower lid's edge.
	float inner = smoothstep(0.55, 0.92, -head_local.x * eye_side) * closeup2;
	float corner = smoothstep(0.42, 0.9, abs(head_local.x)) * closeup2;
	float white = smoothstep(0.35, 0.6, dot(alb, vec3(0.33)));
	float vein = pow(abs(sin(head_local.x * 41.0 + sin(head_local.y * 23.0) * 1.6)), 30.0) * 0.6;
	alb = mix(alb, sclera_warm * dot(alb, vec3(0.33)) / 0.55, white * corner * (0.45 + vein));
	alb = mix(alb, caruncle_color, inner * 0.85);
	float men = exp(-pow((up - bottom - 0.07) / 0.045, 2.0)) * (1.0 - lid) * meniscus * closeup2;
	vec3 col = alb * shade * (1.0 - 0.75 * lash);
	col = mix(col, col * 0.7 + vec3(0.06), men);
	ALBEDO = cs_out(mix(col, lid_color, lid));
	ROUGHNESS = mix(mix(roughness, 0.16, closeup2 * white), 0.62, lid);
	ROUGHNESS = mix(ROUGHNESS, 0.04, men);
	SPECULAR = mix(mix(0.5, 0.6, closeup2), 0.35, lid);
	SPECULAR = mix(SPECULAR, 0.9, men);
	// The wet cornea; none on the lid's skin, less in the shade of the upper lid.
	CLEARCOAT = max((1.0 - lid) * mix(1.0, mix(0.45, 0.7, closeup2), 1.0 - shade), men);
	CLEARCOAT_ROUGHNESS = mix(0.03, 0.015, closeup2);
}
