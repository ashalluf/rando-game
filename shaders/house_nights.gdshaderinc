// A house's night, worked out from ONE integer: the house key (HouseNights.key(): its seed mod
// 997), which the near glass carries in UV2.x - 1 and the far box (MidCity.house_custom()) in
// INSTANCE_CUSTOM.b x 997, exact even as a half float. Everything here is mirrored bit for bit by
// scripts/world/house_nights.gd (change one, change both; tests/house_nights_checks.gd reads
// these numbers back), so the house the street sees lit is the house the hills see lit.
// No globals are declared here: the including shader passes the hour in.

uint hn_ihash(uint x) {
	x ^= x >> 16u;
	x *= 0x7feb352du;
	x ^= x >> 15u;
	x *= 0x846ca68bu;
	x ^= x >> 16u;
	return x;
}

// 0..999 for a house key and a salt.
float hn_pct(int key, uint salt) {
	return float(hn_ihash(uint(key) * 7919u + salt) % 1000u);
}

// Per mille of houses wholly dark (nobody home), with the TV on in one room, and the share of a
// lit house's rooms that are lit: HN_SHARE_LO + HN_SHARE_SPAN x the house's roll.
const float HN_DARK = 110.0;
const float HN_TV = 340.0;
const float HN_SHARE_LO = 0.32;
const float HN_SHARE_SPAN = 0.42;
// Bedtime: the hour after which a house keeps one lamp in four on.
const float HN_BED_LO = 22.4;
const float HN_BED_SPAN = 2.4;
const float HN_BED_KEEP = 0.28;
// Per mille of pools whose light is on (keyed by the pool, not the house).
const float HN_POOL = 650.0;

bool hn_dark(int key) {
	return hn_pct(key, 1u) < HN_DARK;
}

int hn_tone_index(int key) {
	return int(hn_ihash(uint(key) * 7919u + 2u) % 4u);
}

// The house's lamps, LINEAR: warm incandescent, soft white, neutral, a cool LED.
vec3 hn_tone(int t) {
	if (t == 0) return vec3(1.0, 0.56, 0.24);
	if (t == 1) return vec3(1.0, 0.70, 0.40);
	if (t == 2) return vec3(1.0, 0.82, 0.62);
	return vec3(0.84, 0.88, 1.0);
}

bool hn_tv(int key) {
	return hn_pct(key, 4u) < HN_TV;
}

// The share of the house's rooms lit at `hour` (0..24, the city's clock).
float hn_share(int key, float hour) {
	if (hn_dark(key)) return 0.0;
	float s = HN_SHARE_LO + HN_SHARE_SPAN * hn_pct(key, 3u) / 1000.0;
	float h = hour < 6.0 ? hour + 24.0 : hour;
	float bed = HN_BED_LO + HN_BED_SPAN * hn_pct(key, 9u) / 1000.0;
	return h > bed ? s * HN_BED_KEEP : s;
}

bool hn_pool_on(int pool_key) {
	return hn_pct(pool_key, 10u) < HN_POOL;
}

// A TV's light: blue-white, cutting between shots every second or so and flickering within one.
vec3 hn_tv_light(int key, float t) {
	float shot = floor(t * 0.9 + float(key) * 0.137);
	float k = float(hn_ihash(uint(int(shot) + key * 31) & 0xffffffu) % 1000u) / 1000.0;
	float flick = 0.82 + 0.18 * sin(t * 23.0 + float(key)) * sin(t * 7.3);
	vec3 c = mix(vec3(0.30, 0.48, 1.0), vec3(0.75, 0.85, 1.0), k);
	return c * (0.45 + 0.75 * k) * flick;
}
