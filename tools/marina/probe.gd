extends SceneTree
## Marina probe (Marina, BoatMesh): the site, the basin, the channel, the docks and boats, the
## bridge's gap, the buildings, the triangle counts of every boat mesh. Headless, seconds:
##   godot --headless --path . --script tools/marina/probe.gd      (SEED=n for another seed)
func _initialize() -> void:
	var sd := int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 1337
	var t0 := Time.get_ticks_msec()
	var macro := MacroMap.new()
	macro.seed = sd
	macro.setup()
	var plan := CityPlan.new()
	plan.seed = sd
	plan.macro = macro
	var mr: Marina = macro.marina
	print("setup ms=", Time.get_ticks_msec() - t0)
	if mr == null:
		print("NO MARINA on seed ", sd)
		quit()
		return
	print("site=", mr.site, " blocks ix ", mr.ix0, "..", mr.ix1 - 1, " iz ", mr.iz0, "..", mr.iz1 - 1)
	print("zc=%.1f z_north=%.1f z_south=%.1f x_east=%.1f west(n)=%.1f west(s)=%.1f" % [mr.zc, mr.z_north, mr.z_south, mr.x_east, mr.west_x(mr.z_north), mr.west_x(mr.z_south)])
	print("channel=", mr.channel, " breakwater_x=%.1f coast(zc)=%.1f pch(zc)=%.1f gap=%s" % [mr.breakwater_x(), macro.coast_x(mr.zc), mr.pch_x(mr.zc), mr.pch_gap()])
	print("water pts=", mr.water.size(), " grounds=", mr.grounds.size(), " docks=", mr.docks.size(), " piles=", mr.piles.size(), " gangways=", mr.gangways.size())
	var by_type := [0, 0, 0, 0]
	for b in mr.boats:
		by_type[b.type] += 1
	print("boats=", mr.boats.size(), " by type ", by_type, " yard=", mr.yard_boats.size(), " buildings=", mr.buildings.size(), " car parks=", mr.car_parks.size(), " palms=", mr.palms.size(), " lamps=", mr.lamps.size())
	for b in mr.buildings:
		print("  building ", b.kind, " ", b.rect)
	for cp in mr.car_parks:
		print("  car park ", cp)
	print("relief in site=%.2f at edge+20=%.2f beach(%.0f)=%.2f" % [macro.relief_at(mr.site.get_center()), macro.relief_at(Vector2(mr.site.end.x + 20.0, mr.site.get_center().y)), mr.sand_x(mr.zc) - 30.0, macro.relief_at(Vector2(mr.sand_x(mr.zc) - 30.0, mr.zc))])
	print("pch height at gap ends: %.2f %.2f" % [plan.height_at(Vector2(mr.pch_x(mr.pch_gap().x), mr.pch_gap().x)), plan.height_at(Vector2(mr.pch_x(mr.pch_gap().y), mr.pch_gap().y))])
	for ix in range(mr.ix0 - 1, mr.ix1 + 1):
		var line := "  ix %d:" % ix
		for iz in range(mr.iz0 - 1, mr.iz1 + 1):
			line += " %s" % ("M" if plan.marina_block(ix, iz) else ".")
		print(line)
	for t in 4:
		for v in 2:
			var tris := []
			for lv in 3:
				var m := BoatMesh.mesh(t, v, lv)
				tris.append(m.surface_get_array_index_len(0) / 3)
			print("boat type %d var %d tris %s aabb %s" % [t, v, tris, BoatMesh.mesh(t, v, 0).get_aabb()])
	# Roads closed.
	for iz in range(mr.iz0, mr.iz1 + 1):
		print("  road z iz=%d open at x=-900:%s x=-700:%s x=-600:%s" % [iz, plan.road_open(CityPlan.AXIS_Z, iz, -900.0), plan.road_open(CityPlan.AXIS_Z, iz, -700.0), plan.road_open(CityPlan.AXIS_Z, iz, -600.0)])
	quit()
