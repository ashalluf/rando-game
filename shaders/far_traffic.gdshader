shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// The LOD chunks' freeway decks at night: an additive skin a hand over the asphalt carrying
// far_traffic.gdshaderinc's moving head and tail lights, faded in past the range the real
// freeway traffic is kept in (TrafficManager.freeway_range), so the river of lights runs on
// from the cars into the far city's decks. Built by FreewayKit._traffic_skin(): UV (metres along
// the route in the lights' period, metres across from the median, + to the right of travel),
// UV2 the route and the deck's half width, COLOR.rg the route's +s direction in world XZ as 0..1.

global uniform float lamp_factor;
#include "res://shaders/far_traffic.gdshaderinc"

uniform float fade_start = 560.0;
uniform float fade_end = 680.0;

varying vec3 world_pos;
varying vec2 dir;


void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	dir = normalize((MODEL_MATRIX * vec4(COLOR.r * 2.0 - 1.0, 0.0, COLOR.g * 2.0 - 1.0, 0.0)).xz + vec2(1e-6));
}


void fragment() {
	float far = smoothstep(fade_start, fade_end, length(world_pos - CAMERA_POSITION_WORLD)) * lamp_factor;
	if (far < 0.002) {
		discard;
	}
	float mpp = max(fwidth(UV.x), fwidth(UV.y));
	// Freeway.lane_layout(): four lanes each way from 1.305 m off the median; UV2.y is the
	// deck's half width.
	float lane_w = min(3.6, (UV2.y - 0.42 - 1.2 - 1.305) / 4.0);
	vec3 c = traffic_lights(UV.x, UV.y, 1.305, lane_w, 4.0, dir, normalize(CAMERA_POSITION_WORLD - world_pos),
		mpp, traffic_level(city_hour), 27.0, UV2.x);
	ALBEDO = c * far;
}
