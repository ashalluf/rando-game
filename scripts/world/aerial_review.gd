class_name AerialReview
## What the player sees flying (boost, wingsuit, helicopter) at 100-800 m, where the tiers meet:
## the fixes of the aerial review (docs/HANDOFF.md "The aerial review"). Each lives in the shader
## or script it fixes behind one switch, set here from `AERIAL_REVIEW=0` (the A/B: everything as
## it was):
## - the sea: the horizon plane's water painted on the ocean chunks' own hand-over window, both
##   worked out in linear light, under the same layered distance haze (macro_ground.gdshader /
##   ocean.gdshader `aerial_*`), so the streamed sea and the far sea meet with no edge;
## - the hills at night: the plane's lit band is not dimmed on top of the renderer's moonlight;
## - the hills from the air: the terrain's 13 m mottle tile broken up past a pixel footprint
##   (terrain.gdshader `aerial_mottle`);
## - the far rock: RockFar's tors under the plane's layered distance haze (rock_outcrop.gdshader
##   `aerial_haze`), not brown flecks over every range;
## - the far city's trees (Skyline kerb rows and MidCity yard trees): crowns at the real trees'
##   darkness (`CITY_CANOPY_GAIN`), not pale olive confetti beside the FULL chunks' dark green.

static var enabled: bool = OS.get_environment("AERIAL_REVIEW") != "0"


## The horizon plane's material (CityStreamer._build_ground_material) and any material that
## includes the far relief: only the ones with the uniform take it.
static func apply_ground(m: ShaderMaterial) -> void:
	m.set_shader_parameter("aerial_review", enabled)


## The ocean chunks' shared material (PropFactory.ocean_material()).
static func apply_ocean(m: ShaderMaterial) -> void:
	m.set_shader_parameter("aerial_sea", enabled)
	# The plane's range haze is off in FarRanges' A/B; the sea follows it.
	if not FarRanges.enabled:
		m.set_shader_parameter("range_haze", 0.0)


## The hill tiles' terrain material (PropFactory.terrain_material()).
static func apply_terrain(m: ShaderMaterial) -> void:
	m.set_shader_parameter("aerial_mottle", enabled)


## RockFar's tor materials (rock_outcrop.gdshader): the plane's layered haze on them.
static func apply_rock(m: ShaderMaterial) -> void:
	m.set_shader_parameter("aerial_haze", enabled)
	if not FarRanges.enabled:
		m.set_shader_parameter("range_haze", 0.0)


## The far city's tree crowns (the Skyline canopy instances of a city block, kerb rows and yard
## trees) were lit to (151, 168, 121) from 800 m at noon where the FULL chunks' real trees beside
## them drew (40, 80, 30): every LOD-to-FULL hand-over was a block of pale dots turning dark. A
## colour gain only, applied after every roll; no instance moves.
const CITY_CANOPY_GAIN := 0.5


static func darken_city_canopy(colors: Array, from: int) -> void:
	if not enabled:
		return
	for i in range(from, colors.size()):
		var c: Color = colors[i]
		colors[i] = Color(c.r * CITY_CANOPY_GAIN, c.g * CITY_CANOPY_GAIN, c.b * CITY_CANOPY_GAIN, c.a)
