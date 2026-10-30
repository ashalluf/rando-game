class_name BeachGolden
extends RefCounted
## The beach as a postcard (docs/HANDOFF.md "The beach at golden hour"): what a low sun picks out
## on the sand, the boardwalk and the pier, on the systems that already draw them.
##
## * The sand (shaders/beach_sand.gdshader + beach_golden.gdshaderinc): wind ripples, hummocks,
##   trails of footprints down to the water and along it, the damp band the tide left above the
##   swash with standing pools that mirror the sky, the sunset's glow and a broad sun path in the
##   wet sand, the wrack line of kelp at the high-tide mark, quartz glints. Its sky mirror now
##   takes `sky_tint` as the renderer's colour (cs_as_uniform: it was a raw sRGB number on
##   Forward+, a stop too bright).
## * The lifeguard towers (BeachLife._tower, beach_props.gdshader codes 11 / 12): boards with
##   grooves, sun-faded and chalked paint peeling to grey wood, rust and grime run from the
##   window band, silvered posts dark where they meet the sand.
##
## Nothing here rolls anything: every pattern is a hash of TRUE world position in the shader, so
## no seed's layout moves. BEACH_GOLDEN=0 is the A/B (the sand and the towers exactly as before).

static var enabled: bool = OS.get_environment("BEACH_GOLDEN") != "0"

## The tower's vertex-alpha codes (beach_props.gdshader: round(alpha * 20)).
const A_TOWER_PAINT := 0.55
const A_TOWER_WOOD := 0.60


static func tower_paint() -> float:
	return A_TOWER_PAINT if enabled else BeachLife.A_PLAIN


static func tower_wood() -> float:
	return A_TOWER_WOOD if enabled else BeachLife.A_PLAIN


## The sand material's switch (PropFactory.beach_sand_material()).
static func dress_sand(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("golden_on", 1.0 if enabled else 0.0)
	# BEACH_GOLDEN_PARAMS="ripple_amp=0,print_depth=0.02": uniforms for stills and tuning.
	for kv: String in OS.get_environment("BEACH_GOLDEN_PARAMS").split(",", false):
		var p := kv.split("=")
		if p.size() == 2:
			mat.set_shader_parameter(p[0], float(p[1]))
