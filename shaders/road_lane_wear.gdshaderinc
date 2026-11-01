// The dry wear a city street's traffic lays down lane by lane (ChaseCamReview, the chase_cam
// reference camera; docs/HANDOFF.md "The chase camera's street"). From behind the wheel the
// carriageway fills half the frame, and as one even sheet of tarmac it read as a painted floor.
// A real street is worn where cars run on it: two polished wheel tracks down each travel lane
// (darker, smoother: the sheen of rubber-polished aggregate), the oil and drip band between them
// - blotchy, heavier where cars queue at the end of the block -, and the parking lane and gutter
// pan dusty and grey with the grit the traffic throws to the kerb.
//
// The lanes are CityPlan.lane_center()'s (two a side on a street over 15 m, else one), found
// like the wet drying's: the slab UV runs 0..1 across its rect, so its width in metres is the
// ratio of the plan position's screen derivatives to the UV's. Only a long street slab counts
// (run > 1.8 x width); a junction square, a skirt or a replica piece gets nothing.
//
// Needs: plan_pos (plan xz), slab_uv, lamp_axis, value_noise(), CITY_PARKING_LANE. Call it in
// uniform control flow (it takes derivatives). Returns (albedo multiplier, roughness multiplier,
// roughness floor mix, unused); lane_wear 0 returns (1, 1, 0, 0): a material that never sets it
// draws exactly as before.

uniform float lane_wear = 0.0;
// Wheel tracks: how much darker, how much smoother, their half width (m) and spacing from the
// lane's middle (m, half a car's track).
uniform float lw_track_dark = 0.08;
uniform float lw_track_polish = 0.1;
uniform float lw_track_half = 0.34;
uniform float lw_track_offset = 0.82;
// The oil band down a lane's middle: darker by, half width (m), and how much worse it gets over
// the last `lw_queue_run` metres before the block's end (cars standing at the light).
uniform float lw_oil_dark = 0.16;
uniform float lw_oil_half = 0.32;
uniform float lw_queue_run = 28.0;
// The parking lane and gutter: dust (lighter, rougher) and the gutter pan's dirt line.
uniform float lw_kerb_dust = 0.1;
uniform float lw_gutter_dark = 0.16;

vec4 road_lane_wear(vec2 pp, vec2 suv, int axis_mode, float seed_v) {
	if (lane_wear <= 0.0 || axis_mode <= 0) {
		return vec4(1.0, 1.0, 0.0, 0.0);
	}
	float across_p = axis_mode == 1 ? pp.x : pp.y;
	float along_p = axis_mode == 1 ? pp.y : pp.x;
	float across_uv = axis_mode == 1 ? suv.x : suv.y;
	float along_uv = axis_mode == 1 ? suv.y : suv.x;
	float width = length(vec2(dFdx(across_p), dFdy(across_p))) / max(length(vec2(dFdx(across_uv), dFdy(across_uv))), 1.0e-7);
	float run = length(vec2(dFdx(along_p), dFdy(along_p))) / max(length(vec2(dFdx(along_uv), dFdy(along_uv))), 1.0e-7);
	// Metres a pixel: features under about two pixels fade to their average (no crawl).
	float px = length(vec2(length(vec2(dFdx(across_p), dFdy(across_p))), length(vec2(dFdx(along_p), dFdy(along_p))))) * 0.7071;
	if (!(width > 5.0 && width < 60.0 && run > 1.8 * width)) {
		return vec4(1.0, 1.0, 0.0, 0.0);
	}
	float a = clamp(across_uv, 0.0, 1.0) * width;
	float half_w = width * 0.5;
	float from_centre = abs(a - half_w);
	float kerb = half_w - from_centre;
	float travel = half_w - CITY_PARKING_LANE - 0.2;
	float dark = 0.0;
	float polish = 0.0;
	float dust = 0.0;
	// Along the block: 0 at its start, 1 at its end, whichever way the lane runs; the queue end is
	// the far end for traffic on the +across side, the near end for the other (right-hand traffic:
	// a lane's direction is which side of the crown it is on).
	float s = clamp(along_uv, 0.0, 1.0) * run;
	float positive_side = step(half_w, a);
	// (UV taken to rise with the plan coordinate.) A road along z (axis 1): the +x side drives -z.
	// A road along x (axis 2): the +z side drives +x.
	float to_end = axis_mode == 1 ? mix(run - s, s, positive_side) : mix(s, run - s, positive_side);
	float queue = 1.0 - smoothstep(4.0, lw_queue_run, to_end);
	if (from_centre < travel) {
		float lanes = width > 15.0 ? 2.0 : 1.0;
		float lane_w = travel / lanes;
		float lane_id = floor(from_centre / lane_w) + positive_side * 7.0;
		// A lane's wear wanders a little and comes and goes in stretches.
		float wander = 0.3 * (value_noise(vec2(along_p * 0.025, lane_id * 3.1 + seed_v)) - 0.5);
		float o = (fract(from_centre / lane_w) - 0.5) * lane_w + wander;
		float stretch = 0.25 + 0.75 * smoothstep(0.2, 0.75, value_noise(vec2(along_p * 0.05 + 11.0, lane_id * 5.7 + seed_v)));
		// Each track a soft band with a ragged edge (aggregate polished more or less).
		float edge_n = value_noise(vec2(along_p * 1.3, a * 2.1 + seed_v)) - 0.5;
		float tw = lw_track_half * (1.0 + 0.35 * edge_n) + px;
		float track = 1.0 - smoothstep(tw * 0.35, tw, abs(abs(o) - lw_track_offset));
		track *= stretch;
		// The oil band: drips in blotches along the lane's middle, thicker in the queue.
		float drip = smoothstep(0.35, 0.8, value_noise(vec2(along_p * 0.55 + lane_id * 13.0, a * 0.8 + seed_v)));
		float ow = lw_oil_half * (0.8 + 0.5 * drip) + px;
		float oil = (1.0 - smoothstep(ow * 0.2, ow, abs(o))) * mix(0.35 + 0.65 * drip, 1.0, queue * 0.7);
		oil *= 0.55 + 0.45 * queue + 0.25 * stretch;
		dark += lw_track_dark * track + lw_oil_dark * oil;
		polish += lw_track_polish * track + 0.06 * oil;
	} else {
		// The parking lane: dust, broken by where cars stand; the gutter pan's dirt line.
		float d = smoothstep(0.3, 0.75, value_noise(vec2(along_p * 0.12, kerb * 0.9 + seed_v + 31.0)));
		dust = lw_kerb_dust * (0.4 + 0.6 * d);
		float gutter = 1.0 - smoothstep(0.12 + px, 0.55 + px, kerb);
		dark += lw_gutter_dark * gutter * (0.6 + 0.4 * value_noise(vec2(along_p * 0.4, seed_v + 3.0)));
	}
	dark *= lane_wear;
	polish *= lane_wear;
	dust *= lane_wear;
	float mul = (1.0 - dark) * (1.0 + dust);
	return vec4(mul, 1.0 - polish, dust, 0.0);
}
