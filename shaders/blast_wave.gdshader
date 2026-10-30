shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

// The blast's pressure wave (BlastFX._pressure_wave): an expanding sphere that refracts what is
// behind it in a band near its silhouette - the shell of compressed air, seen edge on - and
// passes everything else through untouched. Reads the screen, so the material draws FIRST among
// the transparent things (render_priority MIN, WeaponFX._shimmer's rule) and the web skips it.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float strength = 0.035;
uniform float fade = 1.0;
// Where on the shell the band sits (facing: 0 at the silhouette, 1 square on) and how wide.
uniform float band_at = 0.28;
uniform float band_width = 0.2;


void fragment() {
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float band = 1.0 - smoothstep(0.0, band_width, abs(facing - band_at));
	band *= smoothstep(0.0, 0.06, facing);
	// Bend outward from the centre of the sphere on screen: the view-space normal's xy.
	vec2 off = normalize(NORMAL.xy + vec2(1e-4)) * strength * band * fade;
	vec2 uv = clamp(SCREEN_UV - off, vec2(0.002), vec2(0.998));
	vec3 col = textureLod(screen_tex, uv, 0.0).rgb;
	// A faint brightening along the front: dust and condensation in the shock.
	col *= 1.0 + 0.10 * band * fade;
	ALBEDO = col;
	ALPHA = band * fade;
}
