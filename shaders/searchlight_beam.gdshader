shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// The visible shaft of a police searchlight where there is no volumetric fog to draw it (the web
// build, and every Quality level below HIGH): an open cone, additive, bright at the lamp and
// dying away down its length, soft at its silhouette edges. On Forward+ HIGH the SpotLight3D's
// own volumetric fog energy draws the shaft instead and Helicopter hides this.
// The cone is Godot's CylinderMesh, which runs UV.y from its top (the lamp) to its bottom.

global uniform float lamp_factor;
uniform vec3 tint : source_color = vec3(0.86, 0.92, 1.0);
uniform float strength : hint_range(0.0, 2.0) = 0.22;
// Share of the shaft length over which it fades out.
uniform float length_fade : hint_range(0.05, 1.0) = 0.85;

void fragment() {
	float along = UV.y;
	float fade = pow(1.0 - smoothstep(0.0, length_fade, along), 1.6) * smoothstep(0.0, 0.03, along);
	// Edge-on the cone wall is thin and reads as a hard line; face-on it is the thick of the
	// beam. NORMAL and VIEW are both in view space.
	float face = pow(abs(dot(normalize(NORMAL), normalize(VIEW))), 1.4);
	ALBEDO = tint;
	ALPHA = clamp(fade * face * strength * lamp_factor, 0.0, 1.0);
}
