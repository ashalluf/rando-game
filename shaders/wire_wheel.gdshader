shader_type spatial;
render_mode cull_back;

// The lowriders' wire wheels (Lowrider.wire_wheel()): what a vertex is rides in its colour's
// alpha (0 rubber, 0.25 whitewall, 0.5 chrome, 0.75 gold plate, 1 the dark of the hub's throat),
// its albedo in the rgb (linear, as written). On a renderer with no reflections to mirror
// (Compatibility: the web and every opengl3 still) a metal reads black, so `reflections` false
// turns chrome and gold into a bright satin paint, as PropFactory.wheel_material() does.
uniform bool reflections = true;

void fragment() {
	float k = COLOR.a;
	vec3 c = COLOR.rgb;
	float metal = 0.0;
	float rough = 0.9;
	if (k < 0.125) {
		rough = 0.88;
	} else if (k < 0.375) {
		rough = 0.62;
	} else if (k < 0.625) {
		metal = 1.0;
		rough = 0.10;
	} else if (k < 0.875) {
		metal = 1.0;
		rough = 0.16;
	} else {
		rough = 0.7;
	}
	if (!reflections && metal > 0.5) {
		c = pow(c, vec3(0.62));
		metal = 0.25;
		rough = 0.34;
	}
	ALBEDO = c;
	METALLIC = metal;
	ROUGHNESS = rough;
	SPECULAR = 0.5;
}
