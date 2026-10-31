extends Node
## Runs tools/traffic_motion/stage.gd headless and prints every staged car each step (seconds):
##   KIND=pull godot --headless --path . res://tools/traffic_motion/stage_probe.tscn -- --hour=15.5

func _ready() -> void:
	var root := get_tree().root
	await get_tree().process_frame
	var scene: PackedScene = load("res://scenes/levels/city.tscn")
	root.add_child(scene.instantiate())
	for i in 3:
		await get_tree().process_frame
	var city: Node = root.find_child("City", false, false)
	for i in 120:
		await get_tree().process_frame
	var tm: TrafficManager = city.get_node("Traffic")
	var stage = load("res://tools/traffic_motion/stage.gd")
	var kind := OS.get_environment("KIND") if OS.get_environment("KIND") != "" else "pull"
	print("PROBE eye ", stage.call("stage", tm, kind, root.get_camera_3d()))
	for s in 16:
		stage.call("advance", tm, 0.5)
		for c in stage.get("_cars"):
			var t: Dictionary = c.traffic
			print("  car v %.2f along %.1f why %s react %.2f held %s turn %s qs %s sign %s" % [float(t.get("v", 0)), float(t.get("along", 0)), t.get("why"), float(t.get("react", 0)), t.get("held"), t.get("turn"), t.get("qs"), t.get("sign_ok")])
	get_tree().quit()
