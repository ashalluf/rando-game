extends RefCounted
## The first minute's checks for tests/smoke_test.gd (docs/HANDOFF.md "The first minute"): the
## warm-up draws every item of its list (a kit that hands back meshes no longer aborts it), the
## rehearsal leaves no freed car in CarDamage's lists, the loading screen preloads the streamer's
## own window, FirstFill fills the traffic past its one-car-a-frame cap and does nothing when the
## traffic is staged, and the first-minute monitor stays off unless asked. Loaded at run time.

var _t: Node


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


func run(t: Node, city: Node3D) -> void:
	_t = t
	_effect_list()
	_purge()
	_preload_radius()
	_first_fill(city)
	_monitor()


## Every item the warm-up draws is a Material or a Mesh (NightLifeKit.warm() hands back meshes: a
## typed `for mat: Material` over the list stopped at the first of them, so everything after it was
## never warmed and the holder of quads stayed under the camera for the whole session).
func _effect_list() -> void:
	var items: Array = LoadingScreen.effect_list()
	var bad := 0
	var meshes := 0
	for it: Variant in items:
		if it is Mesh:
			meshes += 1
		elif not (it is Material):
			bad += 1
	_check(items.size() > 20 and bad == 0, "the warm-up's effect list is materials and meshes only (%d items, %d other)" % [items.size(), bad])
	var src := FileAccess.get_file_as_string("res://scripts/ui/loading_screen.gd")
	_check(not src.contains("for mat: Material in effects"), "the warm-up does not type its effect loop as Material (a mesh aborted it)")
	_check(meshes == 0 or src.contains("item is Mesh"), "the warm-up draws a kit's meshes as meshes (%d in the list)" % meshes)


## The rehearsal's burnt car is gone from CarDamage's static lists once it is freed.
func _purge() -> void:
	var gone := Node.new()
	gone.free()
	var keep := Node.new()
	CarDamage._wrecks.append(gone)
	CarDamage._wrecks.append(keep)
	CarDamage._burning.append(gone)
	WarmRehearsal._purge_statics()
	var left_gone := false
	for list: Array in [CarDamage._burning, CarDamage._smokers, CarDamage._wrecks]:
		for x in list:
			if not is_instance_valid(x):
				left_gone = true
	_check(not left_gone and CarDamage._wrecks.has(keep), "the rehearsal's purge drops freed cars from CarDamage's lists and keeps the rest")
	CarDamage._wrecks.erase(keep)
	keep.free()


## The loading screen preloads the streamer's own window (the wider ring was rebuilt as LOD chunks
## through the first minute of play), unless LOAD_WIDE_PRELOAD=1.
func _preload_radius() -> void:
	var fake := FakeCity.new()
	fake.load_radius_blocks = 2
	var screen := LoadingScreen.new()
	screen._preload_world(fake)
	var wide := OS.get_environment("LOAD_WIDE_PRELOAD") == "1"
	_check(fake.asked == (screen.preload_radius_blocks if wide else 2) and fake.load_radius_blocks == 2,
			"the loading screen preloads the streamer's own window (asked %d) and puts its radius back" % fake.asked)
	screen.free()
	fake.free()


class FakeCity extends Node3D:
	var load_radius_blocks: int = 2
	var asked: int = -1

	func update_streaming(_immediate: bool) -> void:
		asked = load_radius_blocks


## FirstFill: nothing while staged; else it runs every round of upkeep's spawns in one call, past
## builds_per_frame, until a round adds nothing. On a stand-in traffic node, never the city's: the
## upkeep sheds and spawns to its own target, and the checks after this one must not see that.
func _first_fill(city: Node3D) -> void:
	var tm := city.get_node_or_null("Traffic")
	if tm != null:
		var was_staged: bool = tm.staged
		var n: int = tm.cars.size()
		tm.staged = true
		_check(FirstFill.traffic(tm) == [0, 0, 0] and tm.cars.size() == n, "FirstFill does nothing while the city's traffic is staged")
		tm.staged = was_staged
	if not FirstFill.enabled:
		_check(true, "FirstFill is off (FIRST_FILL=0)")
		return
	var fake := FakeTraffic.new()
	fake._player = Node3D.new()
	var r: Array = FirstFill.traffic(fake)
	_check(fake.cars.size() == FakeTraffic.TARGET and int(r[2]) == FakeTraffic.TARGET and fake.rounds <= FirstFill.MAX_ROUNDS,
			"FirstFill builds the whole target in one call (%d cars, %d built, %d rounds)" % [fake.cars.size(), int(r[2]), fake.rounds])
	_check(FirstFill.traffic(fake)[2] == 0, "a second FirstFill on a full street builds nothing")
	fake._player.free()
	fake.free()


## The parts of TrafficManager FirstFill uses: an upkeep that queues at most BURST spawns a round
## toward TARGET (as _maintain() queues at most spawn_burst()).
class FakeTraffic extends Node:
	const TARGET := 23
	const BURST := 5
	var staged := false
	var plan: Object = RefCounted.new()
	var _player: Node3D
	var cars: Array = []
	var freeway_cars: Array = []
	var loop_cars: Array = []
	var _spawn_queues: Array = [[], [], []]
	var rounds := 0

	func _maintain() -> void:
		rounds += 1
		for i in mini(TARGET - cars.size(), BURST):
			_spawn_queues[0].append(func() -> void: cars.append(1))

	func _maintain_freeway() -> void:
		pass


## The first-minute monitor is only there when LOAD_FIRST_MINUTE asks for it.
func _monitor() -> void:
	var on := OS.get_environment("LOAD_FIRST_MINUTE") not in ["", "0"]
	_check(on or _t.get_tree().root.get_node_or_null("FirstMinute") == null, "the first-minute monitor is off unless LOAD_FIRST_MINUTE is set")
