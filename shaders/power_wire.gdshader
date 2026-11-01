shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, skip_vertex_transform;

// Every wire of the ridges (RidgeSystem): the transmission lines' conductors and earth wires, the
// masts' guys, and the far tier's lattice - every tower's, mast's and gantry's members drawn again
// as fine lines. One mesh, one draw, for the whole basin.
//
// A wire is a ribbon whose four corners sit on its centre line; the vertex shader turns it to the
// camera and makes it at least `min_px` pixels wide, and the fragment shader draws its true
// thickness as coverage (alpha = radius / half width): a 28 mm conductor 300 m away is a faint
// line, as in life, and never a stair of aliased pixels. It is lit as a cylinder (Kajiya-Kay: the
// highlight runs along the wire where the half vector is square to it), so a span far off flashes
// where it catches the sun, which is how power lines read across a valley.
//   VERTEX  a point on the centre line
//   NORMAL  the wire's tangent there
//   UV      x: -1 / +1 the side of the ribbon; y: kind (0 galvanised steel, 1 conductor, 2 paint)
//   UV2     x: radius, metres; y: the far id + 1 (0: never hidden). An id whose texel in `covered`
//           is set is collapsed: a FULL chunk has built that tower in detail.
//   COLOR   rgb, sRGB as written (vertex colours arrive raw on both renderers)

#include "res://shaders/color_space.gdshaderinc"

uniform sampler2D covered : filter_nearest, repeat_disable;
uniform int covered_width = 1;
// The viewport's height in pixels, set by RidgeSystem every frame: VIEWPORT_SIZE does not reach
// this vertex stage (it read 1 here, which drew every wire metres wide and all but transparent).
uniform vec2 viewport_px = vec2(1920.0, 1080.0);
// The narrowest a wire is drawn, in pixels.
uniform float min_px = 1.0;
// The glint: a cylinder mirrors the sun on the cone of directions with T.V = -T.L, so the highlight
// is exp(-(T.H)^2 * shine) - a narrow band along the wire where the eye is on that cone. Too broad
// and every wire glows as bright as the sky; the glint is only where the geometry puts it.
uniform float shine = 900.0;
uniform float spec_gain = 2.5;
// Beyond this a wire fades out with the distance (its share of a pixel is noise by then).
uniform float fade_start = 2500.0;
uniform float fade_end = 7000.0;

varying vec3 v_t;
varying vec3 v_side;
varying float v_u;
varying float v_cov;
varying float v_kind;
varying vec3 v_col;

void vertex() {
	float id = UV2.y;
	float hidden = 0.0;
	if (id > 0.5) {
		int i = int(id + 0.5) - 1;
		hidden = texelFetch(covered, ivec2(i % covered_width, i / covered_width), 0).r;
	}
	vec3 c = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 t = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 v = normalize(-c);
	vec3 side = cross(t, v);
	float sl = length(side);
	side = sl > 1e-5 ? side / sl : vec3(1.0, 0.0, 0.0);
	float depth = max(-c.z, 0.05);
	// Metres a pixel spans here, across the wire: project a metre along `side` and measure it.
	vec4 p0 = PROJECTION_MATRIX * vec4(c, 1.0);
	vec4 p1 = PROJECTION_MATRIX * vec4(c + side, 1.0);
	vec2 d_px = (p1.xy / p1.w - p0.xy / p0.w) * 0.5 * max(viewport_px, vec2(64.0));
	float px = 1.0 / max(length(d_px), 1e-4);
	float r = UV2.x;
	float w = max(r, px * min_px * 0.5);
	v_cov = clamp(r / w, 0.0, 1.0) * (1.0 - smoothstep(fade_start, fade_end, depth));
	if (hidden > 0.5) {
		w = 0.0;
		v_cov = 0.0;
	}
	VERTEX = c + side * w * UV.x;
	NORMAL = v;
	v_t = t;
	v_side = side;
	v_u = UV.x;
	v_kind = UV.y;
	v_col = cs_srgb_to_linear(COLOR.rgb);
}

void fragment() {
	if (v_cov < 0.003) {
		discard;
	}
	vec3 v = normalize(-VERTEX);
	vec3 t = normalize(v_t);
	vec3 nv = v - t * dot(v, t);
	nv = length(nv) > 1e-4 ? normalize(nv) : v;
	float u = clamp(v_u, -1.0, 1.0);
	NORMAL = normalize(normalize(v_side) * u + nv * sqrt(max(1.0 - u * u, 0.0)));
	ALBEDO = cs_out(v_col);
	METALLIC = v_kind > 1.5 ? 0.0 : 0.45;
	ROUGHNESS = v_kind > 0.5 && v_kind < 1.5 ? 0.42 : 0.55;
	ALPHA = v_cov;
}

void light() {
	vec3 t = normalize(v_t);
	float tl = dot(t, LIGHT);
	// Diffuse averaged round the cylinder: what a wire narrower than a pixel shows.
	float d = sqrt(max(1.0 - tl * tl, 0.0)) * 0.64;
	DIFFUSE_LIGHT += d * ATTENUATION * LIGHT_COLOR / PI;
	vec3 h = normalize(LIGHT + VIEW);
	float th = dot(t, h);
	float s = exp(-th * th * (v_kind > 0.5 && v_kind < 1.5 ? shine : shine * 0.4));
	vec3 tint = v_kind > 1.5 ? vec3(0.04) : mix(vec3(0.5), v_col * 1.4, 0.4);
	SPECULAR_LIGHT += s * spec_gain * tint * ATTENUATION * LIGHT_COLOR / PI * step(0.0, dot(LIGHT, NORMAL) + 0.6);
}
