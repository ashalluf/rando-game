class_name FreewayLook
extends RefCounted
## The freeway refcam pass (wave 4, `rc-freeway`): what read fake on the 110 by downtown at noon,
## fixed in the freeway's own materials. The traffic's side is FreewayFill.
## - The deck's tining fades out while a groove still spans a few pixels and is drawn rounded:
##   the old square grooves at two or three pixels beat with the pixel grid into rings across the
##   near lanes.
## - The milled rumble strip is rounded scoops with dust in the bottom that fade to a faint band,
##   not a ladder of flat dark tiles.
## - The expansion joints are a lighter, duller steel (metal on the Compatibility renderer has
##   nothing to mirror and drew them as black pencil lines across the lanes).
## `FREEWAY_LOOK=0` in the environment is the A/B: every value as it was.

static var enabled := OS.get_environment("FREEWAY_LOOK") != "0"

## Pixels per tining groove pitch where the grooves start / finish fading (was 0.35 .. 1.0).
const TINE_FADE := Vector2(0.12, 0.45)


static func apply_deck(mat: ShaderMaterial) -> void:
	if not enabled:
		return
	mat.set_shader_parameter("tine_fade", TINE_FADE)
	mat.set_shader_parameter("rumble_scoop", true)


static func apply_paint(mat: ShaderMaterial) -> void:
	if not enabled:
		return
	mat.set_shader_parameter("joint_steel", true)


## The mitred normal at one end of deck segment `idx` of route `ri` (`at_a`: its start), scaled
## so an offset of w along it is w across both segments. The segment's own normal at a route's
## end or past MAX_TURN degrees.
const MAX_TURN := 25.0


static func mitre(fw: Freeway, ri: int, idx: int, nrm: Vector2, at_a: bool) -> Vector2:
	var pts: PackedVector2Array = fw._line(ri).points
	var j0 := idx - 1 if at_a else idx + 1
	var j1 := idx if at_a else idx + 2
	if j0 < 0 or j1 >= pts.size():
		return nrm
	var d := pts[j1] - pts[j0]
	if d.length() < 0.5:
		return nrm
	d = d.normalized()
	var other := Vector2(-d.y, d.x)
	if other.dot(nrm) < cos(deg_to_rad(MAX_TURN)):
		return nrm
	var m := (other + nrm).normalized()
	return m / maxf(m.dot(nrm), 0.5)
