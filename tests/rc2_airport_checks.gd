extends RefCounted
## The airport apron refcam (refcam2 "airport_apron", AirportApron) for tests/smoke_test.gd: the
## airport's paint stands proud of the surface it is on (it was pressed under it), the apron's
## yellow lines get a black border and nothing else does, every attended stand has its stains on
## the apron and none on the taxiway, the materials carry the close-up pass, the switch puts the
## old numbers back, and a FULL airport chunk really painted at the new lift. Loaded at run time,
## so it compiles after the autoloads.

var _t: Node
var _tree: SceneTree


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	var plan: CityPlan = city.get("plan")
	if plan == null or plan.macro == null:
		return
	var macro := plan.macro
	_paint(macro)
	_stains(macro)
	_materials()
	_camera_row()
	await _chunk(city, macro)


func _paint(macro: MacroMap) -> void:
	# road_paint presses a stripe box's top to its underside + PAINT_THICK (StreetCloseup); the box
	# is 2 cm tall and centred on its lift.
	var thick: float = StreetCloseup.PAINT_THICK if StreetCloseup.enabled else 0.02
	var yellow_top := AirportApron.paint_lift() - 0.01 + thick
	var border_top := AirportApron.BORDER_LIFT - 0.01 + thick
	_t._check(AirportApron.enabled and yellow_top > 0.003 and border_top > 0.001 and yellow_top - border_top > 0.003,
		"the airport's paint stands over the surface, its yellow over the black border (tops %.4f / %.4f m)" % [yellow_top, border_top])
	var apron: float = macro.tarmac_top
	_t._check(AirportApron.wants_border(Airport.YELLOW, apron, apron) and not AirportApron.wants_border(Airport.YELLOW, Airport.TAXI_TOP, apron)
		and not AirportApron.wants_border(Airport.RED, apron, apron) and not AirportApron.wants_border(Airport.WHITE, apron, apron),
		"only the apron's yellow lines get a black border (not the taxiway's, not red or white paint)")
	AirportApron.enabled = false
	var old := AirportApron.paint_lift()
	var old_border := AirportApron.wants_border(Airport.YELLOW, apron, apron)
	AirportApron.enabled = true
	_t._check(is_equal_approx(old, 0.002) and not old_border, "AIRPORT_APRON=0 puts the old lift back and borders nothing")


func _stains(macro: MacroMap) -> void:
	var list := AirportApron.stain_list()
	var per := {}
	var bad := 0
	var light := 0
	var taxi_edge: float = macro.taxiway_z - macro.taxiway_width * 0.5
	for st: Array in list:
		var p: Vector2 = st[0]
		var g := _nearest_gate(p)
		per[g] = int(per.get(g, 0)) + 1
		if p.y > taxi_edge - 1.0:
			bad += 1
		if float(st[4]) >= 0.6:
			light += 1
	var stands := 0
	var min_n := 1 << 20
	for g: Dictionary in Airport.gates():
		if g.get("empty", false):
			continue
		stands += 1
		min_n = mini(min_n, int(per.get(String(g.number), 0)))
	_t._check(stands > 0 and min_n >= AirportApron.STAND_STAINS.size() + 3,
		"every attended stand has its stains: nose, mains, engines, tracks, spills (fewest %d)" % min_n)
	_t._check(bad == 0 and light == 0, "the stains lie on the apron, none on the taxiway, all dark enough to soak in (%d off, %d light)" % [bad, light])
	_t._check(AirportApron.stain_list() == list, "the stains are pure: the same list twice")


func _nearest_gate(p: Vector2) -> String:
	var best := ""
	var bd := INF
	for g: Dictionary in Airport.gates():
		var d := p.distance_to(g.nose as Vector2)
		if d < bd:
			bd = d
			best = String(g.number)
	return best


func _materials() -> void:
	var kit := AirportKit.material()
	var jet := AirportTerminal.livery_material(2)
	var grass := Airport.grass_material()
	_t._check(float(kit.get_shader_parameter("grime")) > 0.5 and float(jet.get_shader_parameter("detail")) > 0.5
		and float(grass.get_shader_parameter("straw")) > 0.5,
		"the ground equipment wears its grime, the liveries their titles and seams, the infield its straw")
	var glass := AirportApron.glass_params(0.1, 8.0, 9.0)
	_t._check(float(glass.interior_day) >= 0.4 and float(glass.interior_night) > 1.0,
		"the concourse glass shows its hall by day and keeps its night")
	# Every other lawn keeps the old texture (straw 0 is lawn.gdshader's default).
	var lawn: ShaderMaterial = PropFactory.lawn(Color(0.42, 0.56, 0.24), 17, 0.3)
	var straw: Variant = lawn.get_shader_parameter("straw")
	_t._check(straw == null or float(straw) == 0.0, "a street lawn is not turned to straw")
	var src := FileAccess.get_file_as_string("res://shaders/airliner_livery.gdshader")
	# Derivatives only outside branches (llvmpipe reads 0 inside one): the letters and seams take
	# the pixel's size as an argument.
	_t._check(src.count("fwidth(") <= 5 and src.contains("al_line(") and src.contains("uniform float detail"),
		"the livery's close-up pass takes its pixel size outside every branch")


func _camera_row() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/refcams/cameras_w5.json"))
	var row: Dictionary = {}
	if parsed is Dictionary:
		for c: Dictionary in parsed.get("cameras", []):
			if String(c.get("name", "")) == "airport_apron":
				row = c
	_t._check(not row.is_empty() and String(row.get("air", "")) == "taxi" and (row.eye as Array).size() == 5,
		"the airport_apron reference camera is in cameras_w5.json with its taxiing jet")


func _chunk(city: Node3D, macro: MacroMap) -> void:
	var player := _tree.get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var ws: Node = _tree.root.get_node("/root/WorldState")
	var gate: Dictionary = Airport.gates()[3]
	var c: Vector2 = gate.nose
	var was: Vector3 = player.global_position
	player.global_position = ws.call("to_local", Vector3(c.x, 3.0, c.y + 30.0))
	city.call("update_streaming", true)
	for i in 4:
		await _tree.physics_frame
	var plan: CityPlan = city.get("plan")
	var chunks: Dictionary = city.get("chunks")
	var chunk: Node = chunks.get(plan.block_index_at(c))
	# The static the FULL build painted at: read after a FULL airport chunk has been built (the
	# initialiser read AirportApron before it was set, and every line stayed under the ground).
	_t._check(chunk != null and int(chunk.get("level")) == CityChunk.Level.FULL and is_equal_approx(Airport._paint_lift, AirportApron.PAINT_LIFT),
		"a FULL airport chunk paints at the new lift (%.3f)" % Airport._paint_lift)
	var patches := false
	if chunk:
		for n in chunk.get_children():
			patches = patches or String(n.name).begins_with("Batch_patch")
	_t._check(patches, "the stands' stains are laid in the chunk's patch batch")
	player.global_position = was
	city.call("update_streaming", true)
	await _tree.physics_frame
