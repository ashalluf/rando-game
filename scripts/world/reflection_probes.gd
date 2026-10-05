class_name ReflectionProbes
extends Node
## Box-projected reflection probes in the streets round the camera (GAME_PLAN G4), Forward+ only.
##
## Without them every car door, shop window and puddle mirrors the sky's radiance map, which knows
## nothing about the street it stands in (sky.gdshader paints a street grey, now with a real HDRI's
## structure, under its horizon in the cubemap pass). A probe is a cubemap rendered FROM the street:
## the facades on both sides, the kerbs, the trees, the far end of the canyon, and box projection
## puts each of those where it really is, so a car moving along the street sees them slide past.
##
## Where they go is worked out from the plan, never placed by a chunk: every street segment
## between two crossings near the camera is a candidate (a box the length of the block plus the
## crossings, the width of the road plus both pavements and the shop fronts, the height of the
## district's buildings), an open block - a park, a plaza, a schoolyard - is one box over the
## block, and outside the street grid (the beach, the hills, the port, the airport) one open box
## snapped to a grid round the camera. The `budget` nearest are kept.
##
## They are rendered ONCE (Godot spreads a probe over six frames, one face a frame) and never more
## than one at a time: a probe that has to move, or one whose light is stale - the hour moved
## `hour_step`, the lamps or the weather changed - waits for the next `refresh_seconds` slot, the
## nearest first. A probe is hidden until it has been placed and rendered where it stands, so an
## origin re-centre (which moves all of them) costs one probe a slot too, not all at once.
##
## Quality sets `budget` (HIGH 9, MEDIUM 5, none below), `shadows` (HIGH) and the probes'
## `mesh_lod_threshold`. The web and the Compatibility renderer get none (`supported()`), and
## REFLECTION_PROBES=0 in the environment turns them off (the A/B). While any probe stands, the
## `probe_reach` shader global is the radius they cover: car_paint and building glass hand part of
## their faked "canyon" reflection over to the real one inside it.

## How many probes stand at once (Quality: [9, 5, 0, 0]).
static var budget: int = 9
## Shadows in the probes' own render (Quality: HIGH only). Sunlit and shaded facades are most of
## what a mirrored street shows, but a shadowed face costs the shadow pass again.
static var shadows: bool = true
## Off for the A/B (REFLECTION_PROBES=0) and the web; tests may force it on under the dummy driver.
static var enabled: bool = true
static var force: bool = false

## Seconds between two probe renders (a render takes six frames). The cost of the system is one
## small cubemap face a frame while one is due, nothing in between.
@export var refresh_seconds: float = 0.25
## Re-render a probe once the hour has moved this much since it was rendered (game hours).
@export var hour_step: float = 0.35
## ... or the lamps / the weather darkening moved this much.
@export var light_step: float = 0.12
## How often the candidates are worked out again (seconds).
@export var survey_seconds: float = 0.5
## Height of the probe's eye over the street: over the roofs of cars, buses and box trucks, so a
## probe never renders from inside a vehicle, under any freeway deck.
@export var eye_height: float = 4.2
## Each probe's box: margins over the road (pavements and shop fronts), height by district.
@export var canyon_margin: float = 5.0
@export var district_height: PackedFloat32Array = PackedFloat32Array([70.0, 32.0, 14.0, 18.0, 22.0, 14.0])
## Open boxes (parks, plazas, outside the grid).
@export var open_height: float = 40.0
@export var open_cell: float = 160.0
@export var open_size: float = 240.0
## How far a probe's render sees (metres): the far end of a street, the towers over it.
@export var max_distance: float = 320.0
## Blend between neighbouring boxes (metres).
@export var blend_distance: float = 4.0
## A probe's own mesh LOD threshold: its faces are 256 px, so it can take coarse LODs.
@export var probe_lod_threshold: float = 6.0

const STREET_HDRI := "res://assets/textures/sky/street_hdri.png"

var plan: CityPlan
## Boxes to stand in place of the plan's (a small scene with no city: tools/reflections/probe_shot.gd),
## in candidates()' format.
var fixed: Array = []
## Probes rendered so far (tests and stills).
var renders: int = 0

## Slots: {probe, key, box (Dictionary), shown, hour, lamp, dark, offset}
var _slots: Array = []
var _wanted: Array = []
var _survey_t: float = 0.0
var _refresh_t: float = 0.0
var _day: Node = null
var _reach: float = -1.0


## The renderer can take them: Forward+ on a desktop (the Mobile renderer has probes too but no
## room for them; Compatibility and the web keep today's look).
static func supported() -> bool:
	if force:
		return true
	if not enabled or OS.has_feature("web") or OS.get_environment("REFLECTION_PROBES") == "0":
		return false
	if DisplayServer.get_name() == "headless":
		return false
	return RenderingServer.get_current_rendering_method() == "forward_plus"


## Adds the manager to the city (CityStreamer._ready). A plain Node, so the origin re-centre does
## not move the probes behind its back: they are placed from true world positions here.
static func ensure(city: Node) -> ReflectionProbes:
	if not supported() or city.get("plan") == null:
		RenderingServer.global_shader_parameter_set("probe_reach", 0.0)
		return null
	street_sky(_environment_of(city))
	var rp := ReflectionProbes.new()
	rp.name = "ReflectionProbes"
	rp.plan = city.get("plan")
	city.add_child(rp)
	return rp


## The street HDRI under the sky's horizon in its cubemap pass (sky.gdshader `street_hdri`): what
## a reflection out of every probe's reach mirrors. Forward+ only, like the probes.
static func street_sky(env: Environment, amount: float = 1.0) -> void:
	if env == null or env.sky == null or not (env.sky.sky_material is ShaderMaterial):
		return
	var sky := env.sky.sky_material as ShaderMaterial
	var tex := load(STREET_HDRI) as Texture2D
	if tex == null:
		return
	sky.set_shader_parameter("street_hdri", tex)
	sky.set_shader_parameter("street_hdri_amount", amount)


static func _environment_of(city: Node) -> Environment:
	for c in city.get_children():
		if c is WorldEnvironment:
			return (c as WorldEnvironment).environment
	var vp := city.get_viewport()
	return vp.world_3d.environment if vp and vp.world_3d else null


func _ready() -> void:
	_day = get_parent().get_node_or_null("DayNight") if get_parent() else null
	RenderingServer.global_shader_parameter_set("probe_reach", 0.0)


func _exit_tree() -> void:
	RenderingServer.global_shader_parameter_set("probe_reach", 0.0)


## The light a probe was rendered under: [hour, lamp_factor, weather darkening].
func _light_now() -> Array:
	if _day == null:
		return [12.0, 0.0, 0.0]
	return [float(_day.get("hour")), DayNight.lamp_now, float(_day.get("weather_darken"))]


func _process(delta: float) -> void:
	if plan == null and fixed.is_empty():
		return
	var cam := get_viewport().get_camera_3d() if get_viewport() else null
	if cam == null:
		return
	var eye := cam.global_position + WorldState.world_offset
	_survey_t -= delta
	if _survey_t <= 0.0:
		_survey_t = survey_seconds
		_wanted = candidates(plan, Vector2(eye.x, eye.z), budget, self) if fixed.is_empty() else fixed.slice(0, budget)
		_assign()
	_refresh_t -= delta
	if _refresh_t <= 0.0 and _render_next(Vector2(eye.x, eye.z)):
		_refresh_t = refresh_seconds
	_publish_reach(Vector2(eye.x, eye.z))


## The `count` probe boxes nearest `at`: [{key, center (true world Vector3), size, origin (offset
## from the centre), dist}], nearest first. Pure: the same plan and point give the same boxes.
static func candidates(p: CityPlan, at: Vector2, count: int, rp: ReflectionProbes = null) -> Array:
	var out: Array = []
	if count <= 0 or p == null:
		return out
	var cfg: ReflectionProbes = rp if rp else ReflectionProbes.new()
	var here := p.block_index_at(at)
	var seen := {}
	var zone := p.zone_at(at)
	# Outside the street grid (or near its edge): an open box on a fixed grid round the camera.
	if zone != MacroMap.Zone.CITY:
		var cell := Vector2(floorf(at.x / cfg.open_cell + 0.5), floorf(at.y / cfg.open_cell + 0.5)) * cfg.open_cell
		out.append(_open_box(p, "open:%d:%d" % [int(cell.x), int(cell.y)], Rect2(cell - Vector2.ONE * cfg.open_size * 0.5, Vector2.ONE * cfg.open_size), cfg.open_height, at, cfg))
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			var bx := here.x + dx
			var bz := here.y + dz
			var b: Dictionary = p.block(bx, bz)
			var r: Rect2 = b.rect
			if p.zone_at(r.get_center()) != MacroMap.Zone.CITY:
				continue
			var kind: int = b.kind
			if kind == CityPlan.BlockKind.PARK or kind == CityPlan.BlockKind.PLAZA or kind == CityPlan.BlockKind.SCHOOL:
				out.append(_open_box(p, "block:%d:%d" % [bx, bz], r.grow(p.sidewalk_width), cfg.open_height * 0.6, at, cfg))
			# The two streets on this block's -X and -Z sides (each segment once over the 5 x 5).
			for axis in [CityPlan.AXIS_X, CityPlan.AXIS_Z]:
				var i := bx if axis == CityPlan.AXIS_X else bz
				var j := bz if axis == CityPlan.AXIS_X else bx
				var key := "road:%d:%d:%d" % [axis, i, j]
				if seen.has(key):
					continue
				seen[key] = true
				var seg := _street_box(p, axis, i, j, key, at, cfg)
				if not seg.is_empty():
					out.append(seg)
	out.sort_custom(func(a: Dictionary, b2: Dictionary) -> bool: return a.dist < b2.dist)
	if out.size() > count:
		out.resize(count)
	if rp == null:
		cfg.free()
	return out


## Street `i` on `axis` between crossing roads j and j + 1: the canyon box.
static func _street_box(p: CityPlan, axis: int, i: int, j: int, key: String, at: Vector2, cfg: ReflectionProbes) -> Dictionary:
	var other := 1 - axis
	var c := p.road_pos(axis, i)
	var w := p.road_width(axis, i)
	var a0 := p.road_pos(other, j) - p.road_width(other, j) * 0.5
	var a1 := p.road_pos(other, j + 1) + p.road_width(other, j + 1) * 0.5
	var mid := (a0 + a1) * 0.5
	if not p.road_open(axis, i, mid):
		return {}
	var across := w + 2.0 * (p.sidewalk_width + cfg.canyon_margin)
	var rect: Rect2
	if axis == CityPlan.AXIS_X:
		rect = Rect2(c - across * 0.5, a0, across, a1 - a0)
	else:
		rect = Rect2(a0, c - across * 0.5, a1 - a0, across)
	if p.zone_at(rect.get_center()) != MacroMap.Zone.CITY:
		return {}
	var district := int(p.district_at(rect.get_center()))
	var h: float = cfg.district_height[clampi(district, 0, cfg.district_height.size() - 1)]
	return _box(p, key, rect, h, at, cfg)


static func _open_box(p: CityPlan, key: String, rect: Rect2, h: float, at: Vector2, cfg: ReflectionProbes) -> Dictionary:
	return _box(p, key, rect, h, at, cfg)


## A box standing on the ground at the rect's centre, its eye `eye_height` over the street.
static func _box(p: CityPlan, key: String, rect: Rect2, h: float, at: Vector2, cfg: ReflectionProbes) -> Dictionary:
	var ctr := rect.get_center()
	var ground := maxf(p.height_at(ctr), 0.0)
	# Box from a metre under the street to h over it; the eye at eye_height.
	var center := Vector3(ctr.x, ground - 1.0 + h * 0.5, ctr.y)
	var origin := Vector3(0.0, ground + cfg.eye_height - center.y, 0.0)
	var nearest := Vector2(clampf(at.x, rect.position.x, rect.end.x), clampf(at.y, rect.position.y, rect.end.y))
	return {"key": key, "center": center, "size": Vector3(rect.size.x, h, rect.size.y), "origin": origin,
		"dist": nearest.distance_to(at) + ctr.distance_to(at) * 0.05}


## Keeps the probes already standing on wanted boxes; frees the slots of the rest for the queue.
func _assign() -> void:
	var want := {}
	for w: Dictionary in _wanted:
		want[w.key] = w
	var keep := {}
	for s: Dictionary in _slots:
		if want.has(s.key):
			keep[s.key] = true
			s.box = want[s.key]
		else:
			s.key = ""
	while _slots.size() < budget:
		var probe := ReflectionProbe.new()
		probe.name = "Probe%d" % _slots.size()
		probe.visible = false
		probe.update_mode = ReflectionProbe.UPDATE_ONCE
		probe.box_projection = true
		probe.interior = false
		probe.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
		add_child(probe)
		_slots.append({"probe": probe, "key": "", "box": {}, "shown": false, "light": [], "offset": Vector3.ZERO})
	while _slots.size() > budget:
		var s: Dictionary = _slots.pop_back()
		(s.probe as Node).queue_free()
	# Free slots take the wanted boxes nobody stands on (placed by _render_next, one a slot).
	for w: Dictionary in _wanted:
		if keep.has(w.key):
			continue
		for s: Dictionary in _slots:
			if s.key == "":
				s.key = w.key
				s.box = w
				s.shown = false
				(s.probe as ReflectionProbe).visible = false
				keep[w.key] = true
				break
	for s: Dictionary in _slots:
		if s.key == "":
			(s.probe as ReflectionProbe).visible = false
			s.shown = false


## Renders the most urgent probe: one never shown (nearest first), else one moved by a re-centre,
## else the stalest light. True when one was started.
func _render_next(at: Vector2) -> bool:
	var light := _light_now()
	var best: Dictionary = {}
	var best_score := INF
	for s: Dictionary in _slots:
		if s.key == "" or (s.box as Dictionary).is_empty():
			continue
		var score := INF
		var d: float = s.box.dist
		if not s.shown or s.offset != WorldState.world_offset:
			score = d
		elif _stale(s.light, light):
			score = 10000.0 + d
		if score < best_score:
			best_score = score
			best = s
	if best.is_empty():
		return false
	var probe: ReflectionProbe = best.probe
	var box: Dictionary = best.box
	probe.size = box.size
	probe.origin_offset = box.origin
	probe.max_distance = max_distance
	probe.blend_distance = blend_distance
	probe.enable_shadows = shadows
	probe.mesh_lod_threshold = probe_lod_threshold
	var pos: Vector3 = WorldState.to_local(box.center)
	# A re-render where it already stands is a nudge (the documented way to redraw a probe that
	# updates once): a millimetre, alternately up and down.
	if best.shown and best.offset == WorldState.world_offset and probe.position.distance_to(pos) < 0.01:
		pos.y += 0.001 if probe.position.y <= pos.y else 0.0
	probe.position = pos
	probe.visible = true
	best.shown = true
	best.light = light
	best.offset = WorldState.world_offset
	renders += 1
	return true


func _stale(was: Array, now: Array) -> bool:
	if was.size() < 3:
		return true
	var dh := absf(float(now[0]) - float(was[0]))
	dh = minf(dh, 24.0 - dh)
	return dh > hour_step or absf(float(now[1]) - float(was[1])) > light_step or absf(float(now[2]) - float(was[2])) > light_step


## The radius round the camera the shown probes cover (0 with none): the shaders' hand-over.
func _publish_reach(at: Vector2) -> void:
	var reach := 0.0
	for s: Dictionary in _slots:
		if s.shown and s.key != "" and s.offset == WorldState.world_offset:
			var c: Vector3 = s.box.center
			var sz: Vector3 = s.box.size
			reach = maxf(reach, Vector2(c.x, c.z).distance_to(at) + minf(sz.x, sz.z) * 0.5)
	reach = minf(reach, max_distance)
	if absf(reach - _reach) > 1.0:
		_reach = reach
		RenderingServer.global_shader_parameter_set("probe_reach", reach)


## Probes standing and shown (tests, stills).
func shown_count() -> int:
	var n := 0
	for s: Dictionary in _slots:
		if s.shown and s.key != "":
			n += 1
	return n


func probe_boxes() -> Array:
	var out: Array = []
	for s: Dictionary in _slots:
		if s.key != "":
			out.append(s.box)
	return out
