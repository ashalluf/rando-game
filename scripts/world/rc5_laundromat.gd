class_name RcLaundromat
extends RefCounted
## A strip of small shops at 23:30 from the pavement (fleet wave 8, refcam5 `laundromat_night` in
## tools/refcams/cameras_w8.json; docs/HANDOFF.md "The laundromat strip at 23:30"). What the before
## frame gave away, and what this does about each (all in building.gdshader / shop_interior.gdshaderinc,
## behind the `rc5_laundromat` shader global):
##
## - **A closed shop read as an empty window.** A scissor gate's bars were averaged to a coverage of
##   0.42 once they were finer than a pixel and then cut at 0.5, so past a few metres the gate was
##   gone and the shut shop showed bare dark glass. It is now kept as its coverage over the glass
##   (`gate_cover`).
## - **Nobody waiting in the laundromat.** It had washers, an island and a folding table, but no
##   seat and at most two people standing. A row of moulded chairs on a rail stands against a side
##   wall (`LAUND_CHAIR_*`), and one or two people sit there side-on to the street.
## - **The donut shop was any cafe.** A DONUT HOLE (Building.SHOP_NAMES; the shader has the shop's
##   name) has a lit case of donuts on its counter and a backlit menu board of them over the back bar.
##
## `RC5_LAUNDROMAT=0` is the A/B (the strip as it was, bit for bit).

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

static var enabled: bool = OS.get_environment("RC5_LAUNDROMAT") != "0"

## The SHOP_NAMES index + 1 the shader takes for a donut shop (shop_names_a's six-bit code).
const DONUT_CODE := 11


## Pushes the switch to the shaders (DayNight._ready()).
static func install() -> void:
	RenderingServer.global_shader_parameter_set("rc5_laundromat", 1.0 if enabled else 0.0)


static func set_enabled(on: bool) -> void:
	enabled = on
	install()
