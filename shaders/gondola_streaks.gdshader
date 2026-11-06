shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, shadows_disabled;
// The water a window-washing cradle leaves on the glass (TowerGondolas / GondolaRig): one quad
// on the facade, a few centimetres off it, moved with the cradle, read in its own metres (local_m:
// x along the face from the cradle's centre, y up from the cradle's floor, negative below it).
//   above the cradle: the washed glass still wet - a thin film, glossier and a little darker than
//     the dry pane, drying unevenly upward, with runs where the squeegee's ends left water;
//   at the cradle: the soap on the pane they are working (`soap`, 0..1 by the stop's progress);
//   below it: drips running down the dry glass from the cradle's rollers and the squeegee strokes.
// Works in linear on both renderers (color_space.gdshaderinc). Shader files use // comments.

#include "res://shaders/color_space.gdshaderinc"

// Metres of washed glass above the floor (wet), the drips' reach below, the soap still on the pane.
uniform float wet_top = 6.0;
uniform float drip_len = 7.0;
uniform float soap = 0.0;
// Half the width washed (metres).
uniform float half_width = 2.4;
uniform float seed = 0.0;

// Metres in the quad's plane: x along the face from the cradle's centre, y up from its floor.
varying vec2 local_m;

void vertex() {
	local_m = VERTEX.xy;
}

float hash11(float x) {
	return fract(sin(x * 127.1 + seed * 31.7) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash11(i.x + i.y * 57.0);
	float b = hash11(i.x + 1.0 + i.y * 57.0);
	float c = hash11(i.x + (i.y + 1.0) * 57.0);
	float d = hash11(i.x + 1.0 + (i.y + 1.0) * 57.0);
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	float x = local_m.x;
	float y = local_m.y;
	float edge = 1.0 - smoothstep(half_width - 0.35, half_width, abs(x));
	// Runs: thin vertical lines in 3 cm columns, each its own strength, wavering a little.
	float colw = 0.035;
	float cx = x + 0.01 * sin(y * 3.1 + floor(x / 0.21));
	float ci = floor(cx / colw);
	float cf = fract(cx / colw);
	float line = smoothstep(0.5, 0.12, abs(cf - 0.5)) * step(0.72, hash11(ci));
	float alpha = 0.0;
	float film = 0.0;
	float foam = 0.0;
	if (y >= 0.0) {
		// The film thins and breaks up as it dries going up.
		float dry = smoothstep(wet_top * 0.35, wet_top, y + (vnoise(vec2(x * 1.3, y * 0.6)) - 0.5) * 2.0);
		film = (1.0 - dry) * smoothstep(-0.05, 0.4, y);
		float runs = line * (1.0 - smoothstep(0.0, wet_top * 1.2, y)) * 0.8;
		// The squeegee's ends leave a water line at the stroke edges, the band's own edges.
		float band_edge = smoothstep(0.25, 0.0, half_width - abs(x)) * (1.0 - dry);
		alpha = film * 0.16 + runs * 0.14 + band_edge * 0.16;
		// Soap on the pane at the cradle's working height: a thin wash of fine suds over the part
		// not yet squeegeed (the clean part grows across the band as the stop goes on, its edge
		// the S of the last stroke).
		float suds = vnoise(vec2(x * 22.0, y * 22.0)) * 0.6 + vnoise(vec2(x * 55.0, y * 55.0)) * 0.4;
		float band = smoothstep(0.45, 0.7, y) * (1.0 - smoothstep(2.0, 2.4, y));
		float done = (1.0 - soap) * 2.0 * half_width - half_width + 0.12 * sin(y * 5.0);
		float left = smoothstep(done - 0.04, done + 0.04, x);
		foam = band * step(0.001, soap) * left * (0.55 + 0.45 * smoothstep(0.25, 0.75, suds));
	} else {
		// Drips from the rollers and the strokes: a few columns, a drop running down each.
		float dc = floor(x / 0.09);
		float live = step(0.6, hash11(dc + 13.0));
		float speed = 0.35 + hash11(dc + 7.0) * 0.5;
		float d = fract(-y * 0.22 + TIME * speed * 0.18 + hash11(dc));
		float trail = smoothstep(0.22, 0.05, abs(fract(x / 0.09) - 0.5) * 2.0);
		float reach = 1.0 - smoothstep(0.0, drip_len * (0.4 + 0.6 * hash11(dc + 3.0)), -y);
		alpha = live * trail * reach * (0.06 + 0.3 * smoothstep(0.88, 1.0, d));
		film = alpha;
	}
	// Thin lines under a pixel only shimmer: gone by a hundred metres.
	float fade = 1.0 - smoothstep(45.0, 120.0, length(VERTEX));
	alpha *= edge * fade;
	foam *= edge * fade;
	// Wet glass: darker and glossier (the film mirrors the sky sharper); foam is white and matte.
	vec3 water = vec3(0.012, 0.016, 0.02);
	vec3 white = vec3(0.78, 0.80, 0.80);
	ALBEDO = cs_out(mix(water, white, clamp(foam * 1.4, 0.0, 1.0)));
	ROUGHNESS = mix(0.03, 0.75, clamp(foam * 1.4, 0.0, 1.0));
	METALLIC = 0.0;
	SPECULAR = 0.9;
	ALPHA = clamp(max(alpha, foam * 0.32), 0.0, 0.9);
}
