extends Node
## Which planned tors lie along a pixel's ray from the ridge-sign refcam's eye.
##   PX=px,py godot --headless --path . res://tools/rc3_ridge_sign/tor_probe.tscn

func _ready() -> void:
	var city: Node = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	var plan := CityPlan.new()
	plan.seed = city.world_seed
	plan.block_size_range = city.block_size_range
	plan.street_width = city.street_width
	plan.avenue_width = city.avenue_width
	plan.sidewalk_width = city.sidewalk_width
	plan.downtown_radius = city.downtown_radius
	plan.midtown_radius = city.midtown_radius
	plan.macro = MacroMap.new()
	plan.macro.seed = city.world_seed
	plan.macro.setup()
	plan.macro.bake(Vector2.ZERO, 16000.0, 256)
	var eye := Vector3(-262.0, 388.0, -1030.0)
	var yaw := deg_to_rad(-68.0)
	var pitch := deg_to_rad(-11.0)
	var basis := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	var fwd := -basis.z
	var right := basis.x
	var up := basis.y
	var t := tan(deg_to_rad(55.0) * 0.5)
	var args := [OS.get_environment("PX")]
	var px := float(args[0].split(",")[0])
	var py := float(args[0].split(",")[1])
	var d := (fwd + right * ((px / 1280.0) * 2.0 - 1.0) * t * 1280.0 / 720.0 + up * (1.0 - py / 720.0 * 2.0) * t).normalized()
	print("RAY ", d, " tors ", RockOutcrops.tors(plan).size())
	var near: Array = []
	for tr: Dictionary in RockOutcrops.tors(plan):
		var q := Vector2(tr.pos.x - eye.x, tr.pos.y - eye.z)
		if q.length() < 500.0:
			near.append("%d@%s y%.0f top%.0f" % [tr.id, tr.pos, float(tr.y), float(tr.get("top", 0.0))])
	print("NEAR ", near)
	for tr: Dictionary in RockOutcrops.tors(plan):
		var p := Vector3(tr.pos.x, float(tr.y), tr.pos.y)
		var v := p - eye
		var along := v.dot(d)
		if along < 0.0:
			continue
		var off := (v - d * along).length()
		var hd := Vector2(d.x, d.z).normalized()
		var hv := Vector2(v.x, v.z)
		var ang := absf(hd.angle_to(hv))
		if ang < deg_to_rad(4.0) and hv.length() < 4000.0:
			print("TOR id %d kind %d at %s top %.1f along %.0f off %.0f ground %.1f block %s summit %s" % [tr.id, tr.kind, p, float(tr.get("top", 0.0)), along, off, plan.height_at(tr.pos), plan.block_index_at(tr.pos), tr.get("summit", false)])
	city.free()
	get_tree().quit()
