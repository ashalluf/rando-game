extends RefCounted
## The rooftop refcam (docs/HANDOFF.md "The skyline from a tower's roof", RcRooftop) for
## tests/smoke_test.gd:
## - LandmarkRoofs dresses the flat-roofed downtown towers and only them: the mechanical box clad
##   as a penthouse a little outside it, plant on the roof inside the outline, never on the
##   helipad's deck, its net or its stair, never in the penthouse; the plan pure; nothing when off.
## - The helipad deck's close-up coat (rooftop.gdshader pad_closeup) and the cloth windsock.
## - The offshore island's soft silhouette: the uniform in the include, pushed by OffshoreIsland,
##   0 with the switch off.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	_t._check(RcRooftop.enabled and LandmarkRoofs.enabled, "rooftop refcam: on by default")
	_roofs()
	_island(city)
	_pad()


func _roofs() -> void:
	var dressed: Array = []
	for id: String in LandmarkDowntown.TOWERS:
		var p := LandmarkRoofs.plan(id)
		if p.pent.is_empty():
			continue
		dressed.append(id)
		_t._check(var_to_str(p) == var_to_str(LandmarkRoofs.plan(id)), "rooftop refcam: %s's roof plan is pure" % id)
		var t := LandmarkDowntown.tower(id)
		var ext: Rect2 = t.extent
		var keep: Array[Rect2] = []
		for pe: Array in p.pent:
			var c: Vector3 = pe[0]
			var s: Vector3 = pe[1]
			keep.append(Rect2(Vector2(c.x, c.z) - Vector2(s.x, s.z) * 0.5, Vector2(s.x, s.z)))
		var row: Dictionary = LandmarkDowntown.TOWERS[id]
		if row.has("helipad"):
			var pc: Vector3 = row.helipad[0]
			var half := float(row.helipad[1]) * 0.5 + Rooftops.PAD_NET
			keep.append(Rect2(pc.x - half, pc.z - half, half * 2.0, half * 2.0))
		var bad := 0
		for pc: Array in p.pieces:
			var at: Vector3 = pc[1]
			var fp: Vector2 = pc[2]
			var r := Rect2(Vector2(at.x, at.z) - fp * 0.5, fp)
			if not ext.encloses(r):
				bad += 1
			for k: Rect2 in keep:
				if k.intersects(r):
					bad += 1
			if at.y > t.top or at.y < LandmarkRoofs.MECH_MIN_Y:
				bad += 1
		_t._check(bad == 0, "rooftop refcam: %s's plant stands on its roof, off the penthouse and the helipad (%d bad)" % [id, bad])
	_t._check(dressed.has("dt_bronze_slab") and dressed.has("dt_black_twins") and dressed.has("dt_granite_slab"),
		"rooftop refcam: the flat-roofed towers are dressed (%s)" % [dressed])
	for id: String in ["dt_sail_tower", "dt_pyramid_crown", "dt_crown_cylinder", "dt_unfinished"]:
		_t._check(LandmarkRoofs.plan(id).pent.is_empty(), "rooftop refcam: %s (a crown, not a flat roof) is left alone" % id)
	# The penthouse stands round the builders' box, a little outside and above it.
	var bronze := LandmarkRoofs.plan("dt_bronze_slab")
	var pe: Array = bronze.pent[0]
	var c: Vector3 = pe[0]
	var s: Vector3 = pe[1]
	_t._check(s.x > 16.0 and s.z > 12.0 and c.y + s.y * 0.5 > 226.5 and absf(c.z - 6.0) < 0.01,
		"rooftop refcam: the bronze slab's mechanical box is clad (%s, %s)" % [c, s])
	var m := LandmarkRoofs.mesh("dt_black_twins")
	_t._check(m != null and m.surface_get_material(0) == Rooftops.material(),
		"rooftop refcam: the dressed roof is one mesh on the rooftop shader")
	# Off: nothing is put on a tower.
	var holder := Node3D.new()
	LandmarkRoofs.enabled = false
	LandmarkRoofs.dress(holder, Vector3.ZERO, "dt_bronze_slab", null)
	LandmarkRoofs.enabled = true
	_t._check(holder.get_child_count() == 0, "rooftop refcam: LANDMARK_ROOFS=0 puts nothing on the roofs")
	LandmarkRoofs.dress(holder, Vector3.ZERO, "dt_bronze_slab", null)
	var node := holder.get_child(0) as MeshInstance3D if holder.get_child_count() > 0 else null
	_t._check(node != null and node.visibility_range_end > 0.0, "rooftop refcam: the roof is drawn near and fades with distance")
	holder.free()


func _island(city: Node3D) -> void:
	var src := FileAccess.get_file_as_string("res://shaders/offshore_island.gdshaderinc")
	_t._check(src.contains("uniform float island_soft = 0.0;") and src.contains("if (island_soft > 0.0)"),
		"rooftop refcam: the island's soft silhouette is behind its own uniform, 0 the old look")
	_t._check(RcRooftop.island_soft() == 1.0, "rooftop refcam: the island is softened by default")
	RcRooftop.enabled = false
	_t._check(RcRooftop.island_soft() == 0.0, "rooftop refcam: RC_ROOFTOP=0 puts the old island back")
	RcRooftop.enabled = true
	var day := city.get_node_or_null("DayNight")
	var island: Node = day.find_child("OffshoreIsland", true, false) if day else null
	if island == null and day:
		for ch in day.get_children():
			if ch is OffshoreIsland:
				island = ch
	var sky_mat: ShaderMaterial = island.get("_sky") if island else null
	_t._check(sky_mat != null and float(sky_mat.get_shader_parameter("island_soft")) == 1.0,
		"rooftop refcam: OffshoreIsland pushes island_soft to the sky")


func _pad() -> void:
	var src := FileAccess.get_file_as_string("res://shaders/rooftop.gdshader")
	_t._check(src.contains("uniform float pad_closeup = 0.0;") and src.contains("kind == K_PAD && pad_closeup > 0.0"),
		"rooftop refcam: the deck's close-up coat is behind its own uniform, 0 the old deck")
	_t._check(float(Rooftops.material().get_shader_parameter("pad_closeup")) == 1.0,
		"rooftop refcam: the rooftop material has the deck's close-up coat on")
	var g := RooftopGeo.new()
	RcRooftop.windsock(g)
	var want := (RcRooftop.SOCK_RINGS + 1) * (RcRooftop.SOCK_SIDES + 1)
	var tail := Vector3.ZERO
	var row := RcRooftop.SOCK_SIDES + 1
	for k in row:
		tail += g.v[g.v.size() - row + k]
	tail /= float(row)
	_t._check(g.v.size() == want and g.idx.size() == RcRooftop.SOCK_RINGS * RcRooftop.SOCK_SIDES * 12,
		"rooftop refcam: the windsock is a cloth of %d rings round %d sides" % [RcRooftop.SOCK_RINGS, RcRooftop.SOCK_SIDES])
	_t._check(absf(tail.y - RcRooftop.SOCK_LEN) < 0.01 and tail.z > RcRooftop.SOCK_DROOP * 0.9,
		"rooftop refcam: the windsock's tail streams out and sags (%s)" % tail)
