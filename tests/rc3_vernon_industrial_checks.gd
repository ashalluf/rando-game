extends RefCounted
## The vernon_industrial refcam's fixes (wave 6, rc3-vernon-industrial; RcVernon), for
## tests/smoke_test.gd. Loaded at run time, not named there, so it compiles after the autoloads.
##
## The switch reaches both industrial materials; the shaders carry their rc3 branches; a court's
## track axis follows its side and is 0 off a court or with the switch off; more docks get a
## trailer, never fewer (every trailer of the old roll is kept), about MORE_TRAILERS of the empty
## ones, none added with the switch off; the office pop-out writes its piers and header into the
## walls mesh and nothing with the switch off.

var _t: Object


func run(t: Object, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.get("plan")
	if plan == null:
		_t._check(false, "rc3_vernon: the city has a plan")
		return
	_shaders()
	_axis()
	_trailers(plan)
	_popout()


func _shaders() -> void:
	var walls := FileAccess.get_file_as_string("res://shaders/industrial_walls.gdshader")
	_t._check(walls.contains("uniform float rc3") and walls.count("rc3 > 0.5") >= 4,
		"RcVernon: industrial_walls carries the rc3 branches (steel, glass, trailer, tilt-up)")
	var ground := FileAccess.get_file_as_string("res://shaders/industrial_ground.gdshader")
	_t._check(ground.contains("uniform float rc3") and ground.contains("centre_mod > 0.1"),
		"RcVernon: industrial_ground carries the neutral asphalt and the court's tyre tracks")
	var on := 1.0 if RcVernon.enabled else 0.0
	_t._check(is_equal_approx(float(IndustrialKit.walls_material().get_shader_parameter("rc3")), on)
		and is_equal_approx(float(Industrial.ground_material().get_shader_parameter("rc3")), on),
		"RcVernon: both industrial materials carry the switch")


func _axis() -> void:
	var was := RcVernon.enabled
	RcVernon.enabled = true
	_t._check(is_equal_approx(RcVernon.track_axis("court", 0), 0.25) and is_equal_approx(RcVernon.track_axis("apron", 3), 0.75)
		and RcVernon.track_axis("strip", 0) == 0.0 and RcVernon.track_axis("store", 2) == 0.0,
		"RcVernon: a court's tracks run along its axis, nothing off a court")
	# The ballast's track line uses COLOR.b too: an axis must stay clear of 0 (the shader's test).
	_t._check(RcVernon.track_axis("court", 1) * 4.2 > 0.1 and RcVernon.track_axis("court", 2) * 4.2 > 2.1,
		"RcVernon: the shader tells the two axes apart")
	RcVernon.enabled = false
	_t._check(RcVernon.track_axis("court", 0) == 0.0, "RcVernon: RC3_VERNON=0 lays no tracks")
	RcVernon.enabled = was


func _trailers(plan: CityPlan) -> void:
	var was := RcVernon.enabled
	var docks := 0
	var old_n := 0
	var new_n := 0
	var lost := 0
	var off_extra := 0
	for bx in range(23, 26):
		for bz in range(17, 23):
			for e: Dictionary in Industrial.block_entries(plan, bx, bz):
				var lp: Dictionary = e.plan
				if lp.is_empty() or float(lp.get("court", 0.0)) <= 0.0:
					continue
				for dk: Dictionary in lp.docks:
					if int(dk.kind) != 0:
						continue
					var key := int(float(dk.u) * 10.0)
					var r := Industrial._h01([lp.seed, "ind_trl", key])
					var r2 := Industrial._h01([lp.seed, "ind_trl2", key])
					docks += 1
					var old := r < Industrial.TRAILER_ODDS
					RcVernon.enabled = true
					var now := RcVernon.dock_has_trailer(r, Industrial.TRAILER_ODDS, r2)
					RcVernon.enabled = false
					var off := RcVernon.dock_has_trailer(r, Industrial.TRAILER_ODDS, r2)
					old_n += 1 if old else 0
					new_n += 1 if now else 0
					lost += 1 if old and not now else 0
					off_extra += 1 if off != old else 0
	RcVernon.enabled = was
	_t._check(docks >= 20, "RcVernon: Vernon's courts have docks to fill (%d)" % docks)
	_t._check(lost == 0 and new_n > old_n, "RcVernon: more docks have a trailer, none lost (%d -> %d of %d)" % [old_n, new_n, docks])
	var want := Industrial.TRAILER_ODDS + (1.0 - Industrial.TRAILER_ODDS) * RcVernon.MORE_TRAILERS
	_t._check(absf(float(new_n) / maxf(docks, 1) - want) < 0.2, "RcVernon: about %.0f %% of the docks have a trailer (%d of %d)" % [want * 100.0, new_n, docks])
	_t._check(off_extra == 0, "RcVernon: RC3_VERNON=0 keeps the old trailers exactly")


func _popout() -> void:
	var was := RcVernon.enabled
	var counts := []
	for on in [true, false]:
		RcVernon.enabled = on
		var ch := CityChunk.new()
		Industrial._state(ch)
		var f := Industrial.frame(Rect2(0.0, 0.0, 40.0, 60.0), 0)
		var cx := {"ch": ch, "basis": Basis(), "f": f, "floor": 0.1}
		RcVernon.office_popout(cx, 6.0, 9.0, 30.0, 10.0, 11.05, Color(0.86, 0.84, 0.79), 12345)
		var n := 0
		if ch._ind.walls != null:
			# commit_to_arrays(): the headless renderer keeps no mesh data to read back.
			var arrays: Array = (ch._ind.walls as SurfaceTool).commit_to_arrays()
			n = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		counts.append(n)
		ch.free()
	RcVernon.enabled = was
	_t._check(int(counts[0]) >= 4 * 24 and int(counts[1]) == 0, "RcVernon: the office pop-out writes its piers, header and cap, nothing when off (%d / %d vertices)" % counts)
