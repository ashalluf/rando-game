// The cars on a far street by DAY (MidCity, docs/HANDOFF.md "The mid distance"): from a hill or
// a plane a Los Angeles street is a grey band lined both sides with parked cars and dotted with
// moving ones, and a block plate's road painted flat black read as an empty grid. Nothing is
// placed: a car is worked out per pixel from the position along the road, the time and a hash.
// The MOVING cars are far_traffic.gdshaderinc's own (the same cells, keys and speeds as
// ft_lane()), so the cars a hill sees at noon are the ones whose lights it sees at night. The
// PARKED ones fill the kerb lanes (CityPlan.PARKING_LANE) in 6.4 m bays, a share of them taken.
// Used by building_lod.gdshader's block plates and freeway decks and far_ground.gdshader's LOD
// ground. Include far_traffic.gdshaderinc first. Shader includes use // comments.

// A parking bay, the share of bays taken, and the parking lane's width (CityPlan.PARKING_LANE).
const float FC_BAY = 6.4;
const float FC_PARKED = 0.62;
const float FC_PARK_LANE = 2.6;
// A car's footprint, metres.
const float FC_LEN = 4.6;
const float FC_WID = 1.85;

// A car's paint, LINEAR (the colours a real car park is: mostly white, black, silver and grey).
vec3 fc_paint(float h) {
	if (h < 0.24) return vec3(0.62, 0.62, 0.60);
	if (h < 0.44) return vec3(0.025, 0.025, 0.028);
	if (h < 0.61) return vec3(0.36, 0.37, 0.38);
	if (h < 0.75) return vec3(0.15, 0.15, 0.16);
	if (h < 0.82) return vec3(0.025, 0.045, 0.11);
	if (h < 0.88) return vec3(0.30, 0.03, 0.025);
	if (h < 0.94) return vec3(0.33, 0.29, 0.21);
	return vec3(0.07, 0.12, 0.10);
}

// The mean paint of the palette above (for a car under a pixel).
const vec3 FC_MEAN = vec3(0.235, 0.232, 0.236);

// One car body seen from above at (dl along, dw across) from its middle: (paint, coverage). The
// cabin's glass a darker band across its middle, anti-aliased over `aa` metres.
vec4 fc_body(float dl, float dw, float aa, float h) {
	float cov = (1.0 - smoothstep(FC_LEN * 0.5 - aa, FC_LEN * 0.5 + aa, abs(dl)))
		* (1.0 - smoothstep(FC_WID * 0.5 - aa, FC_WID * 0.5 + aa, abs(dw)));
	vec3 paint = fc_paint(h);
	float glass = (1.0 - smoothstep(0.55 - aa, 0.55 + aa, abs(dl + 0.15)))
		* (1.0 - smoothstep(FC_WID * 0.5 - 0.12 - aa, FC_WID * 0.5 - 0.12 + aa, abs(dw)));
	paint = mix(paint, vec3(0.018, 0.02, 0.024), glass * 0.75 * (1.0 - smoothstep(0.4, 1.2, aa)));
	return vec4(paint, cov);
}


// The cars at (s, x) on a surface street `w` metres kerb to kerb: x across from its centre line,
// positive to the right of +s (far_traffic's convention). `moving` scales the moving cars (0 where
// the real traffic still drives), `parked` the parked ones. Returns (paint LINEAR, coverage).
vec4 street_cars(float s, float x, float w, float mpp, float road_id, float moving, float parked) {
	float half_w = w * 0.5;
	float ax = abs(x);
	float sgn = x >= 0.0 ? 1.0 : -1.0;
	float aa = max(mpp * 0.6, 0.04);
	// Past a couple of metres a pixel a car is coverage, not a shape: the lane's mean.
	float sharp = 1.0 - smoothstep(1.4, 3.2, mpp);
	vec4 out_c = vec4(0.0);
	// The kerb lanes.
	if (parked > 0.0 && ax > half_w - FC_PARK_LANE - 0.2 && ax < half_w) {
		float c = floor(s / FC_BAY);
		vec3 key = vec3(c, sgn * 3.0 + 1.0, mod(road_id, 997.0));
		float taken = step(ft_hash(key), FC_PARKED);
		float j = (ft_hash(key + 5.3) - 0.5) * (FC_BAY - FC_LEN - 0.6);
		float dl = s - (c + 0.5) * FC_BAY - j;
		float dw = ax - (half_w - FC_PARK_LANE * 0.5 - 0.05);
		vec4 car = fc_body(dl, dw, aa, ft_hash(key + 2.9));
		float mean = FC_PARKED * FC_LEN * FC_WID / (FC_BAY * FC_PARK_LANE);
		out_c = vec4(mix(FC_MEAN, car.rgb, sharp), mix(mean, car.a * taken, sharp) * parked);
	}
	// The moving lanes: far_traffic's street_traffic(), car for car.
	float lanes = clamp(floor((half_w - 2.6) / 3.3), 1.0, 3.0);
	float lane_w = (half_w - 2.8) / lanes;
	float lx0 = ax - 0.2;
	if (moving > 0.0 && lx0 >= 0.0 && lx0 < lane_w * lanes) {
		float busy = smoothstep(12.0, 22.0, w);
		float level = traffic_level(city_hour) * mix(0.25, 0.95, busy);
		float lane = floor(lx0 / lane_w);
		float lx = (fract(lx0 / lane_w) - 0.5) * lane_w;
		float v = mix(10.0, 15.0, busy) * (1.0 - 0.07 * lane);
		float u = s - sgn * v * TIME;
		float c = floor(u / FT_CELL);
		float wc = u - c * FT_CELL;
		vec3 key = vec3(mod(c, FT_CELLS), lane * 7.0 + (sgn > 0.0 ? 3.0 : 0.0), mod(road_id, 997.0));
		float taken = step(ft_hash(key), level);
		float j = 0.5 + ft_hash(key + 11.7) * (FT_CELL - 5.6);
		vec4 car = fc_body(wc - (j + FC_LEN * 0.5), lx, aa, ft_hash(key + 2.9));
		float mean = level * FC_LEN * FC_WID / (FT_CELL * lane_w);
		out_c = vec4(mix(FC_MEAN, car.rgb, sharp), mix(mean, car.a * taken, sharp) * moving);
	}
	return out_c;
}


// The cars on a freeway carriageway (building_lod's far decks): four lanes each way from `x0`,
// at 27 m/s like their lights (far_traffic.gdshaderinc's traffic_lights() on the deck).
vec4 deck_cars(float s, float x, float x0, float lane_w, float mpp, float seed) {
	float ax = abs(x) - x0;
	float sgn = x >= 0.0 ? 1.0 : -1.0;
	if (ax < 0.0 || ax >= lane_w * 4.0) {
		return vec4(0.0);
	}
	float aa = max(mpp * 0.6, 0.04);
	float sharp = 1.0 - smoothstep(1.4, 3.2, mpp);
	float level = traffic_level(city_hour);
	float lane = floor(ax / lane_w);
	float lx = (fract(ax / lane_w) - 0.5) * lane_w;
	float v = 27.0 * (1.0 - 0.07 * lane);
	float u = s - sgn * v * TIME;
	float c = floor(u / FT_CELL);
	float wc = u - c * FT_CELL;
	vec3 key = vec3(mod(c, FT_CELLS), lane * 7.0 + (sgn > 0.0 ? 3.0 : 0.0), seed);
	float taken = step(ft_hash(key), level);
	float j = 0.5 + ft_hash(key + 11.7) * (FT_CELL - 5.6);
	vec4 car = fc_body(wc - (j + FC_LEN * 0.5), lx, aa, ft_hash(key + 2.9));
	float mean = level * FC_LEN * FC_WID / (FT_CELL * lane_w);
	return vec4(mix(FC_MEAN, car.rgb, sharp), mix(mean, car.a * taken, sharp));
}
