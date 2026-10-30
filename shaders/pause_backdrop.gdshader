shader_type canvas_item;
render_mode unshaded;

// The pause menu's backdrop (scripts/ui/pause_menu.gd): the frozen game behind it, blurred down
// the screen texture's mips (Compatibility builds them too), pulled a little toward grey,
// darkened and vignetted, and darker still on the left where the menu column sits, so white
// type reads over any frame without a flat grey panel hiding the city.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
// Mip level the blur starts at (the second tap is one level softer), how dark the frame gets,
// how much colour it keeps, and how much darker the menu's side is.
uniform float blur_lod = 3.2;
uniform float darken = 0.46;
uniform float saturation = 0.75;
uniform float side_dark = 0.55;
uniform float vignette = 0.9;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 c = textureLod(screen_tex, uv, blur_lod).rgb * 0.55 + textureLod(screen_tex, uv, blur_lod + 1.2).rgb * 0.45;
	float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	c = mix(vec3(l), c, saturation);
	vec2 d = uv - vec2(0.5);
	c *= darken * clamp(1.0 - dot(d, d) * vignette, 0.0, 1.0);
	c *= mix(side_dark, 1.0, smoothstep(0.02, 0.62, uv.x));
	COLOR = vec4(c, 1.0);
}
