extends RefCounted
## The suburbs' and the beach town's nights (HouseNights, house_glass / house_lamp / house_glow /
## lot_yard / building_lod shaders) for tests/smoke_test.gd. Loaded at run time (not named there),
## so it compiles after the autoloads. Checks: the shader include holds HouseNights' numbers and
## its hash; the rolls give the shares they promise (dark houses, TVs, porches, bedtime); the near
## glass and the far box carry the same house key (through the half floats Compatibility hands
## INSTANCE_CUSTOM over as), and a pool's near variant and far key agree; a FULL house chunk draws
## its fixtures as one shadowless mesh, its light in four shadowless glow batches and registers its
## lit porches for the real lights; with the system off everything else in the chunk is the same
## (batches, prop ids, the house meshes); a LOD chunk and the far city get no fixtures.

var _t: Node

## Where to look for a house block (the suburb bookmark).
const NEAR := Vector2(1911, 4260)
var BLOCK := Vector2i.ZERO


func run(t: Node, city: Node3D) -> void:
	_t = t
	var t0 := Time.get_ticks_msec()
	_check(HouseNights.enabled, "house nights: on (HOUSE_NIGHTS is not 0)")
	_shader_mirror()
	_shares()
	_keys()
	var plan: CityPlan = city.plan
	BLOCK = _house_block(plan)
	_full(city)
	_lod(city)
	print("HOUSE_NIGHTS_CHECKS %d ms" % (Time.get_ticks_msec() - t0))


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


func _shader_mirror() -> void:
	var src := FileAccess.get_file_as_string("res://shaders/house_nights.gdshaderinc")
	var want := {"HN_DARK": float(HouseNights.DARK), "HN_TV": float(HouseNights.TV), "HN_SHARE_LO": HouseNights.SHARE_LO,
		"HN_SHARE_SPAN": HouseNights.SHARE_SPAN, "HN_BED_LO": HouseNights.BED_LO, "HN_BED_SPAN": HouseNights.BED_SPAN,
		"HN_BED_KEEP": HouseNights.BED_KEEP, "HN_POOL": float(HouseNights.POOL)}
	var bad: Array = []
	for k: String in want:
		var re := RegEx.create_from_string("const float %s = ([0-9.]+);" % k)
		var m := re.search(src)
		if m == null or absf(float(m.get_string(1)) - float(want[k])) > 1e-5:
			bad.append(k)
	for s: String in ["0x7feb352du", "0x846ca68bu", "uint(key) * 7919u + salt", "% 4u", "hn_pct(key, 1u)", "hn_pct(key, 3u)",
			"hn_pct(key, 4u)", "hn_pct(key, 9u)", "hn_pct(pool_key, 10u)"]:
		if not src.contains(s):
			bad.append(s)
	# The tones, linear on both sides.
	var re2 := RegEx.create_from_string("return vec3\\(([0-9.]+), ([0-9.]+), ([0-9.]+)\\);")
	var tones := re2.search_all(src)
	for i in mini(tones.size(), 4):
		var c: Color = HouseNights.TONES[i]
		var m: RegExMatch = tones[i]
		if absf(float(m.get_string(1)) - c.r) > 1e-4 or absf(float(m.get_string(2)) - c.g) > 1e-4 or absf(float(m.get_string(3)) - c.b) > 1e-4:
			bad.append("tone %d" % i)
	_check(bad.is_empty() and tones.size() >= 4, "house nights: the shader include holds HouseNights' numbers and hash %s" % str(bad))
	var lod_src := FileAccess.get_file_as_string("res://shaders/building_lod.gdshader")
	var glass_src := FileAccess.get_file_as_string("res://shaders/house_glass.gdshader")
	_check(lod_src.contains("house_nights.gdshaderinc") and glass_src.contains("house_nights.gdshaderinc")
		and glass_src.contains("UV2.x - 1.0"), "house nights: the near glass and the far box read the same include")


func _shares() -> void:
	var dark := 0
	var tv := 0
	var porch := 0
	var nice := 0
	var tones := [0, 0, 0, 0]
	var share_ok := true
	var bed := 0
	for k in 997:
		if HouseNights.dark(k):
			dark += 1
		elif HouseNights.tv(k):
			tv += 1
		if HouseNights.porch_on(k):
			porch += 1
		if HouseNights.nice(k):
			nice += 1
		tones[HouseNights.tone_index(k)] += 1
		var s := HouseNights.share(k, 21.5)
		if not HouseNights.dark(k) and (s < 0.3 or s > 0.75):
			share_ok = false
		if HouseNights.share(k, 1.0) < s - 1e-6:
			bed += 1
	_check(dark > 70 and dark < 150, "house nights: about one house in nine is dark (%d of 997)" % dark)
	_check(tv > 220 and tv < 380, "house nights: a TV on in about a third of the lived-in ones (%d)" % tv)
	_check(porch > 650 and porch < 850, "house nights: most porch lights on (%d)" % porch)
	_check(nice > 180 and nice < 330, "house nights: landscape lighting at the nicer houses (%d)" % nice)
	_check(tones.min() > 180, "house nights: every lamp tone in use %s" % str(tones))
	_check(share_ok and bed > 800, "house nights: a lived-in house lights a third to three quarters of its rooms, fewer by 1:00 (%d)" % bed)
	_check(HouseNights.share(5, 21.0) == HouseNights.share(5, 21.0) and HouseNights.house_number(5) >= 101 and HouseNights.house_number(5) <= 998,
		"house nights: the rolls are pure")


## Half-float rounding (11 significant bits), as Compatibility stores INSTANCE_CUSTOM.
static func _half(v: float) -> float:
	if v == 0.0:
		return 0.0
	var e := floorf(log(absf(v)) / log(2.0))
	var q := pow(2.0, e - 10.0)
	return roundf(v / q) * q


func _keys() -> void:
	var ok := true
	for i in 3000:
		var seed_v := hash([i, "house_nights_check"])
		var c := MidCity.house_custom(seed_v)
		var far := int(_half(c.b) * 997.0 + 0.5)
		if far != HouseNights.key(seed_v):
			ok = false
	_check(ok, "house nights: the far box's key (half float) is the near glass's for every house")
	var pools_ok := true
	for i in 200:
		var r := Rect2(Vector2(float(i) * 13.7 - 900.0, float(i % 17) * 31.3), Vector2(4.5, 9.0))
		var c := r.get_center()
		var far_key := absi(hash([c.x, c.y])) % 997
		if far_key != HouseNights.pool_key(r):
			pools_ok = false
		var v := HouseNights.pool_variant(r)
		if (v > 0.5) != HouseNights.pool_on(far_key):
			pools_ok = false
	_check(pools_ok, "house nights: a pool's near light and its far box's agree")


## A house block of the suburbs or the beach town near NEAR with the most houses.
func _house_block(plan: CityPlan) -> Vector2i:
	var c: Vector2i = plan.block_index_at(NEAR)
	var best := c
	var most := -1
	for bx in range(c.x - 2, c.x + 3):
		for bz in range(c.y - 2, c.y + 3):
			var b: Dictionary = plan.block(bx, bz)
			var d := int(b.district)
			if not (d == CityPlan.District.SUBURBS or d == CityPlan.District.BEACHTOWN) or int(b.kind) != CityPlan.BlockKind.BUILDINGS \
					or b.has("site") or plan.zone_at((b.rect as Rect2).get_center()) != MacroMap.Zone.CITY or plan.marina_block(bx, bz):
				continue
			var n: int = plan.lots(bx, bz).size()
			if n > most:
				most = n
				best = Vector2i(bx, bz)
	return best


func _snapshot(ch: CityChunk) -> Dictionary:
	var batches := {}
	var houses := {}
	for c in ch.get_children():
		var n := String(c.name)
		if c is MultiMeshInstance3D:
			batches[n] = (c as MultiMeshInstance3D).multimesh.instance_count
		elif n.begins_with("House_") and c is MeshInstance3D:
			var m: Mesh = (c as MeshInstance3D).mesh
			var verts := 0
			for s in m.get_surface_count():
				verts += (m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			houses[n] = verts
	var props := {}
	for r: Dictionary in ch.prop_records:
		props[String(r.id)] = true
	return {"batches": batches, "houses": houses, "props": props}


func _full(city: Node3D) -> void:
	var was := HouseNights.enabled
	HouseNights.enabled = false
	var off: CityChunk = city._new_chunk(BLOCK, CityChunk.Level.FULL)
	off.build()
	var a := _snapshot(off)
	off.get_parent().remove_child(off)
	off.free()
	HouseNights.enabled = true
	var spots0 := HouseNightLights.spot_count()
	var on: CityChunk = city._new_chunk(BLOCK, CityChunk.Level.FULL)
	on.build()
	HouseNights.enabled = was
	var b := _snapshot(on)
	var moved: Array = []
	for n: String in a.batches:
		if int((b.batches as Dictionary).get(n, -1)) != int(a.batches[n]):
			moved.append("%s %d->%d" % [n, int(a.batches[n]), int((b.batches as Dictionary).get(n, -1))])
	for n: String in a.houses:
		if n != "House_glass" and int((b.houses as Dictionary).get(n, -1)) != int(a.houses[n]):
			moved.append("%s %d->%d" % [n, int(a.houses[n]), int((b.houses as Dictionary).get(n, -1))])
	var props_kept: bool = (a.props as Dictionary).size() == (b.props as Dictionary).size()
	for id: String in a.props:
		if not (b.props as Dictionary).has(id):
			props_kept = false
	_check(not (a.houses as Dictionary).is_empty(), "house nights: the check block has houses (%s)" % str(BLOCK))
	_check(moved.is_empty() and props_kept, "house nights: with it off the chunk's batches, props and house meshes are the same %s" % str(moved.slice(0, 6)))
	var lamp := on.get_node_or_null("House_h_lamp") as MeshInstance3D
	_check(lamp != null and lamp.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"house nights: the fixtures are one shadowless mesh a chunk")
	var glows := 0
	var shadowless := true
	for k: String in HouseNights.GLOW_KEYS:
		var mm := on.get_node_or_null("Batch_" + k) as MultiMeshInstance3D
		if mm != null:
			glows += 1
			shadowless = shadowless and mm.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if on.get_node_or_null("BatchShadow_" + k) != null:
			shadowless = false
	_check(glows >= 3 and shadowless, "house nights: the light is shadowless glow batches (%d kinds)" % glows)
	_check(HouseNightLights.spot_count() > spots0, "house nights: the chunk registers its lit porches for the real lights (%d)" % (HouseNightLights.spot_count() - spots0))
	# Every pane of the chunk's houses carries a house key.
	var glass := on.get_node_or_null("House_glass") as MeshInstance3D
	var keyed := true
	var keys := {}
	if glass != null:
		for s in glass.mesh.get_surface_count():
			var arr := glass.mesh.surface_get_arrays(s)
			var uv2 = arr[Mesh.ARRAY_TEX_UV2]
			if uv2 == null or (uv2 as PackedVector2Array).is_empty():
				keyed = false
				continue
			for p: Vector2 in (uv2 as PackedVector2Array):
				if p.x < 0.5 or p.x > 997.5:
					keyed = false
				keys[int(p.x)] = true
	_check(glass != null and keyed and keys.size() >= 3, "house nights: every pane carries its house's key (%d houses)" % keys.size())
	on.get_parent().remove_child(on)
	on.free()


func _lod(city: Node3D) -> void:
	var lod: CityChunk = city._new_chunk(BLOCK, CityChunk.Level.LOD)
	lod.build()
	var any := lod.get_node_or_null("House_h_lamp") != null
	for k: String in HouseNights.GLOW_KEYS:
		any = any or lod.get_node_or_null("Batch_" + k) != null
	_check(not any, "house nights: a LOD chunk builds no fixtures or glow (its boxes are lit by the shader)")
	lod.get_parent().remove_child(lod)
	lod.free()
