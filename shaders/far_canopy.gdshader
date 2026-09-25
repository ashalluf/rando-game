shader_type spatial;
render_mode cull_back;

// The far hill planting (Skyline's tree and scrub clumps, kilometres out), standing on the
// ground the player can actually see there.
//
// The clumps are laid out on the CPU at MacroMap.height_at(), the real terrain. But past the
// streamed chunks the visible ground is macro_ground.gdshader's lifted plane, which comes from a
// 62 m bake plus synthesized crags, and on a ridge it runs tens of metres below the real height -
// so every clump there hung in the sky above the ridge line like a flock of birds. Here each
// clump is moved, as a whole, onto that plane's surface under its own centre, using the very
// same code the plane lifts itself with (the include), with the same inputs, so the two cannot
// drift apart.
#include "res://shaders/macro_relief.gdshaderinc"

// World Y of the ground follower plane itself, before its vertex shader lifts it. CityStreamer
// keeps the plane at 0.
uniform float plane_y = 0.0;
// Where the plane's vertices are: its centre (local XZ, CityStreamer.update_streaming), half its
// size, and the spacing (CityStreamer.ground_step()). The plane is drawn as flat triangles
// between vertices 70 m apart, and over a ridge those chords run well under the smooth height
// function - so a clump seated on the function still stood clear of the ridge the eye sees.
// The clump has to follow the same triangles.
uniform vec2 plane_origin = vec2(0.0);
uniform float plane_half = 7000.0;
uniform float plane_step = 69.65;
// How far into the ground a clump's base goes, as a fraction of its height, so a clump on a
// slope does not show daylight under its downhill side.
uniform float bury = 0.25;
// Rigid seating, for a thing that has to stay level however the drawn ground undulates under
// it - the far ridge sign. The whole object moves by one amount: the highest drawn ground at
// seven points from seat_a to seat_b (TRUE world XZ) minus seat_ground, the real ground it was
// built level with. The ridge sign is built on the highest real ground under its letters, and
// from across the basin the drawn ridge is lower, so the name hung in the sky beside the peak.
uniform bool rigid = false;
uniform vec2 seat_a = vec2(0.0);
uniform vec2 seat_b = vec2(0.0);
uniform float seat_ground = 0.0;
uniform vec3 rigid_color : source_color = vec3(0.96, 0.96, 0.94);
// Where the horizon plane hands over to the sky (macro_ground.gdshader, set by CityStreamer).
uniform float edge_start = 5040.0;
uniform float edge_end = 6860.0;
global uniform vec4 sky_tint;

varying vec3 tint;
varying float shade;
// Per-instance visibility (Skyline writes it into COLOR.a while a chunk takes a block over or
// hands it back): dithered in the fragment, collapsed at zero.
varying float fade;
varying float rim;


// The plane's own offset (lift minus sink) at one of its vertices, exactly as its shader works it.
float corner_height(vec2 xz, vec3 cam) {
	vec4 m;
	vec2 mg;
	float wet;
	float d;
	float lift = far_ground_lift(vec3(xz.x, plane_y, xz.y), cam, m, mg, wet, d);
	return lift - far_ground_sink(d, wet);
}


// The height of the plane's drawn surface at `xz`: its four surrounding vertices, interpolated
// across whichever of the quad's two triangles `xz` is in. PlaneMesh splits every quad along
// the diagonal from (low x, high z) to (high x, low z) - measured from its index buffer.
float plane_height(vec2 xz, vec3 cam) {
	vec2 g = (xz - (plane_origin - vec2(plane_half))) / plane_step;
	vec2 i = clamp(floor(g), vec2(0.0), vec2(round(2.0 * plane_half / plane_step) - 1.0));
	vec2 f = clamp(g - i, vec2(0.0), vec2(1.0));
	vec2 c0 = plane_origin - vec2(plane_half) + i * plane_step;
	float h01 = corner_height(c0 + vec2(0.0, plane_step), cam);
	float h10 = corner_height(c0 + vec2(plane_step, 0.0), cam);
	if (f.x + f.y < 1.0) {
		float h00 = corner_height(c0, cam);
		return h00 + f.x * (h10 - h00) + f.y * (h01 - h00);
	}
	float h11 = corner_height(c0 + vec2(plane_step), cam);
	return h11 + (1.0 - f.x) * (h01 - h11) + (1.0 - f.y) * (h10 - h11);
}


void vertex() {
	vec3 cam = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float shift;
	if (rigid) {
		float top = -1e9;
		for (int k = 0; k < 7; k++) {
			vec2 p = mix(seat_a, seat_b, float(k) / 6.0) - world_offset;
			top = max(top, plane_height(p, cam));
		}
		tint = rigid_color;
		shade = 1.0;
		shift = plane_y + top - seat_ground;
	} else {
		vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
		float h = length(MODEL_MATRIX[1].xyz);
		// INSTANCE_CUSTOM.r 1: a LOD chunk has drawn the real terrain under this clump, which is
		// exactly where the CPU put it (MacroMap.height_at()), so it stays there. 0: the ground
		// here is the far plane, and it is moved onto that.
		float real = clamp(INSTANCE_CUSTOM.r, 0.0, 1.0);
		shift = 0.0;
		if (real < 0.999) {
			float ground = plane_y + plane_height(origin.xz, cam);
			// The unit box is centred on its origin, so its base is half its height below it.
			shift = (ground - (origin.y - 0.5 * h) - bury * h) * (1.0 - real);
		}
		tint = COLOR.rgb;
		// A canopy is darker low down and on its flanks than on top. Read before the move below,
		// while VERTEX is still the unit box's own -0.5 .. 0.5.
		shade = mix(0.72, 1.0, clamp(VERTEX.y + 0.5, 0.0, 1.0)) * mix(0.85, 1.0, max(NORMAL.y, 0.0));
		// The renderer turns a MultiMesh instance's normals by its basis as it stands, not by the
		// basis' inverse transpose, so on a squashed clump (a chaparral mound is two or three times
		// wider than it is tall) they came out lying almost flat and its sunlit top drew nearly
		// black. Dividing by the scale squared first makes that transform give the true normal.
		vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
		NORMAL = normalize(NORMAL / max(sc * sc, vec3(1e-4)));
	}
	fade = rigid ? 1.0 : COLOR.a;
	vec3 at = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	rim = smoothstep(edge_start, edge_end, length(at.xz - cam.xz));
	if (fade < 0.004) {
		// Collapsed: nothing rasterises, so a hidden block costs no fragments.
		VERTEX = vec3(0.0);
	} else {
		VERTEX += inverse(mat3(MODEL_MATRIX)) * vec3(0.0, shift, 0.0);
	}
}


void fragment() {
	if (fade < 0.999) {
		float d = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
		if (fade < d) {
			discard;
		}
	}
	ALBEDO = tint * shade * (1.0 - rim);
	EMISSION = sky_tint.rgb * rim;
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
}
