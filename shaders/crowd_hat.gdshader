shader_type spatial;
// The crowd's headwear (CrowdHat): a six-panel cotton-twill cap, a ribbed knit beanie, a twill
// bucket hat and the police peaked cap, each one mesh fitted to its rig's head. Everything the
// eye reads up close is drawn here, on the mesh's own coordinates, so it costs no texture and
// no triangles: the twill, the panel seams and their topstitching, the embroidered eyelets, the
// rows of stitching round a brim, the sweatband, the knit's stitches and the cuff's ribs, a
// bucket's vent eyelets, a small original embroidered mark. Every pattern fades to its average
// once it is under a pixel (keep()).
//
// The mesh carries (CrowdHat builds it; the numbers are its constants):
//   COLOR.r  which part, (id + 0.5) / 16: the PART_ constants below
//   COLOR.g  occlusion baked from the shape (1 open, lower in folds and inside)
//   COLOR.b  the part's own 0..1 parameter: up a crown (0 the band edge, 1 the button; a bucket's
//            side wall is 0..0.78, the corner 0.78..0.80, the top 0.80..1), out across a brim
//            (0 at the crown, 1 at the edge), up a cuff (0 its lower edge, 1 the fold)
//   COLOR.a  a crown's ring radius / 0.25 m (its distances round the head in metres)
//   UV       round a crown: its angle x CrowdHat.R_REF (0.095, 0 at the front); up it: metres
//            from the band edge. Along a brim: metres along its edge (0 at its centre); across
//            it: metres in from the edge
// The frame the relief tilts the normal in comes from the screen derivatives of UV (the mesh
// has no tangents). Colours are linear on both renderers (color_space.gdshaderinc): every
// colour uniform is a source_color set from script as sRGB, read through cs_in().
// Both faces: the inside of a crown is seen under a bill, through a cap's opening and up into a
// bucket or a police cap, and drawn as the lining (FRONT_FACING) it needs no geometry of its own.
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

#include "res://shaders/color_space.gdshaderinc"

const int PART_CROWN = 0;
const int PART_BRIM_TOP = 1;
const int PART_BRIM_UNDER = 2;
const int PART_INNER = 3;
const int PART_BUTTON = 4;
const int PART_STRAP = 5;
const int PART_METAL = 6;
const int PART_KNIT = 7;
const int PART_CUFF = 8;
const int PART_PATENT = 9;
const int PART_BINDING = 10;
const int PART_BAND = 11;
const int PART_POLICE_CROWN = 12;
const float R_REF = 0.095;

// 0 cap, 1 beanie, 2 bucket, 3 police (CrowdHat.Kind).
uniform int kind = 0;
uniform vec3 main_color : source_color = vec3(0.12, 0.14, 0.22);
// The undervisor, the strap and the beanie's label.
uniform vec3 second_color : source_color = vec3(0.30, 0.31, 0.30);
uniform vec3 thread_color : source_color = vec3(0.16, 0.18, 0.26);
uniform vec3 metal_color : source_color = vec3(0.62, 0.56, 0.42);
// The embroidered mark on a cap's front or a bucket's side (0 none, 1-3 three original shapes,
// 4 the woven label on a beanie's cuff) and its thread.
uniform int mark = 0;
uniform vec3 mark_color : source_color = vec3(0.85, 0.83, 0.78);
// How many panels meet round the crown (a cap's six; a bucket's side is four).
uniform float panels = 6.0;
// Where the first seam falls round the crown, in radians from the front (a bucket's are off its
// front and back).
uniform float seam_offset = 0.0;
// Fabric: twill pitch (metres between twill lines), cotton roughness, the rim sheen of the pile,
// how far the slubs shift the albedo.
uniform float twill_pitch = 0.0011;
uniform float cotton_rough = 0.86;
uniform float sheen = 0.32;
uniform float slub = 0.07;
// Knit: stitch width and height (metres), and a 2x2 rib's repeat in the cuff.
uniform vec2 knit_stitch = vec2(0.0042, 0.0036);
uniform float rib_pitch = 0.0068;
// How deep the seams, stitches and knit read in the lighting (a gain on every slope).
uniform float relief = 1.0;
// A worn cap: its top faded by the sun (0..1), and grime worked into the band and the brim's
// edge (a rough sleeper's, CrowdHat.material(worn)).
uniform float wear = 0.25;
uniform float grime = 0.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// How much of a pattern of period `period` survives at this pixel footprint: 1 well over a
// pixel, 0 under one (its average takes over).
float keep(float period, float px) {
	return 1.0 - smoothstep(0.35, 0.9, px / period);
}

// A smooth bump of half-width w at distance d: its height and its slope.
vec2 bump(float d, float w) {
	float e = exp(-(d * d) / (w * w));
	return vec2(e, -2.0 * d / (w * w) * e);
}

// Dashes of stitching along `along` (metres): 1 on a stitch, 0 between.
float dashes(float along, float pitch) {
	float f = fract(along / pitch);
	return smoothstep(0.1, 0.25, f) * (1.0 - smoothstep(0.75, 0.9, f));
}

// The embroidered marks, in metres round the mark's centre (x across, y up): coverage.
float mark_shape(vec2 p, int m) {
	float t = 0.0012;
	if (m == 1) {
		// A ring with a dot.
		float r = length(p);
		return max(1.0 - smoothstep(0.0, t, abs(r - 0.0085) - 0.0014), 1.0 - smoothstep(0.0, t, r - 0.0028));
	} else if (m == 2) {
		// Two peaks over a line (a ridge line).
		float y1 = 0.009 - abs(p.x + 0.006) * 1.2;
		float y2 = 0.006 - abs(p.x - 0.008) * 1.1;
		float ridge = max(y1, y2);
		float line = abs(p.y - ridge) - 0.0012;
		float base = abs(p.y + 0.004) - 0.0010;
		float in_x = step(abs(p.x), 0.017);
		return in_x * max(1.0 - smoothstep(0.0, t, line), 1.0 - smoothstep(0.0, t, base));
	} else if (m == 3) {
		// A small wave over a bar.
		float w = p.y - 0.0035 * sin(p.x * 420.0);
		float wave = max(abs(w - 0.003) - 0.0012, abs(p.x) - 0.016);
		float bars = max(abs(p.y + 0.004) - 0.0008, abs(p.x) - 0.014);
		return max(1.0 - smoothstep(0.0, t, wave), 1.0 - smoothstep(0.0, t, bars));
	}
	return 0.0;
}

void fragment() {
	int part = int(COLOR.r * 16.0);
	float occ = COLOR.g;
	float param = COLOR.b;
	vec2 uv = UV;
	float px = max(length(fwidth(uv)), 1.0e-6);
	vec3 base = cs_in(main_color);
	vec3 thread = cs_in(thread_color);
	float rough = cotton_rough;
	float spec = 0.3;
	float metal = 0.0;
	float rim = sheen;
	vec2 slope = vec2(0.0);
	float tone = 1.0;

	bool woven = part == PART_CROWN || part == PART_BRIM_TOP || part == PART_BRIM_UNDER
		|| part == PART_BUTTON || part == PART_STRAP || part == PART_BINDING || part == PART_POLICE_CROWN;
	if (part == PART_BRIM_UNDER || part == PART_STRAP) {
		base = cs_in(second_color);
	}
	if (woven) {
		// Twill: fine diagonal ridges, then slubs (thicker yarn here and there) and a mottle.
		float k = keep(twill_pitch, px);
		float ph = (uv.x * 0.72 + uv.y) / twill_pitch * TAU;
		slope += vec2(0.72, 1.0) * cos(ph) * (0.18 * k * relief);
		tone *= 1.0 + 0.05 * sin(ph) * k;
		float ks = keep(0.004, px);
		float s1 = vnoise(vec2(uv.x * 900.0, uv.y * 160.0));
		tone *= 1.0 + slub * (s1 - 0.5) * ks;
		tone *= 0.94 + 0.12 * vnoise(uv * 60.0);
	}

	if (part == PART_CROWN || part == PART_POLICE_CROWN) {
		float ring = max(COLOR.a * 0.25, 0.004);
		float th = uv.x / R_REF;
		float panel = TAU / panels;
		float local = mod(th - seam_offset + 0.5 * panel, panel) - 0.5 * panel;
		float ds = abs(local) * ring;
		float sgn = sign(local);
		bool across = false;
		if (kind == 2) {
			// A bucket's top is one round piece, sewn to the side panels round its corner.
			float dr = abs(param - 0.79);
			if (param > 0.785 || dr < 0.008) {
				ds = dr;
				sgn = sign(param - 0.79);
				across = true;
			}
		}
		if (kind == 3) {
			// The police crown is one piece of wool: no panel seams.
			ds = 1.0;
		}
		float ks = keep(0.0025, px);
		// The seam: a valley with the cloth puffed up either side of it (metres of height).
		vec2 v = bump(ds, 0.0009);
		vec2 puff = bump(ds - 0.0026, 0.0016);
		float dh = (-0.0006 * v.y + 0.0003 * puff.y) * sgn * ks * relief;
		if (across) {
			slope.y += dh;
		} else {
			slope.x += dh;
		}
		tone *= mix(1.0, 0.72 + 0.28 * smoothstep(0.0, 0.0018, ds), ks);
		occ *= mix(1.0, 0.8 + 0.2 * smoothstep(0.0, 0.002, ds), ks);
		// Topstitching 3.2 mm off each seam: 2.6 mm stitches, 1 mm apart.
		float row = 1.0 - smoothstep(0.00025, 0.0005, abs(ds - 0.0032));
		float stitch = row * dashes(across ? uv.x : uv.y, 0.0036) * keep(0.0016, px) * step(0.06, param) * step(param, 0.94);
		base = mix(base, thread, stitch * 0.85);
		if (kind == 2) {
			// Two metal vent eyelets, one each side of a bucket's crown.
			float ey = (param - 0.42) * 0.09;
			float ex = (abs(th) - 0.5 * PI) * ring;
			float er = length(vec2(ex, ey));
			float ke = keep(0.002, px);
			float rim_m = (1.0 - smoothstep(0.0028, 0.0032, er)) * smoothstep(0.0014, 0.0018, er) * ke;
			float hole = (1.0 - smoothstep(0.0014, 0.0018, er)) * ke;
			base = mix(base, cs_in(metal_color), rim_m);
			metal = max(metal, rim_m);
			rough = mix(rough, 0.35, rim_m);
			base = mix(base, base * 0.1, hole);
		}
		if (kind == 0) {
			// An embroidered eyelet on each panel, two thirds of the way up.
			float ex = (mod(th, panel) - 0.5 * panel) * ring;
			float ey = (param - 0.70) * 0.12;
			float er = length(vec2(ex, ey));
			float ke = keep(0.002, px);
			float hole = 1.0 - smoothstep(0.0011, 0.0015, er);
			float ringe = (1.0 - smoothstep(0.0024, 0.0028, er)) * smoothstep(0.0012, 0.0015, er);
			base = mix(base, thread * 1.1, ringe * ke);
			base = mix(base, base * 0.12, hole * ke);
			occ *= 1.0 - 0.6 * hole * ke;
			vec2 eb = bump(er - 0.0021, 0.0007);
			slope += normalize(vec2(ex, ey) + 1.0e-7) * eb.y * 0.00025 * ke * relief;
		}
		// Sun fades the top.
		tone *= 1.0 - wear * 0.10 * smoothstep(0.5, 1.0, param);
		// The embroidered mark: on a cap's front panels, on a bucket's front.
		if (mark > 0 && mark < 4) {
			vec2 mp = vec2(th * ring, uv.y - (kind == 2 ? 0.024 : 0.040));
			float m = mark_shape(mp, mark);
			if (m > 0.0) {
				vec3 mc = cs_in(mark_color);
				float km = keep(0.003, px);
				// Satin stitches run across the shape; the thread is glossier than the cloth.
				float satin = 0.9 + 0.1 * sin((mp.x * 0.3 + mp.y) * 9000.0) * km;
				base = mix(base, mc * satin, m);
				tone = mix(tone, 1.0, m);
				rough = mix(rough, 0.55, m);
				rim = mix(rim, 0.1, m);
			}
		}
	} else if (part == PART_BRIM_TOP || part == PART_BRIM_UNDER) {
		// Rows of stitching parallel to the edge, 4.5 mm apart: eight on a cap, five on a bucket.
		float d = uv.y;
		float rows = kind == 2 ? 5.0 : 8.0;
		float r = (d - 0.004) / 0.0045;
		float fr = abs(fract(r + 0.5) - 0.5) * 0.0045;
		float in_rows = step(-0.3, r) * step(r, rows - 0.7);
		float row = (1.0 - smoothstep(0.0002, 0.00045, fr)) * in_rows;
		float k = keep(0.0018, px);
		float stitch = row * dashes(uv.x, 0.0034) * k;
		vec3 th_c = part == PART_BRIM_UNDER ? cs_in(second_color) * 0.75 : thread;
		base = mix(base, th_c, stitch * 0.85);
		// Each row pulls the cloth in a little: a soft groove under the stitches.
		vec2 g = bump(fr, 0.0006);
		slope.y += g.y * sign(fract(r + 0.5) - 0.5) * 0.00022 * k * relief * in_rows;
		// The board under the top has a faint wave.
		slope.y += 0.03 * sin(uv.x * 140.0) * keep(0.02, px);
		if (part == PART_BRIM_UNDER) {
			occ *= 0.8;
		}
	} else if (part == PART_BINDING) {
		// The taped edge: one row of stitches down its middle.
		float row = 1.0 - smoothstep(0.2, 0.32, abs(param - 0.5));
		base = mix(base, thread, row * dashes(uv.x, 0.003) * keep(0.0016, px) * 0.8);
	} else if (part == PART_INNER) {
		// The sweatband and the lining: a dull ribbed tape, darkened with use.
		base = mix(cs_in(second_color) * 0.45, vec3(0.012, 0.011, 0.010), 0.5);
		float k = keep(0.0016, px);
		slope.y += cos(uv.y / 0.0014 * TAU) * 0.2 * k * relief;
		rough = 0.9;
		rim = 0.05;
	} else if (part == PART_BUTTON) {
		occ *= 0.9;
	} else if (part == PART_STRAP) {
		float e = min(param, 1.0 - param);
		float row = 1.0 - smoothstep(0.08, 0.14, abs(e - 0.18));
		base = mix(base, thread, row * dashes(uv.x, 0.003) * keep(0.0016, px) * 0.8);
	} else if (part == PART_METAL) {
		base = cs_in(metal_color);
		// Brass and nickel, a little worn: part metal, part the dull film on it (in a city with
		// only the sky to mirror, a pure metal this small reads as a dark blot).
		metal = 0.7;
		rough = 0.34;
		spec = 0.5;
		rim = 0.0;
	} else if (part == PART_PATENT) {
		base = vec3(0.004, 0.004, 0.005);
		rough = 0.14;
		spec = 0.6;
		rim = 0.0;
		CLEARCOAT = 0.6;
		CLEARCOAT_ROUGHNESS = 0.08;
	} else if (part == PART_BAND) {
		// The police cap's band: a fine black braid.
		base = vec3(0.004, 0.004, 0.005);
		float k = keep(0.0015, px);
		slope.y += cos(uv.y / 0.0012 * TAU) * 0.25 * k * relief;
		rough = 0.6;
		rim = 0.15;
	} else if (part == PART_KNIT || part == PART_CUFF) {
		rough = 0.96;
		rim = 0.55;
		spec = 0.2;
		vec2 st = knit_stitch;
		if (part == PART_CUFF) {
			// 2x2 rib: two knit columns standing out, two purl columns sunk between them.
			float rp = rib_pitch;
			float ph = uv.x / rp * TAU;
			float kr = keep(rp, px);
			slope.x += -sin(ph) * (TAU / rp) * 0.0008 * kr * relief;
			tone *= 1.0 + 0.16 * cos(ph) * kr;
			occ *= 1.0 - 0.14 * (0.5 - 0.5 * cos(ph)) * kr;
			st.x = rp * 0.5;
		}
		// Stockinette: every column a stack of Vs, each leg of yarn leaning in to the column's
		// middle. h is the yarn's height over the cell.
		vec2 c = uv / st;
		vec2 f = fract(c);
		float xh = abs(f.x - 0.5) * 2.0;
		float leg = abs(xh - (1.0 - f.y) * 0.85 - 0.08);
		vec2 lb = bump(leg, 0.32);
		float k = keep(st.x, px);
		float h = lb.x * (0.75 + 0.25 * sin(PI * f.y));
		float dhdx = lb.y * sign(f.x - 0.5) * 2.0 / st.x;
		float dhdy = lb.y * 0.85 / st.y;
		slope += vec2(dhdx, dhdy) * 0.0005 * k * relief;
		tone *= mix(1.0, 0.78 + 0.32 * h, k);
		occ *= mix(1.0, 0.86 + 0.14 * h, k);
		// Yarn varies thread to thread (a heather), and the fibres catch the light as fuzz.
		float hv = vnoise(vec2(floor(c.x), c.y * 0.35) * 1.7);
		tone *= 1.0 + 0.10 * (hv - 0.5) * keep(st.x * 2.0, px);
		tone *= 0.95 + 0.1 * vnoise(uv * 45.0);
		if (part == PART_KNIT) {
			// The crown's decreases: six lines in to the top where the stitches were taken in.
			float ring = max(COLOR.a * 0.25, 0.004);
			float th = uv.x / R_REF;
			float panel = TAU / 6.0;
			float ds = abs(mod(th + 0.5 * panel, panel) - 0.5 * panel) * ring;
			float dl = (1.0 - smoothstep(0.0008, 0.0022, ds)) * smoothstep(0.72, 0.86, param);
			tone *= 1.0 - 0.18 * dl * keep(0.003, px);
		}
		if (mark == 4 && part == PART_CUFF) {
			// A small woven label sewn on the cuff's front.
			vec2 lp = vec2(uv.x - 0.030, uv.y - 0.026);
			vec2 q = abs(lp) - vec2(0.013, 0.0075);
			float dbox = max(q.x, q.y);
			float lab = 1.0 - smoothstep(-0.0003, 0.0003, dbox);
			if (lab > 0.0) {
				vec3 lc = cs_in(second_color);
				float border = smoothstep(-0.0016, -0.0010, dbox);
				lc = mix(lc, cs_in(mark_color), border * 0.8);
				float inner = mark_shape(lp * 1.8, 1) * (1.0 - border);
				lc = mix(lc, cs_in(mark_color), inner * 0.9);
				base = mix(base, lc, lab);
				tone = mix(tone, 1.0, lab);
				slope = mix(slope, vec2(0.0), lab);
				rough = mix(rough, 0.7, lab);
				rim = mix(rim, 0.1, lab);
			}
		}
	}

	if (grime > 0.0) {
		// Grime: heaviest where hands and the forehead touch - the band, a brim's edge, a cuff -
		// in blotches.
		float low = part == PART_CROWN || part == PART_KNIT ? 1.0 - smoothstep(0.0, 0.35, param)
			: (part == PART_BRIM_TOP || part == PART_BRIM_UNDER ? smoothstep(0.6, 1.0, param) : 0.6);
		float blot = vnoise(uv * 38.0) * 0.6 + vnoise(uv * 110.0) * 0.4;
		tone *= 1.0 - grime * 0.4 * clamp(low * 0.7 + blot * 0.5, 0.0, 1.0);
		rough = min(1.0, rough + grime * 0.05);
	}

	if (!FRONT_FACING && part != PART_METAL) {
		// The inside: a cap's lining and seam tape, a knit's purl side, a peak's underside, all
		// in the shadow of the head they sit on.
		if (part == PART_KNIT || part == PART_CUFF) {
			base = cs_in(main_color) * 0.55;
		} else if (part == PART_PATENT || part == PART_BAND) {
			base = vec3(0.01, 0.01, 0.012);
		} else {
			base = mix(cs_in(second_color), cs_in(main_color), 0.5) * 0.45;
		}
		tone = 1.0;
		slope = vec2(0.0);
		occ *= 0.4;
		rim = 0.0;
		rough = 0.9;
		metal = 0.0;
	}

	// The surface's frame along UV, from screen derivatives (the mesh has no tangents).
	vec3 nn = normalize(NORMAL);
	vec3 dp1 = dFdx(VERTEX);
	vec3 dp2 = dFdy(VERTEX);
	vec2 duv1 = dFdx(uv);
	vec2 duv2 = dFdy(uv);
	vec3 dp2perp = cross(dp2, nn);
	vec3 dp1perp = cross(nn, dp1);
	vec3 t = dp2perp * duv1.x + dp1perp * duv2.x;
	vec3 b = dp2perp * duv1.y + dp1perp * duv2.y;
	float invmax = inversesqrt(max(max(dot(t, t), dot(b, b)), 1.0e-20));
	NORMAL = normalize(nn - t * invmax * slope.x - b * invmax * slope.y);
	ALBEDO = cs_out(base * tone);
	ROUGHNESS = rough;
	SPECULAR = spec;
	METALLIC = metal;
	AO = clamp(occ, 0.0, 1.0);
	AO_LIGHT_AFFECT = 0.35;
	RIM = rim;
	RIM_TINT = 0.6;
}
