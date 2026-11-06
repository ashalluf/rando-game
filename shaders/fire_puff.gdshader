shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// The fireball's puffs (WeaponFX.explosion, via WeaponFX._fire_material()). They were the plain
// puff material - ramp colour times a grey billow - and forty of them overlapping came out one
// flat orange cloud that read as dust, because every part of a puff was the same temperature.
// Real fire is hottest where it is thickest: here the billow's own density is the heat, so the
// dense lumps burn yellow-white (HDR, so they bloom) and the thin edges cool to red and then to
// soot, and every puff carries its own hot core and dark rim. Desktop only; the web keeps the
// plain puff material (this reads the depth buffer).

uniform sampler2D puff_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;
// Brightness of the densest part of a puff and of its thinnest edge, against the ramp colour.
uniform float core_heat = 1.9;
uniform float edge_cool = 0.32;
// How black the thin edges go as the puff cools (0 = no soot).
uniform float soot = 0.85;
// Metres over which a puff fades out into whatever it meets. At 1.2 the road still cut the
// fireball along a straight line: a puff is metres across and the fade was a sliver of it.
uniform float soft_distance = 2.6;
// Self-shadowed billows (BlastFX sets it; 0 is the old flat puff): each lump of the texture is
// lit from the hot core below it and shaded on its upper side, and the ball's rim is darker, so
// a fireball reads as rolling masses with depth instead of a flat orange card.
uniform float relief = 0.0;

varying vec2 v_down;


void vertex() {
	// Particle billboard that keeps the particle's scale and spins it by its own angle, the same
	// transform StandardMaterial3D's BILLBOARD_PARTICLES + billboard_keep_scale builds.
	mat4 world = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	float a = INSTANCE_CUSTOM.x;
	world = world * mat4(vec4(cos(a), -sin(a), 0.0, 0.0), vec4(sin(a), cos(a), 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * world;
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	// World down in the card's own axes (x along the card, y up it), for the billow shading.
	v_down = vec2(-world[0].y, -world[1].y) / max(length(vec2(world[0].y, world[1].y)), 1e-3);
}


void fragment() {
	vec4 tex = texture(puff_tex, UV);
	// The billow's shade runs 0.40..1.0 (WeaponFX.puff_texture()), 0.13..1.0 once source_color
	// has decoded it; its alpha is the outline.
	float dens = tex.r * smoothstep(0.0, 0.6, tex.a);
	float heat = smoothstep(0.25, 0.85, dens);
	vec3 col = COLOR.rgb * mix(edge_cool, core_heat, heat);
	// How far this puff has cooled, from its own ramp colour: 0 white-hot, 1 spent.
	float spent = 1.0 - clamp(dot(COLOR.rgb, vec3(0.30, 0.55, 0.15)) / 1.4, 0.0, 1.0);
	col = mix(col, vec3(0.035, 0.028, 0.022), spent * (1.0 - heat) * soot);
	if (relief > 0.0) {
		float e = 1.0 / 48.0;
		float gx = texture(puff_tex, UV + vec2(e, 0.0)).r - texture(puff_tex, UV - vec2(e, 0.0)).r;
		float gy = texture(puff_tex, UV - vec2(0.0, e)).r - texture(puff_tex, UV + vec2(0.0, e)).r;
		// A slope facing the core (down) is lit by it; a crest facing up is in its own shadow.
		vec2 slope = -vec2(gx, gy) * 3.0;
		float lit = clamp(dot(slope, v_down), -0.6, 0.6);
		float rim = smoothstep(0.45, 1.0, length((UV - 0.5) * 2.0));
		col *= max(1.0 + relief * (lit - 0.35 * rim) + relief * 0.25 * (heat - 0.5), 0.15);
	}
	ALBEDO = col;
	ALPHA = COLOR.a * tex.a;

	float depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec4 behind = INV_PROJECTION_MATRIX * vec4(vec3(SCREEN_UV, depth) * 2.0 - 1.0, 1.0);
#else
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
#endif
	behind.xyz /= behind.w;
	ALPHA *= clamp(1.0 - smoothstep(behind.z + soft_distance, behind.z, VERTEX.z), 0.0, 1.0);
}
