shader_type spatial;
render_mode cull_back;

// Road paint: lane dashes, centre lines, crosswalk bars, stop lines, arrows and parking stalls.
// They were flat boxes of perfect white and yellow, and nothing says "computer graphics" in a
// street shot faster than a crosswalk that looks freshly printed on. Real paint is worn through
// in patches where the tyres run, carries road grit, and goes dark toward the worn edges. All of
// it is generated from world position, so no two stripes wear alike and nothing tiles.
// The paint colour is the instance colour (white or yellow) times `paint`, as it was before.

uniform vec3 paint : source_color = vec3(0.95, 0.95, 0.92);
// How much of the paint is worn through to the asphalt (0 = pristine).
uniform float wear = 0.18;
// Metres across a typical worn patch.
uniform float wear_scale = 0.45;
// Road grit and grime in the paint (0 = clean).
uniform float grime = 0.34;
// What thinned-out paint fades toward before it wears through: the asphalt showing under it.
uniform vec3 asphalt : source_color = vec3(0.30, 0.30, 0.31);

global uniform float road_wetness;

varying vec3 world_pos;
// Only with it on does the street dry unevenly (road.gdshader); off, everything dries evenly.
global uniform float ground_detail;

#include "res://shaders/wet_drying.gdshaderinc"
#include "res://shaders/specular_aa.gdshaderinc"

// Thin-line AA (specular-aliasing pass): a marking whose width or length comes to under
// `min_px` pixels on screen (a 10 cm centre line 40 m off, a stop line seen edge on) is widened
// in the vertex shader to `min_px` and its paint mixed toward the asphalt by the share it really
// covers (`paint_cover`), so it stays a steady faint line instead of breaking into dashes that
// crawl as the camera moves. Measured in projected pixels, so foreshortening counts.
uniform float min_px = 1.2;
varying float paint_cover;


float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}


float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}


float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 3; i++) {
		v += amp * value_noise(p);
		p *= 2.1;
		amp *= 0.5;
	}
	return v;
}


// How proud of the road the paint stands (m). The markings are boxes 1-2 cm tall centred on
// their height, whose lit sides read as plastic strips laid on the road at a pedestrian's eye;
// thermoplastic is 2-4 mm. 0 keeps the box as it is (StreetCloseup's A/B). Every box vertex over
// the centre is moved down to the box's underside plus this, so any box height works.
uniform float thickness = 0.0;

void vertex() {
	if (thickness > 0.0 && VERTEX.y > 0.0) {
		VERTEX.y = -VERTEX.y + thickness;
	}
	paint_cover = 1.0;
	if (saa_on()) {
		vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		mat4 vpm = PROJECTION_MATRIX * VIEW_MATRIX;
		// VIEWPORT_SIZE can read 0 in a vertex stage (CLAUDE.md, the far shader's masts).
		vec2 vps = VIEWPORT_SIZE.y > 2.0 ? VIEWPORT_SIZE : vec2(1920.0, 1080.0);
		vec4 c0 = vpm * vec4(wp, 1.0);
		if (c0.w > 0.05) {
			for (int a = 0; a < 3; a += 2) {
				float hl = VERTEX[a];
				if (abs(hl) > 1.0e-4) {
					// The opposite edge of the marking across this axis, projected.
					vec4 c1 = vpm * vec4(wp - MODEL_MATRIX[a].xyz * (2.0 * hl), 1.0);
					if (c1.w > 0.05) {
						float px = length((c0.xy / c0.w - c1.xy / c1.w) * 0.5 * vps);
						if (px < min_px) {
							float k = min(min_px / max(px, 0.05), 6.0);
							VERTEX[a] *= k;
							paint_cover /= k;
						}
					}
				}
			}
		}
	}
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


void fragment() {
	vec2 w = world_pos.xz;
	float patches = fbm(w / wear_scale + 17.0);
	float grain = value_noise(w * 11.0);
	// Worn through: cut out, so the asphalt below shows. The box sits on the road, so its back
	// faces are culled and there is nothing behind a hole but the road itself.
	// Paint thins before it goes: a soft band where the asphalt shows through it, then a hole.
	// Cut straight to holes, the wear read as camouflage printed on the stripe.
	// The grain's 9 cm cells in the wear edge only crawl once they are under a couple of pixels.
	float grain_keep = saa_on() ? 1.0 - smoothstep(0.03, 0.08, length(fwidth(w))) : 1.0;
	float v = patches + grain * 0.22 * grain_keep + 0.11 * (1.0 - grain_keep);
	float edge = 0.78 - wear * 0.45;
	float thin = smoothstep(edge - 0.16, edge + 0.03, v);
	// Worn thermoplastic goes speckled before it goes: the stones in the asphalt poke through
	// it one by one. Blended to grey instead, the thinning read as smudges of dirt on the paint.
	// The specks are a couple of centimetres, so once they are smaller than a pixel they only
	// shimmer: past that the thinning falls back to the blend.
	float px = length(fwidth(w));
	float speck_ok = 1.0 - smoothstep(0.012, 0.03, px);
	float stones = 0.6 * value_noise(w * 48.0) + 0.4 * hash12(floor(w * 90.0));
	if (v > edge + 0.03 || stones < thin * 0.9 * speck_ok) {
		discard;
	}
	vec3 col = mix(paint * COLOR.rgb, asphalt, thin * mix(0.85, 0.3, speck_ok));
	// Dirt collects toward the worn patches, and grit speckles all of it.
	float dirty = smoothstep(0.35, 0.72 - wear * 0.45, patches);
	col *= mix(1.0, 0.72, dirty * grime * 2.0);
	col *= 1.0 - grime * 0.35 * grain;
	float wet = clamp(road_wetness, 0.0, 1.0);
	// Drying after the rain, in step with the tarmac under it (wet_drying.gdshaderinc).
	vec2 fd = vec2(wet);
	if (wet > 0.01 && ground_detail > 0.5 && road_drying > 0.0) {
		fd = wet_film_damp(wet, wet_hold_noise(world_pos.xz));
	}
	ALBEDO = col * mix(1.0, 0.85, fd.y);
	// Road paint is smoother than the tarmac around it, and wet it shines.
	ROUGHNESS = mix(0.66, 0.12, fd.x);
	if (paint_cover < 0.999) {
		// Widened past its real width: the asphalt's share of the pixel, at the asphalt's look.
		float c = clamp(paint_cover, 0.0, 1.0);
		ALBEDO = mix(asphalt * mix(1.0, 0.62, fd.y), ALBEDO, c);
		ROUGHNESS = mix(mix(0.85, 0.07, fd.x), ROUGHNESS, c);
	}
	SPECULAR = 0.5;
}
