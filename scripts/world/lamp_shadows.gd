class_name LampShadows
extends Node
## Shadows from the nearest street lamps (night-lamps-review, wave 4; docs/HANDOFF.md "The street
## lamps at eye level"). Every street lamp carries an OmniLight3D ("lamp_light", and
## "street_lamp_light" for the ones CityChunk._add_street_lamp() makes), none of which casts: a car
## or a person under a lamp stood on the pool with no shadow at all, which is the loudest tell of a
## game street at night. This node gives the `budget` lamps nearest the camera (2 at HIGH, none
## below; Forward+ desktop only) a real cube shadow, faded in and out through `shadow_opacity` so a
## hand-over from one lamp to the next never pops.
##
## The lamp's own model must not cast from its own light (the OmniLight sits in the head; the
## twin-globe's sits inside its post, where the cube would see nothing but cast iron): the lamp
## batches of a chunk are moved onto render layer `LAMP_LAYER` the first time one of its lights is
## picked, and the shadowed lights' `shadow_caster_mask` leaves that layer out. Every other light
## (the moon included) still sees the lamps on that layer as before.
##
## One instance under the tree root, made by the first lamp light a chunk builds (ensure()).
## LAMP_SHADOWS=0 in the environment is the A/B (no node).

static var enabled: bool = OS.get_environment("LAMP_SHADOWS") != "0"
## Shadowed lamps at a time; Quality sets it per level (2 / 0 / 0 / 0).
static var budget: int = 2
## Run on the Compatibility renderer too (stills only: in the game Compatibility lights per object).
static var force: bool = false

## The render layer the lamps' own meshes move to (bit 18: 19 and 20 are the vehicles' and the
## no-blood layers).
const LAMP_LAYER := 1 << 17
const GROUP := "street_lamp_light"
## Batches whose meshes are a lamp's model (StreetLamps' keys, the old post, Broadway's lantern),
## and their shadow twins.
const LAMP_PREFIXES := ["Batch_lamp", "BatchShadow_lamp", "Batch_bw_lamp", "BatchShadow_bw_lamp"]

## A lamp further from the camera than this is not shadowed (m); the shadow fades over the last
## `fade_share` of it, and over `fade_seconds` when it moves to another lamp.
@export var reach: float = 34.0
@export var fade_share: float = 0.35
@export var fade_seconds: float = 0.45
## Seconds between picks.
@export var pick_interval: float = 0.2
## A soft lamp shadow: the head is a 40-60 cm lens, not a point.
@export var shadow_blur: float = 1.6
@export var shadow_bias: float = 0.06
@export var shadow_normal_bias: float = 1.2

static var _inst_id: int = 0
## Lights casting now (the checks and the stills read it).
static var active_count: int = 0

var _weights: Dictionary = {} # light instance id -> current opacity weight
var _wanted: Dictionary = {} # light instance id -> target weight
var _pick_t: float = 0.0


static func ensure(from: Node) -> void:
	if not enabled or not NightLamps.enabled or instance() != null or not supported():
		return
	var tree := from.get_tree() if from else null
	if tree == null:
		return
	var n := LampShadows.new()
	n.name = "LampShadows"
	_inst_id = n.get_instance_id()
	tree.root.add_child.call_deferred(n)


static func instance() -> LampShadows:
	var o := instance_from_id(_inst_id) if _inst_id != 0 else null
	return o as LampShadows if o != null and is_instance_valid(o) else null


static func supported() -> bool:
	if force:
		return true
	if OS.has_feature("web"):
		return false
	return RenderingServer.get_current_rendering_method() == "forward_plus"


## The weight a lamp `d` metres from the camera wants (1 near, 0 past reach). Pure.
static func weight_at(d: float, reach_m: float, fade: float) -> float:
	var start := reach_m * (1.0 - fade)
	return 1.0 - smoothstep(start, reach_m, d)


## The `n` best of `lights` for a camera at `cam` (pure over positions): nearest first, lit only.
static func pick(cam: Vector3, positions: Array, lit: Array, n: int, reach_m: float) -> Array:
	var cand: Array = []
	for i in positions.size():
		if not lit[i]:
			continue
		var d := cam.distance_to(positions[i])
		if d < reach_m:
			cand.append([d, i])
	cand.sort_custom(func(a, b): return a[0] < b[0])
	var out: Array = []
	for c in cand.slice(0, n):
		out.append(c[1])
	return out


func _exit_tree() -> void:
	active_count = 0


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d() if get_viewport() else null
	if cam == null:
		return
	_pick_t -= delta
	if _pick_t <= 0.0:
		_pick_t = pick_interval
		_pick(cam.global_position)
	# Ease every weight toward what it wants; a light at zero stops casting.
	var step := delta / maxf(fade_seconds, 0.01)
	var count := 0
	for id in _weights.keys():
		var l := instance_from_id(id) as OmniLight3D
		if l == null or not is_instance_valid(l):
			_weights.erase(id)
			continue
		var target: float = _wanted.get(id, 0.0)
		if target > 0.0:
			target *= weight_at(cam.global_position.distance_to(l.global_position), reach, fade_share)
		var w: float = move_toward(_weights[id], target, step)
		_weights[id] = w
		if w <= 0.001 and target <= 0.0:
			l.shadow_enabled = false
			l.shadow_opacity = 1.0
			_weights.erase(id)
			continue
		l.shadow_enabled = true
		l.shadow_opacity = w
		count += 1
	active_count = count


func _pick(cam: Vector3) -> void:
	_wanted.clear()
	if budget <= 0:
		return
	var lights: Array = []
	var positions: Array = []
	var lit: Array = []
	for n in get_tree().get_nodes_in_group(GROUP):
		var l := n as OmniLight3D
		if l == null or not l.is_inside_tree():
			continue
		# Cheap cut before the sort: a lamp far off is never a candidate.
		var p := l.global_position
		if absf(p.x - cam.x) > reach or absf(p.z - cam.z) > reach:
			continue
		lights.append(l)
		positions.append(p)
		lit.append(l.is_visible_in_tree() and l.light_energy > 0.01)
	for i in pick(cam, positions, lit, budget, reach):
		var l: OmniLight3D = lights[i]
		_dress(l)
		_wanted[l.get_instance_id()] = 1.0
		if not _weights.has(l.get_instance_id()):
			_weights[l.get_instance_id()] = 0.0


## Set a light up to cast, and move its chunk's lamp meshes onto LAMP_LAYER (once a chunk).
func _dress(l: OmniLight3D) -> void:
	if not l.has_meta("lamp_shadow_dressed"):
		l.set_meta("lamp_shadow_dressed", true)
		l.shadow_caster_mask = 0xFFFFFFFF & ~LAMP_LAYER
		l.shadow_blur = shadow_blur
		l.shadow_bias = shadow_bias
		l.shadow_normal_bias = shadow_normal_bias
		l.distance_fade_shadow = reach
	var holder := l.get_parent()
	if holder == null or holder.has_meta("lamp_layer_done"):
		return
	holder.set_meta("lamp_layer_done", true)
	lamp_layer(holder)


## Moves every lamp batch (and its shadow twin) directly under `holder` onto LAMP_LAYER.
static func lamp_layer(holder: Node) -> int:
	var moved := 0
	for c in holder.get_children():
		var g := c as GeometryInstance3D
		if g == null:
			continue
		var nm := String(g.name)
		if nm.begins_with("Batch_lamp_pool"):
			continue
		for pre: String in LAMP_PREFIXES:
			if nm.begins_with(pre):
				g.layers = LAMP_LAYER
				moved += 1
				break
	return moved
