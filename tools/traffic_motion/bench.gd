extends Node
## What the traffic's body motion costs (TrafficMotion), headless: loads the city at a spawn, lets
## it stream SETTLE frames, then averages over TICKS physics frames TrafficMotion.usec (all cars'
## body motion a physics frame), the cars it moved and TrafficManager.drive_usec (the traffic tick):
##   godot --headless --path . res://tools/traffic_motion/bench.tscn -- --spawn=2359.4,880,0,12,2 --hour=12
## TRAFFIC_MOTION=0 is the before. Prints BENCH lines; read them against each other.

func _ready() -> void:
	var root := get_tree().root
	await get_tree().process_frame
	var scene: PackedScene = load("res://scenes/levels/city.tscn")
	root.add_child(scene.instantiate())
	for i in 3:
		await get_tree().process_frame
	var city: Node = root.find_child("City", false, false)
	for i in int(_env("SETTLE", "400")):
		await get_tree().process_frame
	var tm: Node = city.get_node("Traffic")
	var ticks := int(_env("TICKS", "600"))
	var motion := 0.0
	var moved := 0.0
	var drive := 0.0
	var cars := 0.0
	var phys := 0.0
	for i in ticks:
		await get_tree().physics_frame
		motion += TrafficMotion._frame_usec
		moved += TrafficMotion._frame_moving
		drive += float(tm.get("drive_usec"))
		cars += float((tm.get("cars") as Array).size() + (tm.get("freeway_cars") as Array).size())
		phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000000.0
	var n := float(ticks)
	print("BENCH motion %s: %.1f us a physics frame over %.1f cars moved (%.2f us a car); traffic tick %.0f us; %.0f traffic cars; physics process %.0f us" % [
		"on" if TrafficMotion.enabled else "off", motion / n, moved / n, motion / maxf(moved, 1.0), drive / n, cars / n, phys / n])
	get_tree().quit()


func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d
