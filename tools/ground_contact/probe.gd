extends Node
## Floating-prop probe (docs/HANDOFF.md "Ground contact"): builds FULL city blocks headless, rays
## every batch instance of what they placed down to the ground (the world layer, the props' own
## collision skipped) and lists what stands off it: a foot more than FLOAT (3 cm) over the ground
## or more than SINK (5 cm) into it. The foot is the lowest point of the instance's mesh box in
## the city (a tilted instance reads a little low), the ray goes down through the instance's origin
## (a lamp's arm or a tree's crown leans the box off its foot) unless the origin is outside its box. One line per batch key: count, how many float
## or sink, median and worst gap, and an EYE for still_shot.gd at the worst one.
##
##   xvfb-run -a godot --rendering-driver opengl3 --path . res://tools/ground_contact/probe.tscn
##
## BLOCKS="bx,bz;..." the blocks, else one per district near ANCHORS="x,z;..." (DISTRICTS="0,1,2").
## KEYS=prefix,... only those keys; ALL=1 lists every key (also the ones that never meet the ground);
## LIST=n prints the n worst instances of each flagged key.

const FLOAT := 0.03
const SINK := 0.05
## A key counts as standing on the ground when most of its instances' feet are within this of it.
const NEAR := 0.4
## Thinner than this (m) is a flat thing: paint, a cover, litter.
const FLAT := 0.15
## Keys that are not solid (additive light pools, glows, decals on walls) or never meet the
## ground (the facade kit, signs), which the probe leaves out.
const SKIP := ["pool", "spill", "glow", "halo", "atmos", "shaft", "wear", "mural", "kit_", "sign_txt", "text_", "lod_", "beam", "vinyl", "bb_face", "bb_frame", "contact"]


func _ready() -> void:
	await get_tree().process_frame
	var city: Node = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	var plan := CityPlan.new()
	plan.seed = city.world_seed
	plan.block_size_range = city.block_size_range
	plan.street_width = city.street_width
	plan.avenue_width = city.avenue_width
	plan.sidewalk_width = city.sidewalk_width
	plan.downtown_radius = city.downtown_radius
	plan.midtown_radius = city.midtown_radius
	plan.macro = MacroMap.new()
	plan.macro.seed = city.world_seed
	plan.macro.setup()
	var style: Dictionary = city.chunk_style()
	var picks: Array[Vector2i] = _picks(plan)
	var only: PackedStringArray = OS.get_environment("KEYS").split(",", false)
	var list_n := int(OS.get_environment("LIST")) if OS.get_environment("LIST") != "" else 0
	var stats := {} # key -> {n, fl, sk, gaps: [], worst: [gap, pos]}
	ContactShadows.recording = true
	var chunk_script: GDScript = load("res://scripts/world/city_chunk.gd")
	for bk in picks:
		ContactShadows.recorder.clear()
		var ch = chunk_script.new()
		ch.plan = plan
		ch.ix = bk.x
		ch.iz = bk.y
		ch.level = 0
		ch.style = style
		add_child(ch)
		ch.begin_build()
		while not ch.build_step():
			pass
		_visual_ground(ch)
		var owners := _batch_ground(ch)
		for i in 3:
			await get_tree().physics_frame
		var space := (ch as Node3D).get_world_3d().direct_space_state
		if OS.get_environment("TRACE") != "":
			_trace(space, OS.get_environment("TRACE"))
		var b: Dictionary = plan.block(bk.x, bk.y)
		print("BLOCK %d,%d district=%d kind=%d" % [bk.x, bk.y, b.district, b.kind])
		for rec: Array in ContactShadows.recorder:
			var batches: Dictionary = rec[1]
			for key: String in batches:
				if not only.is_empty() and not _matches(key, only):
					continue
				if _skip(key):
					continue
				var batch: Dictionary = batches[key]
				var box: AABB = (batch.mesh as Mesh).get_aabb()
				var xfs: Array = batch.xforms
				var pg: Transform3D = (rec[0] as Node3D).global_transform
				for i in xfs.size():
					var x: Transform3D = xfs[i]
					if x.basis.get_scale().x < 0.001 or x.origin.y < -9000.0:
						continue
					x = pg * x
					var wb: AABB = x * box
					var foot := wb.position.y
					var flat := wb.size.y < FLAT
					var c := x.origin
					if not box.has_point(Vector3(0.0, box.get_center().y, 0.0)):
						c = x * Vector3(box.get_center().x, box.position.y, box.get_center().z)
					var own: RID = owners.get("%s/%d/%d" % [rec[0].get_instance_id(), key.hash(), i], RID())
					var g := _ground(space, Vector3(c.x, foot, c.z), own, minf(wb.size.y, 1.5) + 0.05)
					if not stats.has(key):
						stats[key] = {"n": 0, "fl": 0, "sk": 0, "gaps": [], "bad": [], "nohit": 0, "flat": flat}
					var s: Dictionary = stats[key]
					if is_nan(g):
						s.nohit += 1
						continue
					# A flat thing (paint, a cover, litter) is measured by its top: sunk into the
					# ground on purpose, it only goes wrong once its top is under it.
					var gap := foot - g
					var sunk := (wb.end.y - g) < -0.005 if flat else gap < -SINK
					s.n += 1
					s.gaps.append(gap)
					if gap > FLOAT:
						s.fl += 1
					if sunk:
						s.sk += 1
					if gap > FLOAT or sunk:
						s.bad.append([gap, Vector3(c.x, g, c.z), bk, _last_hit])
		_box_bottoms(space, ch, bk)
		ch.queue_free()
		await get_tree().process_frame
	ContactShadows.recording = false
	var keys := stats.keys()
	keys.sort()
	var all := OS.get_environment("ALL") == "1"
	for key: String in keys:
		var s: Dictionary = stats[key]
		var gaps: Array = s.gaps
		if gaps.is_empty():
			if all:
				print("KEY %-26s nohit=%d" % [key, s.nohit])
			continue
		gaps.sort()
		var med: float = gaps[gaps.size() / 2]
		var near := 0
		for g: float in gaps:
			if absf(g) < NEAR:
				near += 1
		var grounded := near * 2 > gaps.size()
		if not all and (not grounded or (s.fl == 0 and s.sk == 0)):
			continue
		var bad: Array = s.bad
		bad.sort_custom(func(a, b2): return absf(a[0]) > absf(b2[0]))
		var w: Array = bad[0] if not bad.is_empty() else [0.0, Vector3.ZERO, Vector2i.ZERO]
		print("KEY %-26s n=%4d float=%4d sink=%4d median=%+.3f min=%+.3f max=%+.3f flat=%s grounded=%s nohit=%d worst=%+.3f at %s EYE=%s" % [key, s.n, s.fl, s.sk, med, gaps[0], gaps[gaps.size() - 1], s.flat, grounded, s.nohit, w[0], _v(w[1]), _eye(w[1])])
		for i in mini(list_n, bad.size()):
			print("   %+.3f at %s block %s on %s" % [bad[i][0], _v(bad[i][1]), bad[i][2], bad[i][3]])
	city.free()
	get_tree().quit()


func _matches(key: String, only: PackedStringArray) -> bool:
	for p in only:
		if key.begins_with(p):
			return true
	return false


## The ground under a point: the first world-layer surface a ray down from 1.5 m over `at` meets
## that is not a prop's own collision (StreetProps, an EncampmentItem, a breakable), NAN if none
## within 1.5 m under it either.
## Every drawn mesh of the chunk (not the batches: those are the props) as trimesh collision on
## VIS_LAYER only, so the rays measure against what is DRAWN: a forecourt's paving is laid a few cm
## over the slab that collides, and a prop stood on the paving is right. Needs mesh data: run under
## opengl3 (xvfb-run), never --headless.
const VIS_LAYER := 1 << 19


func _visual_ground(ch: Node) -> void:
	var n := 0
	for c in ch.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree() or mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			continue
		var shape := mi.mesh.create_trimesh_shape()
		if shape == null:
			continue
		var body := StaticBody3D.new()
		body.collision_layer = VIS_LAYER
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		mi.add_child(body)
		n += 1
	if n == 0:
		push_warning("no mesh data: run under opengl3")


## The drawn ground under `at`: the first upward face a ray meets coming down from `up` metres over
## it (the instance's own height, at most 1.5 m: a plant sunk in a planter meets the planter's
## soil above its foot), skipping the instance itself.
func _ground(space: PhysicsDirectSpaceState3D, at: Vector3, own: RID, up: float = 0.6) -> float:
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * maxf(up, 0.6), at + Vector3.DOWN * 1.5, VIS_LAYER)
	q.hit_back_faces = false
	if own.is_valid():
		q.exclude = [own]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return NAN
	var col := hit.collider as Node
	_last_hit = String(col.get_parent().name) if col and col.get_parent() else "?"
	return (hit.position as Vector3).y


var _last_hit := ""


## The chunk's merged solid boxes (CityChunk._merge_box(): planters, plinths, walls, kerbs):
## every corner of a downward face that has drawn ground within BOX_REACH under it but not
## touching it is a box standing off the ground. One line per merged mesh.
const BOX_REACH := 0.35


func _box_bottoms(space: PhysicsDirectSpaceState3D, ch: Node, bk: Vector2i) -> void:
	for c in ch.find_children("Boxes*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		var own: Array[RID] = []
		for b in mi.get_children():
			if b is StaticBody3D:
				own.append((b as StaticBody3D).get_rid())
		var xf := mi.global_transform
		var seen := {}
		var n := 0
		var fl := 0
		var worst := 0.0
		var worst_at := Vector3.ZERO
		for si in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(si)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var nr: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			for i in v.size():
				if nr.size() > i and nr[i].y > -0.9:
					continue
				var p := xf * v[i]
				var k := p.snapped(Vector3(0.01, 0.01, 0.01))
				if seen.has(k):
					continue
				seen[k] = true
				var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.01, p + Vector3.DOWN * BOX_REACH, VIS_LAYER)
				q.hit_back_faces = false
				q.exclude = own
				var hit := space.intersect_ray(q)
				if hit.is_empty():
					continue
				n += 1
				var gap := p.y - (hit.position as Vector3).y
				if gap > FLOAT:
					fl += 1
					if gap > worst:
						worst = gap
						worst_at = p
		if fl > 0 or OS.get_environment("ALL") == "1":
			print("BOXES %s block %s corners=%d float=%d worst=%+.3f at %s EYE=%s" % [mi.name, bk, n, fl, worst, _v(worst_at), _eye(worst_at)])


## TRACE="x,z": every surface (drawn or colliding) a vertical ray through that true-world point
## meets, top down, with what it belongs to.
func _trace(space: PhysicsDirectSpaceState3D, at: String) -> void:
	var p := at.split(",")
	var w := WorldState.to_local(Vector3(p[0].to_float(), 0.0, p[1].to_float()))
	var from := Vector3(w.x, 200.0, w.z)
	var ex: Array[RID] = []
	for i in 12:
		var q := PhysicsRayQueryParameters3D.create(from, Vector3(w.x, -200.0, w.z), 0xFFFFFFFF)
		q.exclude = ex
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			break
		var col := hit.collider as Node
		print("TRACE y=%.3f %s / %s layer=%d" % [(hit.position as Vector3).y, col.get_parent().name if col.get_parent() else "", col.name, (col as CollisionObject3D).collision_layer])
		ex.append(hit.rid)


func _skip(key: String) -> bool:
	for p: String in SKIP:
		if key.contains(p):
			return true
	return false


## Every solid batch instance is ground too (a parklet's chairs stand on its deck, a plant in its
## planter, a tree in its grate): one body per instance on VIS_LAYER with its mesh's trimesh
## shape (shared per mesh). Returns "<recorder parent id>/<key hash>/<index>" -> body RID, so an
## instance's own ray skips itself.
func _batch_ground(ch: Node) -> Dictionary:
	var out := {}
	var shapes := {}
	for rec: Array in ContactShadows.recorder:
		var batches: Dictionary = rec[1]
		for key: String in batches:
			if _skip(key):
				continue
			var batch: Dictionary = batches[key]
			var mesh: Mesh = batch.mesh
			if not shapes.has(mesh):
				shapes[mesh] = mesh.create_trimesh_shape()
			var shape: Shape3D = shapes[mesh]
			if shape == null:
				continue
			var xfs: Array = batch.xforms
			for i in xfs.size():
				var x: Transform3D = xfs[i]
				if x.basis.get_scale().x < 0.001 or x.origin.y < -9000.0:
					continue
				var body := StaticBody3D.new()
				body.collision_layer = VIS_LAYER
				body.collision_mask = 0
				var cs := CollisionShape3D.new()
				cs.shape = shape
				body.add_child(cs)
				(rec[0] as Node3D).add_child(body)
				body.transform = x
				out["%s/%d/%d" % [rec[0].get_instance_id(), key.hash(), i]] = body.get_rid()
	return out


func _is_prop_shape(hit: Dictionary) -> bool:
	var col := hit.collider as CollisionObject3D
	if col == null:
		return false
	var owner_id := col.shape_find_owner(int(hit.shape))
	var sh := col.shape_owner_get_owner(owner_id) as Node
	return sh != null and sh.has_meta("prop")


func _v(p: Vector3) -> String:
	var w := WorldState.to_world(p)
	return "%.1f,%.2f,%.1f" % [w.x, w.y, w.z]


func _eye(p: Vector3) -> String:
	var w := WorldState.to_world(p)
	return "%.1f,%.1f,%.1f,45,-30" % [w.x + 2.0, w.y + 2.0, w.z + 2.0]


func _picks(plan: CityPlan) -> Array[Vector2i]:
	var picks: Array[Vector2i] = []
	if OS.get_environment("BLOCKS") != "":
		for b in OS.get_environment("BLOCKS").split(";", false):
			var p := b.split(",")
			picks.append(Vector2i(int(p[0]), int(p[1])))
		return picks
	var anchors := "-700,-150;300,-600;1200,600;2700,300;3200,3200;600,1800"
	if OS.get_environment("ANCHORS") != "":
		anchors = OS.get_environment("ANCHORS")
	var want := {}
	var dl := "0,1,2,3,5"
	if OS.get_environment("DISTRICTS") != "":
		dl = OS.get_environment("DISTRICTS")
	for d in dl.split(","):
		want[int(d)] = true
	for a in anchors.split(";", false):
		var p := a.split(",")
		var home: Vector2i = plan.block_index_at(Vector2(p[0].to_float(), p[1].to_float()))
		for r in 6:
			for dz in range(-r, r + 1):
				for dx in range(-r, r + 1):
					var bk := Vector2i(home.x + dx, home.y + dz)
					var b: Dictionary = plan.block(bk.x, bk.y)
					if b.has("site") or plan.river_block(bk.x, bk.y):
						continue
					if plan.zone_at(b.rect.get_center()) != MacroMap.Zone.CITY:
						continue
					if want.has(int(b.district)):
						want.erase(int(b.district))
						picks.append(bk)
	return picks
