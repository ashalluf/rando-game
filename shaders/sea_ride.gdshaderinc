// The ocean's open-water swell height, for anything that rides it (OceanTraffic's vessels, through
// boat.gdshader's `ride`). It is ocean.gdshader's vertex stage reduced to the vertical: the same
// five Gerstner waves, the same wave groups (the same hash and value noise), the same fine-wave
// fade by camera distance and the tsunami, all off shader TIME - so a boat heaves, pitches and
// rolls in phase with the very water drawn round it, which GDScript cannot do (it has no copy of
// TIME). No shoaling and no surf: the traffic keeps well offshore. The horizontal lean is left
// out (a few tens of centimetres of drift, a hundredth of a wave's phase).
//
// The numbers are ocean.gdshader's uniform defaults, copied (nothing sets them at run time);
// tests/ocean_traffic_checks.gd holds the copies to the originals and OceanTraffic.sea_height()
// to this file.
//
// Needs: global uniform float wave_scale, tsunami_scale (declared here).

global uniform float wave_scale;
global uniform float tsunami_scale;

const float SR_BASE_HEIGHT = 1.2;
const float SR_SWELL_LENGTH = 97.0;
const float SR_GROUP_LENGTH = 310.0;
const float SR_GROUP_DEPTH = 0.55;
const float SR_SPEED = 1.0;
const vec2 SR_FINE_FADE = vec2(170.0, 480.0);
const float SR_TSUNAMI_HEIGHT = 30.0;
const float SR_TSUNAMI_LENGTH = 420.0;
const vec2 SR_TSUNAMI_DIR = vec2(1.0, 0.15);
// The water chunks' surface at rest (CityChunk._build_water()).
const float SR_SEA_LEVEL = 0.15;

float sr_hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float sr_vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = sr_hash12(i);
	float b = sr_hash12(i + vec2(1.0, 0.0));
	float c = sr_hash12(i + vec2(0.0, 1.0));
	float d = sr_hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float sr_wave(vec2 p, vec2 dir, float len, float amp, float t) {
	float k = 6.2831853 / len;
	float c = sqrt(9.8 / k);
	return amp * cos(k * (dot(dir, p) - c * t));
}

// Height of the swell over SR_SEA_LEVEL at true world `p`, at shader time `time`; `fine` is the
// ocean's fine-wave factor (1 near the camera, 0 past SR_FINE_FADE.y).
float sea_height(vec2 p, float time, float fine) {
	float t = time * SR_SPEED;
	float grp = sr_vnoise(p / SR_GROUP_LENGTH + vec2(t * 0.006, -t * 0.004));
	float group = 1.0 - SR_GROUP_DEPTH * (1.0 - grp);
	float amp = SR_BASE_HEIGHT * max(wave_scale, 0.05) * group;
	float l0 = SR_SWELL_LENGTH;
	float h = 0.0;
	h += sr_wave(p, normalize(vec2(1.00, 0.22)), l0, amp * 0.34, t);
	h += sr_wave(p, normalize(vec2(0.86, -0.51)), l0 / 1.59, amp * 0.26, t);
	h += sr_wave(p, normalize(vec2(0.62, 0.78)), l0 / 2.62, amp * 0.19 * mix(0.45, 1.0, fine), t);
	h += sr_wave(p, normalize(vec2(0.97, -0.24)), l0 / 4.51, amp * 0.13 * fine, t);
	h += sr_wave(p, normalize(vec2(0.34, 0.94)), l0 / 7.89, amp * 0.08 * fine * fine, t);
	if (tsunami_scale > 0.001) {
		h += sr_wave(p, normalize(SR_TSUNAMI_DIR), SR_TSUNAMI_LENGTH, SR_TSUNAMI_HEIGHT * tsunami_scale, t * 0.9);
	}
	return h;
}
