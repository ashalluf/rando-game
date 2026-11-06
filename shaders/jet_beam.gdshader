shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// A jet's landing light seen from the side at night (JetTakeoff, refcam5 "jet_takeoff"): the
// lamp's beam as a shaft of lit haze, an open cone from the lamp (Godot's CylinderMesh, UV.y 0 at
// its narrow top) fading down its length and soft at its silhouette, nothing by day. Additive and
// fog-free (CLAUDE.md: a blend_add shader left in the fog adds the fog colour over its quad).
// Its numbers are display-ish and low on purpose: on Forward+ an additive unshaded quad adds in
// linear HDR, so the strength is kept where both renderers read it as a faint shaft.
// Shader files use // comments.

global uniform float lamp_factor;
#include "res://shaders/fwd_review_i.gdshaderinc"
uniform vec3 tint = vec3(1.0, 0.93, 0.80);
uniform float strength : hint_range(0.0, 1.0) = 0.16;

void fragment() {
	float along = UV.y;
	// Bright at the lamp, gone by the far end; never a hard ring where the cone starts.
	float fade = pow(1.0 - along, 2.2) * smoothstep(0.0, 0.04, along);
	// Edge-on the cone wall is a thin line: weight by how face-on the wall is.
	float face = pow(abs(dot(normalize(NORMAL), normalize(VIEW))), 1.6);
	// Seen from close in front (the beam reaching the lens) it would fill the frame: the haze is
	// only drawn some way off, where it reads as a shaft.
	float depth = length(VERTEX);
	float a = fade * face * strength * smoothstep(0.3, 0.8, lamp_factor) * smoothstep(25.0, 60.0, depth);
	if (a < 0.002) {
		discard;
	}
	// fwd-review-i: on Forward+ the amount is handed over as the display number it was tuned as
	// (raw, the faint shaft was a solid cream rod on the Mac).
	ALBEDO = fi_add(tint * a);
	ALPHA = 1.0;
}
