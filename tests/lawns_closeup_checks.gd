extends RefCounted
## Lawns close up (LawnsCloseup) for tests/smoke_test.gd. Loaded at run time (not named there), so
## it compiles after the autoloads. Checks: the shaders compile and their copies of each other's
## numbers agree (the lawn's tints and fields in the blades, the sprinkler hours, the fade inside a
## grass cell's draw distance); the close-up tuft is the old tuft's triangles on fewer vertices,
## every blade marked; the instance encoding round-trips; the parkway plan is pure and keeps off
## the corners and drives; a FULL suburb chunk lays its parkway, plants it, puts every tuft on its
## lawn's numbers and its weeds in the joints and along the fences - and with the pass off the
## chunk's other batches and props are exactly what they were.

var _t: Node

## Where to look for a suburb block with front lawns (the lawns bookmark).
const NEAR := Vector2(-140, 100)


func run(t: Node, city: Node3D) -> void:
	_t = t
	var t0 := Time.get_ticks_msec()
	_shaders()
	_tuft()
	_encoding()
	var plan: CityPlan = city.plan
	var block := _suburb_block(plan)
	_pieces(plan, block)
	_full(city, block)
	print("LAWNS_CLOSEUP_CHECKS %d ms" % (Time.get_ticks_msec() - t0))


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


static func _text(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_as_text() if f else ""


## The default of `uniform <type> <name> ... = <value>;` in a shader's source, as numbers.
static func _default(src: String, name: String) -> PackedFloat64Array:
	var re := RegEx.new()
	re.compile("uniform\\s+\\w+\\s+" + name + "\\b[^=;]*=\\s*([^;]+);")
	var m := re.search(src)
	var out := PackedFloat64Array()
	if m == null:
		return out
	var nums := RegEx.new()
	nums.compile("-?\\d+\\.?\\d*")
	for n in nums.search_all(m.get_string(1)):
		out.append(n.get_string().to_float())
	return out


func _shaders() -> void:
	var ok := true
	var bad: Array = []
	for p: String in ["res://shaders/lawn.gdshader", "res://shaders/grass.gdshader", "res://shaders/lawn_weed.gdshader", "res://shaders/lot_yard.gdshader"]:
		var sh: Shader = load(p)
		if sh == null or sh.get_shader_uniform_list().is_empty():
			ok = false
			bad.append(p)
	_check(ok, "lawns closeup: the lawn, grass, weed and yard shaders compile %s" % str(bad))
	var lawn := _text("res://shaders/lawn.gdshader")
	var grass := _text("res://shaders/grass.gdshader")
	var field := _text("res://shaders/lawn_field.gdshaderinc")
	_check(_default(lawn, "dry_tint") == _default(grass, "lawn_dry_tint") and _default(lawn, "dirt_tint") == _default(grass, "lawn_dirt_tint")
		and _default(lawn, "stripe_amount")[0] == 0.075 and grass.contains("LAWN_STRIPE_AMOUNT = 0.075")
		and _default(lawn, "wear_amount")[0] == 0.30 and grass.contains("LAWN_WEAR = 0.30") and grass.contains("LAWN_STRIPE_WIDTH = 3.4"),
		"lawns closeup: the blades' copies of the lawn's tints, stripes and wear agree with lawn.gdshader")
	_check(_default(grass, "fade_start")[0] == LawnsCloseup.FADE_START and _default(grass, "fade_end")[0] == LawnsCloseup.FADE_END,
		"lawns closeup: grass.gdshader's fade is LawnsCloseup's (%s, %s)" % [str(_default(grass, "fade_start")), str(_default(grass, "fade_end"))])
	# A cell is drawn while its centre is within GRASS_DISTANCE; its farthest blade is half a
	# diagonal further. Every blade must be gone (fade_end) before the cell stops drawing.
	_check(LawnsCloseup.FADE_END + CityChunk.GRASS_CELL * 0.7072 <= LawnsCloseup.GRASS_DISTANCE,
		"lawns closeup: the blades are gone before their cell stops drawing (%.1f + %.1f <= %.1f)" % [LawnsCloseup.FADE_END, CityChunk.GRASS_CELL * 0.7072, LawnsCloseup.GRASS_DISTANCE])
	var hours := "smoothstep(%.1f, %.1f, h) * (1.0 - smoothstep(%.1f, %.1f, h))" % [LawnsCloseup.SPRINKLER_ON.x, LawnsCloseup.SPRINKLER_ON.y, LawnsCloseup.SPRINKLER_OFF.x, LawnsCloseup.SPRINKLER_OFF.y]
	_check(field.contains(hours) and LawnsCloseup.sprinkler_hours(3.0) == 0.0 and LawnsCloseup.sprinkler_hours(6.5) == 1.0
		and LawnsCloseup.sprinkler_hours(12.0) == 0.0, "lawns closeup: the sprinkler hours mirror lf_sprinkler_hours() (wet at 6:30, dry by noon)")


static func _tris(m: Mesh) -> int:
	var n := 0
	for s in m.get_surface_count():
		var arr := m.surface_get_arrays(s)
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		n += idx.size() / 3 if idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n


func _tuft() -> void:
	var old := PropFactory.grass_blade()
	var new := LawnsCloseup.blade_mesh()
	var nv := (new.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var ov := (old.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var a := old.get_aabb()
	var b := new.get_aabb()
	_check(_tris(old) == _tris(new) and nv * 2 < ov and b.size.y < a.size.y * (LawnsCloseup.MOWN + 0.01) and b.size.x > a.size.x,
		"lawns closeup: the close-up tuft is the old tuft's %d triangles on %d vertices (was %d), mown and spread (%s / %s)" % [_tris(new), nv, ov, str(b.size), str(a.size)])
	var uvs: PackedVector2Array = new.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	var ids := {}
	for uv in uvs:
		ids[snappedf(uv.x, 0.001)] = true
	_check(ids.size() == PropFactory.GRASS_BLADES, "lawns closeup: every blade of the tuft carries its own place (%d)" % ids.size())
	var ok := true
	for k in 3:
		var w := LawnsCloseup.weed_mesh(k)
		ok = ok and _tris(w) >= 20 and _tris(w) <= 200 and w.get_aabb().size.y < 0.4
	_check(ok, "lawns closeup: the three weeds build, small and low")


func _encoding() -> void:
	# The seed index / 1024 must be exact in a half float (Compatibility): |k| < 1024.
	var look := LawnsCloseup.lawn_look(PropFactory.lawn(Color(0.9, 0.95, 0.7), -123456789), 0)
	var d := LawnsCloseup.tuft_data(0.5, look, 3.3)
	var k := roundi(d.b * 1024.0)
	_check(absi(k) < 1024 and k == (-123456789) % 997 and d.a >= 16.0 and absf(fmod(d.a, 16.0) - 3.3) < 0.04 and absf(d.g - 0.35) < 0.001,
		"lawns closeup: a tuft carries its lawn's seed index, dryness, stripes and edge (%s)" % str(d))
	var plain := LawnsCloseup.lawn_look(PropFactory.material(Color.WHITE), 7)
	_check(int(plain[2]) == 7 and float(plain[1]) > 0.0, "lawns closeup: grass on a lawn of no known look gets a plain watered one")


## A SUBURBS lawn block round NEAR with houses on it.
func _suburb_block(plan: CityPlan) -> Vector2i:
	var c: Vector2i = plan.block_index_at(NEAR)
	for r in 6:
		for bx in range(c.x - r, c.x + r + 1):
			for bz in range(c.y - r, c.y + r + 1):
				var b: Dictionary = plan.block(bx, bz)
				if int(b.district) == CityPlan.District.SUBURBS and int(b.kind) == CityPlan.BlockKind.BUILDINGS and not b.has("site") \
						and not b.has("grounds") and plan.zone_at((b.rect as Rect2).get_center()) == MacroMap.Zone.CITY and plan.lots(bx, bz).size() >= 6:
					print("LAWNS_CLOSEUP check block %s" % str(Vector2i(bx, bz)))
					return Vector2i(bx, bz)
	return c


func _pieces(plan: CityPlan, block: Vector2i) -> void:
	var rect: Rect2 = plan.block(block.x, block.y).rect
	var drives := [Rect2(rect.position.x + 20.0, rect.position.y - 0.5, 5.0, 8.0)]
	var a := LawnsCloseup.parkway_pieces(rect, drives)
	var b := LawnsCloseup.parkway_pieces(rect, drives)
	var bad: Array = []
	var length := 0.0
	for pc: Array in a:
		var r: Rect2 = pc[0]
		length += maxf(r.size.x, r.size.y)
		if minf(r.size.x, r.size.y) < 1.6 or minf(r.size.x, r.size.y) > 1.8:
			bad.append("width %s" % str(r))
		# Clear of the corners.
		for cx: float in [rect.position.x, rect.end.x]:
			for cz: float in [rect.position.y, rect.end.y]:
				if r.grow(LawnsCloseup.PARKWAY_CORNER - 0.3).has_point(Vector2(cx, cz)):
					bad.append("corner %s" % str(r))
		if r.intersects((drives[0] as Rect2).grow(0.5)):
			bad.append("drive %s" % str(r))
		if not rect.encloses(r):
			bad.append("outside %s" % str(r))
	var perim := 2.0 * (rect.size.x + rect.size.y) - 8.0 * LawnsCloseup.PARKWAY_CORNER
	_check(str(a) == str(b) and bad.is_empty() and length > perim - 9.0 and length < perim + 0.1,
		"lawns closeup: the parkway plan is pure, inside the kerb, clear of the corners and the drive (%.0f of %.0f m) %s" % [length, perim, str(bad.slice(0, 4))])


func _batches(chunk: Node) -> Dictionary:
	var out := {}
	for c in chunk.get_children():
		if c is MultiMeshInstance3D:
			out[String(c.name)] = (c as MultiMeshInstance3D).multimesh.instance_count
	return out


func _full(city: Node3D, block: Vector2i) -> void:
	var was := LawnsCloseup.enabled
	LawnsCloseup.set_enabled(false)
	var off: CityChunk = city._new_chunk(block, CityChunk.Level.FULL)
	off.build()
	var off_props := {}
	for r: Dictionary in off.prop_records:
		off_props[String(r.id)] = true
	var off_batches := _batches(off)
	var off_park := off.get_node_or_null("Parkway")
	off.get_parent().remove_child(off)
	off.free()
	LawnsCloseup.set_enabled(true)
	var on: CityChunk = city._new_chunk(block, CityChunk.Level.FULL)
	on.build()
	LawnsCloseup.set_enabled(was)
	var on_batches := _batches(on)
	var moved: Array = []
	var grass_off := 0
	var grass_on := 0
	var weeds := 0
	for n: String in on_batches:
		if n.contains("grass_"):
			grass_on += int(on_batches[n])
			continue
		if n.contains("lawn_weed"):
			weeds += int(on_batches[n])
			continue
		if int(off_batches.get(n, -1)) != int(on_batches[n]):
			moved.append("%s %d->%d" % [n, int(off_batches.get(n, -1)), int(on_batches[n])])
	for n: String in off_batches:
		if n.contains("grass_"):
			grass_off += int(off_batches[n])
		elif not on_batches.has(n):
			moved.append("%s gone" % n)
	var kept := true
	for r: Dictionary in on.prop_records:
		if not off_props.has(String(r.id)):
			kept = false
	var park: MeshInstance3D = on.get_node_or_null("Parkway")
	_check(off_park == null and park != null and park.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and int(on.get_meta("parkway_pieces", 0)) >= 4,
		"lawns closeup: a FULL suburb chunk lays its parkway as one shadowless mesh (%d pieces), none with the pass off" % int(on.get_meta("parkway_pieces", 0)))
	_check(grass_on > grass_off and weeds > 20 and weeds == int(on.get_meta("lawn_weeds", -1)),
		"lawns closeup: the parkway is planted (%d tufts, %d without) and %d weeds stand in the joints and along the fences" % [grass_on, grass_off, weeds])
	_check(kept and moved.is_empty(), "lawns closeup: with it off the chunk's other props keep their ids and its batches their counts %s" % str(moved.slice(0, 6)))
	# Every tuft on the block's own lawn carries its lawn: the striped flag and an edge distance.
	var data: Dictionary = on._batch.data() if on._batch else {}
	var tufts := 0
	var lawned := 0
	for key: String in data:
		if not key.begins_with("grass_"):
			continue
		for c: Color in data[key].custom:
			tufts += 1
			if c.b != 0.0 or c.g > 0.0:
				lawned += 1
	_check(data.is_empty() or (tufts > 0 and lawned == tufts), "lawns closeup: every tuft carries its lawn's numbers (%d of %d)" % [lawned, tufts])
	on.get_parent().remove_child(on)
	on.free()
