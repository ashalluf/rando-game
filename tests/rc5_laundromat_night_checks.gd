extends RefCounted
## The laundromat strip at 23:30 (RcLaundromat, the laundromat_night reference camera in
## tools/refcams/cameras_w8.json), for tests/smoke_test.gd. Loaded at run time, not named there, so
## it compiles after the autoloads.
##
## Checks: the shader global exists and is on; the scissor gate keeps its coverage past a pixel
## (and the off path is the old cut); the laundromat's chair row stands clear of its table and
## island and its sitters are laid on it; the donut shop's case and menu are keyed on the shop's
## name code, which is DONUT HOLE's; the camera row's building really has an open LAUNDRY beside a
## DONUT HOLE and a shut shop; RC5_LAUNDROMAT=0 turns it off.

var _t: Object


func run(t: Object, _city: Node) -> void:
	_t = t
	var glob: Variant = ProjectSettings.get_setting("shader_globals/rc5_laundromat")
	_t._check(glob is Dictionary and float(glob.get("value", 0.0)) == 1.0 and String(glob.get("type", "")) == "float",
		"rc5_laundromat: the shader global is declared, a float, on by default")
	var b_src := FileAccess.get_file_as_string("res://shaders/building.gdshader")
	var i_src := FileAccess.get_file_as_string("res://shaders/shop_interior.gdshaderinc")
	_t._check(b_src.contains("global uniform float rc5_laundromat;") and b_src.contains("gate_cover = shutter ? 0.0 : 0.42 * gate_fade")
		and b_src.contains("albedo = mix(albedo, vec3(0.16, 0.16, 0.17), gate_cover);"),
		"rc5_laundromat: a scissor gate past a pixel is kept as its coverage over the glass")
	_t._check(b_src.contains("bar = mix(bar, 0.42, gate_fade);\n\t\t\t\t\t\tshutter = bar > 0.5;"),
		"rc5_laundromat: off, the gate is the old averaged cut")
	_t._check(b_src.contains("rc5_laundromat > 0.5 && shop_name == %d" % RcLaundromat.DONUT_CODE)
		and Building.SHOP_NAMES.find("DONUT HOLE") + 1 == RcLaundromat.DONUT_CODE,
		"rc5_laundromat: the donut case is keyed on DONUT HOLE's name code (%d)" % RcLaundromat.DONUT_CODE)
	_t._check(i_src.contains("const int SI_CASE = 27;") and i_src.contains("bid == SI_CASE") and i_src.contains("if (donut) {"),
		"rc5_laundromat: the donut shop's lit case is traced and shaded")
	_chairs(i_src)
	_camera()
	var was := RcLaundromat.enabled
	RcLaundromat.set_enabled(false)
	_t._check(not RcLaundromat.enabled, "RC5_LAUNDROMAT=0: the global goes to 0 (the strip as before)")
	RcLaundromat.set_enabled(was)


## The chair row (constants read back from the include) against the laundromat's own fittings:
## seats x 0.28-0.72 off the wall, the folding table from x 1.2 and z 1.25, the island from z 2.9.
func _chairs(src: String) -> void:
	var z0 := _const(src, "LAUND_CHAIR_Z0")
	var pitch := _const(src, "LAUND_CHAIR_PITCH")
	var n := _const(src, "LAUND_CHAIRS")
	var z1 := z0 + n * pitch
	_t._check(z0 > 0.3 and z1 < 2.9 and n >= 2.0 and pitch >= 0.55,
		"rc5_laundromat: %d chairs from z %.2f to %.2f, clear of the glass and the island" % [int(n), z0, z1])
	# The sitter's knees reach ~0.45 m forward of the hips at x 0.47: short of the table at 1.2.
	_t._check(0.47 + 0.45 < 1.2 and src.contains("at = vec2(flip ? W - 0.47 : 0.47, LAUND_CHAIR_Z0 + (k + 0.5) * LAUND_CHAIR_PITCH);"),
		"rc5_laundromat: the waiting people sit on the chairs, side-on, knees short of the table")


func _const(src: String, name: String) -> float:
	var re := RegEx.create_from_string("const float %s = ([0-9.]+);" % name)
	var m := re.search(src)
	return float(m.get_string(1)) if m else -1.0


## The camera row and the building it frames: seed 519869139's west face (face 2) is BOBA,
## RECORDS, BARBER, DONUT HOLE, LAUNDRY, TATTOO; the laundry open, the tattoo shut behind a gate.
func _camera() -> void:
	var table: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/refcams/cameras_w8.json"))
	var row: Dictionary = {}
	for c: Dictionary in (table.get("cameras", []) if table is Dictionary else []):
		if String(c.get("name", "")) == "laundromat_night":
			row = c
	_t._check(not row.is_empty() and absf(float(row.get("hour", 0.0)) - 23.5) < 0.01 and String(row.get("weather", "")) == "clear",
		"laundromat_night: the camera row is in cameras_w8.json at 23:30 clear")
	var b := Building.new()
	b.seed = 519869139
	var names := b.shop_names(1, 6)
	var named: Array[String] = []
	for i in names:
		named.append(Building.SHOP_NAMES[i])
	var laund := named.find("LAUNDRY")
	var donut := named.find("DONUT HOLE")
	var tattoo := named.find("TATTOO")
	var open_l := laund >= 0 and Building.shop_open(b.shop_key(2, laund))
	var shut_t := tattoo >= 0 and not Building.shop_open(b.shop_key(2, tattoo)) and Building.shop_byte(b.shop_key(2, tattoo), 8) < 140
	_t._check(open_l and absi(laund - donut) == 1 and absi(laund - tattoo) == 1 and shut_t,
		"laundromat_night: the framed face is %s (an open LAUNDRY between a DONUT HOLE and a shut TATTOO)" % [named])
	b.free()
