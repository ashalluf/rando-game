extends RefCounted
## The night game from the hill (StadiumNight, the stadium_night reference camera), for
## tests/smoke_test.gd. Loaded at run time, not named there, so it compiles after the autoloads.
##
## Checks: the camera row; the box cars stand exactly in the stalls Ballpark.stall_car() fills
## (both copies; the detailed copy's tiles over the 3D cars hand over at CAR_DRAW) and cast nothing;
## the lot shader's contact-shadow reach stays inside the tiles' draw range; the car shader's copies
## of Ballpark's lot numbers; one bloom and one shaft per light bank, the bloom fading to zero inside
## its quad; the players stand on the field; the far copy carries the palms; every new uniform's
## default is the old look; the A/B adds nothing.

var _t: Object


func run(t: Object, _city: Node3D) -> void:
	_t = t
	_camera()
	_shaders()
	_build()


func _camera() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/refcams/cameras_w6.json"))
	var row: Dictionary = {}
	if data is Dictionary:
		for c: Variant in (data as Dictionary).get("cameras", []):
			if c is Dictionary and String((c as Dictionary).get("name", "")) == "stadium_night":
				row = c
	_t._check(not row.is_empty() and float(row.get("hour", 0.0)) == 21.0 and String(row.get("weather", "")) == "clear",
		"the stadium_night camera row is in cameras_w6.json at 21:00, clear")
	if row.is_empty():
		return
	var eye: Array = row.eye
	var q := Ballpark.local(Vector2(float(eye[0]), float(eye[2])))
	_t._check(q.y > Ballpark.SITE_V1 and absf(q.x) < 120.0 and float(eye[1]) > Ballpark.PAD_Y + 40.0,
		"the camera stands on the bank above the north lot, looking back over centre field (%s)" % str(q))


func _shaders() -> void:
	var car := FileAccess.get_file_as_string("res://shaders/stadium_car.gdshader")
	var copies := {
		"lot_v0": Ballpark.SITE_V0, "lot_u0": -Ballpark.SITE_U, "module": Ballpark.LOT_MODULE,
		"stall_d": Ballpark.LOT_STALL_D, "block_u": Ballpark.LOT_BLOCK_U,
	}
	var bad: Array = []
	for k: String in copies:
		var re := RegEx.create_from_string("uniform float %s = (-?[0-9.]+);" % k)
		var m := re.search(car)
		if m == null or absf(float(m.get_string(1)) - float(copies[k])) > 1e-3:
			bad.append(k)
	_t._check(bad.is_empty() and car.contains("vec2(%.1f, %.1f)" % [Ballpark.HOME.x, Ballpark.HOME.y])
		and car.contains("vec2(%.4f, %.4f)" % [Ballpark.FWD.x, Ballpark.FWD.y]) and car.contains("vec2(%.4f, %.4f)" % [Ballpark.RIGHT.x, Ballpark.RIGHT.y]),
		"stadium_car.gdshader's lot and frame numbers are Ballpark's (%s)" % str(bad))
	var lot := FileAccess.get_file_as_string("res://shaders/ballpark_lot.gdshader")
	var seats := FileAccess.get_file_as_string("res://shaders/ballpark_seats.gdshader")
	var glow := FileAccess.get_file_as_string("res://shaders/ballpark_glow.gdshader")
	var bank := FileAccess.get_file_as_string("res://shaders/stadium_bank_glow.gdshader")
	_t._check(lot.contains("uniform float box_reach = 0.0;") and lot.contains("uniform float planting2 = 0.0;") and seats.contains("uniform float night2 = 0.0;")
		and glow.contains("uniform float away_from = 150.0;") and glow.contains("uniform float away_gain = 1.0;"),
		"every second-pass uniform defaults to the old look (box_reach 0, night2 0, away 150 / 1)")
	_t._check(bank.contains("(1.0 - smoothstep(0.75, 1.0, r))") and bank.contains("bp_flood()"),
		"a bank's bloom reaches zero inside its quad and is off by day")
	# The tiers' fills are what the seats shader tells them apart by.
	var fills: Array = []
	for tr: Dictionary in Ballpark.TIERS:
		fills.append(float(tr.fill))
	_t._check(fills[0] > 0.83 and fills[1] > 0.76 and fills[1] < 0.83 and fills[2] > 0.67 and fills[2] < 0.76 and fills[3] < 0.59,
		"the seats shader tells the tiers apart by their fills (%s)" % str(fills))


func _stalls() -> Dictionary:
	var out: Dictionary = {}
	var v := Ballpark.SITE_V0
	while v < Ballpark.SITE_V1:
		for side in 2:
			var vc := v + Ballpark.LOT_STALL_D * (0.5 + side)
			var bi := 0
			while -Ballpark.SITE_U + bi * Ballpark.LOT_BLOCK_U < Ballpark.SITE_U:
				for k in Ballpark.LOT_BLOCK_STALLS_N:
					var q := Vector2(-Ballpark.SITE_U + bi * Ballpark.LOT_BLOCK_U + (k + 0.5) * Ballpark.LOT_STALL_W, vc)
					if Ballpark.stall_car(q) >= 0:
						out[Vector2i(roundi(q.x * 10.0), roundi(q.y * 10.0))] = true
				bi += 1
		v += Ballpark.LOT_MODULE
	return out


func _build() -> void:
	var stalls := _stalls()
	for detailed: bool in [false, true]:
		var root := Node3D.new()
		var statics := StaticBody3D.new() if detailed else null
		BallparkBuild.build(root, statics, detailed)
		var holder := root.get_node_or_null("Ballpark")
		var tiles := holder.find_children("StadiumCars_*", "MultiMeshInstance3D", false, false) if holder else []
		var n := 0
		var off := 0
		var casts := 0
		var bad_range := 0
		for mi: MultiMeshInstance3D in tiles:
			if mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				casts += 1
			var near_tile := mi.name.ends_with("_1")
			if (near_tile and not detailed) or (near_tile and not is_equal_approx(mi.visibility_range_begin, BallparkBuild.CAR_DRAW)) \
				or not is_equal_approx(mi.visibility_range_end, StadiumNight.FAR_DRAW):
				bad_range += 1
			var mm := mi.multimesh
			for i in mm.instance_count:
				n += 1
				var p := mm.get_instance_transform(i).origin
				var q := Ballpark.local(Vector2(p.x, p.z))
				if not stalls.has(Vector2i(roundi(q.x * 10.0), roundi(q.y * 10.0))):
					off += 1
		var level := "detailed" if detailed else "far"
		_t._check(n == stalls.size() and n > 1000, "the %s copy has a box car in every filled stall (%d of %d)" % [level, n, stalls.size()])
		# Headless keeps no instance transforms (identity): only judge positions where it does.
		if n > 0 and not (tiles[0] as MultiMeshInstance3D).multimesh.get_instance_transform(0).origin.is_zero_approx():
			_t._check(off == 0, "every %s box car stands in its stall (%d off)" % [level, off])
		_t._check(casts == 0 and bad_range == 0, "the %s copy's car tiles cast nothing and hand over at the right ranges (%d, %d)" % [level, casts, bad_range])
		var reach := float((BallparkBuild.material("lot") as ShaderMaterial).get_shader_parameter("box_reach"))
		_t._check(reach > 100.0 and reach <= StadiumNight.FAR_DRAW - StadiumNight.FAR_TILE * 0.7,
			"the lot paints its cars as shadows only where every tile draws its boxes (%.0f m)" % reach)
		var glow := holder.get_node_or_null("StadiumBankGlow") as MeshInstance3D if holder else null
		var gm := glow.mesh as ArrayMesh if glow else null
		var verts := gm.surface_get_array_len(0) if gm and gm.get_surface_count() > 0 else 0
		_t._check(verts == 12 * 10 and glow.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"the %s copy: a bloom and a shaft for each of the ten light banks (%d vertices)" % [level, verts])
		var players := holder.get_node_or_null("StadiumPlayers") as MeshInstance3D if holder else null
		var pa := (players.mesh as ArrayMesh).get_aabb() if players else AABB()
		var pc := Ballpark.local(Vector2(pa.get_center().x, pa.get_center().z))
		_t._check(players != null and pa.size.y < 2.6 and absf(pa.position.y - Ballpark.PAD_Y) < 0.05 and pc.length() < Ballpark.FENCE_CENTER,
			"the %s copy: the players stand on the field (%s)" % [level, str(pa)])
		if not detailed:
			var palms := 0
			for c in holder.get_children():
				if c is MultiMeshInstance3D and String(c.name).contains("palm_"):
					palms += (c as MultiMeshInstance3D).multimesh.instance_count
			_t._check(palms > 50, "the far copy is planted with the lot's palms (%d)" % palms)
		root.free()
	# The A/B: nothing added.
	StadiumNight._enabled = 0
	var root2 := Node3D.new()
	var holder2 := Node3D.new()
	root2.add_child(holder2)
	StadiumNight.dress(holder2, false)
	_t._check(holder2.get_child_count() == 0, "STADIUM_NIGHT=0 adds nothing")
	root2.free()
	StadiumNight._enabled = -1
