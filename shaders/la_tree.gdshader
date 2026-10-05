shader_type spatial;
render_mode cull_disabled;

// The code-built Los Angeles trees and accents (scripts/world/la_trees.gd). One shader for bark
// and leaves: UV2.x is what a vertex is (LaTrees' B_* and L_*; a cluster card's style rides in
// its quarters), UV2.y a random per leaf (a cluster card: its cover in the fraction, a random in
// the hundreds). Bark UV is (metres round, metres along) so the patterns are at real size; a
// leaf's UV is (-1..1 across, 0..1 base to tip) and the outline is CUT here, so a leaf is two
// triangles whatever its shape. Colours are vertex colours times the instance tint, linear on
// both renderers (nothing here is a source_color), so the Mac and the web agree.
//
// Wind as shaders/foliage.gdshader (the slow bend growing with the square of height, phased by
// the instance's position, under a travelling gust), plus a leaf flutter along each leaf's own
// normal that grows to its tip.

global uniform float wind_factor;
global uniform float road_wetness;
global uniform vec3 sun_direction;

uniform float bend_scale : hint_range(0.0, 0.02) = 0.0012;
uniform float speed : hint_range(0.0, 3.0) = 0.55;
uniform float flutter : hint_range(0.0, 0.2) = 0.03;
uniform float flutter_speed : hint_range(0.0, 12.0) = 5.5;
uniform float gust_speed : hint_range(0.0, 1.0) = 0.17;
uniform float gust_depth : hint_range(0.0, 1.0) = 0.45;

uniform float translucency : hint_range(0.0, 1.0) = 0.4;
uniform float scatter_gain : hint_range(0.0, 4.0) = 1.6;
uniform float scatter_sharpness : hint_range(1.0, 16.0) = 5.0;
uniform float leaf_roughness : hint_range(0.0, 1.0) = 0.7;
uniform float leaf_specular : hint_range(0.0, 1.0) = 0.35;
uniform float wet_roughness : hint_range(0.0, 1.0) = 0.22;
/// A leaf's underside against its top (olive: silver).
uniform vec3 underside = vec3(1.1, 1.1, 1.0);

varying float v_kind;
varying float v_rnd;
varying vec3 v_obj;

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = h21(i);
	float b = h21(i + vec2(1.0, 0.0));
	float c = h21(i + vec2(0.0, 1.0));
	float d = h21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	return vnoise(p) * 0.55 + vnoise(p * 2.13 + 7.1) * 0.3 + vnoise(p * 4.37 + 3.3) * 0.15;
}

void vertex() {
	v_kind = floor(UV2.x + 0.05);
	v_rnd = UV2.y;
	v_obj = VERTEX;
	vec3 origin = MODEL_MATRIX[3].xyz;
	float phase = origin.x * 0.31 + origin.z * 0.23;
	float w = clamp(max(wind_factor, 0.25), 0.0, 3.0);
	w *= 1.0 - gust_depth + gust_depth * (0.5 + 0.5 * sin(TIME * gust_speed + (origin.x + origin.z) * 0.013));
	float radial = length(VERTEX.xz);
	vec2 around = VERTEX.xz / max(radial, 1e-4);
	float t = TIME * speed;
	float p = phase + around.x * 1.3 + around.y * 0.9;
	float gx = sin(t + p) * 0.72 + sin(t * 1.73 + p * 2.1) * 0.28;
	float gz = sin(t * 0.87 + p * 1.4 + 2.1) * 0.72 + sin(t * 1.51 + p) * 0.28;
	float h = max(VERTEX.y, 0.0);
	float bend = h * h * bend_scale * w;
	VERTEX.x += bend * gx;
	VERTEX.z += bend * gz;
	if (v_kind >= 8.0) {
		// The flutter: along the leaf's normal, nothing at its stalk, most at its tip.
		float lp = fract(UV2.y * 7.31) * 6.28;
		VERTEX += NORMAL * sin(TIME * flutter_speed + lp + phase) * flutter * w * UV.y;
	}
}

// --- Leaf outlines: >0 inside, in units of the leaf's half-width -----------------------------

float lance(vec2 uv) {
	float w = pow(sin(3.14159 * pow(clamp(uv.y, 0.0, 1.0), 0.62)), 0.85);
	return w - abs(uv.x);
}

float oval(vec2 uv) {
	float y = (uv.y - 0.47) / 0.53;
	float w = sqrt(max(1.0 - y * y, 0.0)) * (1.0 - 0.35 * smoothstep(0.75, 1.0, uv.y));
	return w - abs(uv.x);
}

float palmate(vec2 uv, float rnd) {
	// Five lobes off the stalk at the base, the middle one up the leaf.
	vec2 q = vec2(uv.x, (uv.y - 0.12) * 2.2);
	float r = length(q);
	float th = atan(q.x, q.y);
	float lobes = 0.52 + 0.48 * pow(abs(cos(th * 2.5 + 0.04 * rnd)), 0.75);
	float teeth = 0.035 * sin(th * 23.0 + rnd * 6.0);
	float keep = (lobes + teeth) * 1.08 - r;
	return min(keep, 1.55 - abs(th)) * 0.9;
}

float scale_spray(vec2 uv, float rnd) {
	// A flattened cypress spray: a tapering frond with ragged sub-sprays down both sides.
	float w = pow(sin(3.14159 * pow(clamp(uv.y, 0.0, 1.0), 0.8)), 0.7);
	float teeth = 0.25 * (0.5 + 0.5 * sin(uv.y * 31.0 + sign(uv.x) * 1.7 + rnd * 9.0));
	float holes = vnoise(vec2(uv.x * 4.0, uv.y * 12.0) + rnd * 13.0);
	return (w * (0.8 + teeth) - abs(uv.x)) - step(0.78, holes) * 0.4;
}

float trifol(vec2 uv) {
	// The terminal leaflet up the middle, two laterals off the stalk at a third.
	vec2 a = (uv - vec2(0.0, 0.66)) / vec2(0.62, 0.34);
	vec2 bl = uv - vec2(-0.45, 0.3);
	vec2 br = uv - vec2(0.45, 0.3);
	mat2 rl = mat2(vec2(0.77, 0.64), vec2(-0.64, 0.77));
	mat2 rr = mat2(vec2(0.77, -0.64), vec2(0.64, 0.77));
	vec2 l = (rl * bl) / vec2(0.52, 0.27);
	vec2 r = (rr * br) / vec2(0.52, 0.27);
	float k = max(1.0 - length(a), max(1.0 - length(l), 1.0 - length(r)));
	return k * 0.5;
}

float sword(vec2 uv) {
	float w = min(1.0, (1.0 - uv.y) * 6.0) * (0.75 + 0.25 * smoothstep(0.0, 0.2, uv.y));
	return w - abs(uv.x);
}

float paddle(vec2 uv, float rnd) {
	float y = (uv.y - 0.5) / 0.5;
	float w = pow(max(1.0 - y * y, 0.0), 0.45);
	float k = w - abs(uv.x);
	// Wind tears from the edge toward the midrib, a few a leaf.
	float tear = abs(fract(uv.y * 6.0 + abs(uv.x) * 0.45 + rnd * 3.0) - 0.5);
	if (abs(uv.x) > 0.3 && fract(floor(uv.y * 6.0 + abs(uv.x) * 0.45 + rnd * 3.0) * 0.618 + rnd) > 0.55) {
		k = min(k, (tear - 0.03) * 4.0);
	}
	return k;
}

float flower(vec2 uv, float rnd, float style) {
	if (style > 0.5) {
		return lance(uv);
	}
	// Coral tree: tubular red flowers radiating up a spike.
	vec2 q = vec2(uv.x, uv.y * 1.6);
	float spine = 0.12 - abs(uv.x);
	float row = fract(uv.y * 9.0 + rnd);
	float petal = 0.5 * (1.0 - uv.y * 0.6) - abs(uv.x - (row - 0.5) * 0.6 * sign(fract(floor(uv.y * 9.0 + rnd) * 0.5) - 0.25));
	float body = 1.0 - length(vec2(uv.x * 1.0, (uv.y - 0.45) * 2.1));
	return min(max(spine, petal), body + 0.1);
}

// A sprig: a stem up the card with leaves off it, alternate (style 0: oval, a fig's; style 1:
// long sickles hanging close to the stem, a gum's; style 2: narrow pairs, an olive's).
float sprig_leaf(vec2 p, vec2 base, vec2 dir, float len, float hw) {
	vec2 q = p - base;
	float t = dot(q, dir);
	float a = dot(q, vec2(-dir.y, dir.x));
	float x = clamp(t / len, 0.0, 1.0);
	float w = hw * pow(sin(3.14159 * pow(x, 0.7)), 0.8);
	return (t < 0.0 || t > len) ? -1.0 : (w - abs(a)) / hw;
}

float sprig(vec2 uv, float style, float rnd) {
	float aspect = style < 0.5 ? 0.42 : (style < 1.5 ? 0.22 : 0.3);
	float n = style < 0.5 ? 8.0 : (style < 1.5 ? 5.0 : 7.0);
	float ang = style < 0.5 ? 0.85 : (style < 1.5 ? 0.3 : 0.6);
	float len = style < 0.5 ? 0.26 : (style < 1.5 ? 0.5 : 0.28);
	float hw = style < 0.5 ? 0.07 : (style < 1.5 ? 0.035 : 0.035);
	vec2 p = vec2(uv.x * aspect, uv.y);
	float best = (0.008 - abs(p.x)) / 0.02 * step(uv.y, 0.9);
	float slot = floor(uv.y * n);
	for (float k = -2.0; k <= 1.0; k += 1.0) {
		float j = slot + k;
		if (j < 0.0 || j >= n) {
			continue;
		}
		float jit = h21(vec2(j, rnd * 37.0));
		float yb = (j + 0.2 + 0.4 * jit) / n * 0.82;
		float l = len * (0.75 + 0.35 * jit) * (1.0 - yb * 0.35);
		float a = ang * (0.85 + 0.3 * jit);
		float sd = mod(j, 2.0) < 0.5 ? 1.0 : -1.0;
		if (style > 1.5) {
			// Opposite pairs.
			best = max(best, sprig_leaf(p, vec2(0.0, yb), vec2(sin(a), cos(a)), l, hw));
			best = max(best, sprig_leaf(p, vec2(0.0, yb), vec2(-sin(a), cos(a)), l, hw));
		} else {
			best = max(best, sprig_leaf(p, vec2(0.0, yb), vec2(sd * sin(a), cos(a)), l, hw));
		}
	}
	// The terminal leaf.
	best = max(best, sprig_leaf(p, vec2(0.0, 0.8), vec2(0.0, 1.0), min(len, 0.2), hw));
	return best * 0.5;
}

float cluster_card(vec2 uv, float cover, float rnd, float style) {
	// A cluster of leaves on one card: leaf-sized blobs in cells, fewer as the cover drops.
	vec2 q = vec2(uv.x * 0.5 + 0.5, uv.y);
	float edge = 1.0 - length(vec2(uv.x, uv.y * 2.0 - 1.0));
	float best = -1.0;
	if (style > 0.5 && style < 1.5) {
		// Eucalyptus: hanging strands of sickle leaves.
		float col = floor(q.x * 7.0);
		float x = fract(q.x * 7.0) - 0.5;
		float len = 0.5 + 0.5 * h21(vec2(col, rnd * 31.0));
		float y = 1.0 - q.y;
		float on = step(y, len) * step(h21(vec2(col, floor(y * 6.0) + rnd)), cover * 1.4);
		best = (0.32 - abs(x + 0.1 * sin(y * 9.0 + col))) * on * 3.0 - (1.0 - on);
		return min(best, edge + 0.3);
	}
	vec2 g = q * vec2(4.0, 4.0);
	vec2 id = floor(g);
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 c = id + vec2(float(i), float(j));
			float hh = h21(c + rnd * 17.0);
			if (hh > cover * 1.15 + 0.05) {
				continue;
			}
			vec2 ctr = c + vec2(h21(c + 3.1), h21(c + 5.7));
			float ang = h21(c + 9.3) * 6.2832;
			vec2 d = g - ctr;
			d = vec2(d.x * cos(ang) - d.y * sin(ang), d.x * sin(ang) + d.y * cos(ang));
			float k = 1.0 - length(d / vec2(0.32, 0.62));
			best = max(best, k);
		}
	}
	return min(best, edge + 0.15);
}

void fragment() {
	float kind = v_kind;
	float rnd = fract(v_rnd);
	vec3 albedo = COLOR.rgb;
	float rough = leaf_roughness;
	float spec = leaf_specular;
	float wet = clamp(road_wetness, 0.0, 1.0);
	bool leaf = kind >= 8.0;
	// Every face keeps the mesh's normal (Godot flips it for a back face; a tube's outside or a
	// leaf's crown normal is the same seen from either side).
	bool back = !FRONT_FACING;
	if (back) {
		NORMAL = -NORMAL;
	}
	if (!leaf) {
		// Bark, at real size (UV metres).
		vec2 b = UV;
		rough = 0.88;
		spec = 0.3;
		if (kind < 0.5) {
			// Smooth (fig, coral, dragon tree): a soft mottle and faint lenticels.
			float m = fbm(b * vec2(1.6, 0.8));
			float len = smoothstep(0.92, 0.97, vnoise(vec2(b.x * 9.0, b.y * 40.0)));
			albedo *= 0.85 + 0.3 * m - len * 0.15;
		} else if (kind < 1.5) {
			// Eucalyptus: cream where the bark has shed, grey-green and salmon patches where it
			// has not, long vertical strips, and the rough old bark kept at the foot.
			float m = fbm(b * vec2(1.4, 0.35));
			float strip = vnoise(vec2(b.x * 7.0, b.y * 0.25));
			vec3 cream = albedo * vec3(1.08, 1.06, 1.0);
			vec3 grey = albedo * vec3(0.62, 0.66, 0.6);
			vec3 salmon = albedo * vec3(1.05, 0.82, 0.68);
			vec3 c = mix(cream, grey, smoothstep(0.5, 0.58, m));
			c = mix(c, salmon, smoothstep(0.62, 0.7, strip) * 0.7);
			float foot = 1.0 - smoothstep(1.0, 2.6, v_obj.y);
			float fib = 0.6 + 0.4 * vnoise(vec2(b.x * 14.0, b.y * 1.5));
			c = mix(c, albedo * vec3(0.45, 0.4, 0.34) * fib, foot);
			albedo = c;
		} else if (kind < 2.5) {
			// Sycamore: white with a jigsaw of tan and grey-olive patches.
			float m = fbm(b * vec2(2.2, 1.4));
			float m2 = vnoise(b * vec2(3.1, 2.3) + 11.0);
			vec3 c = albedo;
			c = mix(c, albedo * vec3(0.72, 0.66, 0.55), smoothstep(0.52, 0.56, m));
			c = mix(c, albedo * vec3(0.6, 0.62, 0.52), smoothstep(0.6, 0.64, m2) * 0.8);
			float foot = 1.0 - smoothstep(0.6, 2.0, v_obj.y);
			c = mix(c, albedo * vec3(0.5, 0.46, 0.4), foot * 0.8);
			albedo = c;
		} else if (kind < 3.5) {
			// Olive: deep twisting furrows.
			float warp = fbm(b * vec2(1.2, 0.5)) * 4.0;
			float f = abs(sin(b.x * 11.0 + warp + b.y * 0.6));
			albedo *= mix(0.45, 1.08, smoothstep(0.1, 0.6, f)) * (0.85 + 0.25 * vnoise(b * 3.0));
		} else if (kind < 4.5) {
			// Fibrous (cypress trunk, yucca stems): the scars of old leaves in rings.
			float ring = 0.5 + 0.5 * sin(b.y * 38.0 + vnoise(b * vec2(6.0, 2.0)) * 3.0);
			albedo *= 0.7 + 0.35 * ring * (0.6 + 0.4 * vnoise(vec2(b.x * 10.0, b.y * 4.0)));
		} else {
			// Green stems and stalks.
			albedo *= 0.9 + 0.15 * vnoise(b * vec2(4.0, 1.0));
			rough = 0.6;
		}
		ALBEDO = albedo * mix(1.0, 0.7, wet);
		ROUGHNESS = mix(rough, wet_roughness + 0.2, wet);
		SPECULAR = spec;
	} else {
	// Leaves: cut the outline, then light it.
	vec2 uv = UV;
	float style = floor(fract(UV2.x) * 4.0 + 0.5);
	float k;
	if (kind < 8.5) {
		k = lance(uv);
	} else if (kind < 9.5) {
		k = oval(uv);
	} else if (kind < 10.5) {
		k = palmate(uv, rnd);
	} else if (kind < 11.5) {
		k = scale_spray(uv, rnd);
	} else if (kind < 12.5) {
		k = cluster_card(uv, fract(v_rnd), floor(v_rnd) * 0.01, style);
	} else if (kind < 14.5) {
		k = 1.0;
	} else if (kind < 15.5) {
		k = sword(uv);
	} else if (kind < 16.5) {
		k = paddle(uv, rnd);
	} else if (kind < 17.5) {
		k = flower(uv, rnd, style);
	} else if (kind < 18.5) {
		k = trifol(uv);
	} else {
		k = sprig(uv, style, rnd);
	}
	float aa = max(fwidth(k), 1e-4);
	ALPHA = clamp(k / aa + 0.5, 0.0, 1.0);
	ALPHA_SCISSOR_THRESHOLD = 0.5;

	// Per leaf: a little tone and hue of its own, a midrib, the tip a shade lighter.
	float tone = 0.88 + 0.24 * rnd;
	albedo *= tone;
	albedo = mix(albedo, albedo * vec3(1.08, 1.0, 0.86), fract(rnd * 7.7) * 0.4);
	if (kind < 12.0 || kind > 14.5 && kind < 16.5) {
		float rib = 1.0 - smoothstep(0.0, 0.09, abs(uv.x));
		albedo *= 1.0 + rib * 0.18;
		albedo *= 0.94 + 0.1 * uv.y;
	}
	if (kind > 12.5 && kind < 14.5) {
		// Agave: a waxy bloom, the margin's teeth, a dark terminal spine; the variegated one
		// with cream-yellow margins.
		float margin = smoothstep(0.62, 0.9, abs(uv.x));
		if (kind > 13.5) {
			albedo = mix(albedo, vec3(0.62, 0.55, 0.22), margin * 0.85);
		}
		float tooth = step(0.82, fract(uv.y * 26.0 + rnd)) * step(0.93, abs(uv.x));
		albedo = mix(albedo, vec3(0.12, 0.08, 0.05), max(tooth, smoothstep(0.93, 0.97, uv.y)));
		albedo *= 0.92 + 0.12 * vnoise(vec2(uv.x * 3.0, uv.y * 20.0) + rnd * 9.0);
		rough = 0.45;
	}
	if (kind > 16.5 && kind < 17.5) {
		rough = 0.5;
	}
	if (back) {
		// The underside is paler.
		albedo *= underside;
	}
	albedo *= mix(1.0, 0.86, wet);
	ALBEDO = albedo;
	ROUGHNESS = mix(rough, wet_roughness, wet);
	SPECULAR = mix(spec, 0.85, wet);
	vec3 to_cam = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	float facing = clamp(dot(to_cam, -normalize(sun_direction)), 0.0, 1.0);
	BACKLIGHT = albedo * translucency * (1.0 + scatter_gain * pow(facing, scatter_sharpness));
	}
}
