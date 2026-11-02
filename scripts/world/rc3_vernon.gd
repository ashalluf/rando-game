class_name RcVernon
## The vernon_industrial reference camera's pass (wave 6, refcam3; docs/HANDOFF.md "The Vernon
## industrial street"): what gave the industrial street away at eye level, fixed in Industrial's own
## shaders and plans.
##   - Painted steel (dumpsters, roll-offs, bollards) rusted in big blotches across every face:
##     yellow bins read as cheese. Rust now runs along lips, the foot, chips and runs from the top.
##   - The office storefront was a flat grey slab: anodised frames round every lite, the glass
##     mirroring the street by the REFLECTED ray (sky over a skyline of roofs, the ground under the
##     horizon), blinds in a third of the lites.
##   - Truck courts were empty khaki planes: the asphalt is neutral and aged, driven in tyre tracks
##     along the court's axis (COLOR.b), and more docks have a trailer (TRAILER_ODDS), which carry
##     red / white conspicuity tape and a fleet band.
##   - Tilt-up walls were one even cast: panel-to-panel tone, rain runs from the coping at the
##     joints and wall packs, splash-back dirt at the foot.
## RC3_VERNON=0 in the environment is the A/B (the `rc3` uniform 0 on both industrial materials, the
## old trailer odds, no track axis).

static var enabled: bool = OS.get_environment("RC3_VERNON") != "0"

## Of the docks the old roll left empty, this share more get a trailer (a second hash, so every
## trailer before stays where it was).
const MORE_TRAILERS := 0.55


## COLOR.b for an industrial ground piece: the axis a court's trucks drive along, 0 elsewhere.
static func track_axis(role: String, side: int) -> float:
	if not enabled or (role != "court" and role != "apron"):
		return 0.0
	return 0.25 if side < 2 else 0.75


## Whether a dock (by the lot's seed and the dock's u roll key) has a trailer at it, given the old
## roll `r` against `odds`.
static func dock_has_trailer(r: float, odds: float, extra_roll: float) -> bool:
	if r < odds:
		return true
	return enabled and extra_roll < MORE_TRAILERS


static func apply(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("rc3", 1.0 if enabled else 0.0)


## The office's tilt-up pop-out: two piers either side of the storefront and a header over it to a
## raised parapet, POPOUT m proud of the wall, painted a contrast of the warehouse's colour - so the
## glass sits in a real reveal (its own shadow) instead of flush on a flat wall. In the warehouse's
## frame (Industrial._fb's `cx`); `ow` the office run, `front_v` the wall's face, `h` the roof
## height, `top` the parapet's.
const POPOUT := 0.38
const POPOUT_RISE := 1.1
const PIER := 0.75
const POPOUT_PAINTS := [Color(0.33, 0.37, 0.41), Color(0.93, 0.92, 0.89), Color(0.22, 0.31, 0.38), Color(0.55, 0.52, 0.47)]


static func office_popout(cx: Dictionary, u: float, ow: float, front_v: float, h: float, top: float, paint: Color, s: int) -> void:
	if not enabled:
		return
	var glass_top := 7.4 if h >= 9.0 else 4.0
	var col: Color = POPOUT_PAINTS[absi(hash([s, "rc3_pop"])) % POPOUT_PAINTS.size()]
	# A pale warehouse takes a dark pop-out and a dark one a pale one.
	if paint.get_luminance() < 0.75 and col.get_luminance() < 0.6:
		col = POPOUT_PAINTS[1]
	var v := front_v - POPOUT * 0.5 - 0.01
	var hh := top + POPOUT_RISE
	var kind := IndustrialKit.K_TILTUP
	for sx: float in [-1.0, 1.0]:
		Industrial._fb(cx, u + sx * (ow * 0.5 - 0.6 + PIER * 0.5), v, hh * 0.5, Vector3(PIER, hh, POPOUT), kind, col, PIER)
	var span := ow - 1.2
	Industrial._fb(cx, u, v, glass_top + (hh - glass_top) * 0.5 + 0.05, Vector3(span, hh - glass_top - 0.1, POPOUT), kind, col, span)
	# The cap on top.
	Industrial._fb(cx, u, v, hh + 0.04, Vector3(ow - 1.2 + PIER * 2.0 + 0.1, 0.08, POPOUT + 0.08), IndustrialKit.K_GALV, Color(0.7, 0.71, 0.7))
