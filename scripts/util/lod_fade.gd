class_name LodFade
extends Node
## Turns every hard draw-distance cut in the city into a crossfade (wave 5, "lod-pops").
##
## The city sets visibility ranges on hundreds of kinds of node - a car's near body and its far
## twin swap at 30 m, its wheel rigs end at 85, shop names at 75, hats at 60, the car parks' real
## cars hand over to static ones at 42 - and about half of them had no fade: an audit
## (tools/lod_pops/range_audit.gd) counted ~200 kinds with VISIBILITY_RANGE_FADE_DISABLED or a
## zero margin. Each is a pop the eye catches while driving.
##
## Godot fades a range by itself on Forward+ (the Mac): with VISIBILITY_RANGE_FADE_SELF an
## instance is drawn alpha-blended while it is inside its margin, fading out over [end, end +
## margin] and in over [begin - margin, begin] (measured, tools/lod_pops/fade_probe.gd). A near /
## far pair with both margins set therefore crossfades: the far one fades in under the still
## opaque near one, then the near one fades out over the now opaque far one. So this node does
## not touch the builders: it watches the tree (SceneTree.node_added) and, a frame after a
## GeometryInstance3D arrives, gives a hard range a margin of `SHARE` of its distance (MIN..MAX
## metres) and FADE_SELF. A range that already fades is left alone.
##
## Compatibility (the web, every opengl3 still) has no range fade: there a margin only moves the
## cut and makes a near / far pair overlap (two cars z-fighting for a few metres), so nothing is
## changed there unless `force` is set. LOD_POPS=0 in the environment is the A/B.
## A node with meta "lod_hard" is skipped (a range that must cut).

## Off with LOD_POPS=0 (the A/B).
static var enabled: bool = OS.get_environment("LOD_POPS") != "0"
## Soften on the Compatibility renderer too (the checks; never in play).
static var force: bool = false
## A margin is this share of the range's distance ...
const SHARE := 0.12
## ... never under this ...
const MIN_MARGIN := 2.0
## ... nor over this (metres).
const MAX_MARGIN := 40.0
## How many nodes a frame it works through (the rest wait for the next frame).
const PER_FRAME := 4000

static var _node: Node
## Nodes softened since load (the checks read it).
static var softened: int = 0

var _pending: Array[GeometryInstance3D] = []


## Puts the watcher in the tree once (CityStreamer._ready calls it). Nothing on Compatibility.
static func install(parent: Node) -> void:
	if not enabled or is_instance_valid(_node):
		return
	if not force and not supported():
		return
	_node = (load("res://scripts/util/lod_fade.gd") as GDScript).new()
	_node.name = "LodFade"
	parent.add_child(_node)


## True where Godot fades visibility ranges (Forward+ / Mobile, not Compatibility).
## Never headless: the dummy renderer draws nothing, and it reports forward_plus.
static func supported() -> bool:
	return RenderingServer.get_current_rendering_method() != "gl_compatibility" and not OS.has_feature("web") \
		and DisplayServer.get_name() != "headless"


func _enter_tree() -> void:
	process_priority = 1000
	get_tree().node_added.connect(_on_added)
	# What is already there (the player, the far landmarks, the first chunks).
	_collect(get_tree().root)


func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_on_added):
		get_tree().node_added.disconnect(_on_added)
	if _node == self:
		_node = null


func _collect(n: Node) -> void:
	if n is GeometryInstance3D:
		_pending.append(n)
	for c in n.get_children():
		_collect(c)


func _on_added(n: Node) -> void:
	if n is GeometryInstance3D:
		_pending.append(n)


func _process(_delta: float) -> void:
	if _pending.is_empty():
		return
	var count := mini(_pending.size(), PER_FRAME)
	for i in count:
		var g := _pending[i]
		if is_instance_valid(g):
			soften(g)
	_pending = _pending.slice(count)


## Godot's range fade is an ALPHA blend (the instance moves to the transparent pass, which writes
## no depth), not a dither: on a flat thing - a sign, a letter, a lamp's glow, a hat, a downpipe on
## a wall - it reads as a fade, but on a body of many parts seen through itself it does not. A car
## fading out over its far twin showed its own underside, wheels and cabin through the paint
## (tools/lod_pops/car_pop_shot.gd, Forward+), worse than the cut. So vehicles (anything under a
## node in the "vehicle" group: cars, buses, cruisers, motorcycles) and the car parks' real far
## bodies keep their hard swap, and skinned meshes (people) are left to their own tiers.
static func _closed_body(g: GeometryInstance3D) -> bool:
	if g is MeshInstance3D and (g as MeshInstance3D).skin != null:
		return true
	if String(g.name).contains("RealCars"):
		return true
	var p := g.get_parent()
	while p != null:
		if p.is_in_group("vehicle"):
			return true
		p = p.get_parent()
	return false


## The margin a range of `d` metres gets.
static func margin_for(d: float) -> float:
	return clampf(d * SHARE, MIN_MARGIN, MAX_MARGIN)


## Gives a hard range on `g` a fading margin. True when it changed anything.
static func soften(g: GeometryInstance3D) -> bool:
	if g.has_meta("lod_hard") or _closed_body(g):
		return false
	var end := g.visibility_range_end
	var begin := g.visibility_range_begin
	if end <= 0.0 and begin <= 0.0:
		return false
	var fades := g.visibility_range_fade_mode != GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	var end_ok := end <= 0.0 or (fades and g.visibility_range_end_margin > 0.0)
	var begin_ok := begin <= 0.0 or (fades and g.visibility_range_begin_margin > 0.0)
	if end_ok and begin_ok:
		return false
	if end > 0.0:
		g.visibility_range_end_margin = maxf(g.visibility_range_end_margin, margin_for(end))
	if begin > 0.0:
		g.visibility_range_begin_margin = maxf(g.visibility_range_begin_margin, margin_for(begin))
	if g.visibility_range_fade_mode == GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED:
		g.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	softened += 1
	return true


## Metres a crowd body tier is held past its threshold (Pedestrian._update_lod), so somebody
## walking along a threshold - or a player standing on one - does not swap body, hair and
## shadow back and forth every update.
const TIER_BAND := 4.0


## The tier to draw given the one drawn now (`current`), the one the distance `d` asks for
## (`wanted`) and the thresholds between tiers in order: a tier changes only once `d` is
## TIER_BAND past the threshold it crosses.
static func tier_band(current: int, wanted: int, d: float, thresholds: Array) -> int:
	if wanted > current:
		# Going out: every threshold crossed must be passed by the band.
		var t := current
		while t < wanted and t < thresholds.size() and d >= float(thresholds[t]) + TIER_BAND:
			t += 1
		return t
	var u := current
	while u > wanted and u - 1 < thresholds.size() and d < float(thresholds[u - 1]) - TIER_BAND:
		u -= 1
	return u
