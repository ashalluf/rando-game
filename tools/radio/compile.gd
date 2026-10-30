extends SceneTree
func _initialize() -> void:
	for p in ["res://scripts/vehicles/car_radio.gd", "res://scripts/ui/radio_hud.gd", "res://scripts/ui/debug_hud.gd", "res://scripts/vehicles/vehicle.gd"]:
		var s: Script = load(p)
		print(p, " ", s != null and s.can_instantiate())
	quit()
