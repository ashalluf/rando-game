shader_type spatial;
render_mode cull_disabled;

// The marketplace lane's thin pieces, seen from both sides: papel picado, awning canvas, hanging
// sarapes and dresses, pinata fringes (PuebloMarket). Light comes through them from behind
// (BACKLIGHT); papel picado is cut out by its pattern. See pueblo_market.gdshaderinc.

#include "res://shaders/pueblo_market.gdshaderinc"

void vertex() {
	PM_VERTEX
}

void fragment() {
	PmSurf s = pm_surface(UV, length(VERTEX), length(fwidth(UV)));
	if (s.cut) {
		discard;
	}
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	// Always (derivatives in a branch are undefined); a zero height leaves the normal as it is.
	NORMAL = pm_bump(NORMAL, VERTEX, s.height);
	ALBEDO = cs_out(s.albedo);
	ROUGHNESS = s.rough;
	METALLIC = s.metal;
	EMISSION = cs_out(s.emit);
	BACKLIGHT = cs_out(s.albedo * s.through * paper_glow);
}
