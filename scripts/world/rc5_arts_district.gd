class_name RcArtsDistrict
## The arts_district reference camera's pass (wave 8, refcam5; docs/HANDOFF.md "The Arts District
## at 10:00"): what gave the Arts District's brick warehouses away from the pavement, fixed in
## Industrial's own shader and builder.
##   - The brick was a flat photo: its normal map was bound to the material and never read. The
##     courses now stand in relief, with lime bloom low on the wall.
##   - The steel factory windows were painted flat on the face - a pixel grid of dark squares with
##     white "missing" panes. The sash now sits ~22 cm back in a real reveal seen along the view
##     ray (brick returns, the sill a pale ledge, the head's shadow on the glass), a heavier
##     perimeter frame, drawn panes each at its own tilt mirroring the street, a few painted out
##     grey-green, open or milky.
##   - Murals on brick were painted as if on concrete (chips showed grey cement, hard vector-black
##     outlines): the courses show through the paint, chips go back to the brick, softer ink.
##   - Grade doors in brick were flush slabs: a dark steel frame (jambs and a deep header) stands
##     proud round each, so the door reads set into the wall.
## RC5_ARTS=0 in the environment is the A/B (the `rc5_arts` uniform 0, the mural flag and the
## frames left out).

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

static var enabled: bool = OS.get_environment("RC5_ARTS") != "0"

## The steel frame round a grade door in a brick wall: jamb width, how far it stands proud, the
## header's height.
const JAMB := 0.22
const PROUD := 0.2
const HEADER := 0.42
const FRAME_PAINT := Color(0.14, 0.145, 0.15)


static func apply(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("rc5_arts", 1.0 if enabled else 0.0)


## COLOR.b of a mural box: 1 when it is painted over brick (the shader shows the courses through
## the paint), else the old 0.5.
static func mural_flag(brick: bool) -> float:
	return 1.0 if enabled and brick else 0.5


## The frame round a grade door at u on a brick front (Industrial's warehouse frame `cx`, the
## front's face at `front_v`, the door `size` (width, height)).
static func door_frame(cx: Dictionary, u: float, front_v: float, size: Vector2) -> void:
	if not enabled:
		return
	var v := front_v - PROUD * 0.5
	for sx: float in [-1.0, 1.0]:
		Industrial._fb(cx, u + sx * (size.x * 0.5 + JAMB * 0.5), v, (size.y + HEADER) * 0.5, Vector3(JAMB, size.y + HEADER, PROUD), IndustrialKit.K_STEEL, FRAME_PAINT)
	Industrial._fb(cx, u, v, size.y + HEADER * 0.5, Vector3(size.x, HEADER, PROUD), IndustrialKit.K_STEEL, FRAME_PAINT)
