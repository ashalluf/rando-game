class_name RcLighthouse
extends RefCounted
## The lighthouse_night reference camera's review (Gull Point light at 22:00 clear from the
## breakwater's armour stones, the beam held sweeping over the harbour; docs/HANDOFF.md "The
## lighthouse from the breakwater at night"): what read fake first in that frame, fixed in the
## lighthouse kit's own materials. Every fix rides one `look` uniform (0 = the shader exactly as it
## was), set here when the kit builds a material. RC5_LIGHTHOUSE=0 in the environment puts every
## one of them back (the A/B).
##
## 1. The beam was a solid tube: the old shaft lit the cone's surface by |N.V|, the same brightness
##    from the lens to the edge of the frame and a hard rim. Now it is the light scattered by the
##    air in a Gaussian pencil round the beam's axis, integrated along the view ray analytically
##    (lighthouse_beam.gdshader look: one back face per ray, the closest approach of the ray to the
##    axis), dimmer as it spreads, forward-scattered (bright looking back up it toward the lens),
##    falling off with distance and drifting with patches of haze.
## 2. The lantern did not read as the source: the far point was a faint dot between flashes. Now
##    it is a steady lamp with a halo, swelling as a panel swings toward the eye (lighthouse_lamp).
## 3. The surge foam round the breakwater's foot was flat white sheets, the brightest thing in the
##    frame at night: torn into lace, greyer, see-through at its edge (breakwater_foam).
## 4. The armour stones were flat-faceted boxes with paper-white lime patches: the faces are
##    bumped by a rock-scale noise normal and the lime is a dull streaked speckle (armour_stone).

static var enabled: bool = OS.get_environment("RC5_LIGHTHOUSE") != "0"

## The beam's Gaussian half-width at the lens (m) and its spread (half angle, degrees): the
## drawn cone (LighthouseKit.beam_mesh(), 1.15 degrees) holds it out to ~2.4 sigma.
const BEAM_WAIST := 0.35
const BEAM_SPREAD_DEG := 0.48
## Henyey-Greenstein asymmetry of the night air (sea haze scatters forward).
const BEAM_G := 0.5


## Sets the review's uniforms on one of the kit's materials (kind: "beam", "lamp", "foam",
## "armour"). The old look is `look` 0.
static func apply(sh: ShaderMaterial, kind: String) -> void:
	if sh == null:
		return
	sh.set_shader_parameter("look", 1.0 if enabled else 0.0)
	if not enabled:
		return
	if kind == "beam":
		sh.set_shader_parameter("waist", BEAM_WAIST)
		sh.set_shader_parameter("spread", tan(deg_to_rad(BEAM_SPREAD_DEG)))
		sh.set_shader_parameter("phase_g", BEAM_G)


## The Henyey-Greenstein phase, relative to its value at 90 degrees (the beam seen side-on is 1).
## `cos_t` the cosine between the light's travel and the way to the eye. The shader's copy.
static func phase(cos_t: float, g: float = BEAM_G) -> float:
	var side := pow(1.0 + g * g, 1.5)
	return side / pow(maxf(1.0 + g * g - 2.0 * g * cos_t, 1e-4), 1.5)
