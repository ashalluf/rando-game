extends RefCounted
## Tower roofs (Rooftops), for tests/smoke_test.gd. Loaded at run time, not named there, so it
## compiles after the autoloads.
##
## Over a spread of planned towers: the plan is pure (the same twice, and what a generating
## building plans is what the far boxes plan); every piece stands on its roof, off the others and
## off the plant it may not cover; a pad never stands over a spire or a tank; turning the kit off
## moves nothing the building rolled (parts, colours, the plant); a generated pool building has
## its one mesh and has lost exactly the units the plan covers; the far boxes carry the pad and
## the pool and drop the covered plant; the landmark pads sit inside their towers' plans.

var _t: Node
const BUILDING := "res://scenes/props/building.tscn"


func run(t: Node, city: Node3D) -> void:
	_t = t
	var scene := load(BUILDING) as PackedScene
	_plans(scene)
	_stable(scene)
	_near_far(scene, city)
	_landmarks()
	var R = load("res://scripts/world/rooftops.gd")
	var src := FileAccess.get_file_as_string("res://shaders/rooftop.gdshader")
	_t._check(src.contains("const int K_WATER = 6;") and src.contains("const int K_PAD = 3;") and R.material() != null,
		"the rooftop shader's kinds are the ones RooftopGeo writes (pad 3, water 6)")


func _make(scene: PackedScene, seed_v: int, lot: float, h: float) -> Node:
	var b = scene.instantiate()
	b.seed = seed_v
	b.lot_size = Vector2(lot, lot)
	b.min_height = h * 0.88
	b.max_height = h
	return b


func _plans(scene: PackedScene) -> void:
	var R = load("res://scripts/world/rooftops.gd")
	var counts := {}
	var bad := ""
	var impure := 0
	for i in 160:
		var b = _make(scene, 5003 + i * 7919, 36.0 + float(i % 4) * 6.0, lerpf(30.0, 210.0, float(i) / 159.0))
		b.plan_only()
		b.roof_plan()
		var p: Dictionary = R.plan(b)
		var p2: Dictionary = R.plan(b)
		if str(p) != str(p2):
			impure += 1
		if p.is_empty():
			b.free()
			continue
		var size: Vector3 = p.size
		var c: Vector3 = p.c
		var rects: Array[Rect2] = []
		for f: Dictionary in p.feats:
			counts[f.kind] = int(counts.get(f.kind, 0)) + 1
			var r := Rect2(f.at - f.size * 0.5, f.size)
			if r.position.x < -size.x * 0.5 - 0.01 or r.end.x > size.x * 0.5 + 0.01 or r.position.y < -size.z * 0.5 - 0.01 or r.end.y > size.z * 0.5 + 0.01:
				bad += " %d:%s off its roof" % [b.seed, f.kind]
			for o in rects:
				if r.intersects(o):
					bad += " %d:%s overlaps" % [b.seed, f.kind]
			rects.append(r)
			for prop: Array in b.roof_props:
				if int(prop[3]) != int(p.part):
					continue
				var fp: Vector2 = b._prop_footprint(prop[0])
				var pr := Rect2(Vector2(prop[1].x - c.x, prop[1].z - c.z) - fp * 0.5, fp)
				var never: bool = (f.kind == "helipad" and R.TALL_PLANT.has(prop[0])) \
					or (f.kind != "helipad" and not R.HIDEABLE.has(prop[0]))
				if never and pr.intersects(r):
					bad += " %d:%s on a %s" % [b.seed, f.kind, prop[0]]
		b.free()
	_t._check(impure == 0, "the rooftop plan is pure (%d of 160 planned differently twice)" % impure)
	_t._check(bad == "", "every rooftop piece stands on its roof, off the others and off the plant it may not cover%s" % bad.left(300))
	for kind in ["helipad", "pool", "garden", "penthouse", "mast", "bmu"]:
		_t._check(int(counts.get(kind, 0)) > 0, "160 planned towers carry a %s (%d)" % [kind, int(counts.get(kind, 0))])


## Turning the rooftop pieces off moves nothing the building rolls.
func _stable(scene: PackedScene) -> void:
	var R = load("res://scripts/world/rooftops.gd")
	var moved := 0
	var checked := 0
	for i in 40:
		var s := 9001 + i * 104729
		var rec := []
		for on in [false, true]:
			R.enabled = on
			var b = _make(scene, s, 40.0, lerpf(40.0, 200.0, float(i) / 39.0))
			var style: Dictionary = b.plan_only()
			var props := []
			for prop: Array in b.roof_plan():
				props.append([prop[0], prop[1]])
			rec.append(str([b.parts, b.facade_color, b.roof_style, style.tint, props]))
			b.free()
		R.enabled = true
		checked += 1
		if rec[0] != rec[1]:
			moved += 1
	_t._check(moved == 0, "the rooftop pieces move none of a building's rolls (%d of %d differ with them on)" % [moved, checked])


## A generating building plans what its far boxes plan, builds one mesh, and loses exactly the
## units its pieces cover; its far boxes carry the pieces and drop the covered plant.
func _near_far(scene: PackedScene, city: Node3D) -> void:
	var R = load("res://scripts/world/rooftops.gd")
	var FB = load("res://scripts/world/far_building.gd")
	var found := {}
	for i in 600:
		if found.has("pool") and found.has("helipad"):
			break
		var b = _make(scene, 777 + i * 7919, 42.0, lerpf(60.0, 160.0, float(i % 50) / 49.0))
		b.plan_only()
		b.roof_plan()
		var p: Dictionary = R.plan(b)
		for f: Dictionary in ([] if p.is_empty() else p.feats):
			if (f.kind == "pool" or f.kind == "helipad") and not found.has(f.kind) and not R.hidden(b, p).is_empty():
				found[f.kind] = b.seed
		b.free()
	_t._check(found.has("pool") and found.has("helipad"), "there are pool and pad towers whose pieces cover plant (%s)" % [found])
	for kind: String in found:
		var seed_v: int = found[kind]
		var h := 0.0
		for i in 600:
			if 777 + i * 7919 == seed_v:
				h = lerpf(60.0, 160.0, float(i % 50) / 49.0)
		# The far boxes.
		var far = _make(scene, seed_v, 42.0, h)
		var style: Dictionary = far.plan_only()
		var boxes: Array = FB.boxes(far, style, 0.0)
		var p: Dictionary = R.plan(far)
		var covered: Dictionary = R.hidden(far, p)
		var ac_total := 0
		var ac_hidden := 0
		for pi in far.roof_props.size():
			if far.roof_props[pi][0] == "ac":
				ac_total += 1
				if covered.has(pi):
					ac_hidden += 1
		var want: int = FB.Plant.HELIPAD if kind == "helipad" else FB.Plant.POOL
		var has_piece := false
		var plant_boxes := 0
		for bx: Array in boxes:
			var cu: Color = bx[2]
			if is_equal_approx(cu.a, FB.PLANT_FLAG):
				plant_boxes += 1
				if roundi(cu.r) == want:
					has_piece = true
		_t._check(has_piece, "a %s tower's far boxes carry the %s" % [kind, kind])
		far.free()
		# The near building.
		var b = _make(scene, seed_v, 42.0, h)
		city.add_child(b)
		var near_plan: Dictionary = b.get_meta("rooftops", {})
		_t._check(str(near_plan) == str(p), "the %s tower's near plan is its far plan" % kind)
		var roof := b.get_node_or_null("Rooftop") as MeshInstance3D
		_t._check(roof != null and roof.mesh != null and roof.mesh.get_surface_count() >= 1 and roof.material_override == null,
			"the %s tower builds its pieces as one mesh (%s)" % [kind, roof.mesh.get_surface_count() if roof and roof.mesh else 0])
		if kind == "pool":
			_t._check(b.roof_unit_spots.size() == ac_total - ac_hidden,
				"the pool tower lost exactly the units its deck covers (%d of %d kept, %d covered)" % [b.roof_unit_spots.size(), ac_total, ac_hidden])
		if kind == "helipad":
			var shapes := 0
			for ch in b.get_children():
				if ch is CollisionShape3D and (ch as CollisionShape3D).shape is BoxShape3D:
					var bs := (ch as CollisionShape3D).shape as BoxShape3D
					if bs.size.y < 0.31 and bs.size.x > 10.0:
						shapes += 1
			_t._check(shapes == 1, "the pad tower's deck is solid (%d deck shapes)" % shapes)
		b.free()


func _landmarks() -> void:
	var LD = load("res://scripts/world/landmark_downtown.gd")
	var R = load("res://scripts/world/rooftops.gd")
	var bad := ""
	var n := 0
	for id: String in LD.TOWERS:
		var row: Dictionary = LD.TOWERS[id]
		if not row.has("helipad"):
			continue
		n += 1
		var pad: Array = row.helipad
		var local: Vector3 = pad[0]
		var half: float = float(pad[1]) * 0.5 + R.PAD_NET
		var ext: Rect2 = LD.tower(id).extent
		var r := Rect2(Vector2(local.x, local.z) - Vector2(half, half), Vector2(half, half) * 2.0)
		if not ext.encloses(r):
			bad += " " + id
		if local.y > float(LD.tower(id).top) + 0.5:
			bad += " %s(high)" % id
	_t._check(n >= 3 and bad == "", "the flat-roofed downtown towers carry pads inside their plans (%d%s)" % [n, bad])
