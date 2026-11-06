extends RefCounted
## The parked car at arm's length (CarCloseup, scripts/vehicles/car_closeup.gd; refcam3
## `car_closeup`) for tests/smoke_test.gd. Loaded at run time, so it can name Vehicle, CarCloseup,
## CarDetail and PropFactory. Builds its own car high over the city and frees it. Checks: the
## bumper pieces are picked by island (a wide low band at an end and a fog pocket kept; a lamp
## bezel above the zone, a sill along the length and a piece that crosses the zone's top left
## alone); the car wheel's material carries the contact patch and the satin sidewall and the
## shader reads them only from tagged car wheels; a crossover's paint takes the soft grime;
## CAR_CLOSEUP off makes none of it; the camera row stages a parked crossover.

var _t: Node
var _tree: SceneTree
var _city: Node3D


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	_city = city
	_pieces()
	_wheels()
	await _grime()
	_camera()


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


## An axis-aligned box as 12 triangles (36 indices) appended to vv / ii.
func _box(vv: PackedVector3Array, ii: PackedInt32Array, lo: Vector3, hi: Vector3) -> void:
	var base := vv.size()
	for k in 8:
		vv.append(Vector3(hi.x if k & 1 else lo.x, hi.y if k & 2 else lo.y, hi.z if k & 4 else lo.z))
	for f: Array in [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]:
		for c: int in [f[0], f[1], f[2], f[0], f[2], f[3]]:
			ii.append(base + c)


func _pieces() -> void:
	# A body 4.6 m long along z, 1.5 m tall, its nose at z -2.3.
	var box := AABB(Vector3(-0.9, 0.0, -2.3), Vector3(1.8, 1.5, 4.6))
	var vv := PackedVector3Array()
	var ii := PackedInt32Array()
	_box(vv, ii, Vector3(-0.85, 0.30, -2.32), Vector3(0.85, 0.55, -2.20))   # 0: the nose band
	_box(vv, ii, Vector3(0.55, 0.32, -2.30), Vector3(0.75, 0.45, -2.25))    # 1: a fog pocket
	_box(vv, ii, Vector3(0.40, 0.80, -2.30), Vector3(0.85, 0.95, -2.10))    # 2: a lamp bezel
	_box(vv, ii, Vector3(0.88, 0.15, -1.60), Vector3(0.92, 0.30, 1.60))     # 3: the sill
	_box(vv, ii, Vector3(-0.40, 0.50, -2.31), Vector3(0.40, 0.75, -2.25))   # 4: crosses the top
	_box(vv, ii, Vector3(-0.85, 0.30, 2.20), Vector3(0.85, 0.55, 2.32))     # 5: the tail band
	var keep := CarCloseup.pieces(vv, ii, box, false)
	var got := {}
	for t in keep:
		got[int(t / 12)] = true
	_check(got.has(0) and got.has(5), "CarCloseup: the nose and tail bumper bands are kept (%s)" % str(got.keys()))
	_check(got.has(1), "CarCloseup: a fog-lamp pocket low on the nose is kept")
	_check(not got.has(2), "CarCloseup: a lamp bezel above the bumper zone is left alone")
	_check(not got.has(3), "CarCloseup: a sill running the car's length is left alone")
	_check(not got.has(4), "CarCloseup: a piece that crosses the zone's top is left alone (no slivers)")
	_check(keep.size() == 36, "CarCloseup: whole pieces only, 12 triangles each (%d)" % keep.size())
	# Welded by position: the same band split at a hard edge into two vertex runs is one piece.
	var vv2 := PackedVector3Array()
	var ii2 := PackedInt32Array()
	_box(vv2, ii2, Vector3(-0.85, 0.30, -2.32), Vector3(0.0, 0.55, -2.20))
	_box(vv2, ii2, Vector3(0.0, 0.30, -2.32), Vector3(0.85, 0.95, -2.20))
	_check(CarCloseup.pieces(vv2, ii2, box, false).is_empty(), "CarCloseup: pieces are joined through shared positions (a band welded to a bezel is left alone)")


func _wheels() -> void:
	var mat := PropFactory.wheel_material(0)
	_check(is_equal_approx(float(mat.get_shader_parameter("squash")), CarCloseup.TYRE_SQUASH) == CarCloseup.enabled,
			"CarCloseup: the car wheel material carries the contact patch (squash %s)" % str(mat.get_shader_parameter("squash")))
	_check(float(mat.get_shader_parameter("rubber_look")) == (1.0 if CarCloseup.enabled else 0.0),
			"CarCloseup: and the satin sidewall")
	var code := PropFactory.WHEEL_SHADER
	_check(code.contains("squash > 0.0 && UV.y > 1.0"), "CarCloseup: the wheel shader squashes only tagged car-wheel rubber")
	_check(code.contains("transpose(mat3(MODEL_MATRIX)) * vec3(0.0, -1.0, 0.0)"), "CarCloseup: the patch is at WORLD down, not the turning wheel's")
	_check(is_equal_approx(PropFactory._wheel_tag, 0.5), "CarCloseup: the wheel tag is put back after a car wheel is built")
	_check(CarCloseup.TYRE_SQUASH > 0.0 and CarCloseup.TYRE_SQUASH < 0.03, "CarCloseup: the squash is a centimetre or two (%.3f)" % CarCloseup.TYRE_SQUASH)
	var truck: Material = BigVehicles.wheel_material(Vehicle.BodyType.BUS)
	_check(truck is ShaderMaterial, "CarCloseup: the trucks' wheels share the shader (their meshes are untagged)")


func _grime() -> void:
	var src := FileAccess.get_file_as_string("res://shaders/car_paint.gdshaderinc")
	_check(src.contains("uniform float grime_look = 0.0;"), "CarCloseup: the paint's grime look defaults to the old one")
	_check(src.contains("dirt * mix(0.9, 0.58, gl)"), "CarCloseup: the close-up grime is a film the paint reads through")
	var car := Vehicle.new()
	car.body_type = Vehicle.BodyType.CROSSOVER
	_city.add_child(car)
	var player := _tree.get_first_node_in_group("player") as Node3D
	car.global_position = player.global_position + Vector3(0.0, 380.0, -25.0)
	await _tree.process_frame
	var mats := CarDetail.paint_materials(car)
	var look := -1.0
	if not mats.is_empty():
		look = float(mats[0].get_shader_parameter("grime_look"))
	if CarDetail.enabled:
		_check(look == (1.0 if CarCloseup.enabled else 0.0), "CarCloseup: a crossover's paint takes the close-up grime (grime_look %s)" % str(look))
	var holder := car.get_node_or_null("BodyModel")
	var bands := holder.find_child("BumperBands", true, false) if holder else null
	# The headless renderer keeps no mesh data: nothing to copy, so no node (stills show it).
	_check(bands == null or bands.get("visibility_range_end") == CarCloseup.NEAR,
			"CarCloseup: a bumper copy, when built, draws only near")
	car.queue_free()


func _camera() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/refcams/cameras_w6.json"))
	var row := {}
	if parsed is Dictionary:
		for c: Dictionary in parsed.get("cameras", []):
			if c.get("name", "") == "car_closeup":
				row = c
	_check(not row.is_empty(), "car_closeup: the refcam row is in cameras_w6.json")
	var pc: Dictionary = row.get("park_car", {})
	_check(String(pc.get("type", "")) == "CROSSOVER" and Vehicle.BodyType.has("CROSSOVER"),
			"car_closeup: it stages a parked crossover")
	_check(float(row.get("hour", 0.0)) == 15.0 and String(row.get("weather", "")) == "clear", "car_closeup: at 15:00, clear")
	var e: Array = pc.get("eye", [])
	_check(e.size() == 3 and Vector2(float(e[0]) - 0.9, float(e[2]) + 2.3).length() < 2.5,
			"car_closeup: the eye stands about 2 m off the front corner")
