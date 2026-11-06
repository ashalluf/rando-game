extends SceneTree
## Runs tests/car_dealers_checks.gd alone against the city (minutes, not the smoke test's twenty):
##   godot --headless --path . --script tools/car_dealers/check_only.gd
## DIFF=1 also prints what differs outside a site with the dealers on and off.
var _fails := 0


func _check(ok: bool, label: String) -> void:
	printerr("%s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_fails += 1


func _initialize() -> void:
	var city: Node3D = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	root.add_child(city)
	for i in 30:
		await process_frame
	var holder := Node.new()
	holder.set_script(_stub())
	holder.set("owner_tree", self)
	root.add_child(holder)
	await load("res://tests/car_dealers_checks.gd").new().run(holder, city)
	printerr("CHECKS DONE")
	quit()


func _stub() -> GDScript:
	var s := GDScript.new()
	s.source_code = "extends Node\nvar owner_tree\nfunc _check(ok, label):\n\towner_tree._check(ok, label)\n"
	s.reload()
	return s
