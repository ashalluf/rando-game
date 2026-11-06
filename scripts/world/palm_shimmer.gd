class_name PalmShimmer
extends RefCounted
## Palm crowns that hold still as the camera moves (palm-shimmer, 2026-11-02; docs/HANDOFF.md
## "Palm crowns without the flecks"). The palms are one vertex-coloured mesh of single-sided
## leaflet blades on shaders/foliage.gdshader (PropFactory.palm()). Two things made a crown
## flicker, dither and show dark holes:
##   * The two ranks of every frond are mirror images, so their blades wind opposite ways: from
##     any side one rank is back-facing, and Godot turns a back face's normal to the camera. The
##     leaflets' normal leans up (the crown lights as one mass); flipped, every second leaflet
##     faced the ground, took no sun and drew near-black. Those dark blades under a pixel wide,
##     between lit ones, were the flecks and the "holes", and they crawled with any camera move.
##     The shader keeps the mesh's normal on both faces (la_tree's and foliage_tex's rule).
##   * A leaflet is 3-8 cm across: under a pixel from ~40 m, where the rasteriser keeps or drops
##     it pixel by pixel as the camera moves. Each leaflet vertex carries its offset across the
##     blade (CUSTOM0, PropFactory._palm_leaf_vertex()), and the vertex shader widens a blade
##     narrower than `MIN_PX` pixels to that width (at most `MAX_WIDEN` times), keeping it by its
##     true coverage: dithered per frame on Forward+ (TAA resolves it to the exact share), whole
##     on Compatibility (no temporal pass: a fixed dither crawls - specular-aliasing's finding),
##     where the far crown is a touch denser instead.
## `PALM_SHIMMER=0` in the environment is the A/B: the shader as it was (`palm_shimmer` 0) and
## the palm meshes without CUSTOM0.

static var enabled: bool = OS.get_environment("PALM_SHIMMER") != "0"

## A leaflet narrower than this many pixels is widened to it (foliage.gdshader `leaf_min_px`).
const MIN_PX := 1.5
## At most this many times its own width (an edge-on blade is never widened into a sheet).
const MAX_WIDEN := 4.0
## The fronds' dry specular (foliage.gdshader's default 0.34 is the A/B). With every leaflet's
## normal now leaning up, every one caught the sky's grazing reflection, where only the lit rank
## did before: a low sun ahead (a backlit morning street) veiled whole crowns in a pale sheen.
const LEAF_SPECULAR := 0.18
## The boots' undersides (the sawn frond stubs on the trunk) lean this far outward: straight
## down (the old -nt) only the ground's bounce lit them, and from the pavement they were black
## triangles stuck to every trunk.
const BOOT_UNDER_OUT := 0.7


## The switch on a palm material (PropFactory.foliage_material()).
static func mark(mat: ShaderMaterial) -> void:
	if mat == null:
		return
	mat.set_shader_parameter("palm_shimmer", 1.0 if enabled else 0.0)
	mat.set_shader_parameter("leaf_specular", LEAF_SPECULAR if enabled else 0.34)
	# PALM_MIN_PX / PALM_MAX_WIDEN override the two for a strip's A/B (tools/palm_shimmer/).
	var mp := OS.get_environment("PALM_MIN_PX")
	var mw := OS.get_environment("PALM_MAX_WIDEN")
	mat.set_shader_parameter("leaf_min_px", float(mp) if mp != "" else MIN_PX)
	mat.set_shader_parameter("leaf_max_widen", float(mw) if mw != "" else MAX_WIDEN)


## The widening a leaflet gets (the vertex shader's rule, for the checks): `width_px` its
## projected width in pixels -> the factor its offset is scaled by and the coverage it is kept at.
static func widen(width_px: float) -> Vector2:
	var k := clampf(MIN_PX / maxf(width_px, 1.0e-5), 1.0, MAX_WIDEN)
	return Vector2(k, 1.0 / k)
