extends Node
## The ridge sign's ground (rc-hills): for each letter of Landmarks.SIGN_TEXT, the ground under it on
## the sign's line and the highest ground south of it (toward the basin), and where the letter
## would stand on the south face (HillSignLetters.letter_z()). Headless, seconds:
##   godot --headless --path . res://tools/rc_hills/sign_probe.tscn

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
	var anchor := Vector2(0.0, -1180.0)
	for l: Dictionary in Landmarks.all():
		if l.id == "sign":
			anchor = l.anchor
	var line := Landmarks.sign_line(anchor, plan)
	print("SIGN anchor ", anchor, " level ground ", line.ground)
	for x in range(-180, 181, 20):
		var row := "x %4d:" % x
		for dz in range(-120, 161, 20):
			row += " %6.1f" % plan.height_at(Vector2(anchor.x + x, anchor.y + dz))
		print(row)
	print("columns: z offset -120 .. +160 step 20 (south is +)")
	# The refcam's eye (cameras.json hills: 260 m over the ground at (300, -650)) to each letter's
	# middle: the most the ground stands over the sight line on the way.
	var eye := Vector3(300.0, plan.height_at(Vector2(300.0, -650.0)) + 260.0, -650.0)
	print("EYE ", eye)
	for x in range(-160, 161, 40):
		for yy in [line.ground + 4.0, line.ground + 16.0, line.ground + 28.0]:
			var tgt := Vector3(anchor.x + x, yy, anchor.y)
			var worst := -1e9
			for k in range(1, 200):
				var p := eye.lerp(tgt, float(k) / 200.0)
				worst = maxf(worst, plan.height_at(Vector2(p.x, p.z)) - p.y)
			print("  letter x %4d at y %.0f: ground over the sight line by %.1f m" % [x, yy, worst])
	city.free()
	get_tree().quit()
