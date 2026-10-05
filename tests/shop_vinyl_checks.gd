extends RefCounted
## The shop-window vinyl's words (shaders/vinyl_lettering.gdshaderinc, building.gdshader's
## shop_decal()), for tests/smoke_test.gd. Loaded at run time, not named there.
##
## The generated text table holds Building.SHOP_NAMES in order (so a shop's name index is its
## string), then the phrases the shader picks by number; the six-bit name codes Building hands
## the shader decode back to shop_names(); and the shader includes the font and draws no
## invented letters any more.

var _t: Node
var _src := ""


func run(t: Node, _city: Node3D) -> void:
	_t = t
	_src = FileAccess.get_file_as_string("res://shaders/vinyl_lettering.gdshaderinc")
	_t._check(_src != "", "the vinyl lettering include exists")
	if _src == "":
		return
	_names()
	_kinds()
	_codes()
	_shader()


func _const_int(name: String) -> int:
	var m := RegEx.create_from_string("const int " + name + " = (\\d+);").search(_src)
	return int(m.get_string(1)) if m else -1


func _array(name: String) -> PackedInt64Array:
	var m := RegEx.create_from_string("const \\w+ " + name + "\\[\\d+\\] = \\w+\\[\\]\\(([^;]*)\\);").search(_src)
	var out := PackedInt64Array()
	if m == null:
		return out
	for part in m.get_string(1).split(","):
		var s := part.strip_edges().trim_suffix("u")
		if s != "":
			out.append(int(s))
	return out


func _string(i: int, text: PackedInt64Array, starts: PackedInt64Array, lens: PackedInt64Array, chars: String) -> String:
	var out := ""
	for k in lens[i]:
		var at: int = starts[i] + k
		var c := (text[at / 5] >> (6 * (at % 5))) & 63
		out += " " if c == 0 else ("@" if c == chars.length() + 1 else chars[c - 1])
	return out


func _names() -> void:
	var names: Array = Building.SHOP_NAMES
	var p0 := _const_int("VT_PHRASE0")
	_t._check(p0 == names.size() and names.size() < 63,
		"the vinyl text table starts with Building.SHOP_NAMES (%d names, phrases from %d; six-bit codes hold under 63)" % [names.size(), p0])
	var chars := ""
	var cm := RegEx.create_from_string("// Codes: 0 space, 1\\.\\. '(.*)', (\\d+) a digit").search(_src)
	if cm:
		chars = cm.get_string(1)
	_t._check(chars.length() > 36 and chars.find("0") == 26 and int(cm.get_string(2)) == chars.length() + 1,
		"the font's codes put '0' at 27 (shop_decal's hash digits) and the hash digit after the glyphs")
	var text := _array("VT_TEXT")
	var starts := _array("VT_T_START")
	var lens := _array("VT_T_LEN")
	var bad := []
	for i in names.size():
		if i >= starts.size() or _string(i, text, starts, lens, chars) != names[i]:
			bad.append(names[i])
	_t._check(bad.is_empty() and starts.size() == lens.size() and starts.size() > p0,
		"every shop name decodes from the vinyl table as Building names it (%d strings; wrong: %s) - rerun tools/make_vinyl_font.py" % [starts.size(), bad])
	# The phrases shop_decal() picks by number are the ones it means.
	var want := {0: "SALE", 15: "HOURS", 25: "OPEN", 26: "CALL 555-01@@", 33: "@@@@"}
	var wrong := []
	for k: int in want:
		if p0 + k >= starts.size() or _string(p0 + k, text, starts, lens, chars) != want[k]:
			wrong.append(want[k])
	_t._check(wrong.is_empty(), "shop_decal()'s phrase numbers name the phrases it means (wrong: %s)" % [wrong])
	# Every glyph fits the segment loop.
	var counts := _array("VT_G_COUNT")
	var most := 0
	for c in counts:
		most = maxi(most, c)
	_t._check(counts.size() == chars.length() + 1 and most <= _const_int("VT_MAX_SEGS"),
		"%d vinyl glyphs, none over the shader's %d segments (most %d)" % [counts.size(), _const_int("VT_MAX_SEGS"), most])


## The lines under a name and the promos are per room kind: every one of a kind's lines fits it
## (VT_FITS, the generator's table), and, independently of that table, the lines that belong to
## one trade never stand in another's window (no SALE at the bank, no WASH & FOLD at the cafe).
func _kinds() -> void:
	var chars := RegEx.create_from_string("// Codes: 0 space, 1\\.\\. '(.*)', (\\d+) a digit").search(_src).get_string(1)
	var text := _array("VT_TEXT")
	var starts := _array("VT_T_START")
	var lens := _array("VT_T_LEN")
	var p0 := _const_int("VT_PHRASE0")
	var tag := _array("VT_TAG")
	var promo := _array("VT_PROMO")
	var fits := _array("VT_FITS")
	var kinds := Building.ShopRoom.size()
	_t._check(tag.size() == kinds * 8 and promo.size() == kinds * 8 and fits.size() == starts.size() - p0,
		"the vinyl has eight lines and eight promos for each of the %d room kinds" % kinds)
	var misfit := []
	for k in kinds:
		for list: PackedInt64Array in [tag, promo]:
			for i in 8:
				var ph: int = list[k * 8 + i]
				if ph < 0 or ph >= fits.size() or (fits[ph] >> k) & 1 == 0:
					misfit.append("%s:%d" % [Building.ShopRoom.keys()[k], ph])
	_t._check(misfit.is_empty(), "every room kind's window lines are ones that fit it (misfits: %s)" % [misfit])
	# Whose lines are whose, written here and not taken from the generator.
	var only := {
		"WASH & FOLD": ["LAUNDROMAT"], "COIN LAUNDRY": ["LAUNDROMAT"], "WALK-INS WELCOME": ["BARBER"],
		"ALTERATIONS": ["CLOTHING"], "NEW ARRIVALS": ["CLOTHING"], "FRESH DAILY": ["CAFE"],
		"SALE": ["RETAIL", "CLOTHING"], "50% OFF": ["RETAIL", "CLOTHING"], "CLOSING SALE": ["RETAIL", "CLOTHING"],
		"EVERYTHING MUST GO": ["RETAIL", "CLOTHING"], "ATM INSIDE": ["RETAIL"],
		"FREE WIFI": ["CAFE", "RESTAURANT", "LAUNDROMAT"], "DINE IN - TAKE OUT": ["CAFE", "RESTAURANT"],
		"CATERING": ["CAFE", "RESTAURANT"], "WE DELIVER": ["CAFE", "RESTAURANT"],
		"MON-FRI 9-5": ["BANK"], "FREE CONSULTATION": ["BANK"], "FREE ESTIMATES": [],
	}
	var wrong := []
	for k in kinds:
		var kind_name: String = Building.ShopRoom.keys()[k]
		for list: PackedInt64Array in [tag, promo]:
			for i in 8:
				var line := _string(p0 + int(list[k * 8 + i]), text, starts, lens, chars)
				if only.has(line) and not (only[line] as Array).has(kind_name):
					wrong.append("%s at a %s" % [line, kind_name])
	_t._check(wrong.is_empty(), "no shop kind wears another trade's line in its window (wrong: %s)" % [wrong])
	var sh := FileAccess.get_file_as_string("res://shaders/building.gdshader")
	_t._check(sh.contains("VT_TAG[int(kind) * 8") and sh.contains("VT_PROMO[int(kind) * 8") and sh.contains("shop_door_i, room_kind)"),
		"shop_decal() picks its lines from the shop's room kind")


func _codes() -> void:
	var b := Building.new()
	var ok := true
	for s in [7, 1234, 98765]:
		b.seed = s
		var codes: Array[Vector4i] = b.shop_name_codes()
		for face in 4:
			var names := b.shop_names(face, Building.SHOP_ROOM_SLOTS)
			for run in Building.SHOP_ROOM_SLOTS:
				var c := (codes[0][face] >> (6 * run)) & 63 if run < 5 else (codes[1][face] >> (6 * (run - 5))) & 63
				ok = ok and c == names[run] + 1
	b.free()
	_t._check(ok, "Building.shop_name_codes() decodes, six bits a shop, to shop_names() on every face")


func _shader() -> void:
	var sh := FileAccess.get_file_as_string("res://shaders/building.gdshader")
	_t._check(sh.contains("#include \"res://shaders/vinyl_lettering.gdshaderinc\"") and sh.contains("uniform ivec4 shop_names_a")
		and sh.contains("uniform ivec4 shop_names_b") and not sh.contains("fake_glyph"),
		"building.gdshader writes its window vinyl in real words (the font included, the name codes in, no invented letters)")
