shader_type spatial;
render_mode cull_back;

// The marketplace lane's solid pieces: stalls, goods, the kiosk's ironwork (PuebloMarket). The
// kinds, the vertex data and the colour space are in pueblo_market.gdshaderinc.

#include "res://shaders/pueblo_market.gdshaderinc"

void vertex() {
	PM_VERTEX
}

void fragment() {
	PmSurf s = pm_surface(UV, length(VERTEX), length(fwidth(UV)));
	// Always (derivatives in a branch are undefined); a zero height leaves the normal as it is.
	NORMAL = pm_bump(NORMAL, VERTEX, s.height);
	ALBEDO = cs_out(s.albedo);
	ROUGHNESS = s.rough;
	METALLIC = s.metal;
	EMISSION = cs_out(s.emit);
}
