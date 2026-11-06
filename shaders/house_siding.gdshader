shader_type spatial;
render_mode cull_back;

// Painted timber cladding on the houses (HouseKit): what a craftsman bungalow, a ranch house's
// front and a mid-century accent wall are made of, where the rest of the city is stucco. Worked
// out from the UV - metres along the wall and metres up it (HouseKit._wall()) - so every board is
// its real size on any wall:
//   COLOR.a > 0.75   lap siding: horizontal boards 18 cm apart, each lapped over the one below,
//                    a dark shadow line under every lap
//   0.25 .. 0.75     board and batten: wide vertical boards with a raised batten over each joint
//   below 0.25       vertical tongue and groove, stained rather than painted (mid-century)
// COLOR.rgb is the paint (sRGB as written; vertex colours arrive raw on both renderers).

#include "res://shaders/color_space.gdshaderinc"

uniform float lap = 0.18;
uniform float batten_pitch = 0.40;
uniform float groove_pitch = 0.12;
// Paint grain, a dirt band at the foot of the wall, and the faint wood grain under the paint.
uniform float grain = 0.05;
uniform float foot_dirt = 0.14;


float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}


float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}


void fragment() {
	vec2 uv = UV;
	float mpp = max(length(dFdx(uv)), length(dFdy(uv)));
	vec3 base = cs_srgb_to_linear(COLOR.rgb);
	float mode = COLOR.a;
	float shade = 1.0;
	float nx = 0.0;
	float ny = 0.0;
	float rough = 0.7;
	if (mode > 0.75) {
		// Lap siding: each board tapers from its thick butt (bottom) to its thin top, under the
		// next board's butt, so it leans out and down; a shadow line under every butt.
		float f = fract(uv.y / lap);
		float det = 1.0 - smoothstep(lap * 0.15, lap * 0.4, mpp);
		float aa = clamp(mpp / lap, 0.02, 0.5);
		float line = 1.0 - smoothstep(0.0, 0.12 + aa, 1.0 - f);
		shade = 1.0 - 0.38 * line * det;
		ny = (-0.22 + 0.9 * (1.0 - smoothstep(0.0, 0.08, f))) * det;
		shade *= 1.0 + 0.04 * (h21(vec2(floor(uv.y / lap), floor(uv.x / 3.6))) - 0.5) * det;
	} else if (mode > 0.25) {
		// Board and batten.
		float f = fract(uv.x / batten_pitch);
		float det = 1.0 - smoothstep(batten_pitch * 0.12, batten_pitch * 0.35, mpp);
		float d = abs(f - 0.5) * batten_pitch;
		float bat = 1.0 - smoothstep(0.03, 0.036 + mpp, d);
		float side = smoothstep(0.03, 0.045 + mpp, d) * (1.0 - smoothstep(0.045, 0.075 + mpp, d));
		shade = 1.0 + (0.06 * bat - 0.22 * side) * det;
		nx = (f < 0.5 ? -1.0 : 1.0) * side * 0.6 * det;
	} else {
		// Tongue and groove, stained: each board its own tone, a dark groove between them.
		float f = fract(uv.x / groove_pitch);
		float id = floor(uv.x / groove_pitch);
		float det = 1.0 - smoothstep(groove_pitch * 0.12, groove_pitch * 0.4, mpp);
		float groove = 1.0 - smoothstep(0.0, 0.05 + mpp / groove_pitch, min(f, 1.0 - f));
		shade = (1.0 + 0.18 * (h21(vec2(id, 1.3)) - 0.5) * det) * (1.0 - 0.45 * groove * det);
		// The grain along the board.
		shade *= 1.0 + 0.10 * (vnoise(vec2(uv.x * 40.0, uv.y * 1.5)) - 0.5) * det;
		nx = (f < 0.5 ? 1.0 : -1.0) * groove * 0.5 * det;
		rough = 0.62;
	}
	float wood = 1.0 + grain * (vnoise(vec2(uv.x * 7.0, uv.y * 60.0)) - 0.5) * (1.0 - smoothstep(0.003, 0.01, mpp));
	// Splash dirt at the foot of the wall (the wall starts 0.6 m below the floor, under ground).
	float foot = 1.0 - foot_dirt * (1.0 - smoothstep(0.55, 1.1, uv.y));
	ALBEDO = cs_out(clamp(base * shade * wood * foot, vec3(0.0), vec3(1.0)));
	ROUGHNESS = rough;
	SPECULAR = 0.4;
	NORMAL_MAP = normalize(vec3(nx, ny, 1.0)) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;
}
