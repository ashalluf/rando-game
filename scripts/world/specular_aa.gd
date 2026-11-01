class_name SpecularAA
extends RefCounted
## Shimmer and crawl in motion (docs/HANDOFF.md "Shimmer and crawl in motion"): glossy lobes
## narrower than a pixel's spread of normals, and cut-outs and features thinner than a pixel,
## sample one value per pixel per frame and sparkle or crawl as the camera moves. The shaders that
## did it worst widen their lobe and fade their detail by the pixel's footprint
## (shaders/specular_aa.gdshaderinc). This is the switch: `SPECULAR_AA=0` in the environment turns
## it off (the A/B): the `specular_aa` shader global goes to 0 and every shader keeps its old line.
## tools/specular_aliasing/strip.py shoots and measures the frame strips that prove it.

static var enabled: bool = OS.get_environment("SPECULAR_AA") != "0"


## Pushes the switch to the shaders (Weather._ready(), beside PavingAA's).
static func install() -> void:
	RenderingServer.global_shader_parameter_set("specular_aa", 1.0 if enabled else 0.0)


## Turns it on or off at once (tests, stills).
static func set_enabled(on: bool) -> void:
	enabled = on
	install()


# --- Mirror of shaders/specular_aa.gdshaderinc (the checks hold the two together) --------------

## saa_geometric(): roughness widened by the variance of the normal across the pixel.
static func geometric(rough: float, var_sum: float, amount: float, limit: float) -> float:
	var k := minf(2.0 * amount * var_sum, limit)
	return sqrt(clampf(rough * rough + k, 0.0, 1.0))


## saa_minified(): roughness widened by the slope variance a normal map's mips threw away.
static func minified(rough: float, slope_var: float, texels: float) -> float:
	var lost := slope_var * clampf(1.0 - 1.0 / maxf(texels * texels, 1.0), 0.0, 1.0)
	return sqrt(clampf(rough * rough + lost, 0.0, 1.0))


## saa_shine(): a highlight's exponent brought down to what the pixel can hold.
static func shine(s: float, var_sum: float) -> float:
	return 1.0 / (1.0 / maxf(s, 1.0) + 0.5 * var_sum)


## saa_shine_gain(): the energy kept as the lobe widens.
static func shine_gain(s: float, widened: float) -> float:
	return clampf((widened + 2.0) / (s + 2.0), 0.0, 1.0)
