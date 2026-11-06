shader_type spatial;
render_mode cull_back;

// The real cabin of the car the player drives (and of parked cars he stands by): CarInteriorKit's
// one mesh per body type, what each vertex is in COLOR.r (CarInteriorKit.R_* / 16), UV in metres,
// UV2 0..1 across the screen, the cluster and the speaker grilles. The colours are a scheme per car
// (CarInterior.SCHEMES: charcoal cloth, black, grey, tan or oxblood leather), LINEAR Vector3s set
// from script; the jamb is the car's own paint. No textures: leather grain, cloth weave, carpet
// pile, perforations and the grille are a height drawn here and turned into a normal by screen
// derivatives (the mesh has no tangents, and a NORMAL_MAP without them does nothing). The cluster
// and the screen light up while somebody is at the wheel (`powered`), brighter after dark.

#include "res://shaders/color_space.gdshaderinc"

global uniform float night_factor;
global uniform float lamp_factor;

uniform vec3 seat_col = vec3(0.025, 0.025, 0.027);
uniform vec3 insert_col = vec3(0.03, 0.03, 0.032);
uniform vec3 dash_col = vec3(0.022, 0.022, 0.024);
uniform vec3 plastic_col = vec3(0.03, 0.03, 0.032);
uniform vec3 carpet_col = vec3(0.018, 0.018, 0.02);
uniform vec3 headliner_col = vec3(0.32, 0.31, 0.29);
uniform vec3 jamb_col = vec3(0.5, 0.5, 0.5);
// 1: leather seats (grain, a perforated insert); 0: cloth (a weave).
uniform float leather = 1.0;
uniform float powered = 0.0;
// The cabin's own light: interiors read darker than the street (most light comes in sideways).
uniform float cabin_ao = 0.82;
// DriverRain's night cabin (0 = as before): the street's sodium light that comes in through the glass
// lifting what faces the windows (`night_fill`, its colour `fill_col`, LINEAR), and the screens in
// their night mode - dark maps, dimmed - rather than daylight panels turned up after dark.
uniform float night_fill = 0.0;
uniform vec3 fill_col = vec3(0.9, 0.76, 0.6);
uniform float night_screens = 0.0;

varying vec3 lp;


float ih(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}


float inoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(ih(i), ih(i + vec2(1.0, 0.0)), u.x), mix(ih(i + vec2(0.0, 1.0)), ih(i + vec2(1.0, 1.0)), u.x), u.y);
}


void vertex() {
	lp = VERTEX;
}


void fragment() {
	int role = int(floor(COLOR.r * 16.0));
	vec2 uv = UV;
	vec3 alb = plastic_col;
	float rough = 0.6;
	float metal = 0.0;
	float h = 0.0;
	float h_scale = 0.0;
	vec3 emit = vec3(0.0);
	if (role == 0 || role == 1 || role == 11) {
		// Seats, inserts and the wheel's rim: leather grain or a cloth weave.
		alb = role == 1 ? insert_col : seat_col;
		if (role == 11) {
			alb = seat_col * 0.6 + vec3(0.004);
		}
		if (leather > 0.5 || role == 11) {
			h = inoise(uv * 260.0) * 0.6 + inoise(uv * 90.0) * 0.4;
			h_scale = 0.00035;
			rough = 0.42 + 0.12 * inoise(uv * 13.0);
			if (role == 1) {
				// Perforations in a grid.
				vec2 g = fract(uv * 110.0) - 0.5;
				float hole = 1.0 - smoothstep(0.12, 0.2, length(g));
				alb *= 1.0 - 0.6 * hole;
				h -= hole * 0.8;
			}
		} else {
			vec2 w = uv * vec2(420.0, 420.0);
			h = 0.5 + 0.5 * sin(w.x) * sin(w.y) + 0.3 * inoise(uv * 60.0);
			h_scale = 0.0002;
			rough = 0.9;
			alb *= 0.9 + 0.2 * inoise(uv * 40.0);
		}
	} else if (role == 2) {
		// Soft-touch dash: a fine pebble grain.
		alb = dash_col;
		h = inoise(uv * 380.0);
		h_scale = 0.00025;
		rough = 0.72;
	} else if (role == 3) {
		alb = plastic_col;
		h = inoise(uv * 300.0);
		h_scale = 0.0002;
		rough = 0.6;
	} else if (role == 4) {
		alb = carpet_col * (0.85 + 0.3 * inoise(uv * 70.0));
		h = inoise(uv * 520.0);
		h_scale = 0.0006;
		rough = 0.97;
	} else if (role == 5) {
		alb = headliner_col * (0.95 + 0.1 * inoise(uv * 30.0));
		h = inoise(uv * 400.0);
		h_scale = 0.0002;
		rough = 0.95;
	} else if (role == 6) {
		// Satin aluminium trim.
		alb = vec3(0.55, 0.56, 0.58);
		metal = 0.9;
		rough = 0.32;
		h = inoise(vec2(uv.x * 900.0, uv.y * 8.0));
		h_scale = 0.00005;
	} else if (role == 7) {
		// Piano black.
		alb = vec3(0.006);
		rough = 0.07;
	} else if (role == 8 || role == 9) {
		// The centre screen and the cluster: black glass, lit while somebody is at the wheel.
		alb = vec3(0.004);
		rough = 0.06;
		vec2 q = UV2;
		float on = powered * (0.55 + 0.45 * night_factor);
		float nm = night_screens * night_factor;
		on *= 1.0 - 0.45 * nm;
		vec3 ui = vec3(0.0);
		if (role == 8) {
			// A navigation map: blocks and a route, a strip of controls along the bottom.
			vec2 m = q * vec2(6.0, 4.0);
			float road = 1.0 - smoothstep(0.03, 0.06, min(abs(fract(m.x) - 0.5), abs(fract(m.y) - 0.5)));
			ui = vec3(0.03, 0.05, 0.08) + vec3(0.12, 0.13, 0.15) * road;
			if (nm > 0.0) {
				// Night mode: a near-black map, the streets faint grey, blocks a shade apart.
				vec2 blk = floor(m);
				float shade = 0.006 + 0.008 * ih(blk);
				vec3 dark = vec3(shade, shade * 1.15, shade * 1.5) + vec3(0.02, 0.024, 0.03) * road;
				ui = mix(ui, dark, nm);
			}
			float route = 1.0 - smoothstep(0.012, 0.02, abs(q.y - 0.55 - 0.15 * sin(q.x * 4.0)));
			ui += vec3(0.1, 0.45, 0.9) * route * (1.0 + 0.8 * nm);
			if (q.y > 0.82) {
				ui = vec3(0.05, 0.06, 0.08) + vec3(0.25) * step(0.7, fract(q.x * 6.0)) * step(0.88, q.y) * step(q.y, 0.95);
			}
		} else {
			// Two dials either side of a middle display.
			for (int k = 0; k < 2; k++) {
				vec2 c = vec2(k == 0 ? 0.22 : 0.78, 0.5);
				vec2 d = (q - c) * vec2(2.8, 1.0);
				float r = length(d);
				float ring = 1.0 - smoothstep(0.012, 0.025, abs(r - 0.4));
				float a = atan(d.y, d.x);
				float tick = step(0.55, fract(a * 6.0)) * (1.0 - smoothstep(0.02, 0.04, abs(r - 0.36)));
				float needle_a = k == 0 ? 2.4 : 1.8;
				vec2 nd = vec2(cos(needle_a), -sin(needle_a));
				float along = dot(d, nd);
				float off = abs(d.x * nd.y - d.y * nd.x);
				float needle = step(0.0, along) * step(along, 0.36) * (1.0 - smoothstep(0.006, 0.014, off));
				// Night mode: the rings a cool dim grey under the ticks, the needle the brightest thing.
				vec3 ring_col = mix(vec3(0.7, 0.75, 0.8), vec3(0.16, 0.2, 0.26), nm);
				ui += ring_col * (ring * 0.6 + tick * mix(0.5, 1.2, nm)) + vec3(1.0, 0.25, 0.05) * needle * (1.0 + 0.6 * nm);
			}
			vec2 mid = q - vec2(0.5);
			float panel = step(abs(mid.x), 0.1) * step(abs(mid.y), 0.3);
			// Night mode: a dark middle display with a lit frame and a speed readout, not a pale slab.
			float frame = panel * (1.0 - step(abs(mid.x), 0.092) * step(abs(mid.y), 0.28));
			float digits = step(abs(mid.x), 0.035) * step(abs(mid.y), 0.09) * step(0.5, fract(mid.x * 70.0 + 0.25));
			ui += mix(vec3(0.1, 0.25, 0.5) * panel, vec3(0.02, 0.04, 0.07) * panel + vec3(0.08, 0.2, 0.45) * frame + vec3(0.5, 0.6, 0.7) * digits, nm);
		}
		emit = ui * on * 1.4;
	} else if (role == 10) {
		alb = vec3(0.012);
		rough = 0.8;
	} else if (role == 12) {
		alb = vec3(0.45, 0.46, 0.48);
		metal = 0.85;
		rough = 0.4;
	} else if (role == 13) {
		alb = jamb_col;
		rough = 0.35;
	} else if (role == 14) {
		// A speaker grille: holes on a tight grid inside a ring.
		alb = vec3(0.012);
		vec2 g = fract(UV2 * 28.0) - 0.5;
		h = 1.0 - smoothstep(0.15, 0.3, length(g));
		h_scale = -0.0006;
		rough = 0.7;
	}
	if (h_scale != 0.0) {
		// A bump from the height's screen derivatives (Mikkelsen's surface gradient).
		vec3 dpdx = dFdx(VERTEX);
		vec3 dpdy = dFdy(VERTEX);
		float dhdx = dFdx(h) * h_scale;
		float dhdy = dFdy(h) * h_scale;
		vec3 r1 = cross(dpdy, NORMAL);
		vec3 r2 = cross(NORMAL, dpdx);
		float det = dot(dpdx, r1);
		if (abs(det) > 1e-12) {
			vec3 grad = sign(det) * (dhdx * r1 + dhdy * r2);
			NORMAL = normalize(abs(det) * NORMAL - grad);
		}
	}
	if (night_fill > 0.0) {
		// The street light through the glass: what faces up or sideways catches most of it.
		vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		float catch_l = 0.3 + 0.45 * max(wn.y, 0.0) + 0.25 * abs(wn.x) + 0.15 * max(-wn.y, 0.0);
		emit += alb * fill_col * lamp_factor * night_fill * catch_l;
	}
	ALBEDO = cs_out(alb);
	ROUGHNESS = rough;
	METALLIC = metal;
	AO = cabin_ao;
	AO_LIGHT_AFFECT = 0.3;
	EMISSION = cs_out(emit);
}
