extends RefCounted
## The reset between check files (docs/HANDOFF.md "Every check file starts from a clean city").
##
## The smoke test takes a SNAPSHOT of the city once its setup is done (before the first city
## part) and puts it back before every check file of city_files, so no file's result depends on
## which files ran before it - in one process, in a shard, or in a shuffled order
## (SMOKE_SHUFFLE=<seed>). What it puts back:
## - every class's static switches: public bools, and any static whose name says it forces,
##   stages or holds something (Onlookers.enabled, RainCrowd.forced, CarPanic.force_kind,
##   ServiceFleet.enabled, ...), read generically off every global class's script;
## - the city's own nodes: Weather (state, blend, wetness, forced ...), DayNight's hour, Quality's
##   level and force, Traffic's cap and `staged`, and every child's `enabled` / `staged`
##   (Police, Emergency, NewsCrews, Birds, OceanTraffic, CoastTraffic, ...);
## - the world: WorldState's destruction, the police's stars and units, open onlooker scenes,
##   wrecks and burning cars, debris (bodies, rubble), Engine.time_scale, the audio speed, pause,
##   the player out of any car with full health.
## `light()` is the statics alone (no node freed, no frame waited): it runs before a file the
## list does not await. `full()` is everything; the proxy then stages the player at home.
## SMOKE_LEAKS=1 prints, after each file, every primitive static it changed (counters too), so a
## new leak is found by name.
##
## Untyped where a class uses an autoload: this file is loaded at run time, after the autoloads,
## but the smoke test's own script is not.

## Static names put back whatever their type (besides public bools).
const RESTORE_WORDS := ["force", "forced", "staged", "hold"]
## Static names never touched: caches and registries that only grow, and counters.
const SKIP_PREFIX := ["_"]

var _statics := {} # Script -> {name: value}
var _all := {} # Script -> {name: value}, every primitive static (SMOKE_LEAKS)
var _nodes := {} # NodePath (from the city) -> {property: value}
var _city: Node
var _weather := {}
var _hour := 9.0
var _quality := {}
var _traffic := {}
var leaks := OS.get_environment("SMOKE_LEAKS") == "1"
## How many resets ran, and what the last put back (the checks read them).
var count := 0
var last := {}

const WEATHER_KEYS := ["state", "_previous", "blend", "wetness", "drying", "_forced", "_timer", "_wet_hold"]
const PRIMITIVE := [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_VECTOR2, TYPE_VECTOR3, TYPE_VECTOR2I, TYPE_VECTOR3I]


static func _restorable(prop: String, value: Variant) -> bool:
	for p in SKIP_PREFIX:
		if prop.begins_with(p):
			return false
	if typeof(value) == TYPE_BOOL:
		return true
	if not PRIMITIVE.has(typeof(value)):
		return false
	for w in RESTORE_WORDS:
		if prop == w or prop.begins_with(w + "_") or prop.ends_with("_" + w):
			return true
	return false


func snapshot(city: Node) -> void:
	_city = city
	for c in ProjectSettings.get_global_class_list():
		var path: String = c.path
		if not path.begins_with("res://scripts/"):
			continue
		var s: Script = load(path)
		if s == null:
			continue
		var keep := {}
		var every := {}
		for p in s.get_property_list():
			if not (int(p.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE):
				continue
			var v: Variant = s.get(p.name)
			if PRIMITIVE.has(typeof(v)):
				every[p.name] = v
				if _restorable(p.name, v):
					keep[p.name] = v
		if not keep.is_empty():
			_statics[s] = keep
		if leaks and not every.is_empty():
			_all[s] = every
	for child in city.get_children():
		var keep := {}
		for prop in ["enabled", "staged"]:
			if prop in child and typeof(child.get(prop)) == TYPE_BOOL:
				keep[prop] = child.get(prop)
		if not keep.is_empty():
			_nodes[city.get_path_to(child)] = keep
	var weather: Node = city.get_node_or_null("Weather")
	if weather:
		for key in WEATHER_KEYS:
			if key in weather:
				_weather[key] = weather.get(key)
	var dn: Node = city.get_node_or_null("DayNight")
	if dn:
		_hour = float(dn.get("hour"))
	var quality: Node = city.get_node_or_null("Quality")
	if quality:
		_quality = {"level": quality.get("level"), "_forced": quality.get("_forced")}
	var traffic: Node = city.get_node_or_null("Traffic")
	if traffic:
		_traffic = {"max_cars": traffic.get("max_cars"), "staged": traffic.get("staged")}


## Statics only: synchronous, no node freed.
func light() -> int:
	var changed := 0
	for s in _statics:
		var keep: Dictionary = _statics[s]
		for prop in keep:
			if s.get(prop) != keep[prop]:
				s.set(prop, keep[prop])
				changed += 1
				last[str(s.resource_path.get_file()) + ":" + prop] = true
	return changed


## Everything. Synchronous too (the proxy stages the player and waits afterwards).
func full(tree: SceneTree) -> void:
	count += 1
	last = {}
	light()
	if _city == null or not is_instance_valid(_city):
		return
	Engine.time_scale = 1.0
	AudioServer.playback_speed_scale = 1.0
	tree.paused = false
	for path in _nodes:
		var node: Node = _city.get_node_or_null(path)
		if node == null:
			continue
		var keep: Dictionary = _nodes[path]
		for prop in keep:
			if node.get(prop) != keep[prop]:
				node.set(prop, keep[prop])
				last[str(path) + ":" + prop] = true
	var weather: Node = _city.get_node_or_null("Weather")
	if weather:
		for key in _weather:
			if weather.get(key) != _weather[key]:
				weather.set(key, _weather[key])
				last["Weather:" + key] = true
	var dn: Node = _city.get_node_or_null("DayNight")
	if dn and float(dn.get("hour")) != _hour:
		dn.set("hour", _hour)
		last["DayNight:hour"] = true
	var quality: Node = _city.get_node_or_null("Quality")
	if quality and not _quality.is_empty() and (quality.get("level") != _quality.level or quality.get("_forced") != _quality._forced):
		quality.call("force_level", int(_quality.level))
		quality.set("_forced", _quality._forced)
		last["Quality"] = true
	var traffic: Node = _city.get_node_or_null("Traffic")
	if traffic and not _traffic.is_empty():
		for key in _traffic:
			if traffic.get(key) != _traffic[key]:
				traffic.set(key, _traffic[key])
				last["Traffic:" + key] = true
	# The player: out of any car, on his feet, full health.
	var player: Node = tree.get_first_node_in_group("player")
	if player:
		if player.get("vehicle") != null:
			player.call("exit_vehicle")
			last["player:vehicle"] = true
		var health: Object = player.get("health")
		if health:
			if bool(health.get("downed")):
				last["player:downed"] = true
			health.set("downed", false)
			health.set("health", float(health.get("max_health")))
	# The police: no stars, no units.
	var police: Node = _city.get_node_or_null("Police")
	if police and (int(police.get("stars")) > 0 or not (police.get("cruisers") as Array).is_empty() or not (police.get("officers") as Array).is_empty()):
		police.call("clear")
		last["Police:stars"] = true
	police = null
	# Destruction remembered across rebuilds.
	var ws: Node = tree.root.get_node_or_null("WorldState")
	if ws and int(ws.call("destroyed_count")) > 0:
		ws.call("reset_destruction")
		last["WorldState:destroyed"] = true
	# Onlooker scenes: everyone released, the scenes gone.
	var onlookers = Onlookers.find()
	if onlookers and not onlookers.scenes.is_empty():
		for s: Dictionary in onlookers.scenes.duplicate():
			for m in (s.members as Array).duplicate():
				if is_instance_valid(m):
					m.call("_end_act", true)
		onlookers.scenes.clear()
		last["Onlookers:scenes"] = true
	# Wrecks and burning cars (they open onlooker scenes and stand in later files' streets), and
	# what blasts and bodies left (debris).
	var freed := 0
	for list: Array in [CarDamage._burning, CarDamage._wrecks]:
		for item in list.duplicate():
			if item == null or not is_instance_valid(item):
				continue
			var car: Node = item.get("car") if item is CarDamage else item as Node
			if car and is_instance_valid(car) and not car.is_queued_for_deletion() and car != (player.get("vehicle") if player else null):
				car.queue_free()
				freed += 1
		list.clear()
	for node in tree.get_nodes_in_group(PhysicsBudget.DEBRIS_GROUP):
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			node.queue_free()
			freed += 1
	if freed > 0:
		last["freed"] = freed


## SMOKE_LEAKS=1: which primitive statics the file just run changed (and left changed).
func report(file: String) -> void:
	if not leaks:
		return
	var out: Array = []
	for s in _all:
		var every: Dictionary = _all[s]
		for prop in every:
			var now: Variant = s.get(prop)
			if now != every[prop]:
				out.append("%s:%s %s -> %s" % [s.resource_path.get_file(), prop, every[prop], now])
				every[prop] = now
	if not out.is_empty():
		printerr("LEAKS %s: %s" % [file, ", ".join(out)])
