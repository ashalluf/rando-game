shader_type spatial;
render_mode cull_back;

// The land beyond the streamed chunks. The ground follower used to be one grass-textured plane,
// so from the air everything outside the loaded city was a flat green table with a hard edge
// where the plane stopped. This shades the same plane from a small image of the whole basin
// baked by MacroMap.bake(): ocean to the west, the mountains to the north, the airport, the
// city sprawl, with relief shading from the baked height and haze that hands the horizon over
// to the sky.

// RGB is the ground colour, A is land height / 400 m (exactly 0 on water).
uniform sampler2D macro_tex : filter_linear, source_color;
// World XZ the baked image is centred on, and how many metres across it covers.
uniform vec2 macro_centre = vec2(0.0);
uniform float macro_span = 16000.0;
// The scene's origin has been shifted this far; local + offset is the true world position.
uniform vec2 world_offset = vec2(0.0);

// Close to the camera the plane is the ground the player is standing on, so a real texture
// takes over, tinted by whatever the macro map says is there.
uniform sampler2D near_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D near_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float near_scale = 6.0;
uniform float near_fade_start = 60.0;
uniform float near_fade_end = 340.0;

// Aerial perspective: the far land washes out into the sky's own horizon colour, which DayNight
// keeps in step with the weather and the hour.
uniform vec3 haze_color : source_color = vec3(0.70, 0.78, 0.88);
// Only a last touch at the very edge of the plane, to hide its rim. The Environment's own
// aerial-perspective fog does the real distance wash, and doing it twice turned the whole basin
// into milk: at the settings this scene uses, 3 km of air is already half haze.
uniform float haze_start = 4500.0;
uniform float haze_end = 7400.0;
uniform float haze_strength : hint_range(0.0, 1.0) = 0.45;

uniform vec3 sun_dir = vec3(0.45, 0.72, 0.28);
global uniform float night_factor;

varying vec3 world_pos;


float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}


float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}


void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 vuv = ((wp.xz + world_offset) - macro_centre) / macro_span + vec2(0.5);

	// Drop the plane right out from under the sea. The water chunks put their surface 15 cm
	// above it and their troughs a metre or more BELOW it, so this plane kept drawing through
	// the waves in smooth grey patches, and a kilometre out the 15 cm is below depth precision
	// and the two z-fight as well. Wherever the baked map says water (alpha exactly zero), the
	// plane goes 24 m down, which is under the deepest storm trough. Over land it does not
	// move, so the coast keeps its shape.
	float wet = 1.0 - step(0.0005, textureLod(macro_tex, vuv, 0.0).a);
	// And a small sink with distance for the land, which the chunk ground sits only centimetres
	// above.
	float d = distance(wp, (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz);
	float sink = wet * 24.0 + (1.0 - wet) * smoothstep(400.0, 2000.0, d) * 5.0;
	VERTEX.y -= sink;
	world_pos = wp - vec3(0.0, sink, 0.0);
}


void fragment() {
	vec2 w = world_pos.xz + world_offset;
	vec2 uv = (w - macro_centre) / macro_span + vec2(0.5);
	vec4 m = texture(macro_tex, uv);

	// Relief shading from the baked height. Without it the far land is a flat colour field and
	// the mountains read as a green stain rather than as mountains.
	float texel = 1.0 / float(textureSize(macro_tex, 0).x);
	float metres_per_texel = macro_span * texel;
	float hx = texture(macro_tex, uv + vec2(texel, 0.0)).a - texture(macro_tex, uv - vec2(texel, 0.0)).a;
	float hz = texture(macro_tex, uv + vec2(0.0, texel)).a - texture(macro_tex, uv - vec2(0.0, texel)).a;
	vec3 n = normalize(vec3(-hx * 400.0 / (2.0 * metres_per_texel), 1.0, -hz * 400.0 / (2.0 * metres_per_texel)));
	float shade = 0.42 + 0.72 * clamp(dot(n, normalize(sun_dir)), 0.0, 1.0);
	vec3 col = m.rgb * shade;

	// Break up the bilinear smear between texels: at 60 m per texel the bare image reads as a
	// blurred painting, and a little noise at field and hillside scale reads as terrain.
	float grain = 0.86 + 0.28 * vnoise(w * 0.011) * (0.5 + 0.5 * vnoise(w * 0.047));
	col *= grain;

	vec3 eye = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float dist = length(world_pos - eye);
	float rough = 0.95;

	// The sea is not a flat blue field. Looked down on it is nearly black and takes its colour
	// from the sky it reflects, and there is a glare path burning along the line to the sun.
	float water = 1.0 - step(0.0005, m.a);
	if (water > 0.5) {
		vec3 view = normalize(world_pos - eye);
		float fres = pow(1.0 - clamp(-view.y, 0.0, 1.0), 5.0);
		vec3 refl = reflect(view, vec3(0.0, 1.0, 0.0));
		float glare = pow(max(dot(refl, normalize(sun_dir)), 0.0), 70.0);
		col = mix(m.rgb, haze_color, clamp(0.10 + 0.78 * fres, 0.0, 0.92));
		col += vec3(1.0, 0.94, 0.82) * glare * 1.8 * (1.0 - night_factor);
		rough = 0.22;
	}

	// Under the player's feet this is just ground, so the real texture takes over, tinted by
	// whatever the macro map says is down there (sand on a beach, green on a hillside).
	// Never blend the grass detail over open water.
	float near = (1.0 - smoothstep(near_fade_start, near_fade_end, dist)) * (1.0 - water);
	vec3 nm = vec3(0.5, 0.5, 1.0);
	if (near > 0.002) {
		// Use the detail texture for its light and shade only, not its colour: it is a grass
		// photograph, and letting its green through painted a green verge along the beach and
		// over the sea. The zone colour from the macro map stays in charge.
		vec3 detail = texture(near_albedo, w / near_scale).rgb;
		float lum = dot(detail, vec3(0.3333));
		col = mix(col, m.rgb * (0.62 + 1.05 * lum) * shade, near);
		nm = mix(nm, texture(near_normal, w / near_scale).rgb, near);
	}

	col = mix(col, haze_color, smoothstep(haze_start, haze_end, dist) * haze_strength);
	col *= mix(1.0, 0.16, night_factor);

	// Beyond the detail band this plane is a painted horizon, not a surface: it is dead flat,
	// it has no texture to catch light, and leaving the renderer to light it washed the whole
	// basin into whatever the ambient happened to be - a blue midday sky turned grass, sand and
	// tarmac into the same grey-blue. Past the near band it is emitted at face value instead,
	// so the map reads the way it was painted (the relief shading above is already baked into
	// it), and the Environment's aerial-perspective fog still does the distance wash on top.
	float painted = smoothstep(near_fade_end * 0.6, near_fade_end * 1.8, dist);
	ALBEDO = col * (1.0 - painted);
	EMISSION = col * painted;
	ROUGHNESS = mix(rough, 1.0, (1.0 - near) * 0.25);
	METALLIC = 0.0;
	SPECULAR = mix(0.15, 0.55, water);
	NORMAL_MAP = nm;
	NORMAL_MAP_DEPTH = near * 0.7;
}
