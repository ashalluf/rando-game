extends Node
## Which car bodies and paints a player actually sees (car-variety-4): loads the city at a spawn,
## then for FRAMES physics frames (3600 = a game minute at 60 Hz) every EVERY frames records every
## Vehicle within RADIUS m of the camera - its body type, its paint family (white, black, grey,
## silver, red, blue, ...) and whether it is street traffic, freeway traffic or parked - once per
## car (by instance id), and prints the shares at the end. Headless and fast:
##
##   godot --headless --path . tools/car_variety/census.tscn -- --spawn=2359.4,880,0,12,2 --hour=15.5
## (a scene, so the autoloads exist before Vehicle compiles)
##   (the freeway: --spawn=1989,160,-6,-3,12 with RADIUS=220)
##
## CARS_4=0 is the before. Lines: CENSUS_BODY <name> <count> <share%>, CENSUS_PAINT <family> <count>
## <share%>, CENSUS_TOP3 <share of the three commonest bodies>, CENSUS_KINDS <distinct bodies>.


func _ready() -> void:
	var scene: PackedScene = load("res://scenes/levels/city.tscn")
	get_tree().root.add_child.call_deferred(scene.instantiate())
	for i in 5:
		await get_tree().process_frame
	var frames := int(_env("FRAMES", "3600"))
	var every := int(_env("EVERY", "60"))
	var radius := float(_env("RADIUS", "160"))
	var seen := {}
	for f in frames:
		await get_tree().physics_frame
		if (f + 1) % every == 0:
			_sample(seen, radius)
	_report(seen)
	get_tree().quit()


func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d


func _sample(seen: Dictionary, radius: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var eye: Vector3 = cam.global_position if cam else (player.global_position if player else Vector3.ZERO)
	for n in get_tree().get_nodes_in_group("vehicle"):
		var car := n as Vehicle
		if car == null or not car.is_inside_tree() or seen.has(car.get_instance_id()):
			continue
		var d := car.global_position - eye
		d.y = 0.0
		if d.length() > radius:
			continue
		var kind := "parked"
		if not car.traffic.is_empty():
			kind = "freeway" if car.traffic.has("fw") else "street"
		seen[car.get_instance_id()] = [int(car.body_type), paint_family(car.paint), kind]


static func paint_family(c: Color) -> String:
	var h := c.h * 360.0
	var s := c.s
	var v := c.v
	if v < 0.13:
		return "black"
	if s < 0.12:
		if v > 0.80:
			return "white"
		if v > 0.55:
			return "silver"
		return "grey"
	if h < 18.0 or h >= 340.0:
		return "red"
	if h < 45.0:
		return "brown" if v < 0.55 else "orange"
	if h < 70.0:
		return "gold" if s > 0.35 else "beige"
	if h < 170.0:
		return "green"
	if h < 260.0:
		return "blue"
	return "purple"


func _report(seen: Dictionary) -> void:
	var bodies := {}
	var paints := {}
	var kinds := {}
	for id in seen:
		var r: Array = seen[id]
		bodies[r[0]] = int(bodies.get(r[0], 0)) + 1
		paints[r[1]] = int(paints.get(r[1], 0)) + 1
		kinds[r[2]] = int(kinds.get(r[2], 0)) + 1
	var n := maxi(1, seen.size())
	print("CENSUS_TOTAL %d cars (%s)" % [seen.size(), kinds])
	var bk := bodies.keys()
	bk.sort_custom(func(a, b): return bodies[a] > bodies[b])
	for t in bk:
		print("CENSUS_BODY %-16s %4d %5.1f%%" % [Vehicle.BODY_NAMES[t], bodies[t], 100.0 * bodies[t] / n])
	var pk := paints.keys()
	pk.sort_custom(func(a, b): return paints[a] > paints[b])
	for p in pk:
		print("CENSUS_PAINT %-8s %4d %5.1f%%" % [p, paints[p], 100.0 * paints[p] / n])
	var top3 := 0
	for i in mini(3, bk.size()):
		top3 += int(bodies[bk[i]])
	print("CENSUS_TOP3 %.1f%%" % (100.0 * top3 / n))
	print("CENSUS_KINDS %d" % bk.size())
