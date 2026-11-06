shader_type canvas_item;
render_mode unshaded;

// The downed screen (PlayerHealth): the world drained to a cold grey, the edges closing in, and a
// band of smoked glass across the middle for the card to sit on - the same frosted look as the
// weapon wheel and the wanted stars, so the whole HUD is one family. Reads the screen, so it
// works on the web build too (the blur is a handful of taps on the screen copy's mips).

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
// 0 off .. 1 fully down (PlayerHealth eases it in over the first half second).
uniform float amount : hint_range(0.0, 1.0) = 0.0;
// How much colour survives, and the cold tint the grey takes.
uniform float keep_color = 0.12;
uniform vec3 cold = vec3(0.90, 0.94, 1.0);
// The glass band: half its height as a fraction of the screen, and how dark it is.
uniform float band_half = 0.105;
uniform float band_dark = 0.55;

void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;
	float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	vec3 grey = mix(vec3(l), c, keep_color) * cold;
	vec2 d = (SCREEN_UV - 0.5) * vec2(1.25, 1.0);
	float vig = 1.0 - smoothstep(0.25, 0.85, length(d));
	grey *= mix(0.42, 1.0, vig);
	// The band: blurred and darkened, with a hairline of light along each edge.
	float edge = abs(SCREEN_UV.y - 0.5);
	float band = 1.0 - smoothstep(band_half - 0.002, band_half + 0.002, edge);
	if (band > 0.0) {
		vec3 b = vec3(0.0);
		for (int i = 0; i < 8; i++) {
			float a = float(i) * 0.785398;
			b += textureLod(screen_tex, SCREEN_UV + vec2(cos(a), sin(a)) * 0.012, 3.5).rgb;
		}
		b /= 8.0;
		float bl = dot(b, vec3(0.2126, 0.7152, 0.0722));
		vec3 glass = mix(vec3(bl), b, keep_color) * cold * band_dark;
		float rim = smoothstep(band_half - 0.004, band_half - 0.0005, edge) * 0.35;
		grey = mix(grey, glass + vec3(rim), band);
	}
	COLOR = vec4(mix(c, grey, amount), amount);
}
