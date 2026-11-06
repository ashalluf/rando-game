shader_type canvas_item;
render_mode unshaded;

// Photo mode's side panel (scripts/ui/photo_mode.gd): a rounded slab of smoked glass. The frame
// behind it blurred down the screen texture's mips (Compatibility builds them too, as for the
// pause menu's backdrop), pulled toward grey and darkened so white type reads over any shot, a
// hairline rim, and nothing outside the rounded rect, so the photo beside it stays untouched.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
// The rect's size and corner radius in the control's own pixels (set by the script each layout).
uniform vec2 rect_size = vec2(440.0, 900.0);
uniform float radius = 22.0;
uniform float blur_lod = 3.0;
uniform float darken = 0.42;
uniform float saturation = 0.7;
uniform float rim = 0.16;

void fragment() {
	vec2 p = (UV - 0.5) * rect_size;
	vec2 q = abs(p) - (rect_size * 0.5 - vec2(radius));
	float d = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
	float a = clamp(0.5 - d, 0.0, 1.0);
	vec3 c = textureLod(screen_tex, SCREEN_UV, blur_lod).rgb * 0.5
		+ textureLod(screen_tex, SCREEN_UV, blur_lod + 1.3).rgb * 0.5;
	float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	c = mix(vec3(l), c, saturation) * darken;
	// A lighter top, like light falling on a pane, and the hairline round the edge.
	c += vec3(0.035) * (1.0 - UV.y);
	c += vec3(rim) * (1.0 - smoothstep(0.0, 1.6, abs(d + 0.8)));
	COLOR = vec4(c, a);
}
