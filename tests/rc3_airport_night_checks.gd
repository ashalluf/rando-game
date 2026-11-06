extends RefCounted
## The airfield at night (refcam3 "airport_night", AirportNight) for tests/smoke_test.gd: the masts
## the floods come from, the pool's curve and its numbers, the jets' and the equipment's materials
## carrying the masts and the logo lights, the landing lights' off-axis share, the patrol beam, the
## switch, the camera row, and a FULL airport chunk laying the new pools. Loaded at run time, so it
## compiles after the autoloads.

var _t: Node
var _tree: SceneTree


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	var plan: CityPlan = city.get("plan")
	if plan == null or plan.macro == null:
		return
	var macro := plan.macro
	_masts(macro)
	_flood(macro)
	_materials()
	_lights()
	_camera_row()
	await _chunk(city, macro)


func _masts(macro: MacroMap) -> void:
	AirportNight.note_macro(macro)
	var spots := Airport.mast_spots(macro)
	var m := AirportNight.masts()
	var ok := AirportNight.enabled and m.size() == mini(spots.size(), 16) and m.size() >= 10
	for i in m.size():
		var v: Vector4 = m[i]
		var p: Vector2 = spots[i][0]
		var f: Vector2 = spots[i][1]
		ok = ok and is_equal_approx(v.x, p.x) and is_equal_approx(v.z, p.y) and Vector2(sin(v.w), cos(v.w)).distance_to(f) < 0.001
	_t._check(ok, "the floods come from every apron mast, at its foot, facing where it faces (%d masts)" % m.size())


## The floods' light in GDScript, as airport_flood.gdshaderinc works it out (the checks only).
func _flood_at(p: Vector3, n: Vector3) -> float:
	var e := 0.0
	var h := Airport.MAST_HEIGHT
	for v: Vector4 in AirportNight.masts():
		var l := Vector3(v.x, v.y + h, v.z) - p
		var d := Vector2(l.x, l.z).length()
		if d > AirportNight.REACH:
			continue
		var r2 := l.length_squared() + 1.0
		var lit := maxf(n.dot(l / sqrt(r2)), 0.0)
		var fwd := Vector2(-l.x, -l.z).dot(Vector2(sin(v.w), cos(v.w))) / maxf(d, 1.0)
		var aim := lerpf(AirportNight.BACK, 1.0, smoothstep(-0.3, 0.4, fwd))
		e += h * h * lit / r2 * aim * (1.0 - smoothstep(AirportNight.REACH * 0.7, AirportNight.REACH, d))
	return e


func _flood(macro: MacroMap) -> void:
	var m := AirportNight.masts()
	if m.is_empty():
		_t._check(false, "no masts noted for the floods")
		return
	var v: Vector4 = m[3]
	var y: float = macro.tarmac_top
	var under := _flood_at(Vector3(v.x, y, v.z), Vector3.UP)
	var face := Vector2(sin(v.w), cos(v.w))
	var front := _flood_at(Vector3(v.x + face.x * 40.0, y, v.z + face.y * 40.0), Vector3.UP)
	var behind := _flood_at(Vector3(v.x - face.x * 40.0, y, v.z - face.y * 40.0), Vector3.UP)
	var far := _flood_at(Vector3(v.x, y, v.z + 400.0), Vector3.UP)
	_t._check(under > 0.5 and front > behind and front > 0.15 and far == 0.0,
		"the floods light the concrete under a mast, more in front than behind, nothing far off (%.2f / %.2f / %.2f)" % [under, front, behind])
	# A jet's side facing a mast is lit; the side turned away is not.
	var p := Vector3(v.x + face.x * 25.0, y + 4.0, v.z + face.y * 25.0)
	var to_mast := Vector3(-face.x, 0.0, -face.y)
	_t._check(_flood_at(p, to_mast) > 0.2 and _flood_at(p, -to_mast) < _flood_at(p, to_mast) * 0.5,
		"a side facing the mast takes the floods, the side turned away much less")
	var src := FileAccess.get_file_as_string("res://shaders/airport_flood.gdshaderinc")
	var pool := FileAccess.get_file_as_string("res://shaders/airport_flood.gdshader")
	_t._check(src.contains("af_height * af_height * lit / r2 * aim") and src.contains("smoothstep(-0.3, 0.4, fwd)")
		and pool.contains("pow(1.0 + d2, -1.5)") and pool.contains("smoothstep(-0.3, 0.4, fwd)"),
		"the shaders' floods are the curve the checks work out")


func _materials() -> void:
	var jet := AirportTerminal.livery_material(2)
	var kit := AirportKit.material()
	_t._check(float(jet.get_shader_parameter("logo_light")) > 0.5 and int(jet.get_shader_parameter("af_count")) >= 10
		and float(jet.get_shader_parameter("af_gain")) > 0.0,
		"an airliner's livery carries the logo lights and the masts")
	_t._check(int(kit.get_shader_parameter("af_count")) >= 10 and float(kit.get_shader_parameter("af_gain")) > 0.0,
		"the ground equipment's material carries the masts")
	AirportNight.enabled = false
	var off := ShaderMaterial.new()
	off.shader = load("res://shaders/airliner_livery.gdshader")
	AirportApron.dress_jet(off)
	AirportNight.enabled = true
	_t._check(off.get_shader_parameter("logo_light") == null and off.get_shader_parameter("af_count") == null,
		"AIRPORT_NIGHT=0 leaves a livery as it was (no floods, no logo lights)")


func _lights() -> void:
	var src := FileAccess.get_file_as_string("res://shaders/aircraft_lights.gdshader")
	_t._check(src.contains("uniform float landing_side") and src.contains("uniform float landing_glare") and AirportNight.LANDING_SIDE > 0.06 and AirportNight.LANDING_GLARE > 0.0,
		"a landing light keeps a share of its glare off its axis (%.2f) and flares down its beam" % AirportNight.LANDING_SIDE)
	# The landing lights' pool: under a low jet with the lights on, gone when high or off.
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/aircraft_lights.gdshader")
	mat.set_shader_parameter("landing_on", 1.0)
	var holder := _LightHolder.new()
	holder._light_mat = mat
	_tree.root.add_child(holder)
	holder.global_position = Vector3(0.0, 20.0, 0.0)
	AirportNight.landing_pool(holder, 20.0, Vector3(-1.0, 0.0, 0.0))
	var pool := holder.get_node_or_null("LandingPool") as MeshInstance3D
	var low_ok := pool != null and pool.visible and pool.global_position.x < -40.0 and absf(pool.global_position.y - 0.08) < 0.01
	AirportNight.landing_pool(holder, 300.0, Vector3(-1.0, 0.0, 0.0))
	var high_off := pool != null and not pool.visible
	mat.set_shader_parameter("landing_on", 0.0)
	AirportNight.landing_pool(holder, 10.0, Vector3(-1.0, 0.0, 0.0))
	var off_off := pool != null and not pool.visible
	_t._check(low_ok and high_off and off_off, "a low jet's landing lights lay a pool down the runway ahead; none high up or with them off")
	holder.queue_free()
	var beam := FileAccess.get_file_as_string("res://scripts/vehicles/helicopter.gd")
	_t._check(AirportNight.PATROL_BEAM < 0.6 and beam.contains("AirportNight.PATROL_BEAM"),
		"a patrol helicopter's shaft is fainter than a pursuit's")


func _camera_row() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://tools/refcams/cameras_w6.json"))
	var row := {}
	if data is Dictionary:
		for c in data.get("cameras", []):
			if c.get("name", "") == "airport_night":
				row = c
	_t._check(not row.is_empty() and is_equal_approx(float(row.get("hour", 0.0)), 21.5) and row.get("air", "") == "final",
		"the airport_night camera row: 21:30, a jet on final")


func _chunk(city: Node3D, macro: MacroMap) -> void:
	var player := _tree.get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var ws: Node = _tree.root.get_node("/root/WorldState")
	var spot: Vector2 = Airport.mast_spots(macro)[4][0]
	var was: Vector3 = player.global_position
	player.global_position = ws.call("to_local", Vector3(spot.x, 3.0, spot.y + 20.0))
	city.call("update_streaming", true)
	for i in 4:
		await _tree.physics_frame
	var plan: CityPlan = city.get("plan")
	var chunks: Dictionary = city.get("chunks")
	var chunk: Node = chunks.get(plan.block_index_at(spot))
	var ours := false
	if chunk:
		for n in chunk.find_children("Batch_ap_pool*", "", true, false):
			var mi := n as MultiMeshInstance3D
			if mi and mi.multimesh and mi.multimesh.mesh == AirportNight.pool_mesh():
				ours = true
	_t._check(ours, "a FULL airport chunk lays the floods' pools")
	player.global_position = was
	city.call("update_streaming", true)
	await _tree.physics_frame


## Stands in for an AmbientJet: AirportNight.landing_pool() reads its `_light_mat`.
class _LightHolder extends Node3D:
	var _light_mat: ShaderMaterial = null
