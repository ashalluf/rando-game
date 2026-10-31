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


## FirstFill: nothing while staged; else it builds past builds_per_frame in one call.
func _first_fill(city: Node3D) -> void:
	var tm := city.get_node_or_null("Traffic")
	if tm == null:
		_check(false, "FirstFill: the city has its Traffic node")
		return
	var was_staged: bool = tm.staged
	tm.staged = true
	var r: Array = FirstFill.traffic(tm)
	_check(r == [0, 0, 0], "FirstFill does nothing while the traffic is staged")
	tm.staged = false
	if not FirstFill.enabled:
		_check(true, "FirstFill is off (FIRST_FILL=0)")
		tm.staged = was_staged
		return
	# A small fill: the street cap a few over what stands, the freeway's at what stands.
	var cap: int = tm.max_cars
	var fcap: int = tm.max_freeway_cars
	var lcap: int = tm.max_loop_cars
	var street_before: int = tm.cars.size()
	tm.max_cars = street_before + 6
	tm.max_freeway_cars = tm.freeway_cars.size()
	tm.max_loop_cars = tm.loop_cars.size()
	r = FirstFill.traffic(tm, 3000000)
	_check(int(r[2]) >= 0 and tm.cars.size() >= street_before and tm.cars.size() <= street_before + 6 + 4,
			"FirstFill fills the street toward its target in one call (%d -> %d, %d built)" % [street_before, tm.cars.size(), int(r[2])])
	tm.max_cars = cap
	tm.max_freeway_cars = fcap
	tm.max_loop_cars = lcap
	tm.staged = was_staged


## The first-minute monitor is only there when LOAD_FIRST_MINUTE asks for it.
func _monitor() -> void:
	var on := OS.get_environment("LOAD_FIRST_MINUTE") not in ["", "0"]
	_check(on or _t.get_tree().root.get_node_or_null("FirstMinute") == null, "the first-minute monitor is off unless LOAD_FIRST_MINUTE is set")
