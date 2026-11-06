// Traffic past the streamed range, as its lights: the rivers of white headlights and red tail
// lights that are what a freeway or a boulevard is from a hill or a plane at night. Nothing is
// simulated and nothing is per car: the lights are worked out per pixel from the time, the
// position along the road and a hash, so a whole basin of freeway costs the deck it is drawn on.
// Used by the far city's freeway decks and block plates (building_lod.gdshader), the LOD chunks'
// ground (far_ground.gdshader) and the LOD chunks' freeway decks (far_traffic.gdshader), past
// the range the real traffic is kept in. The day profiles (traffic_level(), window_hour_scale()
// in window_lights.gdshaderinc) read `city_hour`, which DayNight publishes.
//
// Conventions: `s` is metres along the road (continuous from segment to segment), `x` metres
// across it from its centre line, positive to the RIGHT of the +s direction; traffic keeps
// right, so the cars on the +x side move toward +s. `dir` is +s in world XZ.
// Shader includes use // comments.

#ifndef CITY_HOUR_DECLARED
#define CITY_HOUR_DECLARED
global uniform float city_hour;
#endif

// Metres of road one car and its gap take, and how many of those cells make the pattern's
// period (the deck carries its start in that period: NightCity.PERIOD in GDScript).
const float FT_CELL = 14.0;
const float FT_CELLS = 32.0;

// A lamp: a headlight is a hard white point, a tail light a deep red one (red held under ~1 in
// every channel: through AgX a red brighter than that turns salmon).
const vec3 FT_HEAD = vec3(1.0, 0.92, 0.80) * 9.0;
const vec3 FT_TAIL = vec3(1.0, 0.07, 0.035) * 1.6;
// Radius of one lamp, metres, and the least it is drawn at in pixels (a car a kilometre out is a
// tenth of a pixel; drawn at that size it would sparkle and vanish, so it grows to this and dims
// by less than its area: the eye and the lens bloom a distant point light).
const float FT_LAMP_R = 0.22;
const float FT_MIN_PX = 0.9;
// The mean of a lane a kilometre or more out, against its lamps' own share of the pixel: a
// stream of headlights reads far brighter than its area (bloom, the eye), and at 1 the freeways
// across the basin were dark threads.
const float FT_FAR_BLOOM = 3.5;

// The night flight pass (NightFlight; NIGHT_FLIGHT=0 sets the global 0: the A/B). Traffic comes
// in PLATOONS - bunched behind a slow truck, thinned out after a light - so from the air a
// freeway is a broken river of bright knots and gaps, not one even band: the share of cells
// taken is scaled by a smooth noise along the moving road, FT_PLATOON metres a cell, mean 1.
// And a far lane's tail lights count FT_TAIL_MEAN times in its mean: from above both directions
// showed the same cream, where a real freeway reads white one way and red the other.
#ifndef NIGHT_FLIGHT_DECLARED
#define NIGHT_FLIGHT_DECLARED
global uniform float night_flight;
#endif
const float FT_PLATOON = 120.0;
const float FT_PLATOON_LO = 0.3;
const float FT_PLATOON_SPAN = 1.4;
const float FT_TAIL_MEAN = 2.2;

// The night aerial review (NightAerial; NIGHT_AERIAL=0 sets the global 0: the A/B). A freeway
// 400-900 m below a camera in the air drew each lane's mean spread evenly over the lane and bloomed
// for a river kilometres off, so four lanes were one solid cream slab. Where a pixel still spans
// less than a car cell along the road the mean is drawn as the cars it averages: each cell taken
// lit along its car's 4.6 m and dark between, the light held to the lamps' line across the lane
// (two lamps 1.5 m apart, not the lane's 3.6 m), its total kept; and the bloom eases in with
// distance (FT_NEAR_BLOOM of it at a couple of metres a pixel, all of it from FT_BLOOM_FULL).
#ifndef NIGHT_AERIAL_DECLARED
#define NIGHT_AERIAL_DECLARED
global uniform float night_aerial;
#endif
const float FT_NEAR_BLOOM = 0.5;
const float FT_BLOOM_FULL = 8.0;
// Up to this many metres a pixel the cells are drawn; gone by FT_CELLS_GONE.
const float FT_CELLS_FROM = 5.0;
const float FT_CELLS_GONE = 13.0;


// Cars on the road through the day, 0..1 of the lanes' cells taken (an LA weekday: the morning
// and evening peaks, a busy evening, near empty at three in the morning).
float traffic_level(float h) {
	h = mod(h, 24.0);
	// Keys every two hours, from midnight.
	float k[13] = float[13](0.30, 0.16, 0.12, 0.45, 0.95, 0.70, 0.66, 0.72, 0.95, 0.80, 0.62, 0.48, 0.30);
	float f = h * 0.5;
	int i = int(floor(f));
	float t = f - float(i);
	t = t * t * (3.0 - 2.0 * t);
	return mix(k[clamp(i, 0, 12)], k[clamp(i + 1, 0, 12)], t);
}


float ft_hash(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}


// The platoon factor at `u` metres along the moving road (the cars' own frame), `key` tells one
// carriageway from another. NightCity.platoon() is the GDScript copy.
float ft_platoon(float u, float key) {
	if (night_flight < 0.5) {
		return 1.0;
	}
	float f = u / FT_PLATOON;
	float c = floor(f);
	float t = f - c;
	t = t * t * (3.0 - 2.0 * t);
	float n = mix(ft_hash(vec3(c, key, 5.3)), ft_hash(vec3(c + 1.0, key, 5.3)), t);
	return FT_PLATOON_LO + FT_PLATOON_SPAN * smoothstep(0.1, 0.9, n);
}


// The lane mean's shape at (u, lx): 1 on average, more on a car and on the lamps' line, less
// between. `u` the moving road (s - sgn v t), `key_lane` and `seed` as ft_lane's, `lvl` the share of
// cells taken (with the platoons), `mpp` metres a pixel.
float ft_mean_shape(float u, float lx, float sgn, float lane, float lane_w, float lvl, float seed, float mpp) {
	if (night_aerial < 0.5) {
		return 1.0;
	}
	// Across: the lamps' line, never narrower than a pixel or wider than the lane.
	float hw = min(max(0.75 + FT_LAMP_R * 2.0, mpp * 0.5), lane_w * 0.5);
	float across = (1.0 - smoothstep(hw - mpp * 0.25, hw + mpp * 0.25, abs(lx))) * (lane_w * 0.5 / hw);
	// Along: the cells, each taken or not by the same roll as ft_lane's.
	float cells = 1.0 - smoothstep(FT_CELLS_FROM, FT_CELLS_GONE, mpp);
	float along = 1.0;
	if (cells > 0.001 && lvl > 0.001) {
		float c = floor(u / FT_CELL);
		float w = u - c * FT_CELL;
		vec3 key = vec3(mod(c, FT_CELLS), lane * 7.0 + (sgn > 0.0 ? 3.0 : 0.0), seed);
		float taken = ft_hash(key) < lvl ? 1.0 : 0.0;
		float j = 0.5 + ft_hash(key + 11.7) * (FT_CELL - 5.6);
		float soft = max(mpp * 0.5, 0.3);
		float car = smoothstep(j - soft, j + soft, w) * (1.0 - smoothstep(j + 4.6 - soft, j + 4.6 + soft, w));
		along = mix(1.0, taken * car * FT_CELL / (4.6 * lvl), cells);
	}
	return across * along;
}


// One lane's lights at (s, lx): lx metres across the lane from its middle. `sgn` +1 when its
// cars move toward +s. Returns (head share, tail share) of a lit lamp at this point, already
// scaled for the pixel size.
vec2 ft_lane(float s, float lx, float sgn, float lane, float level, float speed, float seed, float mpp) {
	float u = s - sgn * speed * TIME;
	float c = floor(u / FT_CELL);
	float w = u - c * FT_CELL;
	float cm = mod(c, FT_CELLS);
	vec3 key = vec3(cm, lane * 7.0 + (sgn > 0.0 ? 3.0 : 0.0), seed);
	if (ft_hash(key) >= min(level * ft_platoon(u, seed * 2.0 + (sgn > 0.0 ? 1.0 : 0.0)), 1.0)) {
		return vec2(0.0);
	}
	// The car: 4.6 m long somewhere in its cell, its lamps 0.75 m either side of its middle.
	float j = 0.5 + ft_hash(key + 11.7) * (FT_CELL - 5.6);
	float front = sgn > 0.0 ? j + 4.6 : j;
	float rear = sgn > 0.0 ? j : j + 4.6;
	float re = max(FT_LAMP_R, mpp * FT_MIN_PX);
	float gain = pow(FT_LAMP_R / re, 1.05);
	float dx = abs(lx) - 0.75;
	float hf = length(vec2(w - front, dx));
	float hr = length(vec2(w - rear, dx));
	float head = (1.0 - smoothstep(re * 0.5, re, hf)) * gain;
	float tail = (1.0 - smoothstep(re * 0.5, re, hr)) * gain;
	return vec2(head, tail);
}


// The lights of a road with `lanes` lanes each way of `lane_w` metres, the first starting `x0`
// from the centre line. `to_cam` is the unit world vector toward the camera: a car coming at it
// shows its headlights, one going away its tail lights. `speed` m/s, `seed` tells roads apart.
vec3 traffic_lights(float s, float x, float x0, float lane_w, float lanes, vec2 dir, vec3 to_cam,
		float mpp, float level, float speed, float seed) {
	float sgn = x >= 0.0 ? 1.0 : -1.0;
	float ax = abs(x) - x0;
	if (ax < 0.0 || ax >= lane_w * lanes || level <= 0.0) {
		return vec3(0.0);
	}
	float lane = floor(ax / lane_w);
	float lx = (fract(ax / lane_w) - 0.5) * lane_w;
	// Which way this carriageway's cars face against the camera.
	vec2 move = dir * sgn;
	float toward = dot(move, normalize(to_cam.xz + vec2(1e-5))) * clamp(length(to_cam.xz) * 1.6, 0.0, 1.0);
	float head_w = 0.15 + 0.85 * smoothstep(-0.25, 0.45, toward);
	float tail_w = 0.25 + 0.75 * smoothstep(0.25, -0.45, toward);
	// Faster in the inside lanes.
	float v = speed * (1.0 - 0.07 * lane);
	// Up close, the lamps themselves; once a car is under a couple of pixels, their mean over the
	// lane, so a far river is a steady line rather than a crawl of sparkles.
	float sharp = 1.0 - smoothstep(0.9, 2.6, mpp);
	vec3 col = vec3(0.0);
	if (sharp > 0.001) {
		vec2 l = ft_lane(s, lx, sgn, lane, level, v, seed, mpp);
		col += (FT_HEAD * l.x * head_w + FT_TAIL * l.y * tail_w) * sharp;
	}
	if (sharp < 0.999) {
		// The mean of a lane: two lamps of the drawn size per car, `level` of the cells taken,
		// with the same bloom gain, spread over the lane (the bloom held from about 4 m a pixel,
		// or a river ten kilometres off would outshine the one below the camera).
		float re = max(FT_LAMP_R, min(mpp, 4.0) * FT_MIN_PX);
		float gain = pow(FT_LAMP_R / re, 1.05);
		float area = 2.0 * 0.6 * re * re * 3.14159 * gain / (FT_CELL * lane_w);
		float lvl = min(level * ft_platoon(s - sgn * v * TIME, seed * 2.0 + (sgn > 0.0 ? 1.0 : 0.0)), 1.0);
		float tail_k = night_flight > 0.5 ? FT_TAIL_MEAN : 1.0;
		float bloom = FT_FAR_BLOOM;
		float shape = 1.0;
		if (night_aerial > 0.5) {
			bloom *= mix(FT_NEAR_BLOOM, 1.0, smoothstep(1.0, FT_BLOOM_FULL, mpp));
			shape = ft_mean_shape(s - sgn * v * TIME, lx, sgn, lane, lane_w, lvl, seed, mpp);
		}
		col += (FT_HEAD * head_w + FT_TAIL * tail_k * tail_w) * lvl * area * bloom * shape * (1.0 - sharp);
	}
	return col;
}


// A surface street `w` metres kerb to kerb: its lanes share what the parking lanes leave
// (CityPlan.lane_center), a side street carries a car now and then, an avenue a stream.
// `road_id` tells one road from the next (any number constant along it).
vec3 street_traffic(float s, float x, float w, vec2 dir, vec3 to_cam, float mpp, float road_id) {
	float half_w = w * 0.5;
	float lanes = clamp(floor((half_w - 2.6) / 3.3), 1.0, 3.0);
	float lane_w = (half_w - 2.8) / lanes;
	float busy = smoothstep(12.0, 22.0, w);
	float level = traffic_level(city_hour) * mix(0.25, 0.95, busy);
	return traffic_lights(s, x, 0.2, lane_w, lanes, dir, to_cam, mpp, level, mix(10.0, 15.0, busy), mod(road_id, 997.0));
}
