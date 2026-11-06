shader_type spatial;
render_mode cull_back;

// The lowriders' wire wheels (Lowrider.wire_wheel()): what a vertex is rides in its colour's
// alpha (0 rubber, 0.25 whitewall, 0.5 chrome, 0.75 gold plate, 1 the dark of the hub's throat),
// its albedo in the rgb (linear, as written). On a renderer with no reflections to mirror
// (Compatibility: the web and every opengl3 still) a metal reads black, so `reflections` false
// turns chrome and gold into a bright satin paint, as PropFactory.wheel_material() does.
uniform bool reflections = true;
varying float wheel_r;

void vertex() {
	wheel_r = length(VERTEX.yz);
}

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
		// Satin, and darker than the whitewall, or the chrome lip reads as one wide white band
		// with it.
		c = c * 0.62;
		metal = 0.3;
		rough = 0.3;
	}
	if (k >= 0.125 && k < 0.375) {
		// The whitewall's dirt: greyer toward the tread and the bead.
		c *= 0.9 + 0.06 * sin(wheel_r * 380.0);
	}
	ALBEDO = c;
	METALLIC = metal;
	ROUGHNESS = rough;
	SPECULAR = 0.5;
}
