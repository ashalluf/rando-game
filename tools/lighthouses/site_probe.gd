extends SceneTree
## Prints the headland's south-east shore (height, slope, zone) and the sea off the port, to
## choose where the lighthouse and the breakwater stand.
##   godot --headless --path . --script tools/lighthouses/site_probe.gd

func _initialize() -> void:
	await process_frame
	var m := MacroMap.new()
	m.seed = 1337
	m.setup()
	var c := m.peninsula_center
	var b := deg_to_rad(m.peninsula_axis_bearing)
	var ax0 := Vector2(sin(b), -cos(b))
	var ax1 := Vector2(-ax0.y, ax0.x)
	print("axes ", ax0, ax1)
	for deg in range(-60, 100, 8):
		var t := deg_to_rad(float(deg))
		var e := Vector2(cos(t), sin(t))
		var shore := c + ax0 * e.x * m.peninsula_axes.x + ax1 * e.y * m.peninsula_axes.y
		var line := "ANG %4d shore (%.0f,%.0f) zone %s |" % [deg, shore.x, shore.y, MacroMap.zone_name(m.zone_at(shore))]
		for inset in [-60.0, -20.0, 20.0, 50.0, 90.0, 140.0]:
			var p: Vector2 = shore + (c - shore).normalized() * inset
			line += " %.0f:%.1f/%s" % [inset, m.height_at(p), MacroMap.zone_name(m.zone_at(p)).substr(0, 3)]
		print(line)
	for z in [6600.0, 6700.0, 6800.0, 6900.0, 7000.0, 7100.0]:
		var line := "Z %.0f |" % z
		for x in range(2000, 4001, 200):
			var p := Vector2(float(x), z)
			line += " %d:%s%.1f" % [x, MacroMap.zone_name(m.zone_at(p)).substr(0, 3), m.height_at(p)]
		print(line)
	quit()
