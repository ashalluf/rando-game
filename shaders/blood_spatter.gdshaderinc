// Blood spattered on the hero when he is close to a wound (HeroBlood, blood-gore-2), included by
// hero_cloth.gdshader and hero_skin.gdshader. Up to six spatters, each a point on his posed body
// in skeleton space with its radius (spat_p[i], skeleton units) and the way the spray travelled
// with how dense it was (spat_d[i]: xyz direction, w density 0..1); HeroBlood moves them with the
// bones they landed on. A spatter is drops, not a stain: three octaves of 3D cells (2.4, 1.1 and
// 0.45 cm), each holding a drop by chance - denser toward the middle and with the density -,
// stretched along the spray, only on the side that faced it. spat_dry 0 fresh (dark red, glossy)
// .. 1 dried (near black-brown, matt). spat_count 0 (nobody near a wound yet, BLOOD_GORE_2=0)
// skips everything. The colours are source_color defaults, so they arrive in the same space as
// the textures they are mixed with on either renderer.

uniform float spat_count = 0.0;
uniform vec4 spat_p[6];
uniform vec4 spat_d[6];
uniform float spat_unit = 100.0;
uniform float spat_dry = 0.0;
uniform vec3 spat_fresh : source_color = vec3(0.30, 0.02, 0.016);
uniform vec3 spat_old : source_color = vec3(0.12, 0.03, 0.022);

varying vec3 v_sp_p;
varying vec3 v_sp_n;


vec4 sp_hash(vec3 c) {
	vec4 p = fract(vec4(c.xyzx) * vec4(0.1031, 0.1030, 0.0973, 0.1099));
	p += dot(p, p.wzxy + 33.33);
	return fract((p.xxyz + p.yzzw) * p.zywx);
}


// One octave: is there a drop in the cell `p` falls in (metres), sized for a cell of `cell` m?
float sp_drops(vec3 p, float cell, float chance, vec3 dir, float salt) {
	vec3 g = p / cell;
	vec3 i = floor(g);
	vec4 h = sp_hash(i + salt);
	if (h.x > chance) {
		return 0.0;
	}
	vec3 c = (i + 0.25 + 0.5 * h.yzw) * cell;
	vec3 q = p - c;
	// Stretched along the spray: a drop arriving at a slant is a tear, not a dot.
	float along = dot(q, dir);
	q -= dir * along * 0.45;
	float r = cell * (0.12 + 0.13 * fract(h.x * 7.31 + h.y));
	return 1.0 - smoothstep(r * 0.65, r, length(q));
}


// How much of the point is under blood, 0..1.
float sp_cover(vec3 pos, vec3 nrm) {
	float cover = 0.0;
	vec3 pm = pos / spat_unit;
	vec3 n = normalize(nrm);
	for (int i = 0; i < 6; i++) {
		if (float(i) >= spat_count) {
			break;
		}
		vec4 s = spat_p[i];
		vec4 d = spat_d[i];
		float r = s.w / spat_unit;
		vec3 q = pm - s.xyz / spat_unit;
		float dist = length(q) / max(r, 1e-4);
		if (dist > 1.25) {
			continue;
		}
		vec3 dir = normalize(d.xyz + vec3(1e-4));
		float facing = smoothstep(-0.15, 0.35, dot(n, -dir));
		float fall = pow(clamp(1.0 - dist / 1.25, 0.0, 1.0), 1.3) * d.w * facing;
		float c = sp_drops(pm, 0.024, fall * 0.5, dir, float(i) * 13.0);
		c = max(c, sp_drops(pm, 0.011, fall * 0.75, dir, float(i) * 13.0 + 5.0));
		c = max(c, sp_drops(pm, 0.0045, fall * 0.9, dir, float(i) * 13.0 + 9.0));
		cover = max(cover, c);
	}
	return cover;
}
