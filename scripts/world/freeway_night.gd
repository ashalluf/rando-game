class_name FreewayNight
extends Node3D
## The freeway at night from the driver's seat (wave 6 refcam `freeway_night`, branch
## `wt/rc3-freeway-night`; docs/HANDOFF.md "The freeway at night"). Three things the deck lacked:
##
## - **Pools with a rhythm.** Each median light standard's two cobra heads threw a 46 x 16 m soft dot
##   every 48 m - one continuous warm strip over the inner lanes, no pool under each light and no
##   darker road between them. Now each head throws the illuminance a point source HEAD_H metres up
##   gives, (1 + d^2/h^2)^-1.5, on a quad centred under the head (light_pool.gdshader's cobra
##   branch; FreewayKit shifts the quad's u by 4): bright under the standard, about a fifth of that
##   halfway to the next one.
## - **Light that lights something.** The heads had no real light: cars, trucks, the barriers and
##   the gantries drove through the pools unlit. A budget of OmniLight3Ds (`budget()`) stands at the
##   heads nearest the camera, in the `lamp_light` group (DayNight drives their energy, NightLamps
##   normalises them for the head's height). They leave the deck alone (its pools are its light at
##   every distance, so a near pool is never brighter than a far one): the deck top is on its own
##   render layer (DECK_LAYER), which the lights' cull mask skips.
## - **The river of tail lights.** A car's lamps stopped drawing at 160 m (Vehicle._add_night_lights),
##   so the traffic ahead was dark bodies past a few cars. Freeway cars keep theirs to FAR_LIGHTS
##   (car_lights.gdshader keeps a far lamp's core 1.5 pixels across), street cars go back to 160.
##
## FREEWAY_NIGHT=0 in the environment is the A/B: the old pool, no lights, no layer, the old reach.

static var enabled: bool = OS.get_environment("FREEWAY_NIGHT") != "0"

## The cobra pool's quad (metres along the road, across it) centred on the head's foot: across it
## stays on the deck (the head is 3.15 m off the median, the deck edge 17.7 m out), along it overlaps
## the next standard's (48 m) so the dimmer road between two is lit by both.
const POOL_SIZE := Vector2(62.0, 28.0)
## The head's height over the deck (FreewayKit.LIGHT_HEIGHT + the arm's rise - the lens' drop).
const HEAD_H := 12.7
## The pool's gain (x the old dot's strength and colour alpha) at its peak under the head.
const POOL_GAIN := 0.5
## The real lights' share of a street lamp's (NightLamps normalises a light by its head's height; a
## median standard's light on the barriers and cars 10-15 m off read too hot at 1).
const LIGHT_GAIN := 0.45
## The deck top's render layer (layer 17): the freeway lights' cull mask leaves it out.
const DECK_LAYER := 1 << 16
## Freeway cars' lamps are drawn this far (metres; street cars keep Vehicle's 160).
const FAR_LIGHTS := 720.0
const NEAR_LIGHTS := 160.0
## How far from the camera a head may hold a light, and how often the lights are dealt (real s).
const REACH := 240.0
const TICK := 0.25

static var _inst: FreewayNight = null

var _plan: CityPlan = null
var _lights: Array[OmniLight3D] = []
var _timer := 0.0


## Each light standard's pool: the material's cobra numbers (0 with the switch off).
static func dress_pool(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("cobra_size", Vector4(HEAD_H, POOL_SIZE.x, POOL_SIZE.y, POOL_GAIN) if enabled else Vector4.ZERO)


## FreewayKit.commit(): the deck top goes on its own layer, and a FULL chunk makes the lights' node.
static func deck_built(chunk: Node3D, deck: MeshInstance3D, full: bool) -> void:
	if not enabled:
		return
	deck.layers = DECK_LAYER
	if full and not bool(chunk.get("capturing")):
		ensure(chunk)


static func ensure(chunk: Node3D) -> void:
	if _inst != null and is_instance_valid(_inst):
		return
	var root := chunk.get_parent()
	if root == null:
		return
	_inst = FreewayNight.new()
	_inst.name = "FreewayNight"
	_inst._plan = chunk.get("plan")
	root.add_child.call_deferred(_inst)


static func instance() -> FreewayNight:
	return _inst if _inst != null and is_instance_valid(_inst) else null


## How many real lights: none on the web (the pools carry it there), fewer on Compatibility.
static func budget() -> int:
	if not enabled or OS.has_feature("web"):
		return 0
	return 8 if RenderingServer.get_current_rendering_method() == "forward_plus" else 6


## The heads of every light standard within `reach` of `at` (true world XZ), nearest first:
## [{"pos": Vector3 true world, "sodium": bool, "d": metres}]. Pure on the plan: FreewayKit's own
## rule (every LIGHT_EVERY-th segment, `% LIGHT_EVERY == 1`, none under the stack's upper decks).
static func heads_near(plan: CityPlan, at: Vector2, reach: float) -> Array:
	var out: Array = []
	if plan == null or plan.macro == null or plan.macro.freeway == null:
		return out
	var fw: Freeway = plan.macro.freeway
	var segs := fw.segments_in(Rect2(at - Vector2(reach, reach), Vector2(reach, reach) * 2.0))
	for seg in segs:
		if seg.has("link") or int(seg.index) % FreewayKit.LIGHT_EVERY != 1:
			continue
		var ri := int(seg.route)
		var idx := int(seg.index)
		if fw.stack != null and fw.stack.covered.has(Vector2i(ri, idx)):
			continue
		var a: Vector2 = seg.a
		var b: Vector2 = seg.b
		if a.distance_to(b) < 0.5 or a.distance_to(at) > reach:
			continue
		var dir := (b - a).normalized()
		var nrm := Vector2(-dir.y, dir.x)
		var sodium := FreewayKit.is_sodium(str(fw.routes[ri].name))
		for side: float in [-1.0, 1.0]:
			var p := a + nrm * ((FreewayKit.LIGHT_ARM + 0.35) * side)
			out.append({"pos": Vector3(p.x, float(seg.ha) + HEAD_H, p.y), "sodium": sodium, "d": p.distance_to(at)})
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x.d) < float(y.d))
	return out


func _ready() -> void:
	for i in budget():
		var l := OmniLight3D.new()
		l.name = "FreewayLight%d" % i
		l.shadow_enabled = false
		l.light_cull_mask = 0xFFFFF & ~DECK_LAYER
		l.light_energy = 0.0
		l.visible = false
		l.distance_fade_enabled = true
		l.distance_fade_begin = REACH - 50.0
		l.distance_fade_length = 40.0
		l.top_level = true
		l.omni_range = 32.0
		l.omni_attenuation = 1.0
		NightLamps.tune_light(l, HEAD_H)
		l.set_meta("lamp_gain", float(l.get_meta("lamp_gain", 1.0)) * LIGHT_GAIN)
		add_child(l)
		_lights.append(l)


func _process(delta: float) -> void:
	_timer -= delta / maxf(Engine.time_scale, 0.0001)
	if _timer > 0.0:
		return
	_timer = TICK
	update_now()


## Deal the lights to the nearest heads (ahead of the camera first) and set the cars' lamp reach.
func update_now() -> void:
	_car_reach()
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return
	var ws := get_node_or_null("/root/WorldState")
	var eye: Vector3 = ws.call("to_world", cam.global_position) if ws else cam.global_position
	var fwd := -cam.global_transform.basis.z
	var heads := heads_near(_plan, Vector2(eye.x, eye.z), REACH) if not _lights.is_empty() else []
	# Behind the camera counts three times as far: its light falls on nothing in view.
	for h: Dictionary in heads:
		var to: Vector3 = (h.pos as Vector3) - eye
		h.w = float(h.d) * (3.0 if to.dot(fwd) < -12.0 else 1.0)
	heads.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x.w) < float(y.w))
	var lit := DayNight.lamp_now > 0.001
	for i in _lights.size():
		var l := _lights[i]
		if i >= heads.size():
			if l.is_in_group("lamp_light"):
				l.remove_from_group("lamp_light")
			l.visible = false
			continue
		var h: Dictionary = heads[i]
		var p: Vector3 = h.pos
		l.global_position = ws.call("to_local", p) if ws else p
		var base := Color(1.0, 0.66, 0.30) if bool(h.sodium) else Color(0.86, 0.92, 1.0)
		l.light_color = NightLamps.light_color(base) if NightLamps.enabled else base
		if not l.is_in_group("lamp_light"):
			# Joined dark: DayNight shows it again with the lamps (its "dark_hidden" rule).
			l.add_to_group("lamp_light")
			var day := get_parent().get_node_or_null("DayNight")
			l.light_energy = maxf(float(day.get("_lamp_level")), 0.0) * float(l.get_meta("lamp_gain", 1.0)) if day else 0.0
			l.visible = lit
			if not lit:
				l.set_meta("dark_hidden", true)


## Freeway cars' lamps reach FAR_LIGHTS, street cars' NEAR_LIGHTS (a pooled car changes job).
func _car_reach() -> void:
	var traffic := get_parent().get_node_or_null("Traffic") if get_parent() else null
	if traffic == null:
		return
	for c in traffic.get("freeway_cars"):
		_reach(c, FAR_LIGHTS)
	for c in traffic.get("cars"):
		_reach(c, NEAR_LIGHTS)


static func _reach(c: Variant, metres: float) -> void:
	if not is_instance_valid(c):
		return
	var nl: Variant = (c as Node).get("_night_lights")
	if nl is MeshInstance3D and is_instance_valid(nl) and absf((nl as MeshInstance3D).visibility_range_end - metres) > 1.0:
		(nl as MeshInstance3D).visibility_range_end = metres
