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
uniform float wear = 0.22;
// Metres across a typical worn patch.
uniform float wear_scale = 0.9;
// Road grit and grime in the paint (0 = clean).
uniform float grime = 0.28;

global uniform float road_wetness;

varying vec3 world_pos;


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


void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


void fragment() {
	vec2 w = world_pos.xz;
	float patches = fbm(w / wear_scale + 17.0);
	float grain = value_noise(w * 11.0);
	// Worn through: cut out, so the asphalt below shows. The box sits on the road, so its back
	// faces are culled and there is nothing behind a hole but the road itself.
	float through = smoothstep(0.72 - wear * 0.45, 0.80 - wear * 0.45, patches + grain * 0.18);
	if (through > 0.5) {
		discard;
	}
	vec3 col = paint * COLOR.rgb;
	// Dirt collects toward the worn patches, and grit speckles all of it.
	float dirty = smoothstep(0.35, 0.72 - wear * 0.45, patches);
	col *= mix(1.0, 0.72, dirty * grime * 2.0);
	col *= 1.0 - grime * 0.35 * grain;
	float wet = clamp(road_wetness, 0.0, 1.0);
	ALBEDO = col * mix(1.0, 0.85, wet);
	// Road paint is smoother than the tarmac around it, and wet it shines.
	ROUGHNESS = mix(0.66, 0.12, wet);
	SPECULAR = 0.5;
}
