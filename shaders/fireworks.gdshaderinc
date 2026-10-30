// Fireworks (scripts/world/fireworks.gd, docs/HANDOFF.md "Fireworks"): the show's PLAN, shared by
// the stars, the smoke and (bit for bit, in GDScript) Fireworks.shell(). A show is worked out from
// one clock and one seed, never simulated: time is cut into bins of FW_BIN seconds, a bin launches
// a shell or not by an integer hash of (show seed, bin), and everything about that shell - when it
// leaves the mortar within its bin, where along the launch line, how high it breaks, its type, its
// colours, its size - is more rolls of the same hash. A mesh slot s draws the newest bin b with
// b % slots == s, so FW_SLOTS bins of history are on screen at once (a shell's whole life is under
// FW_SLOTS * FW_BIN). Change a number here, change it in Fireworks (tests/fireworks_checks.gd
// reads these lines back).

const float FW_BIN = 0.4;
const int FW_SLOTS = 24;
const int FW_STARS = 96;
const int FW_TRAIL = 10;
const int FW_SMOKE_SLOTS = 84;
const float FW_SMOKE_LIFE = 28.0;
// The programme loops every FW_ACT_BINS bins: an opening, the body, a build and a finale, a gap.
const int FW_ACT_BINS = 375;
const int FW_OPEN_END = 20;
const int FW_BODY_END = 250;
const int FW_BUILD_END = 320;
const int FW_FINALE_END = 358;
const float FW_P_OPEN = 0.30;
const float FW_P_BODY = 0.40;
const float FW_P_BUILD = 0.60;
const float FW_P_FINALE = 0.95;
// Types, by cumulative roll (the finale has its own table: willow curtains and strobes).
const int FW_PEONY = 0;
const int FW_WILLOW = 1;
const int FW_CROSSETTE = 2;
const int FW_STROBE = 3;
const int FW_RING = 4;
const float FW_TYPE_CUT[4] = float[4](0.36, 0.56, 0.74, 0.88);
const float FW_FINALE_CUT[4] = float[4](0.28, 0.55, 0.66, 0.90);
// Per type: star speed (m/s), drag (1/s), gravity (m/s2), star life (s), trail (s of travel).
const float FW_V0[5] = float[5](95.0, 72.0, 82.0, 80.0, 92.0);
const float FW_DRAG[5] = float[5](1.6, 2.3, 1.2, 1.5, 1.6);
const float FW_GRAV[5] = float[5](6.0, 5.5, 5.0, 5.0, 4.0);
const float FW_LIFE[5] = float[5](2.3, 5.0, 2.7, 3.0, 2.1);
const float FW_TAIL[5] = float[5](0.11, 0.42, 0.12, 0.025, 0.10);
// A crossette's comets split into four at this age.
const float FW_SPLIT = 0.8;
const float FW_SPLIT_V = 32.0;
// Star colours (linear; red and purple hold green low, or AgX turns them salmon).
const vec3 FW_COLORS[7] = vec3[7](
	vec3(1.0, 0.10, 0.035), vec3(0.16, 1.0, 0.10), vec3(0.10, 0.24, 1.0), vec3(1.0, 0.52, 0.12),
	vec3(0.88, 0.90, 1.0), vec3(0.55, 0.12, 1.0), vec3(0.12, 0.82, 1.0));
const vec3 FW_WILLOW_COLOR = vec3(1.0, 0.42, 0.10);
const vec3 FW_STROBE_COLOR = vec3(0.95, 0.97, 1.0);


uint fw_hash(uint key, uint salt) {
	uint h = key * 747796405u + salt * 2891336453u;
	h ^= h >> 16u;
	h *= 2246822519u;
	h ^= h >> 13u;
	h *= 3266489917u;
	h ^= h >> 16u;
	return h;
}


float fw_roll(uint key, uint salt) {
	return float(fw_hash(key, salt) >> 8u) * (1.0 / 16777216.0);
}


uint fw_key(int show_seed, int bin) {
	return fw_hash(uint(show_seed), uint(bin));
}


// The newest bin drawn by slot s at bin `now_bin` (negative: nothing yet).
int fw_slot_bin(int now_bin, int s, int slots) {
	int m = (now_bin - s) % slots;
	if (m < 0) {
		m += slots;
	}
	return now_bin - m;
}


float fw_launch_odds(int bin) {
	int ph = bin % FW_ACT_BINS;
	if (ph < FW_OPEN_END) return FW_P_OPEN;
	if (ph < FW_BODY_END) return FW_P_BODY;
	if (ph < FW_BUILD_END) return FW_P_BUILD;
	if (ph < FW_FINALE_END) return FW_P_FINALE;
	return 0.0;
}


bool fw_finale(int bin) {
	int ph = bin % FW_ACT_BINS;
	return ph >= FW_BUILD_END && ph < FW_FINALE_END;
}


// The shell of a bin. Returns false when the bin launches nothing.
// time: x launch, y burst (both show seconds); off: launch point in the site's frame (metres);
// burst: the break point; type, c1, c2 colour indices; size: star speed scale.
bool fw_shell(int show_seed, int bin, vec2 line_dir, float spread, float h_min, float h_max,
		out vec2 time, out vec3 off, out vec3 burst, out int type, out int c1, out int c2, out float size) {
	time = vec2(0.0);
	off = vec3(0.0);
	burst = vec3(0.0);
	type = 0;
	c1 = 0;
	c2 = 0;
	size = 1.0;
	if (bin < 0) {
		return false;
	}
	uint k = fw_key(show_seed, bin);
	if (fw_roll(k, 1u) >= fw_launch_odds(bin)) {
		return false;
	}
	float tl = (float(bin) + 0.8 * fw_roll(k, 2u)) * FW_BIN;
	float along = (fw_roll(k, 3u) - 0.5) * spread;
	float across = (fw_roll(k, 4u) - 0.5) * 18.0;
	vec2 perp = vec2(-line_dir.y, line_dir.x);
	vec2 o = line_dir * along + perp * across;
	off = vec3(o.x, 0.0, o.y);
	float h = mix(h_min, h_max, fw_roll(k, 5u));
	float rise = 1.4 + h / 130.0;
	time = vec2(tl, tl + rise);
	float tr = fw_roll(k, 6u);
	bool fin = fw_finale(bin);
	type = 4;
	for (int i = 0; i < 4; i++) {
		float cut = fin ? FW_FINALE_CUT[i] : FW_TYPE_CUT[i];
		if (tr < cut) {
			type = i;
			break;
		}
	}
	c1 = int(fw_roll(k, 7u) * 7.0);
	c2 = int(fw_roll(k, 8u) * 7.0);
	size = mix(0.78, 1.22, fw_roll(k, 11u));
	vec2 drift = (vec2(fw_roll(k, 9u), fw_roll(k, 10u)) - 0.5) * 0.14 * h;
	burst = off + vec3(drift.x, h, drift.y);
	return true;
}


// Where the shell's head is t seconds after launch (0..rise), in the site's frame.
vec3 fw_rise_point(vec3 off, vec3 burst, float rise, float t) {
	float u = clamp(t / max(rise, 0.01), 0.0, 1.0);
	// The shell leaves the mortar fast and slows to its break: y = h (1 - (1 - u)^2).
	float y = burst.y * (1.0 - (1.0 - u) * (1.0 - u));
	vec2 xz = mix(off.xz, burst.xz, u * u);
	return vec3(xz.x, y, xz.y);
}


// A star's direction out of the break (unit), by type.
vec3 fw_star_dir(int type, int star, uint k) {
	float n = float(FW_STARS);
	float spin = fw_roll(k, 12u) * 6.2832;
	if (type == FW_RING) {
		float a = (float(star) + 0.5) / n * 6.2832 + spin;
		vec3 d = vec3(cos(a), 0.0, sin(a));
		// The ring's plane, tilted toward the crowd by a roll.
		float tilt = mix(0.5, 1.35, fw_roll(k, 13u));
		float ct = cos(tilt);
		float st = sin(tilt);
		d = vec3(d.x, d.z * st, d.z * ct);
		float yaw = fw_roll(k, 14u) * 6.2832;
		return vec3(d.x * cos(yaw) - d.z * sin(yaw), d.y, d.x * sin(yaw) + d.z * cos(yaw));
	}
	float i = float(star);
	float m = n;
	if (type == FW_CROSSETTE) {
		// 24 comets of four stars each: the four share their comet's direction.
		i = floor(i / 4.0);
		m = n / 4.0;
	}
	float z = 1.0 - 2.0 * (i + 0.5) / m;
	float r = sqrt(max(0.0, 1.0 - z * z));
	float phi = i * 2.39996 + spin;
	// A real shell's stars are not on a perfect sphere.
	float jit = (fw_roll(k, 20u + uint(star)) - 0.5) * 0.22;
	return normalize(vec3(r * cos(phi + jit), z + jit * 0.5, r * sin(phi - jit)));
}


// A star's place and velocity `a` seconds after the break, relative to the break point.
void fw_star(int type, int star, uint k, float size, float a, vec2 wind, out vec3 pos, out vec3 vel) {
	vec3 d = fw_star_dir(type, star, k);
	float v0 = FW_V0[type] * size * mix(0.9, 1.08, fw_roll(k, 140u + uint(star)));
	float kd = FW_DRAG[type];
	float e = exp(-kd * a);
	pos = d * v0 * (1.0 - e) / kd;
	vel = d * v0 * e;
	if (type == FW_CROSSETTE && a > FW_SPLIT) {
		int c = star % 4;
		// The split: four children out across the comet's path.
		vec3 up = abs(d.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
		vec3 u = normalize(cross(d, up));
		vec3 w = cross(d, u);
		vec3 cd = (c == 0) ? u : ((c == 1) ? -u : ((c == 2) ? w : -w));
		float b = a - FW_SPLIT;
		float e2 = exp(-2.2 * b);
		pos += cd * FW_SPLIT_V * size * (1.0 - e2) / 2.2;
		vel += cd * FW_SPLIT_V * size * e2;
	}
	float g = FW_GRAV[type];
	pos.y -= 0.5 * g * a * a;
	vel.y -= g * a;
	pos.xz += wind * a * 0.6;
	vel.xz += wind * 0.6;
}
