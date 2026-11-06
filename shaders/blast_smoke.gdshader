shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// The blast's smoke column, cap and debris trails (BlastFX). The old smoke was flat grey cards:
// unshaded, every puff the same colour on its sunny and its shaded side, so a column of them read
// as fog. Here every puff is LIT by hand (unshaded, so both renderers draw the same thing): a
// round billow's normal from its place on the card plus the relief of the puff texture, the sun
// (`sun_direction`) on it with a wrap, the sky (`sky_tint`) from above, a darker ground bounce
// from below, and while the puff is young (INSTANCE_CUSTOM.y, its age over its life) the fire's
// orange glow on its underside. Dense cores take less of the light through (self-shadowing), so a
// billow has a bright shoulder toward the sun and a dark belly. Colours are linear on both
// renderers (color_space.gdshaderinc); COLOR is the ramp's linear albedo and alpha.

#include "res://shaders/color_space.gdshaderinc"

global uniform vec4 sky_tint;
global uniform vec3 sun_direction;
global uniform float night_factor;
global uniform float lamp_factor;

uniform sampler2D puff_tex : filter_linear_mipmap, repeat_disable;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;
// Sun and sky strength on the smoke's albedo.
uniform float sun_gain = 2.6;
uniform float sky_gain = 0.85;
uniform float ground_gain = 0.25;
// How much the puff texture's own relief bends the billow's normal.
uniform float relief = 2.2;
// The fire under a young puff: colour (linear) and how long (share of the life) it lasts.
uniform vec3 fire_glow = vec3(2.6, 0.9, 0.22);
uniform float fire_share = 0.12;
// Soft particles (metres) and the fade near the lens.
uniform float soft_distance = 3.0;
uniform float near_fade = 2.5;
// Blast3 (explosions-3): the fires burning now (xyz world, w strength 0..1 x their reach in m,
// packed as reach + strength / 2: Blast3.push_fires()), so smoke is lit from below only by fire
// that is still burning. `fire_count` 0 is the old "young puff" glow alone.
uniform vec4 fires[4];
uniform int fire_count = 0;
uniform float fire_light_gain = 1.6;
// How much of the old young-puff glow stays when the fires are known (0..1).
uniform float young_glow = 1.0;
// After dark the street lamps' glow on the smoke's underside (linear, x lamp_factor).
uniform vec3 city_glow = vec3(0.0);
// Light through thin smoke looking toward the sun (a forward-scattering lobe, 0 off).
uniform float forward_scatter = 0.0;

varying float v_age;
varying mat3 v_card;
varying vec3 v_world;


void vertex() {
	mat4 world = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	float a = INSTANCE_CUSTOM.x;
	mat4 spin = mat4(vec4(cos(a), -sin(a), 0.0, 0.0), vec4(sin(a), cos(a), 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	world = world * spin;
	MODELVIEW_MATRIX = VIEW_MATRIX * world;
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	v_age = INSTANCE_CUSTOM.y;
	v_world = MODEL_MATRIX[3].xyz;
	// The card's own axes in WORLD space (x right along the card, y up it, z toward the eye).
	v_card = mat3(normalize(world[0].xyz), normalize(world[1].xyz), normalize(world[2].xyz));
}


void fragment() {
	vec4 tex = texture(puff_tex, UV);
	float e = 1.0 / 48.0;
	float tx = texture(puff_tex, UV + vec2(e, 0.0)).r - texture(puff_tex, UV - vec2(e, 0.0)).r;
	float ty = texture(puff_tex, UV + vec2(0.0, e)).r - texture(puff_tex, UV - vec2(0.0, e)).r;
	// A ball's normal from where on the card this is, bent by the billows in the texture.
	vec2 q = (UV - 0.5) * 2.0;
	q.y = -q.y;
	float r2 = dot(q, q);
	vec3 nc = vec3(q * 0.9, sqrt(max(1.0 - min(r2, 1.0) * 0.81, 0.05)));
	nc.xy -= vec2(tx, -ty) * relief;
	vec3 n = normalize(v_card * normalize(nc));

	float dens = tex.r * smoothstep(0.0, 0.6, tex.a);
	vec3 alb = COLOR.rgb;
	vec3 L = normalize(sun_direction);
	float day = 1.0 - night_factor;
	// The sun warms as it sets and is gone at night (the city's glow comes through sky_tint).
	vec3 sun = mix(vec3(1.0, 0.55, 0.3), vec3(1.0, 0.95, 0.88), smoothstep(0.0, 0.35, L.y)) * smoothstep(-0.05, 0.08, L.y) * day;
	float wrap = clamp((dot(n, L) + 0.35) / 1.35, 0.0, 1.0);
	// Self-shadowing: light through a thick core is lost, so the dense side away from the sun
	// stays dark and only the shoulder catches it.
	float through = mix(1.0, 0.35, dens) ;
	float lit_sun = wrap * mix(through, 1.0, wrap);
	vec3 sky = cs_srgb_to_linear(sky_tint.rgb);
	float up = n.y * 0.5 + 0.5;
	vec3 amb = sky * sky_gain * mix(0.35, 1.0, up) + sky * ground_gain * (1.0 - up) * vec3(0.9, 0.85, 0.8);
	// The fire under a young puff, on its underside.
	float young = 1.0 - smoothstep(0.0, fire_share, v_age);
	vec3 glow = fire_glow * young * young * clamp(-n.y * 0.7 + 0.45, 0.0, 1.0) * (0.6 + 0.4 * dens);
	glow *= young_glow;
	// The fires that are burning now, each lighting the side of the puff that faces it.
	for (int i = 0; i < 4; i++) {
		if (i >= fire_count) {
			break;
		}
		vec4 f = fires[i];
		float reach = floor(f.w);
		float str = fract(f.w) * 2.0;
		vec3 to = f.xyz - v_world;
		float d = length(to);
		float fall = str / (1.0 + d * d / max(reach * reach * 0.12, 1.0));
		float face = clamp(dot(n, to / max(d, 0.01)) * 0.6 + 0.5, 0.0, 1.0);
		glow += fire_glow * fire_light_gain * fall * face * (0.6 + 0.4 * dens) / 6.0;
	}
	// The city's sodium glow on the underside after dark.
	glow += city_glow * lamp_factor * clamp(-n.y * 0.6 + 0.5, 0.0, 1.0) / 6.0;
	// Thin smoke between the eye and the sun glows (silver lining); thick cores do not.
	vec3 vdir = normalize(v_world - CAMERA_POSITION_WORLD);
	float g = 0.6;
	float cosv = dot(vdir, L);
	float hg = (1.0 - g * g) / pow(max(1.0 + g * g - 2.0 * g * cosv, 1e-3), 1.5) * 0.08;
	vec3 fwd = sun * forward_scatter * hg * (1.0 - dens) * (1.0 - tex.a * 0.5);
	vec3 col = alb * (sun * sun_gain * lit_sun + amb * mix(1.0, 0.55, dens)) + alb * glow * 6.0 + fwd * 0.12;
	ALBEDO = cs_out(col);
	ALPHA = COLOR.a * tex.a;

	float depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec4 behind = INV_PROJECTION_MATRIX * vec4(vec3(SCREEN_UV, depth) * 2.0 - 1.0, 1.0);
#else
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
#endif
	behind.xyz /= behind.w;
	ALPHA *= clamp(1.0 - smoothstep(behind.z + soft_distance, behind.z, VERTEX.z), 0.0, 1.0);
	// A puff over the lens would black the screen out.
	ALPHA *= smoothstep(0.3, near_fade, -VERTEX.z);
}
