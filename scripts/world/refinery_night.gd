class_name RefineryNight
extends RefCounted
## The refinery at night from the road outside the fence (wave 6, refcam `refinery_night` in
## tools/refcams/cameras_w6.json, docs/HANDOFF.md "The refinery at night"). What the view gave away:
##   - the flares lit nothing: a 75-96 m flame over its own derrick, and the steel round it was lit
##     by the moon alone (the old OmniLight sat 4 m over the tip with a 70 m range, FULL chunks only,
##     and reached nothing but the sky). Now refinery.gdshader lights every piece of the plant near a
##     flame (`flare_tips`, TRUE world, a flicker per flare), the same in FULL chunks and in the far
##     pieces, on both renderers, for nothing on the CPU; the old OmniLight is gone;
##   - no haze round a flame: a refinery's flares sit in a dome of lit orange air. The flame mesh has
##     one more sprite a flare (UV2.x 3), wide and faint, zero at its edge (fwd-review-d's rule);
##   - the steam read as brown smoke: it is lit from its luminance only (the puff texture is a
##     fire-and-smoke billow, brown), cool white by the moon and the city, warm from the plant under it;
##   - the berms round the tanks were one flat tan plane at the fence: dry weedy dirt now, darker,
##     patched, runnels down the slope, the foot in shadow.
## REFINERY_NIGHT=0 is the A/B: every block it adds in the shaders is behind `night_look`, which
## stays 0, and the flame mesh is built as before.

static var enabled: bool = OS.get_environment("REFINERY_NIGHT") != "0"

## How far a flare's light reaches (metres) and how bright it is on the steel next to it.
const FLARE_REACH := 160.0
const FLARE_GAIN := 1.15
## The distance at which a flare's light has fallen to half (metres).
const FLARE_HALF := 24.0
## The haze dome round a flame: its width (metres) and strength.
const HAZE_W := 170.0
const HAZE_GAIN := 0.06
## The high masts' OmniLights (FULL chunks, desktop): a shorter reach and a steeper falloff.
const MAST_RANGE := 40.0
const MAST_ATTENUATION := 2.2
## The most flares the shader takes (the default seed's plant has five).
const MAX_FLARES := 8


## The flame tips (TRUE world: x, y, z; w a phase) of the plant on `plan`: where the light comes from.
static func flare_tips(lay: Dictionary, plan: CityPlan) -> Array[Vector4]:
	var out: Array[Vector4] = []
	if lay.is_empty():
		return out
	for it: Dictionary in lay.items:
		if String(it.type) != "flare" or out.size() >= MAX_FLARES:
			continue
		var at: Vector2 = it.at
		var rel := plan.macro.relief_at(at) if plan != null and plan.macro != null else 0.0
		# The light comes from the flame's body, a few metres over the tip.
		var y := Refinery.BASE_Y + rel + float(it.h) + 5.0
		out.append(Vector4(at.x, y, at.y, float(int(it.seed) % 997) / 997.0))
	return out


static var _applied_for: int = 0


## apply() once per plan (RefineryFar does it at load; a site chunk built without the far city -
## block_shot, the checks - does it here).
static func ensure(lay: Dictionary, plan: CityPlan) -> void:
	if plan == null or _applied_for == plan.get_instance_id():
		return
	apply(lay, plan)


## Hands the plant's materials the night look and the flares (called once the city's layout exists).
static func apply(lay: Dictionary, plan: CityPlan) -> void:
	var mat := RefineryKit.material()
	var flame := Refinery.flame_material()
	var plume := Refinery.plume_material()
	if plan != null:
		_applied_for = plan.get_instance_id()
	var on := 1.0 if enabled else 0.0
	for m: ShaderMaterial in [mat, flame, plume]:
		m.set_shader_parameter("night_look", on)
	if not enabled:
		return
	var tips := flare_tips(lay, plan)
	var arr := PackedVector4Array()
	arr.resize(MAX_FLARES)
	for i in tips.size():
		arr[i] = tips[i]
	mat.set_shader_parameter("flare_tips", arr)
	mat.set_shader_parameter("flare_count", tips.size())
	mat.set_shader_parameter("flare_reach", FLARE_REACH)
	mat.set_shader_parameter("flare_gain", FLARE_GAIN)
	mat.set_shader_parameter("flare_half", FLARE_HALF)
	flame.set_shader_parameter("haze_w", HAZE_W)
	flame.set_shader_parameter("haze_gain", HAZE_GAIN)


## The flare light at a TRUE world point facing `n` (0..~1), refinery.gdshader's term in GDScript
## (without the flicker) - the checks hold the two together.
static func flare_light(tips: Array[Vector4], p: Vector3, n: Vector3) -> float:
	var sum := 0.0
	for t: Vector4 in tips:
		var d := Vector3(t.x, t.y, t.z) - p
		var dist := d.length()
		if dist >= FLARE_REACH:
			continue
		var fall := 1.0 / (1.0 + (dist * dist) / (FLARE_HALF * FLARE_HALF))
		fall *= 1.0 - smoothstep(FLARE_REACH * 0.55, FLARE_REACH, dist)
		var facing := clampf(n.dot(d / maxf(dist, 0.01)) * 0.7 + 0.3, 0.0, 1.0)
		sum += fall * facing
	return sum
