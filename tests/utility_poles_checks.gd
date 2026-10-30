extends RefCounted
## The overhead utilities (UtilityPoles), for tests/smoke_test.gd. Loaded at run time, not named
## there, so it compiles after the autoloads.
##
## Checks: every hardware mesh builds on the one hardware shader inside its triangle budget, the
## big ones with a lighter shadow twin; the head's middle pin carries its conductor where
## StreetDetail's pin line is; the runs are pure and on StreetDetail's world grid; a suburban FULL
## chunk built from the plan hangs poles with heads, one ribbon mesh of wires (shadowless, on the
## wire shader) and no box cables; every middle primary of its block's in-block spans is exactly
## the span Birds lands crows on (Birds._wire_spans); nearly every house gets a drop, always from a
## pole in front of it; the same block builds the same line; built with UTILITY_POLES off the rest
## of the block is the same block (nothing else rolled); a LOD chunk hangs nothing.

var _t: Node

const BUDGET := {"shaft": 420, "head": 1000, "xfmr": 1000, "light": 400, "riser": 200, "splice": 220,
	"coil": 220, "guard": 80, "anchor": 120, "meter": 160, "mast": 40, "whead": 160}
## Batch keys that are the line's own (left out when the block is compared with the line off).
## "wear" is StreetWear's batch: its flyers on the poles are keyed by the pole's foot, which moved.
const OWN := ["wear", "upole", "up_head", "up_xfmr", "up_light", "up_lens", "up_riser", "up_splice", "up_coil", "up_guard",
	"up_anchor", "up_meter", "up_mast", "up_whead", "crossarm", "insulator", "transformer", "cable", "lamp_pool"]


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	_meshes()
	_runs(plan)
	var keys := _blocks(plan, CityPlan.District.SUBURBS, 12)
	_t._check(keys.size() >= 2, "utility poles: the suburbs have blocks that hang a line (%d)" % keys.size())
	if keys.is_empty():
		return
	var birds: Node = city.get_node_or_null("Birds")
	var built := 0
	var houses := 0
	var drops := 0
	var fronts_ok := true
	var mid_ok := true
	var bird_spans := 0
	var nodes_ok := true
	var same := true
	var off_same := true
	var poles := 0
	var heads_ok := true
	for k: Vector2i in keys:
		if built >= 2:
			break
		var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
		chunk.build()
		var sm: Dictionary = chunk.get_meta("utility_poles", {})
		if int(sm.get("poles", 0)) == 0:
			_free(chunk)
			continue
		built += 1
		poles += int(sm.poles)
		houses += int(sm.houses)
		drops += int(sm.house_drops)
		for f: float in (sm.drop_fronts as Array):
			fronts_ok = fronts_ok and f >= UtilityPoles.HOUSE_DROP_FRONT - 0.01
		# The batch is consumed by the finish: read the nodes it built.
		var shafts := chunk.get_node_or_null("Batch_upole") as MultiMeshInstance3D
		var heads := chunk.get_node_or_null("Batch_up_head") as MultiMeshInstance3D
		heads_ok = heads_ok and shafts != null and heads != null and shafts.multimesh.instance_count == heads.multimesh.instance_count \
			and shafts.multimesh.instance_count == int(sm.poles) and shafts.multimesh.mesh == UtilityPoles.shaft_mesh() \
			and chunk.get_node_or_null("Batch_cable") == null and chunk.get_node_or_null("Batch_crossarm") == null
		var wires := chunk.get_node_or_null("UtilityWires") as MeshInstance3D
		nodes_ok = nodes_ok and wires != null and wires.mesh.get_surface_count() == 1 and wires.material_override == UtilityPoles.wire_material() \
			and wires.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and int(sm.wires) > 0
		# Birds' spans: every one has a middle primary on exactly its polyline.
		if birds != null:
			var mids: Array = sm.mid
			for sp: Array in birds.call("_wire_spans", k.x, k.y):
				bird_spans += 1
				var found := false
				for m: Array in mids:
					if (m[0] as Vector3).distance_to(sp[0]) < 0.01 and (m[1] as Vector3).distance_to(sp[1]) < 0.01 and absf(float(m[2]) - float(sp[2])) < 1e-4:
						found = true
						break
				if not found:
					mid_ok = false
					print("  no middle primary on the birds' span ", sp)
		var sig := _signature(chunk)
		var sm_copy := sm.duplicate(true)
		_free(chunk)
		var again: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
		again.build()
		var sm2: Dictionary = again.get_meta("utility_poles", {})
		for key in ["poles", "xfmrs", "lights", "risers", "guys", "splices", "coils", "wall_drops", "houses", "house_drops", "wires"]:
			same = same and int(sm2.get(key, -1)) == int(sm_copy[key])
		_free(again)
		UtilityPoles.enabled = false
		var bare: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
		bare.build()
		UtilityPoles.enabled = true
		var bare_sig := _signature(bare)
		if bare_sig != sig:
			for x in sig:
				if not x in bare_sig:
					print("  poles on only: ", x)
			for x in bare_sig:
				if not x in sig:
					print("  poles off only: ", x)
		off_same = off_same and bare_sig == sig and bare.get_node_or_null("UtilityWires") == null
		_free(bare)
	_t._check(built >= 1 and poles >= 4 and heads_ok, "utility poles: suburban blocks hang poles with heads, no box cables or primitive arms (%d poles on %d blocks)" % [poles, built])
	_t._check(nodes_ok, "utility poles: a chunk's wires are one ribbon mesh on the wire shader, casting no shadow")
	_t._check(bird_spans > 0 and mid_ok, "utility poles: every span the birds land on is a middle primary's exact polyline (%d spans)" % bird_spans)
	_t._check(houses > 0 and float(drops) >= 0.8 * float(houses) and fronts_ok,
		"utility poles: nearly every house gets a service drop, always from a pole in front of it (%d of %d)" % [drops, houses])
	_t._check(same, "utility poles: the same block hangs the same line")
	_t._check(off_same, "utility poles: the line rolls nothing from the block (built with it off, the rest is the same block)")
	var lod: CityChunk = city._new_chunk(keys[0], CityChunk.Level.LOD)
	lod.build()
	_t._check(lod.get_node_or_null("UtilityWires") == null and lod.get_node_or_null("Batch_upole") == null and lod.get_node_or_null("Batch_up_head") == null, "utility poles: a LOD chunk hangs no line")
	_free(lod)


func _meshes() -> void:
	var counts := UtilityPoles.triangle_counts()
	var over: Array = []
	for k: String in BUDGET:
		if not counts.has(k) or int(counts[k]) <= 0 or int(counts[k]) > int(BUDGET[k]):
			over.append("%s %s" % [k, counts.get(k, "missing")])
	_t._check(over.is_empty(), "utility poles: every hardware mesh builds inside its triangle budget %s" % [over])
	var mat_ok := true
	for m: Mesh in [UtilityPoles.shaft_mesh(), UtilityPoles.head_mesh(), UtilityPoles.transformer_mesh(), UtilityPoles.light_mesh(), UtilityPoles.meter_mesh()]:
		mat_ok = mat_ok and m.get_surface_count() == 1 and m.surface_get_material(0) == UtilityPoles.material()
	_t._check(mat_ok, "utility poles: the hardware is one surface on the one hardware shader")
	var twins := true
	for m: Mesh in [UtilityPoles.shaft_mesh(), UtilityPoles.head_mesh(), UtilityPoles.transformer_mesh(), UtilityPoles.light_mesh()]:
		twins = twins and PropFactory.shadow_proxy(m) != null
	_t._check(twins, "utility poles: the pole, head, transformer and light cast from lighter twins")
	_t._check(PropFactory.upole() == UtilityPoles.shaft_mesh(), "utility poles: PropFactory.upole() is the new shaft (alleys' poles get it too)")
	# The ribbon: two vertices per point, two triangles per piece.
	var rm := UtilityPoles.ribbon_mesh([[PackedVector3Array([Vector3.ZERO, Vector3(5, -0.2, 0), Vector3(10, 0, 0)]), 0.01, 0]])
	_t._check(rm != null and rm.get_surface_count() == 1 and rm.custom_aabb.size.x >= 10.0, "utility poles: a wire becomes a ribbon of two vertices a point")


func _runs(plan: CityPlan) -> void:
	var keys := _blocks(plan, CityPlan.District.SUBURBS, 6)
	var pure := true
	var grid := true
	for k: Vector2i in keys:
		var a := UtilityPoles.block_runs(plan, k.x, k.y)
		UtilityPoles._runs_cache.clear()
		var b := UtilityPoles.block_runs(plan, k.x, k.y)
		pure = pure and a.size() == b.size()
		for i in mini(a.size(), b.size()):
			pure = pure and (a[i].poles as Array).size() == (b[i].poles as Array).size()
		for r: Dictionary in a:
			for pole: Dictionary in r.poles:
				var p: Vector3 = pole.pin
				var u: float = p.z if bool(r.along_z) else p.x
				var slot := (u - float(r.phase)) / StreetDetail.POLE_SPACING
				grid = grid and absf(slot - roundf(slot)) < 1e-3
				# The middle pin sits on the pin line: the pole stands POLE_FACE behind it, along the run.
				var foot := UtilityPoles.foot_of(p, r.zl)
				grid = grid and absf(Vector2(foot.x, foot.z).distance_to(Vector2(p.x, p.z)) - UtilityPoles.POLE_FACE) < 1e-4
	_t._check(pure and grid, "utility poles: a block's runs are pure and on StreetDetail's world-space pole grid")


func _blocks(plan: CityPlan, district: int, want: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for r in range(0, 60):
		for ix in range(-r, r + 1):
			for iz in [-r, r]:
				_try(plan, Vector2i(ix, iz), district, out)
			if out.size() >= want:
				return out
		for iz in range(-r + 1, r):
			for ix in [-r, r]:
				_try(plan, Vector2i(ix, iz), district, out)
			if out.size() >= want:
				return out
	return out


func _try(plan: CityPlan, k: Vector2i, district: int, out: Array[Vector2i]) -> void:
	if out.has(k):
		return
	var block: Dictionary = plan.block(k.x, k.y)
	var c: Vector2 = (block.rect as Rect2).get_center()
	if plan.zone_at(c) != MacroMap.Zone.CITY or int(plan.district_at(c)) != district:
		return
	if UtilityPoles.block_runs(plan, k.x, k.y).is_empty():
		return
	out.append(k)


## What the block built, less the line: every other batch's instance count (from the nodes the
## batch built: its data is consumed by the finish), the other children.
func _signature(ch: CityChunk) -> Array:
	var out: Array = []
	var kids := 0
	for c in ch.get_children():
		var n := String(c.name)
		if n.begins_with("Batch_"):
			var key := n.trim_prefix("Batch_")
			if not key in OWN:
				out.append("%s:%d" % [key, (c as MultiMeshInstance3D).multimesh.instance_count])
		# Climbers grow trumpet vines up some poles by a hash of the pole's foot, which moved.
		elif n != "UtilityWires" and not n.begins_with("BatchShadow") and not n.begins_with("Climbe"):
			kids += 1
	out.append("children:%d" % kids)
	out.sort()
	return out


func _free(ch: CityChunk) -> void:
	if ch.get_parent() != null:
		ch.get_parent().remove_child(ch)
	ch.free()
