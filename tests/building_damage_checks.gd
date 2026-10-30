extends RefCounted
## Building damage checks for tests/smoke_test.gd (scripts/world/building_damage.gd). Loaded at
## run time, so it compiles after the autoloads and can name BuildingDamage, Explosion and
## LandmarkDowntown freely.
## Checks: the shader carries the damage list and the include's outline and seed are the script's;
## a building nobody shot has no records; the pane a point is in is worked out as the shader draws
## it (glass in a bay, wall on a pier); a round crazes a pane, a second takes it out (shards' glass
## recorded on the ground), a third does nothing more; rounds in the wall leave scars, capped; the
## list is capped; another building stays clean; a blast against a wall punches a hole (rim built,
## rubble thrown as debris) and blows the panes round it; the damage comes back when the building
## is rebuilt; a sanctuary takes none; a downtown tower's detailed copy takes its glass damage on
## its own materials and the shared ones stay clean.

var _t: Node
var _tree: SceneTree
var _ws: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	_ws = _tree.root.get_node("/root/WorldState")
	_shader_contract()
	var player := _tree.get_first_node_in_group("player") as Node3D
	var b := _pick_building(player)
	_check(b != null, "a building with a storefront to shoot near the player")
	if b == null:
		return
	var mat := _walls_mat(b)
	_check(mat != null and _n(mat) == 0, "an undamaged building has no damage records")
	_check(not _ws.get("building_damage").has(BuildingDamage.key_of(b)), "an undamaged building has no WorldState entry")
	var other := _other_building(b)

	# A storefront bay and the pier beside it, on the part's +Z face.
	var part: Dictionary = _shop_part(b)
	var size: Vector3 = part.size
	var c: Vector3 = part.center
	var pitch: float = part.pitch_x
	var face_z := c.z + size.z * 0.5
	var sf_h: float = float(part.gfh) - float(part.base_y)
	var y_glass: float = float(part.base_y) - b.position.y + sf_h * 0.45
	var x0 := c.x - size.x * 0.5
	# u runs along -x on a +Z face: bay k's centre is at u = (k + 0.5) * pitch.
	var bay_x := x0 + size.x - 1.5 * pitch
	var pier_x := x0 + size.x - 1.0 * pitch
	var glass_pt := Vector3(bay_x, y_glass, face_z)
	var pane := BuildingDamage.pane_at(b, glass_pt, Vector3.BACK)
	_check(pane.has("centre"), "the middle of a shop bay is glass")
	_check(pane.has("centre") and absf((pane.centre as Vector3).x - bay_x) < 0.05, "the pane's centre is the bay's centre")
	_check(BuildingDamage.pane_at(b, Vector3(pier_x, y_glass, face_z), Vector3.BACK).is_empty(), "the pier between two bays is wall")
	_check(BuildingDamage.pane_at(b, glass_pt, Vector3.UP).is_empty(), "a roof is never a pane")

	# Rounds into the glass: crazed, then gone, then nothing more.
	var key := BuildingDamage.key_of(b)
	BuildingDamage.bullet(_hit(b, glass_pt, Vector3.BACK), Vector3.FORWARD)
	var entry: Dictionary = _ws.get("building_damage").get(key, {})
	_check(entry.get("recs", []).size() == 1 and _kind(entry.recs[0]) == BuildingDamage.K_CRACK, "a round crazes the pane")
	_check(_n(mat) == 1, "the facade material carries the record")
	BuildingDamage.bullet(_hit(b, glass_pt + Vector3(0.2, -0.1, 0.0), Vector3.BACK), Vector3.FORWARD)
	_check(entry.recs.size() == 1 and _kind(entry.recs[0]) == BuildingDamage.K_SHATTER, "a second round in the same pane takes it out")
	_check(entry.litter.size() == 1, "the pane's glass is recorded on the ground under it")
	await _ticks(2)
	BuildingDamage.bullet(_hit(b, glass_pt, Vector3.BACK), Vector3.FORWARD)
	_check(entry.recs.size() == 1, "a round through an empty frame adds nothing")
	_check(_tree.root.find_children("GlassShards*", "CPUParticles3D", true, false).size() > 0, "the pane's shards fall")

	# Scars in the wall, capped.
	BuildingDamage.bullet(_hit(b, Vector3(pier_x, y_glass, face_z), Vector3.BACK), Vector3.FORWARD)
	_check(entry.recs.size() == 2 and _kind(entry.recs[1]) == BuildingDamage.K_POCK, "a round in the wall leaves a scar")
	for i in 30:
		BuildingDamage.bullet(_hit(b, Vector3(pier_x, y_glass + 0.3 + i * 0.12, face_z), Vector3.BACK), Vector3.FORWARD)
	var pocks := 0
	for r: Vector4 in entry.recs:
		pocks += 1 if _kind(r) == BuildingDamage.K_POCK else 0
	_check(pocks == BuildingDamage.MAX_POCKS, "scars are capped (%d)" % pocks)
	_check(_kind(entry.recs[0]) == BuildingDamage.K_SHATTER, "the cap drops old scars, not the broken pane")
	_check(other == null or _n(_walls_mat(other)) == 0, "another building stays clean")

	# A blast against the wall.
	var at := b.to_global(Vector3(x0 + size.x * 0.5, float(part.base_y) - b.position.y + 3.0, face_z + 0.8))
	var debris_before := _tree.get_nodes_in_group("debris").size()
	Explosion.blast(b, at, 9.0, 30.0, 0.0)
	var holes := 0
	var blasts := 0
	for r: Vector4 in entry.recs:
		holes += 1 if _kind(r) == BuildingDamage.K_HOLE else 0
		blasts += 1 if _kind(r) == BuildingDamage.K_BLAST else 0
	var solid := b.finish != Building.Finish.GLASS and b.window_style != Building.WindowStyle.CURTAIN
	_check(blasts == 1, "a blast records itself once on the building")
	_check(not solid or holes == 1, "a blast against a solid wall punches a hole")
	_check(not solid or b.get_node_or_null("DamageRim") != null, "the hole's rim is built")
	_check(not solid or _tree.get_nodes_in_group("debris").size() > debris_before, "the hole throws rubble as debris")
	_check(entry.recs.size() <= BuildingDamage.MAX_RECORDS, "the records are capped")
	for i in 60:
		BuildingDamage.bullet(_hit(b, Vector3(x0 + 0.3 + i * 0.02, y_glass, face_z), Vector3.BACK), Vector3.FORWARD)
	_check(entry.recs.size() <= BuildingDamage.MAX_RECORDS, "the records stay capped under fire")
	_check(not solid or _count(entry, BuildingDamage.K_HOLE) == 1, "the cap never drops a hole")

	# The damage comes back when the building is built again (a chunk streaming back in).
	var n_before: int = entry.recs.size()
	b.generate()
	_check(_n(_walls_mat(b)) == 0, "a rebuilt building starts on a clean material")
	BuildingDamage.restore(b)
	_check(_n(_walls_mat(b)) == n_before, "restore() puts every record back")
	_check(not solid or b.get_node_or_null("DamageRim") != null, "restore() rebuilds the hole's rim")

	# A sanctuary takes nothing.
	if other != null:
		other.add_to_group(Sanctuary.BODY_GROUP)
		_check(BuildingDamage.target_of(other, -1).is_empty(), "a sanctuary is never a damage target")
		other.remove_from_group(Sanctuary.BODY_GROUP)
	await _tower()


func _shader_contract() -> void:
	var names := []
	for u: Dictionary in Building.SHADER.get_shader_uniform_list():
		names.append(u.name)
	_check(names.has("damage") and names.has("damage_count"), "building.gdshader carries the damage list")
	var inc := FileAccess.get_file_as_string("res://shaders/building_damage.gdshaderinc")
	_check(inc.contains("r * (0.80 + 0.12 * sin(3.0 * a + s) + 0.07 * sin(7.0 * a + 2.3 * s) + 0.045 * sin(13.0 * a + 4.1 * s))"),
		"the shader's hole outline is BuildingDamage.hole_radius()")
	_check(inc.contains("mod(p.x * 1.37 + p.y * 2.11 + p.z * 0.73, 6.2832)"), "the shader's record seed is BuildingDamage.record_seed()")
	_check(inc.contains("uniform vec4 damage[%d]" % BuildingDamage.MAX_RECORDS), "the shader's list is MAX_RECORDS long")
	_check(is_equal_approx(BuildingDamage.hole_radius(1.0, 0.0, 0.0), 0.80), "hole_radius() at angle 0, seed 0")


func _tower() -> void:
	var lm := {}
	for e: Dictionary in LandmarkDowntown.entries():
		if e.id == "dt_dark_glass":
			lm = e
	if lm.is_empty():
		return
	# Built 3 km up, out of the way of the city's own copy of the tower.
	var holder := Node3D.new()
	holder.position.y = 3000.0
	_tree.root.add_child(holder)
	var statics := StaticBody3D.new()
	statics.collision_layer = 1
	holder.add_child(statics)
	LandmarkDowntown.build(lm, holder, statics, true)
	await _ticks(3)
	var body := holder.get_node_or_null("Tower_" + String(lm.id)) as MeshInstance3D
	_check(body != null and body.is_in_group(BuildingDamage.TOWER_GROUP), "a detailed tower is marked for damage")
	var anchor: Vector2 = lm.anchor
	var y := LandmarkDowntown.BASE_Y + 30.0
	var from := Vector3(anchor.x, y + 3000.0, anchor.y + 200.0)
	var hit := statics.get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(from, from + Vector3(0, 0, -400.0), 1))
	_check(not hit.is_empty() and hit.collider == statics, "a round reaches the tower's hull")
	if body != null and not hit.is_empty() and hit.collider == statics:
		BuildingDamage.bullet(hit, Vector3.FORWARD)
		var own := body.get_surface_override_material(0) as ShaderMaterial
		var shared := body.mesh.surface_get_material(0) as ShaderMaterial
		var first := -1
		for i in body.mesh.get_surface_count():
			if body.get_surface_override_material(i) != null:
				first = i
				break
		_check(first >= 0, "the damaged tower wears its own facade materials")
		if first >= 0:
			own = body.get_surface_override_material(first) as ShaderMaterial
			shared = body.mesh.surface_get_material(first) as ShaderMaterial
			_check(_n(own) == 1, "the tower's own material carries the record")
			var shared_n: Variant = shared.get_shader_parameter("damage_count")
			_check(shared_n == null or int(shared_n) == 0, "the shared tower material stays clean")
	holder.queue_free()
	_ws.get("building_damage").erase("t:" + String(lm.id))


func _pick_building(player: Node3D) -> Building:
	var best: Building = null
	var best_d := INF
	for n: Node in _tree.get_nodes_in_group("building"):
		var b := n as Building
		if b == null or not b.is_inside_tree() or _walls_mat(b) == null or _shop_part(b).is_empty():
			continue
		if absf(b.global_rotation.y) > 0.01:
			continue
		var d := b.global_position.distance_to(player.global_position)
		if d < best_d:
			best_d = d
			best = b
	return best


func _other_building(b: Building) -> Building:
	for n: Node in _tree.get_nodes_in_group("building"):
		if n != b and n is Building and _walls_mat(n as Building) != null:
			return n as Building
	return null


## A ground part with a storefront at least three bays wide, its +Z face clear of other parts.
func _shop_part(b: Building) -> Dictionary:
	for part: Dictionary in b.parts:
		if not part.has("pitch_x") or not bool(part.storefront) or bool(part.get("parking", false)):
			continue
		var size: Vector3 = part.size
		if size.x < float(part.pitch_x) * 3.0:
			continue
		var c: Vector3 = part.center
		var probe := c + Vector3(size.x * 0.5 - 1.5 * float(part.pitch_x), -size.y * 0.5 + 1.5, size.z * 0.5 + 0.4)
		var blocked := false
		for other: Dictionary in b.parts:
			var l := probe - (other.center as Vector3)
			var h: Vector3 = (other.size as Vector3) * 0.5
			if absf(l.x) < h.x and absf(l.y) < h.y and absf(l.z) < h.z:
				blocked = true
		if not blocked:
			return part
	return {}


func _walls_mat(b: Building) -> ShaderMaterial:
	var walls := BuildingDamage.walls_of(b)
	return walls.material_override as ShaderMaterial if walls != null else null


## A ray result as the guns hand it over, for a point and normal in the building's space.
func _hit(b: Building, local: Vector3, normal: Vector3) -> Dictionary:
	return {"collider": b, "position": b.to_global(local), "normal": b.global_basis * normal, "shape": 0}


## A material's record count (an unset uniform reads null: none).
func _n(m: ShaderMaterial) -> int:
	if m == null:
		return -1
	var v: Variant = m.get_shader_parameter("damage_count")
	return 0 if v == null else int(v)


func _kind(r: Vector4) -> int:
	return int(floor(r.w / 100.0 + 0.001))


func _count(entry: Dictionary, kind: int) -> int:
	var n := 0
	for r: Vector4 in entry.recs:
		n += 1 if _kind(r) == kind else 0
	return n


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


func _ticks(n: int) -> void:
	for i in n:
		await _tree.physics_frame
