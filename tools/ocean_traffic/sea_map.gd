extends SceneTree
## Ocean traffic probe: draws the sea (MacroMap.zone_at OCEAN) over the basin as a PNG with the
## coast, the headland, the port and the marina, so routes can be laid on water. Headless:
##   godot --headless --path . --script tools/ocean_traffic/sea_map.gd   (OUT=map.png)
func _initialize() -> void:
	var macro := MacroMap.new()
	macro.seed = 1337
	macro.setup()
	var x0 := -14000.0
	var z0 := -6000.0
	var step := 40.0
	var w := 500
	var h := 450
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for j in h:
		for i in w:
			var p := Vector2(x0 + i * step, z0 + j * step)
			var zn := macro.zone_at(p)
			var c := Color(0.5, 0.5, 0.5)
			match zn:
				MacroMap.Zone.OCEAN:
					c = Color(0.1, 0.25, 0.5)
				MacroMap.Zone.BEACH:
					c = Color(0.8, 0.7, 0.5)
				MacroMap.Zone.HILLS:
					c = Color(0.35, 0.3, 0.2)
				MacroMap.Zone.PORT:
					c = Color(0.8, 0.3, 0.3)
				MacroMap.Zone.AIRPORT:
					c = Color(0.6, 0.6, 0.7)
			if int(p.x) % 1000 < 40 or int(p.y) % 1000 < 40:
				c = c.darkened(0.3)
			img.set_pixel(i, j, c)
	var out := OS.get_environment("OUT")
	img.save_png(out if out != "" else "/tmp/claude-0/sea_map.png")
	for z in [-3000, -1000, 0, 1000, 2000, 3000, 4000, 5000, 6000, 7000]:
		print("z=%d coast_x=%.0f west_head=%.0f" % [z, macro.coast_x(z), macro.headland_west_x(z)])
	var mr: Marina = macro.marina
	if mr:
		print("marina zc=", mr.zc, " channel=", mr.channel, " breakwater_x=", mr.breakwater_x())
	print("port=", macro.port_rect, " harbor=", macro.harbor_rect, " bay_z=", macro.bay_z, " bay_east=", macro.bay_east_x, " pen=", macro.peninsula_center, macro.peninsula_axes)
	for lm in Landmarks.all():
		var id: String = lm.id
		if id.contains("pier") or id.contains("ship") or id.contains("light"):
			print("landmark ", id, " ", lm.anchor)
	quit()
