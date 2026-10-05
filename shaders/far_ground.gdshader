shader_type spatial;
render_mode specular_disabled;

// The merged ground of a far (LOD) chunk: roads, pavements, lots and lawns in one vertex-coloured
// mesh (CityChunk._add_ground_grid). Far chunks build no street lamps, so after dark every street
// out there was black and the city seen from the air was lit towers standing in a void - where a
// real one is a grid of orange lines. The vertex colour's alpha marks the carriageway and which
// way it runs (1.0 along Z, 0.75 along X, 0.5 a junction, 0.25 a pavement, 0 anything else),
// and the glow comes on with the `lamp_factor` global like the real lamps in the near chunks.
// The pattern and levels match road.gdshader's far glow, so a street does not change as its
// chunk swaps level.

#include "res://shaders/street_glow.gdshaderinc"
#include "res://shaders/far_traffic.gdshaderinc"

// The street traffic is real out to about here (TrafficManager.spawn_max / despawn_distance):
// past it the roads carry far_traffic's lights instead, faded in over this band from the camera.
uniform float traffic_fade_start = 270.0;
uniform float traffic_fade_end = 380.0;
// The far streets' glow against the near road's, and a junction's (building_lod.gdshader's numbers).
uniform float far_glow_gain = 1.8;
uniform float junction_glow = 1.6;

varying vec2 plan_pos;
varying vec2 slab_uv;
varying vec3 world_pos;


void vertex() {
	// Object space is plan space: the chunk's vertices are laid out in plan coordinates and the
	// streamer moves the holder, so this does not jump when the origin is re-centred.
	plan_pos = VERTEX.xz;
	slab_uv = UV;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.95;
	float a = COLOR.a;
	if (a > 0.1 && lamp_factor > 0.001) {
		if (a > 0.35) {
			int axis = a > 0.9 ? 1 : (a > 0.6 ? 2 : 0);
			vec3 lr = lamp_ratio(plan_pos);
			EMISSION = street_glow(plan_pos, slab_uv, axis) * lr * street_glow_level() * far_glow_gain * (axis == 0 ? junction_glow : 1.0);
			float far = smoothstep(traffic_fade_start, traffic_fade_end, length(world_pos - CAMERA_POSITION_WORLD));
			if (axis != 0) {
				// The slab's UV runs 0..1 across its rect: its width in metres is the ratio of
				// the plan position's screen derivatives to the UV's (road.gdshader's rule).
				float across_p = axis == 1 ? plan_pos.x : plan_pos.y;
				float across_uv = axis == 1 ? slab_uv.x : slab_uv.y;
				float width = length(vec2(dFdx(across_p), dFdy(across_p))) / max(length(vec2(dFdx(across_uv), dFdy(across_uv))), 1.0e-7);
				if (width > 8.0 && width < 60.0) {
					float centre = (clamp(across_uv, 0.0, 1.0) - 0.5) * width;
					float mpp = max(fwidth(plan_pos.x), fwidth(plan_pos.y));
					float road_id = floor(across_p - centre + 0.5);
					EMISSION += street_glow_color * lr * street_lamp_heads(axis == 1 ? plan_pos.y : plan_pos.x,
						clamp(across_uv, 0.0, 1.0) * width, width, mpp) * street_glow_level();
					EMISSION += street_traffic(axis == 1 ? plan_pos.y : plan_pos.x, axis == 1 ? -centre : centre, width,
						axis == 1 ? vec2(0.0, 1.0) : vec2(1.0, 0.0), normalize(CAMERA_POSITION_WORLD - world_pos), mpp, road_id) * lamp_factor * far;
				}
			}
		} else {
			// A pavement: the lamps stand on it, so it catches their spill.
			EMISSION = street_glow(plan_pos, slab_uv, 0) * lamp_ratio(plan_pos) * street_glow_level() * 0.25 * far_glow_gain;
		}
	}
}
