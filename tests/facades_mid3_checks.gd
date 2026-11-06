extends RefCounted
## Facades at mid distance, third pass (FacadeMid3, shaders/facade_mid3.gdshaderinc, docs/HANDOFF.md
## "Facades at mid distance, third pass"): checks for tests/smoke_test.gd. Loaded at run time, so it
## compiles after the autoloads. No shader runs under --headless, so the GDScript copy of the pier
## roll is held to the shader source and to values worked out by hand (a Python copy of wl_hash);
## the stills (tools/glshot/building_shot.gd, still_shot.gd) show the pixels.

var _t: Node


func run(t: Node, _city: Node3D) -> void:
	_t = t
	_system_matches_the_shader()
	_both_shaders_share_it()
	_parapet_steps_stand_on_the_parapet()
	_no_roll_moves()


## fm3_system() and FacadeMid3.system(): salt 120, the same thresholds, known values, the shares.
func _system_matches_the_shader() -> void:
	var why := ""
	# [seed, finish, system] from the Python copy.
	var known := [[1, 0, 2], [5, 0, 1], [6, 0, 0], [9, 0, 0], [9, 1, 1], [17, 1, 1], [31, 1, 0], [1, 2, 1], [9, 2, 0]]
	for k: Array in known:
		var got := FacadeMid3.system(k[0], Building.WindowStyle.PUNCHED, k[1])
		if got != int(k[2]):
			why += " seed %d finish %d: %d, want %d" % [k[0], k[1], got, k[2]]
	var counts := [0, 0, 0]
	for sd in 1000:
		counts[FacadeMid3.system(sd, Building.WindowStyle.PUNCHED, Building.Finish.FLAT)] += 1
		for ws: int in [Building.WindowStyle.RIBBON, Building.WindowStyle.CURTAIN]:
			if FacadeMid3.system(sd, ws, Building.Finish.FLAT) != 0:
				why += " a ribbon or curtain wall has piers"
				break
		if FacadeMid3.system(sd, Building.WindowStyle.PUNCHED, Building.Finish.GLASS) != 0:
			why += " a glass finish has piers"
			break
	if counts != [337, 387, 276]:
		why += " shares %s, want [337, 387, 276]" % [counts]
	var src := FileAccess.get_file_as_string("res://shaders/facade_mid3.gdshaderinc")
	for want: String in ["wl_roll(uint(clamp(b_seed, 0.0, 999.0) + 0.5), 120u)", "k < 0.22 ? 0 : (k < 0.68 ? 1 : 2)",
			"k < 0.45 ? 0 : 1", "k < 0.34 ? 0 : (k < 0.74 ? 1 : 2)"]:
		if src.find(want) < 0:
			why += " the include lost '%s'" % want
	_t._check(why == "", "a masonry wall's piers are rolled the way the shaders roll them%s" % why)


## Both shaders include the piers and the weathered gravel; both materials switch them together.
func _both_shaders_share_it() -> void:
	var why := ""
	for p: String in ["res://shaders/building.gdshader", "res://shaders/building_lod.gdshader"]:
		var src := FileAccess.get_file_as_string(p)
		if src.find("#include \"res://shaders/facade_mid3.gdshaderinc\"") < 0:
			why += " %s lost the include" % p.get_file()
		for f: String in ["fm3_system(", "fm3_run(", "fm3_piers(", "fm3_recess_mul(", "rw_gravel("]:
			if src.find(f) < 0:
				why += " %s does not call %s" % [p.get_file(), f]
	for far: bool in [false, true]:
		var m := PropFactory.building_lod_material(far)
		if bool(m.get_shader_parameter("facade_mid3")) != FacadeMid3.enabled:
			why += " far material %s" % far
	var scene: PackedScene = load("res://scenes/props/building.tscn")
	var bld: Building = scene.instantiate()
	bld.seed = 4410
	bld.lot_size = Vector2(26.0, 24.0)
	bld.min_height = 20.0
	bld.max_height = 34.0
	_t.add_child(bld)
	var walls := bld.get_node_or_null("Walls") as MeshInstance3D
	if walls == null or not (walls.material_override is ShaderMaterial):
		why += " no walls"
	elif bool((walls.material_override as ShaderMaterial).get_shader_parameter("facade_mid3")) != FacadeMid3.enabled:
		why += " the near walls' switch"
	bld.free()
	_t._check(why == "", "the near walls and the far boxes draw the same piers and gravel%s" % why)


## The raised parapets stand on the parapet of a face (never the alley's back, a glass tower or a
## warehouse), above the roof, inside the face; the far boxes carry every piece; the near building
## builds them with a collision box each.
func _parapet_steps_stand_on_the_parapet() -> void:
	var why := ""
	if not FacadeMid3.enabled:
		return
	var scene: PackedScene = load("res://scenes/props/building.tscn")
	var with_steps := 0
	var pick := []
	for i in 40:
		var fin: int = [Building.Finish.FLAT, Building.Finish.BRICK, Building.Finish.PANELS, Building.Finish.GLASS][i % 4]
		var bld: Building = scene.instantiate()
		bld.seed = 7100 + i * 37
		bld.lot_size = Vector2(28.0, 24.0)
		bld.min_height = 14.0
		bld.max_height = 40.0
		bld.finish_options.assign([fin])
		bld.back_face = 1 + i % 4
		var style := bld.plan_only()
		var steps := FacadeMid3.parapet_steps(bld, style)
		if not steps.is_empty():
			with_steps += 1
			if pick.is_empty():
				pick = [bld.seed, fin, bld.back_face]
		if (fin == Building.Finish.GLASS or bld.shape == Building.Shape.WAREHOUSE) and not steps.is_empty():
			why += " seed %d (glass or warehouse) has steps" % bld.seed
		for piece: Array in steps:
			var size: Vector3 = piece[0]
			var c: Vector3 = piece[1]
			if c.y - size.y * 0.5 < bld.height - 0.2:
				why += " seed %d a piece below the roof" % bld.seed
				break
			var half := Vector2(bld.footprint.x, bld.footprint.y) * 0.5 + Vector2(0.2, 0.2)
			if absf(c.x) - size.x * 0.5 > half.x or absf(c.z) - size.z * 0.5 > half.y:
				why += " seed %d a piece outside the footprint" % bld.seed
				break
			# On the back face's line? The back face's outward normal (Building.back_face).
			var back := [Vector3.ZERO, Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD][bld.back_face] as Vector3
			if c.dot(back) > (half.x if absf(back.x) > 0.5 else half.y) - 1.0:
				why += " seed %d a piece on the alley's face" % bld.seed
				break
		# The far boxes carry them: as many plant boxes more than with the pass off.
		var far := FarBuilding.boxes(bld, style, 0.0)
		FacadeMid3.enabled = false
		var far_off := FarBuilding.boxes(bld, style, 0.0)
		FacadeMid3.enabled = true
		if far.size() - far_off.size() != steps.size():
			why += " seed %d far boxes %d more, want %d" % [bld.seed, far.size() - far_off.size(), steps.size()]
		bld.free()
		if why != "":
			break
	if with_steps < 6:
		why += " only %d of 40 buildings raise a parapet" % with_steps
	# Built near: one collision box a piece more than with the pass off.
	var counts := []
	if pick.is_empty():
		pick = [7100, Building.Finish.FLAT, 1]
	for on: bool in [false, true]:
		FacadeMid3.enabled = on
		var b := _plan(pick[0], pick[1], pick[2])
		_t.add_child(b)
		var shapes := 0
		for ch in b.get_children():
			if ch is CollisionShape3D:
				shapes += 1
		counts.append([shapes, FacadeMid3.parapet_steps(b, b.plan_only()).size() if on else 0])
		b.free()
	FacadeMid3.enabled = true
	if int(counts[1][0]) - int(counts[0][0]) != int(counts[1][1]):
		why += " collision %s" % [counts]
	_t._check(why == "", "raised parapets stand on the parapet of a street face, near and far alike (%d of 40 raise one)%s" % [with_steps, why])


## The pass rolls nothing of the Building's own: the same parts, colours, roof plant and shop
## names with it off and on.
func _no_roll_moves() -> void:
	var why := ""
	var was := FacadeMid3.enabled
	for i in 8:
		var sig := []
		for on: bool in [false, true]:
			FacadeMid3.enabled = on
			var b := _plan(6200 + i * 53, [Building.Finish.FLAT, Building.Finish.BRICK][i % 2], 0)
			_t.add_child(b)
			var plant := []
			for p: Array in b.roof_props:
				plant.append([p[0], (p[1] as Vector3).snapped(Vector3.ONE * 0.001)])
			var parts := []
			for p: Dictionary in b.parts:
				parts.append([p.center, p.size])
			sig.append([parts, b.facade_color, plant, b.shop_names(3, 3), b.roof_style, b.window_style])
			b.free()
		if str(sig[0]) != str(sig[1]):
			why += " seed %d moved" % (6200 + i * 53)
	FacadeMid3.enabled = was
	_t._check(why == "", "the facade pass rolls nothing of a Building's own (parts, colours, roof plant, shop names)%s" % why)


func _plan(sd: int, fin: int, back: int) -> Building:
	var scene: PackedScene = load("res://scenes/props/building.tscn")
	var b: Building = scene.instantiate()
	b.seed = sd
	b.lot_size = Vector2(28.0, 24.0)
	b.min_height = 14.0
	b.max_height = 40.0
	b.finish_options.assign([fin])
	b.back_face = back
	return b
