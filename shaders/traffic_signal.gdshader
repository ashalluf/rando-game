shader_type spatial;
render_mode cull_back;

// The lenses of every traffic signal and pedestrian head (tools/make_signals.py, placed by
// CityChunk._add_signal_corner()). Nothing ticks per signal: each head is a MultiMesh instance
// whose INSTANCE_CUSTOM carries its intersection's offset into the shared cycle (r, a fraction
// of it) and the axis it serves (g: the road axis whose traffic a vehicle head controls, or the
// road a pedestrian head's crosswalk crosses), and the lamp is worked out here from the
// `signal_clock` global - the same sum TrafficSignals does for the cars and the crowd, from the
// same four numbers (`timing`, pushed from TrafficSignals by PropFactory.signal_lens_material()).
//
// Which lamp a fragment belongs to is in UV2.x ((id + 0.5) / 8: 0 red, 1 amber, 2 green, 3 the
// pedestrian glyph, 4 the countdown); UV is that lamp's own 0..1 square, top left at (0, 0).
// Lit lamps are LED arrays: HDR emission broken into dots (faded to their average once a dot is
// under a pixel), dimmer off-axis the way a real LED signal is. Unlit ones are dark tinted glass.
// The walking figure, the raised hand and the countdown digits are drawn from distance fields.

global uniform float signal_clock;
// Green, amber, all-red and walk seconds (TrafficSignals.GREEN, AMBER, ALL_RED, WALK_TIME).
uniform vec4 timing = vec4(16.0, 3.5, 1.5, 7.0);
// HDR brightness of a lit vehicle lamp and of a lit pedestrian glyph.
uniform float energy = 3.2;
uniform float ped_energy = 2.4;
// LED dots across a lens, and their pitch on the pedestrian panel (in glyph units).
uniform float dots = 15.0;
uniform float ped_pitch = 0.075;

varying flat vec4 v_custom;

void vertex() {
	v_custom = INSTANCE_CUSTOM;
}

float sd_capsule(vec2 p, vec2 a, vec2 b, float r) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h) - r;
}

float sd_rbox(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// A figure in mid stride, facing right. Glyph units: y -1..1 up the panel, x at the same scale.
float sd_walker(vec2 p) {
	float d = length(p - vec2(0.05, 0.71)) - 0.135;
	d = min(d, sd_capsule(p, vec2(0.01, 0.47), vec2(-0.03, -0.01), 0.1));
	d = min(d, sd_capsule(p, vec2(0.02, 0.41), vec2(0.17, 0.16), 0.048));
	d = min(d, sd_capsule(p, vec2(0.17, 0.16), vec2(0.27, -0.05), 0.044));
	d = min(d, sd_capsule(p, vec2(-0.01, 0.41), vec2(-0.17, 0.17), 0.048));
	d = min(d, sd_capsule(p, vec2(-0.17, 0.17), vec2(-0.29, 0.0), 0.044));
	d = min(d, sd_capsule(p, vec2(-0.03, -0.02), vec2(0.13, -0.43), 0.068));
	d = min(d, sd_capsule(p, vec2(0.13, -0.43), vec2(0.22, -0.84), 0.062));
	d = min(d, sd_capsule(p, vec2(0.22, -0.86), vec2(0.34, -0.87), 0.04));
	d = min(d, sd_capsule(p, vec2(-0.03, -0.02), vec2(-0.15, -0.44), 0.068));
	d = min(d, sd_capsule(p, vec2(-0.15, -0.44), vec2(-0.33, -0.79), 0.062));
	return d;
}

// An open hand raised palm out: four fingers, a thumb, a cuff.
float sd_hand(vec2 p) {
	float d = sd_rbox(p - vec2(0.02, -0.1), vec2(0.24, 0.25), 0.09);
	d = min(d, sd_capsule(p, vec2(-0.16, 0.08), vec2(-0.17, 0.46), 0.052));
	d = min(d, sd_capsule(p, vec2(-0.04, 0.1), vec2(-0.04, 0.6), 0.054));
	d = min(d, sd_capsule(p, vec2(0.08, 0.1), vec2(0.09, 0.57), 0.054));
	d = min(d, sd_capsule(p, vec2(0.19, 0.06), vec2(0.21, 0.42), 0.05));
	d = min(d, sd_capsule(p, vec2(-0.2, -0.18), vec2(-0.37, 0.1), 0.058));
	d = min(d, sd_capsule(p, vec2(0.02, -0.38), vec2(0.02, -0.74), 0.16));
	return d;
}

int seg_mask(int n) {
	if (n == 0) return 63;
	if (n == 1) return 6;
	if (n == 2) return 91;
	if (n == 3) return 79;
	if (n == 4) return 102;
	if (n == 5) return 109;
	if (n == 6) return 125;
	if (n == 7) return 7;
	if (n == 8) return 127;
	return 111;
}

// One seven-segment digit centred at `c`: distance to its lit segments.
float sd_digit(vec2 p, vec2 c, int n) {
	float hw = 0.15;
	float hh = 0.46;
	float in_ = 0.05;
	float r = 0.042;
	int m = seg_mask(n);
	vec2 q = p - c;
	float d = 1.0e3;
	if ((m & 1) != 0) d = min(d, sd_capsule(q, vec2(-hw + in_, hh), vec2(hw - in_, hh), r));
	if ((m & 2) != 0) d = min(d, sd_capsule(q, vec2(hw, hh - in_), vec2(hw, in_), r));
	if ((m & 4) != 0) d = min(d, sd_capsule(q, vec2(hw, -in_), vec2(hw, -hh + in_), r));
	if ((m & 8) != 0) d = min(d, sd_capsule(q, vec2(-hw + in_, -hh), vec2(hw - in_, -hh), r));
	if ((m & 16) != 0) d = min(d, sd_capsule(q, vec2(-hw, -in_), vec2(-hw, -hh + in_), r));
	if ((m & 32) != 0) d = min(d, sd_capsule(q, vec2(-hw, hh - in_), vec2(-hw, in_), r));
	if ((m & 64) != 0) d = min(d, sd_capsule(q, vec2(-hw + in_, 0.0), vec2(hw - in_, 0.0), r));
	return d;
}

// Coverage of a distance field with a one-pixel soft edge.
float fill(float d) {
	float w = max(fwidth(d), 1.0e-4);
	return clamp(0.5 - d / w, 0.0, 1.0);
}

// LED dots at `pitch`, faded to their average brightness once a dot is under a pixel or two.
float led(vec2 p, float pitch) {
	vec2 q = p / pitch;
	vec2 f = fract(q) - 0.5;
	float spot = smoothstep(0.5, 0.2, length(f));
	float px = length(fwidth(q));
	return mix(0.35 + 0.65 * spot, 0.62, smoothstep(0.3, 0.9, px));
}

void fragment() {
	int id = int(floor(UV2.x * 8.0));
	float half_cycle = timing.x + timing.y + timing.z;
	float cycle = half_cycle * 2.0;
	float t = mod(signal_clock + v_custom.r * cycle, cycle);
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float beam = mix(0.35, 1.0, smoothstep(0.1, 0.8, facing));
	vec3 glass = vec3(0.012);
	vec3 glow = vec3(0.0);
	if (id <= 2) {
		// A vehicle lamp: this axis' time into its own half of the cycle.
		float ta = mod(t - v_custom.g * half_cycle, cycle);
		float lit = 0.0;
		vec3 col = vec3(1.0, 0.06, 0.02);
		vec3 tint = vec3(0.07, 0.008, 0.006);
		if (id == 0) {
			lit = step(timing.x + timing.y, ta);
		} else if (id == 1) {
			lit = step(timing.x, ta) * (1.0 - step(timing.x + timing.y, ta));
			col = vec3(1.0, 0.4, 0.02);
			tint = vec3(0.07, 0.04, 0.004);
		} else {
			lit = 1.0 - step(timing.x, ta);
			col = vec3(0.04, 1.0, 0.52);
			tint = vec3(0.004, 0.05, 0.035);
		}
		vec2 p = UV - 0.5;
		float edge = smoothstep(0.5, 0.42, length(p));
		glass = tint;
		glow = col * energy * lit * led(p, 1.0 / dots) * edge * beam;
	} else {
		// A pedestrian panel: they walk with the traffic running beside them, the other axis.
		float tw = mod(t - (1.0 - v_custom.g) * half_cycle, cycle);
		bool walk = tw < timing.w;
		bool flash = !walk && tw < timing.x;
		// Glyph units: y -1..1 up the panel, x at the same scale (the panel is 0.188 x 0.38 m).
		vec2 p = vec2((UV.x - 0.5) * 0.99, 0.5 - UV.y) * 2.0;
		vec3 white = vec3(0.92, 0.96, 1.0);
		vec3 orange = vec3(1.0, 0.36, 0.05);
		if (id == 3) {
			float man = fill(sd_walker(p * vec2(1.0, 1.02)));
			float hand = fill(sd_hand(p * 1.35 - vec2(0.0, -0.05)));
			float blink = step(fract(tw - timing.w), 0.5);
			float hand_on = walk ? 0.0 : (flash ? blink : 1.0);
			float lamp = led(p, ped_pitch);
			glow = (white * man * (walk ? 1.0 : 0.0) + orange * hand * hand_on) * ped_energy * lamp * beam;
			// The unlit glyphs show faintly through the lens, as they do on a real head.
			glass = vec3(0.012) + vec3(0.02, 0.018, 0.016) * max(man, hand);
		} else {
			// Countdown to the end of the flashing hand, while there is one to count.
			float left = timing.x - tw;
			if (walk || flash) {
				int n = int(ceil(left));
				int tens = n / 10;
				int ones = n - tens * 10;
				float d = sd_digit(p, vec2(0.21, 0.0), ones);
				if (tens > 0) {
					d = min(d, sd_digit(p, vec2(-0.21, 0.0), tens));
				}
				glow = orange * ped_energy * fill(d) * led(p, ped_pitch) * beam;
			}
		}
	}
	ALBEDO = glass;
	ROUGHNESS = 0.12;
	SPECULAR = 0.6;
	EMISSION = glow;
}
