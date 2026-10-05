extends RefCounted
## The reservoir in the front range (Reservoir, LandmarkReservoir), for tests/smoke_test.gd. Loaded
## at run time, not named there, so it compiles after the autoloads.
##
## The land: a lake of real size held below its rim (the flood never reaches the edge of the box),
## nothing standing through its water, its ground still HILLS, the carve continuous at the edge of
## its box (no cliff where it hands back to the range), the dam keyed into ground over its crest at
## both ends, its footprint at its foundation, the spillway's weir over the water, the trail on its
## bench round the lake. The build: the far copy and the
## detailed one on the same meshes, inside a triangle budget; the detail's collision, lights, fence
## and pines; the terrain material's bathtub ring and the water's mirror table; planting and shells
## kept off the water and the ring.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	var macro: MacroMap = plan.macro
	var res: Reservoir = macro.reservoir if macro else null
	_t._check(res != null, "the reservoir is built")
	if res == null:
		return
	_land(res, macro)
	_dam(res, macro)
	_trail(res, macro)
	_build(res, plan, city)
	# Other seeds: tools/reservoir/probe.tscn SEED=n (a MacroMap.setup() is seconds, too slow here).


func _land(res: Reservoir, macro: MacroMap) -> void:
	_t._check(res.level > Reservoir.MIN_LEVEL and res.level <= Reservoir.DESIGN_LEVEL and is_equal_approx(res.crest, res.level + Reservoir.FREEBOARD),
		"the lake stands at %.1f m, the crest %.1f m over it" % [res.level, Reservoir.FREEBOARD])
	_t._check(res.wet_area() > 40000.0, "the lake covers %.1f ha" % (res.wet_area() / 10000.0))
	var n := res.grid_size()
	var edge := false
	var through := 0
	var past_dam := 0
	var wet := 0
	for j in n.y:
		for i in n.x:
			if res.wet_grid[j * n.x + i] == 0:
				continue
			wet += 1
			edge = edge or i < 2 or j < 2 or i > n.x - 3 or j > n.y - 3
			var p := res.grid_point(i, j)
			if macro.height_at(p) > res.level - 0.05:
				through += 1
			if p.distance_to(res.dam_centre) < Reservoir.DAM_RADIUS:
				past_dam += 1
	_t._check(not edge and past_dam == 0, "the water is held: it never reaches the edge of its box and stays upstream of the dam")
	_t._check(through == 0, "nothing stands through the water (%d of %d wet points over the level)" % [through, wet])
	var c := res.lake_centre()
	_t._check(macro.zone_at(c) == MacroMap.Zone.HILLS and res.wet(c), "the lake's middle is wet and still HILLS ground (a hill chunk builds it)")
	# The carve hands back to the range without a step at the edge of its box.
	var jump := 0.0
	var box := Reservoir.BOX
	for k in 60:
		var t := float(k) / 59.0
		for pair: Array in [[Vector2(box.position.x + 1.0, lerpf(box.position.y, box.end.y, t)), Vector2(box.position.x - 1.0, lerpf(box.position.y, box.end.y, t))],
				[Vector2(lerpf(box.position.x, box.end.x, t), box.position.y + 1.0), Vector2(lerpf(box.position.x, box.end.x, t), box.position.y - 1.0)],
				[Vector2(box.end.x - 1.0, lerpf(box.position.y, box.end.y, t)), Vector2(box.end.x + 1.0, lerpf(box.position.y, box.end.y, t))]]:
			jump = maxf(jump, absf(macro.raw_height_at(pair[0]) - macro.raw_height_at(pair[1])))
	_t._check(jump < 6.0, "no cliff where the carve hands back to the range at its box (largest step over 2 m: %.1f m)" % jump)
	_t._check(res.keep_clear(c, macro.height_at(c)) and not res.keep_clear(c + Vector2(0.0, -900.0), 300.0),
		"keep_clear() is true on the water and false far off it")


func _dam(res: Reservoir, macro: MacroMap) -> void:
	var height := res.crest - res.toe
	_t._check(height >= Reservoir.MIN_DAM_HEIGHT - 0.01 and height <= Reservoir.MAX_DAM_HEIGHT + 0.01 and res.crest_length() > 100.0 and res.crest_length() < 450.0,
		"the dam: %.0f m high, %.0f m along its crest" % [height, res.crest_length()])
	var keyed := true
	for a: float in [res.dam_a0 - 6.0 / Reservoir.DAM_RADIUS, res.dam_a1 + 6.0 / Reservoir.DAM_RADIUS]:
		keyed = keyed and macro.height_at(res.arc_point(a, Reservoir.DAM_RADIUS + 3.0)) > res.crest - 4.0
	_t._check(keyed, "both ends of the dam run into ground over its crest")
	var foot := res.arc_point((res.dam_a0 + res.dam_a1) * 0.5, Reservoir.DAM_RADIUS - res.dam_base * 0.5)
	_t._check(absf(macro.height_at(foot) - (res.toe - 1.5)) < 0.6, "under the dam the ground is its foundation")
	var shelf := res.arc_point((res.dam_a0 + res.dam_a1) * 0.5, Reservoir.DAM_RADIUS - res.dam_base - 12.0)
	_t._check(absf(macro.height_at(shelf) - (res.toe - 1.5)) < 1.5, "a shelf at the toe below the downstream face")
	_t._check(res.spill.size() >= 4 and res.spill_floor[1] > res.level + 0.4 and not res.wet(res.spill[2]) and res.wet(res.spill[0]),
		"the spillway's weir stands over the water: its approach is in the lake, the chute past it dry")


func _trail(res: Reservoir, macro: MacroMap) -> void:
	var total := 0.0
	var on := 0
	var pts := 0
	for line in res.trail:
		total += Reservoir._length(line)
		for k in range(0, line.size(), 4):
			pts += 1
			if absf(macro.height_at(line[k]) - (res.level + Reservoir.TRAIL_RISE)) < 0.6:
				on += 1
	_t._check(total > 600.0 and pts > 0 and float(on) / float(pts) > 0.9,
		"the trail runs %.0f m round the lake on its bench (%d of %d points at it)" % [total, on, pts])


func _build(res: Reservoir, plan: CityPlan, city: Node3D) -> void:
	var lm := {}
	for e: Dictionary in Landmarks.all():
		if e.id == "reservoir":
			lm = e
	_t._check(not lm.is_empty() and res.wet(lm.anchor), "the reservoir is a landmark anchored on its water")
	if lm.is_empty():
		return
	var p := LandmarkReservoir.parts(res)
	var tris: int = int(p.dam_tris) + int(p.trim_tris) + int(p.detail_tris)
	_t._check(int(p.water_tris) > 1000 and int(p.dam_tris) > 2000 and tris < 60000 and int(p.water_tris) < 20000,
		"its meshes: water %d, dam %d, trim %d, trail %d triangles (%.0f ms to build)" % [p.water_tris, p.dam_tris, p.trim_tris, p.detail_tris, p.build_ms])
	var far := Node3D.new()
	city.add_child(far)
	Landmarks.build(lm, far, null, plan, false)
	var water := far.get_node_or_null("ReservoirWater") as MeshInstance3D
	var dam := far.get_node_or_null("ReservoirDam") as MeshInstance3D
	var trim := far.get_node_or_null("ReservoirTrim") as MeshInstance3D
	_t._check(water != null and dam != null and trim != null and water.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		and trim.visibility_range_end > 0.0 and far.get_node_or_null("ReservoirTrail") == null,
		"the far copy: water (no shadow), dam, trim drawn to %.0f m, no trail" % (trim.visibility_range_end if trim else 0.0))
	var near := Node3D.new()
	city.add_child(near)
	var statics := StaticBody3D.new()
	near.add_child(statics)
	Landmarks.build(lm, near, statics, plan, true)
	var lights := 0
	var batches := 0
	for c in near.get_children():
		if c is OmniLight3D and c.is_in_group("lamp_light"):
			lights += 1
		if c is MultiMeshInstance3D:
			batches += 1
	var nwater := near.get_node_or_null("ReservoirWater") as MeshInstance3D
	_t._check(nwater != null and water != null and nwater.mesh == water.mesh and statics.get_child_count() >= 1 and lights >= 8 and batches >= 2,
		"the detailed copy shares the far meshes, adds collision, %d lit lanterns and %d batches (fence, pines, pools)" % [lights, batches])
	far.queue_free()
	near.queue_free()
	var tm := PropFactory.terrain_material() as ShaderMaterial
	_t._check(tm != null and is_equal_approx(float(tm.get_shader_parameter("lake_level")), res.level) and tm.get_shader_parameter("lake_mask") != null,
		"the terrain material paints the bathtub ring at the lake's level")
	var prof := res.ridge_profile()
	var tans: PackedFloat32Array = prof[0]
	var dams: PackedFloat32Array = prof[1]
	var dam_seen := 0
	for d in dams:
		dam_seen += int(d > 0.5)
	_t._check(tans.size() == Reservoir.N_RIDGE and dam_seen >= 2, "the water's mirror knows the ridge round the lake and the dam in it (%d of %d azimuths)" % [dam_seen, tans.size()])
	var marks := res.shell_marks(Rect2(res.lake_centre() - Vector2(150.0, 150.0), Vector2(300.0, 300.0)))
	_t._check(marks.size() > 10, "the shells keep off the shore, the trail, the dam and the spillway (%d marks)" % marks.size())

