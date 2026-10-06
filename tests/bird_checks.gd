extends RefCounted
## The city's birds (Birds, BirdMesh, bird.gdshader) for tests/smoke_test.gd. Loaded at run time
## (not named there), so it compiles after the autoloads and can name Birds freely. Checks: every
## species' three meshes build inside their triangle budgets with both poses on the vertices, the
## atlas layout and spine landmarks match the painter, the textures and sounds load; the survey
## plans pigeons on a plaza and gulls on the beach, the same spots every time; a staged flock
## walks, flushes when the player comes close, wheels and lands again; an alarm startles it; a
## shot kills exactly the bird on the line (and no star); a blast kills what is close; birds on a
## wire sit on the wire StreetDetail draws; the draw counts what is alive.

var _t: Node
var _tree: SceneTree
var _city: Node3D

const BUDGET := [2600, 620, 150]


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	_city = city
	_meshes()
	_layout()
	_sounds()
	var birds: Node = city.get_node_or_null("Birds")
	_t._check(birds != null and birds.get("enabled") == true, "birds: the Birds node is in the city and on")
	if birds == null:
		return
	await _tree.process_frame
	_survey(birds)
	await _flock(birds)
	await _shots(birds)
	_wire(birds)


func _meshes() -> void:
	for sp in ["pigeon", "gull", "crow", "sparrow"]:
		for lod in 3:
			var m: ArrayMesh = BirdMesh.mesh(sp, lod)
			var tris := m.surface_get_array_index_len(0) / 3
			var fmt := m.surface_get_format(0)
			var two_poses := (fmt & Mesh.ARRAY_FORMAT_CUSTOM0) != 0 and (fmt & Mesh.ARRAY_FORMAT_CUSTOM1) != 0
			_t._check(tris > 40 and tris <= BUDGET[lod] and two_poses, "birds: %s LOD %d builds with both poses, %d triangles (budget %d)" % [sp, lod, tris, BUDGET[lod]])
		var mat := BirdMesh.material(sp)
		var ok := true
		for k in ["albedo_tex", "normal_tex", "mask_tex"]:
			ok = ok and mat.get_shader_parameter(k) is Texture2D
		_t._check(ok, "birds: %s's plumage atlas, normal map and mask load" % sp)
	# The folded wing hugs the body: no ground-pose vertex further out than the body's widest
	# point plus two centimetres (the wing used to stand out like epaulettes).
	var arr := BirdMesh.mesh("pigeon", 0).surface_get_arrays(0)
	var c0: PackedFloat32Array = arr[Mesh.ARRAY_CUSTOM0]
	var widest := 0.0
	for i in range(0, c0.size(), 4):
		if c0[i + 3] > 0.5 and c0[i + 3] < 1.5:
			widest = maxf(widest, absf(c0[i]))
	_t._check(widest > 0.0 and widest < 0.052 + 0.02, "birds: the pigeon's folded wings lie on its flanks (%.3f m out)" % widest)
	# The near body's normals are welded: every body vertex at one point (the loft's seam, the
	# beak tip) has one normal, so the loft shades smooth rather than in facets.
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var seen := {}
	var split := 0
	for i in verts.size():
		if c0[i * 4 + 3] > 0.5:
			continue
		var key := Vector3i(roundi(verts[i].x * 1e5), roundi(verts[i].y * 1e5), roundi(verts[i].z * 1e5))
		if seen.has(key) and (seen[key] as Vector3).dot(norms[i]) < 0.999:
			split += 1
		seen[key] = norms[i]
	_t._check(split == 0, "birds: the near pigeon's body normals are welded (%d split)" % split)
	# An underwing of its own (the wing and tail cards' back faces), not the top seen through.
	for sp in ["pigeon", "gull", "sparrow"]:
		var mat := BirdMesh.material(sp)
		_t._check(float(mat.get_shader_parameter("under_mix")) > 0.5, "birds: the %s has its own underwing" % sp)
	var pu: Vector3 = BirdMesh.material("pigeon").get_shader_parameter("under_cov")
	_t._check(pu.length() < 0.5, "birds: a pigeon's underwing coverts are grey, not white (%s)" % pu)


## The atlas regions and spine landmarks are a contract with the painter.
func _layout() -> void:
	var f := FileAccess.open("res://tools/birds/make_bird_textures.py", FileAccess.READ)
	if f == null:
		_t._check(true, "birds: the texture painter is not shipped (export), layout check skipped")
		return
	var src := f.get_as_text()
	var ok := true
	for k: String in BirdMesh.SLOTS:
		var r: Rect2 = BirdMesh.SLOTS[k]
		var want := "\"%s\": (%d, %d, %d, %d)" % [k, r.position.x, r.position.y, r.size.x, r.size.y]
		ok = ok and src.contains(want)
	for pair in [["S_NECK", BirdMesh.S_NECK], ["S_HEAD", BirdMesh.S_HEAD], ["S_EYE", BirdMesh.S_EYE], ["S_BEAK", BirdMesh.S_BEAK]]:
		ok = ok and src.contains("%s = %s" % [pair[0], str(pair[1])])
	var cs := BirdMesh.COV_SHEET_RECT
	ok = ok and src.contains("COV_SHEET = (%d, %d, %d, %d)" % [cs.position.x, cs.position.y, cs.size.x, cs.size.y])
	_t._check(ok, "birds: BirdMesh's atlas slots and spine landmarks match tools/birds/make_bird_textures.py")


func _sounds() -> void:
	var sfx: Node = _tree.root.get_node("/root/Sfx")
	var missing: Array = []
	for n in ["pigeon_coo", "wings", "crow", "sparrow", "gull_close"]:
		if not sfx.call("has", n):
			missing.append(n)
	_t._check(missing.is_empty(), "birds: coos, wing claps, caws, chirps and gull calls load (%s)" % ",".join(missing))


func _survey(birds: Node) -> void:
	var plan: CityPlan = _city.get("plan")
	# A plaza in the city plans pigeons, and plans the same flocks twice.
	var plaza := Vector2.INF
	for ix in range(-20, 21):
		for iz in range(-20, 21):
			var b := plan.block(ix, iz)
			var town: bool = b.district == CityPlan.District.DOWNTOWN or b.district == CityPlan.District.MIDTOWN
			if town and b.kind == CityPlan.BlockKind.PLAZA and plan.macro.zone_at((b.rect as Rect2).get_center()) == MacroMap.Zone.CITY and not b.has("site"):
				plaza = (b.rect as Rect2).get_center()
				break
		if plaza != Vector2.INF:
			break
	if plaza == Vector2.INF:
		_t._check(true, "birds: no plaza near the origin on this seed (skipped)")
	else:
		var a: Array = birds.call("_spots_near", plaza)
		var b2: Array = birds.call("_spots_near", plaza)
		var pigeons := 0
		for s: Dictionary in a:
			if s.species == "pigeon" and (s.at as Vector2).distance_to(plaza) < 200.0:
				pigeons += 1
		_t._check(pigeons > 0 and a.size() == b2.size(), "birds: a plaza plans pigeon flocks (%d spots, the same twice)" % pigeons)
	# The beach plans gulls.
	var beach := Vector2.INF
	for z in [1250.0, 1800.0, 600.0, 2400.0]:
		for x in range(-2000, 0, 8):
			if plan.macro.zone_at(Vector2(x, z)) == MacroMap.Zone.BEACH:
				beach = Vector2(x, z)
				break
		if beach != Vector2.INF:
			break
	var gulls := 0
	if beach != Vector2.INF:
		for s: Dictionary in birds.call("_spots_near", beach):
			if s.species == "gull":
				gulls += 1
	_t._check(gulls > 0, "birds: the beach at %s plans gull flocks (%d)" % [str(beach), gulls])


func _ground_point(near: Vector3) -> Vector3:
	var space := _city.get_world_3d().direct_space_state
	for k in 24:
		var p := near + Vector3(cos(k * 0.9) * (3.0 + k), 0.0, sin(k * 0.9) * (3.0 + k))
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 20.0, p - Vector3.UP * 20.0, 1))
		if not hit.is_empty() and (hit.normal as Vector3).y > 0.95:
			return hit.position
	return Vector3.INF


func _flock(birds: Node) -> void:
	var player := _tree.get_first_node_in_group("player") as Node3D
	var p := _ground_point(player.global_position + Vector3(9.0, 0.0, 9.0))
	if p == Vector3.INF:
		_t._check(false, "birds: found open ground near the player to stage a flock on")
		return
	var before: int = birds.call("bird_count")
	var id: int = birds.call("stage", "pigeon", p, 20, 3.0)
	_t._check(id != 0 and int(birds.call("bird_count")) == before + 20, "birds: a staged flock of 20 pigeons stands on the ground")
	if id == 0:
		return
	var info := _info(birds, id)
	_t._check(absf((info.home as Vector3).y - p.y) < 0.3, "birds: the flock stands on the ground it was put on (%.2f m off)" % absf((info.home as Vector3).y - p.y))
	birds.call("advance", 3.0)
	info = _info(birds, id)
	_t._check(int(info.state) == Birds.FlockState.GROUND, "birds: left alone for 3 s the flock stays down, walking and pecking")
	var flushes := Birds.flushes
	birds.call("flush_flock", id, p + Vector3(1.5, 0.0, 0.0))
	info = _info(birds, id)
	_t._check(int(info.state) == Birds.FlockState.AIR and Birds.flushes == flushes + 1, "birds: the player walking in flushes the flock")
	birds.call("advance", 1.5)
	info = _info(birds, id)
	_t._check((info.center as Vector3).y > p.y + 1.5, "birds: 1.5 s later the flock is up in the air (%.1f m)" % ((info.center as Vector3).y - p.y))
	birds.call("advance", 40.0)
	info = _info(birds, id)
	_t._check(int(info.state) != Birds.FlockState.AIR and int(info.count) == 20, "birds: within 40 s the flock has come down again somewhere, all 20 (state %d)" % int(info.state))
	# An alarm (a gunshot, Pedestrian.alarm) startles a grounded flock in reach.
	var id2: int = birds.call("stage", "pigeon", p, 10, 2.0)
	Birds.startle(p + Vector3(20.0, 0.0, 0.0), 45.0)
	_t._check(int(_info(birds, id2).state) == Birds.FlockState.AIR, "birds: a gunshot 20 m away startles a flock up")
	await _tree.process_frame


func _shots(birds: Node) -> void:
	var player := _tree.get_first_node_in_group("player") as Node3D
	var p := _ground_point(player.global_position + Vector3(-11.0, 0.0, 6.0))
	if p == Vector3.INF:
		return
	var id: int = birds.call("stage", "gull", p, 6, 3.0)
	if id == 0:
		_t._check(false, "birds: staged gulls for the shot")
		return
	var live: Birds = birds as Birds
	var f = live._flocks[id]
	var target = f.birds[0]
	var at := live.to_global(target.pos) + Vector3.UP * 0.22
	var police: Node = _city.get_node_or_null("Police")
	var stars_before: int = int(police.get("stars")) if police else 0
	var kills := Birds.kills
	var hit := Birds.hit_ray(at + Vector3(-6.0, 1.0, 0.0), at + (at - (at + Vector3(-6.0, 1.0, 0.0))) * 1.0)
	_t._check(hit and Birds.kills == kills + 1 and f.birds.size() == 5, "birds: a round through a gull kills that one gull and no other")
	var stars_after: int = int(police.get("stars")) if police else 0
	_t._check(stars_after == stars_before, "birds: the police do not count a dead bird")
	_t._check(int(_info(birds, id).state) == Birds.FlockState.AIR, "birds: the rest of the flock takes off at the shot")
	var miss := Birds.hit_ray(at + Vector3(0, 30, 0), at + Vector3(5, 30, 0))
	_t._check(not miss, "birds: a shot over their heads hits nothing")
	birds.call("advance", 4.0)
	var lying := false
	for b in live._dead:
		if b.species == "gull" and b.vel.length() < 0.01:
			lying = true
	_t._check(lying, "birds: the shot gull falls and lies on the ground")
	# A blast kills what is close.
	var id3: int = birds.call("stage", "pigeon", p, 12, 1.5)
	if id3 != 0:
		kills = Birds.kills
		live._blasted(live.to_local(p))
		_t._check(Birds.kills - kills >= 8, "birds: a blast among a flock kills the birds within 7 m (%d)" % (Birds.kills - kills))
	# The draw counts what is alive and near.
	live._draw()
	var drawn := 0
	for key: String in live._mm:
		var mmi: MultiMeshInstance3D = live._mm[key]
		if mmi.visible:
			drawn += mmi.multimesh.visible_instance_count
	_t._check(drawn > 0 and drawn <= live.bird_count() + live._dead.size(), "birds: the MultiMeshes draw the living and the dead near the camera (%d)" % drawn)


func _wire(_birds: Node) -> void:
	var a := Vector3(0.0, 8.6, 0.0)
	var b := Vector3(30.0, 8.6, 0.0)
	var ends := Birds.wire_point(a, b, 1.1, 0.0).distance_to(a) < 1e-4 and Birds.wire_point(a, b, 1.1, 1.0).distance_to(b) < 1e-4
	var mid := Birds.wire_point(a, b, 1.1, 0.5)
	# StreetDetail draws the parabola in CABLE_SEGMENTS straight pieces: mid-span is on the piece
	# that holds s = 0.5.
	var n := StreetDetail.CABLE_SEGMENTS
	var s0 := float(floori(0.5 * n)) / float(n)
	var s1 := s0 + 1.0 / float(n)
	var want := lerpf(8.6 - 1.1 * 4.0 * s0 * (1.0 - s0), 8.6 - 1.1 * 4.0 * s1 * (1.0 - s1), (0.5 - s0) / (s1 - s0))
	_t._check(ends and absf(mid.y - want) < 1e-3, "birds: a bird on a span sits on the sagging wire StreetDetail draws (mid %.2f m)" % mid.y)


func _info(birds: Node, id: int) -> Dictionary:
	for d: Dictionary in birds.call("flocks_info"):
		if int(d.id) == id:
			return d
	return {"state": -1, "home": Vector3.ZERO, "center": Vector3.ZERO, "count": 0}
