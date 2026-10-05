extends RefCounted
## The code-built Los Angeles trees and accents (LaTrees), for tests/smoke_test.gd. Loaded at run
## time, not named there, so it compiles after the autoloads.
##
## Every species and variant builds: a ladder of five levels, each cheaper than the one before,
## the crown's extent kept to the coarsest (a LOD that shrinks the tree pops), the base under its
## triangle budget, a shadow twin registered with PropFactory, the "foliage_ladder" flag that makes
## MultiMeshBatch scale its edges, the species' material on la_tree.gdshader, and the shader
## handling every kind the script writes. Then the city: a downtown block whose kerb rows swap to
## laurel figs builds FULL with a fig batch, and the same block with LaTrees off is the same block
## (every other batch, every prop, every parked car unchanged; each fig planted where a tree was).
## A run of suburban chunks plants cypress pairs by their houses, and the street species are on
## the district tables.

var _t: Node

## Triangles a variant's full-detail level may cost (the palms are ~24k).
const BUDGET := 20000


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	_meshes()
	_shader()
	_downtown(city, plan)
	_suburbs(city, plan)


func _meshes() -> void:
	var bad := ""
	var over := ""
	var shrink := ""
	var flags := true
	for sp in LaTrees.NAMES.size():
		for v in LaTrees.VARIANTS:
			var levels: Array = LaTrees.level_arrays(sp, v)
			var prev := 1 << 30
			var box0 := AABB()
			for l in levels.size():
				var idx: PackedInt32Array = levels[l][Mesh.ARRAY_INDEX]
				var n := idx.size() / 3
				if n <= 0 or n > prev:
					bad += " %s_%d L%d" % [LaTrees.NAMES[sp], v, l]
				prev = n
				var verts: PackedVector3Array = levels[l][Mesh.ARRAY_VERTEX]
				var box := AABB(verts[0], Vector3.ZERO)
				for p in verts:
					box = box.expand(p)
				if l == 0:
					box0 = box
					if n > BUDGET:
						over += " %s_%d %d" % [LaTrees.NAMES[sp], v, n]
				elif box.size.x < box0.size.x * 0.75 or box.size.y < box0.size.y * 0.8 or box.size.z < box0.size.z * 0.75:
					shrink += " %s_%d L%d" % [LaTrees.NAMES[sp], v, l]
			var m := LaTrees.mesh(sp, v)
			var mat := m.surface_get_material(0) as ShaderMaterial
			flags = flags and m.has_meta("foliage_ladder") and PropFactory.shadow_proxy(m) == LaTrees.shadow_mesh(sp, v) \
				and mat != null and mat.shader.resource_path == "res://shaders/la_tree.gdshader"
	_t._check(bad == "", "every LaTrees level is cheaper than the one before it%s" % bad)
	_t._check(over == "", "every LaTrees variant's full detail is under %d triangles%s" % [BUDGET, over])
	_t._check(shrink == "", "no LaTrees level shrinks the crown%s" % shrink)
	_t._check(flags, "every LaTrees mesh is a foliage ladder with a shadow twin, on la_tree.gdshader")
	var edges := LaTrees.level_edges(LaTrees.Species.FIG)
	var rising := true
	for l in range(1, edges.size()):
		rising = rising and float(edges[l]) > float(edges[l - 1])
	_t._check(rising, "the LaTrees ladder's edges rise level by level (%s)" % str(edges))


func _shader() -> void:
	var src := FileAccess.get_file_as_string("res://shaders/la_tree.gdshader")
	# The fragment branches on these thresholds, one past each kind the script writes.
	var ok := src.contains("float sprig(") and src.contains("kind < 18.5") and src.contains("kind < 12.5") \
		and LaTrees.L_SPRIG == 19 and LaTrees.L_TRIFOL == 18 and LaTrees.L_CLUSTER == 12 and LaTrees.B_STEM == 5
	_t._check(ok, "la_tree.gdshader handles every kind LaTrees writes")
	var tables := true
	for d: int in LaTrees.STREET:
		for e: Array in (LaTrees.STREET[d] as Array)[1]:
			tables = tables and int(e[0]) <= LaTrees.Species.CORAL
	_t._check(tables and LaTrees.STREET.size() == CityPlan.District.size(), "every district has its street species, all trees")


## The batches of a built chunk: key -> instance count (shadow twins left out).
static func _batches(chunk: Node) -> Dictionary:
	var out := {}
	for c in chunk.get_children():
		if c is MultiMeshInstance3D and String(c.name).begins_with("Batch_"):
			out[String(c.name).substr(6)] = (c as MultiMeshInstance3D).multimesh.instance_count
	return out


func _downtown(city: Node3D, plan: CityPlan) -> void:
	var centre: Vector2i = plan.block_index_at(plan.macro.downtown_center)
	var found := Vector2i(99999, 99999)
	for r in 8:
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if found.x != 99999 or maxi(absi(dx), absi(dz)) != r:
					continue
				var k := centre + Vector2i(dx, dz)
				var b := plan.block(k.x, k.y)
				if b.kind == CityPlan.BlockKind.BUILDINGS and int(b.district) == CityPlan.District.DOWNTOWN \
						and not b.has("site") and LaTrees.street_species(plan, k.x, k.y) == LaTrees.Species.FIG:
					found = k
	_t._check(found.x != 99999, "a downtown block near the centre lines its kerbs with laurel figs")
	if found.x == 99999:
		return
	var on: CityChunk = city._new_chunk(found, CityChunk.Level.FULL)
	on.build()
	var a := _batches(on)
	var props_on := on.prop_records.size()
	var cars_on: int = (on.get("_cars") as Array).size()
	LaTrees.enabled = false
	var off: CityChunk = city._new_chunk(found, CityChunk.Level.FULL)
	off.build()
	LaTrees.enabled = true
	var b := _batches(off)
	var props_off := off.prop_records.size()
	var cars_off: int = (off.get("_cars") as Array).size()
	var figs := 0
	var trees_on := 0
	var trees_off := 0
	var moved := ""
	for key: String in a:
		if key.begins_with("la_"):
			if key.begins_with("la_fig"):
				figs += int(a[key])
			if key.begins_with("la_") and not (key.contains("agave") or key.contains("bird") or key.contains("yucca") or key.contains("dracaena") or key.contains("cypress")):
				trees_on += int(a[key])
		elif key.begins_with("tree_"):
			trees_on += int(a[key])
		elif not key.begins_with("bush_") and int(b.get(key, -1)) != int(a[key]):
			moved += " %s %d/%d" % [key, int(a[key]), int(b.get(key, -1))]
	for key: String in b:
		if key.begins_with("tree_"):
			trees_off += int(b[key])
		elif not key.begins_with("bush_") and not a.has(key):
			moved += " %s gone" % key
	_t._check(figs > 0, "the fig block plants laurel figs on its kerbs (%d)" % figs)
	_t._check(moved == "" and props_on == props_off and cars_on == cars_off,
		"the fig block with LaTrees off is the same block (props %d/%d, cars %d/%d)%s" % [props_on, props_off, cars_on, cars_off, moved])
	_t._check(trees_on == trees_off, "each LaTrees tree stands where a tree stood (%d with, %d without)" % [trees_on, trees_off])
	# The figs keep their crowns off the building line: narrowed across the street.
	var narrow := true
	for c in on.get_children():
		if c is MultiMeshInstance3D and String(c.name).begins_with("Batch_la_fig"):
			var mm := (c as MultiMeshInstance3D).multimesh
			var xf := mm.get_instance_transform(0)
			var sc := xf.basis.get_scale()
			# (identity under the headless renderer, which keeps no instance data: then nothing to say)
			if sc.is_equal_approx(Vector3.ONE):
				continue
			narrow = narrow and minf(sc.x, sc.z) < maxf(sc.x, sc.z) * 0.8
	_t._check(narrow, "street figs are narrowed across the pavement")
	on.free()
	off.free()


func _suburbs(city: Node3D, plan: CityPlan) -> void:
	# Suburban house blocks round the player's start, until one plants a cypress pair.
	var start: Vector2i = plan.block_index_at(Vector2.ZERO)
	var cypress := 0
	var accents := 0
	var tried := 0
	for r in 30:
		if cypress > 0 and accents > 0:
			break
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r or tried >= 8 or (cypress > 0 and accents > 0):
					continue
				var k := start + Vector2i(dx * 3, dz * 3)
				var b := plan.block(k.x, k.y)
				if b.kind != CityPlan.BlockKind.BUILDINGS or not (int(b.district) in [CityPlan.District.SUBURBS, CityPlan.District.BEACHTOWN]):
					continue
				if plan.macro.zone_at(b.rect.get_center()) != MacroMap.Zone.CITY:
					continue
				tried += 1
				var ch: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
				ch.build()
				var bs := _batches(ch)
				for key: String in bs:
					if key.begins_with("la_cypress"):
						cypress += int(bs[key])
					elif key.begins_with("la_agave") or key.begins_with("la_bird") or key.begins_with("la_yucca") or key.begins_with("la_dracaena"):
						accents += int(bs[key])
				_t._check(int(ch.get_meta("la_cypress", 0)) <= LaTrees.MAX_CYPRESS and int(ch.get_meta("la_accents", 0)) <= LaTrees.MAX_ACCENTS,
					"a suburban chunk keeps to its cypress and accent caps")
				ch.free()
	_t._check(cypress > 0, "suburban houses get cypress pairs (%d in %d chunks)" % [cypress, tried])
	_t._check(accents > 0, "suburban front gardens and yards get agave, yucca, bird of paradise or dracaena (%d)" % accents)
