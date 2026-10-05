class_name BuildingDamage
extends RefCounted
## Buildings that take damage: panes that craze and then fall out, bullet scars in stone and
## render, and blasts that blow every window near them and punch a hole through the wall.
##
## All of it is DATA: a building that has been hit keeps a short list of records (a point in its
## own space and a kind, `K_*`), which `shaders/building.gdshader` reads through
## `shaders/building_damage.gdshaderinc` - the pane holding a CRACK point is a web of cracks, a
## SHATTER point's pane is an empty frame onto its traced room, a BLAST takes out the panes round
## it, a HOLE is traced as the burnt room behind a broken edge, a POCK is a pit in the wall. A
## building nobody has shot has no records and its walls cost one branch more than before.
## A Building's facade material is its own already (Building._part_material()); a downtown
## tower's is shared with its twin and its far copy, so a damaged tower's detailed copy gets its
## own copies as surface overrides on its first hit (`_tower_mats()`), the CarDamage rule.
##
## What is not in the shader is real geometry under the building, rebuilt from the same records:
## the rim of every hole (broken masonry, bent rebar: `DamageRim`) and the glass lying on the
## pavement under every pane that fell (`DamageLitter`). And the moment itself: shards falling
## out of the frame, chunks of the wall thrown as debris (PhysicsBudget), dust, the glass Sfx.
##
## The records live in `WorldState.building_damage` by building key, so a building that streams
## out and back keeps its damage (`restore()` from Building._ready(), `restore_tower()` from
## LandmarkDowntown.build()). Never on a place of worship (Sanctuary). `BUILDING_DAMAGE=0` in the
## environment turns it all off (the A/B).
##
## Hooks: AssaultRifle.fire_ray(), Shotgun.fire_pellet() and PoliceOfficer's rounds call
## `bullet()`; Explosion.blast() calls `blast()`.

const K_CRACK := 1
const K_SHATTER := 2
const K_BLAST := 3
const K_HOLE := 4
const K_POCK := 5
## Records a building can hold (the shader's `damage[]` array length).
const MAX_RECORDS := 32
## Bullet scars a building keeps; the oldest goes first.
const MAX_POCKS := 12
## Holes a building keeps (their rims are real geometry).
const MAX_HOLES := 6
## A blast takes out the panes within this share of its radius (and crazes them to 1.8x that).
const BLAST_SHATTER := 0.7
## A blast this share of its radius from a wall or nearer punches a hole in it.
const HOLE_REACH := 0.36
## Hole radius (m) for a blast right on the wall and one at the edge of HOLE_REACH.
const HOLE_RADIUS := Vector2(2.0, 0.9)
## Largest hole (m): a hole hit again grows toward this.
const HOLE_MAX := 2.6
## Pane shard bursts a blast throws (the nearest panes), and litter patches it lays.
const BLAST_SHARD_PANES := 8
const BLAST_LITTER_PANES := 14
## Glass on the pavement: triangles a metre of pane width, and the cap a building keeps.
const LITTER_PER_METRE := 40
const MAX_LITTER := 30
## Rubble a hole throws (rigid debris, PhysicsBudget) and how long it lies.
const RUBBLE_MAX := 10
const RUBBLE_LIFE := 14.0
const TOWER_GROUP := "damage_tower"

static var enabled: bool = OS.get_environment("BUILDING_DAMAGE") != "0"

static var _shard_mat: StandardMaterial3D = null
static var _litter_mat: StandardMaterial3D = null
static var _rim_mat: StandardMaterial3D = null
static var _shard_mesh: Mesh = null


# --- Entry points ------------------------------------------------------------------------------

## A round landed (`hit` is a physics ray result). `heavy` is a shotgun pellet (merges its scars).
static func bullet(hit: Dictionary, dir: Vector3, heavy: bool = false) -> void:
	if not enabled or hit.is_empty():
		return
	var t := target_of(hit.get("collider"), int(hit.get("shape", -1)))
	if t.is_empty():
		return
	var node: Node3D = t.node
	var at: Vector3 = hit.position
	var mp := node.to_local(at)
	var mn: Vector3 = (node.global_basis.inverse() * (hit.normal as Vector3)).normalized()
	if absf(mn.y) > 0.5:
		return # a roof or a soffit
	var entry := _entry(t.key)
	var b: Building = t.building
	var pane := {}
	var is_glass := false
	if b != null:
		pane = pane_at(b, mp, mn)
		is_glass = pane.has("centre")
	else:
		# A tower: glass if its facade is a curtain wall or glass (the shader keeps a crack to a
		# pane, so one landing on a mullion draws nothing).
		is_glass = _tower_glass(t.mats)
		if is_glass:
			pane = {"key": "", "centre": mp, "half": Vector2(0.7, 1.0), "normal": mn, "mu": _mu(mn)}
	if is_glass:
		var idx := _find_pane(entry, pane, mp)
		if idx >= 0:
			var rec: Vector4 = entry.recs[idx]
			if _kind(rec) == K_CRACK:
				entry.recs[idx] = Vector4(rec.x, rec.y, rec.z, K_SHATTER * 100.0)
				_push(t, entry, false)
				_shatter_fx(t, pane, entry)
			return
		_add(entry, Vector4(mp.x, mp.y, mp.z, K_CRACK * 100.0), pane.get("key", ""))
	else:
		# A scar in the wall; pellets landing on one another make one scar.
		var merge := 0.22 if heavy else 0.04
		for rec: Vector4 in entry.recs:
			if int(rec.w / 100.0) == K_POCK and Vector3(rec.x, rec.y, rec.z).distance_to(mp) < merge:
				return
		var r := randf_range(0.05, 0.075) if heavy else randf_range(0.07, 0.11)
		_add(entry, Vector4(mp.x, mp.y, mp.z, K_POCK * 100.0 + r), "")
	_push(t, entry, false)


## A blast at `at` (global) of `radius`; `power` 1 is a rocket.
static func blast(node: Node, at: Vector3, radius: float, power: float = 1.0) -> void:
	if not enabled or node == null or not node.is_inside_tree() or radius <= 0.1:
		return
	var space := (node as Node3D).get_world_3d().direct_space_state if node is Node3D else null
	if space == null:
		return
	var shape := SphereShape3D.new()
	shape.radius = radius * BLAST_SHATTER * 1.8
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), at)
	q.collision_mask = 1
	var seen := {}
	for res: Dictionary in space.intersect_shape(q, 128):
		var t := target_of(res.get("collider"), int(res.get("shape", -1)))
		if t.is_empty() or seen.has(t.key):
			continue
		seen[t.key] = true
		_blast_target(node, t, at, radius, power)


## A Building has come into the tree: put back what was done to it.
static func restore(b: Building) -> void:
	if not enabled or not WorldState.building_damage.has(key_of(b)):
		return
	var t := target_of(b, -1)
	if not t.is_empty():
		_push(t, WorldState.building_damage[t.key])


## A downtown tower's detailed copy has been built: mark it and put back its damage.
static func restore_tower(body: MeshInstance3D, id: String) -> void:
	if not enabled:
		return
	body.add_to_group(TOWER_GROUP)
	body.set_meta("tower_id", id)
	if WorldState.building_damage.has("t:" + id):
		var t := {"key": "t:" + id, "node": body, "mats": _tower_mats(body), "building": null}
		_push(t, WorldState.building_damage[t.key])


# --- What was hit ----------------------------------------------------------------------------

## The building or tower a collider is, or {}: {key, node (the space the records are in), mats
## (the facade materials to write), building (a Building, or null for a tower)}.
static func target_of(collider: Variant, shape: int) -> Dictionary:
	if collider == null or not is_instance_valid(collider) or Sanctuary.is_sanctuary(collider as Object):
		return {}
	if collider is Building:
		var b := collider as Building
		var walls := walls_of(b)
		if walls == null:
			return {}
		return {"key": key_of(b), "node": b, "mats": [walls.material_override], "building": b}
	var co := collider as CollisionObject3D
	if co == null or shape < 0 or not co.is_inside_tree():
		return {}
	var cs := co.shape_owner_get_owner(co.shape_find_owner(shape)) as CollisionShape3D
	if cs == null:
		return {}
	# A tower's hulls stand at its anchor, which is where its mesh stands.
	for n: Node in co.get_tree().get_nodes_in_group(TOWER_GROUP):
		var body := n as MeshInstance3D
		if body != null and body.global_position.distance_to(cs.global_position) < 0.5:
			var id: String = body.get_meta("tower_id", "")
			return {"key": "t:" + id, "node": body, "mats": _tower_mats(body), "building": null}
	return {}


## A Building's merged walls ("Walls", on the facade shader), skipping one a rebuild is freeing.
static func walls_of(b: Building) -> MeshInstance3D:
	for child: Node in b.get_children():
		var mi := child as MeshInstance3D
		if mi != null and not mi.is_queued_for_deletion() and mi.material_override is ShaderMaterial \
				and (mi.material_override as ShaderMaterial).shader == Building.SHADER:
			return mi
	return null


## A building's key in WorldState: its seed and lot, which a rebuilt chunk gives it again.
static func key_of(b: Building) -> String:
	return "b%d_%d_%d" % [b.seed, roundi(b.lot_size.x * 10.0), roundi(b.lot_size.y * 10.0)]


## The tower's own copies of its facade materials (made on its first damage, kept as overrides).
static func _tower_mats(body: MeshInstance3D) -> Array:
	var out: Array = []
	if body.mesh == null:
		return out
	for i in body.mesh.get_surface_count():
		var own := body.get_surface_override_material(i) as ShaderMaterial
		if own == null:
			var src := body.mesh.surface_get_material(i) as ShaderMaterial
			if src == null or src.shader != Building.SHADER:
				continue
			own = src.duplicate() as ShaderMaterial
			body.set_surface_override_material(i, own)
		out.append(own)
	return out


static func _tower_glass(mats: Array) -> bool:
	for m: ShaderMaterial in mats:
		var style: Variant = m.get_shader_parameter("window_style")
		var fin: Variant = m.get_shader_parameter("facade_finish")
		if (style != null and int(style) == Building.WindowStyle.CURTAIN) or (fin != null and int(fin) == Building.Finish.GLASS):
			return true
	return false


## The direction a wall's `u` runs along (building.gdshader's tangent times u_sign), model space.
static func _mu(mn: Vector3) -> Vector3:
	if absf(mn.x) > 0.5:
		return Vector3(0.0, 0.0, signf(mn.x))
	return Vector3(-signf(mn.z), 0.0, 0.0)


## The pane of a Building at model point `mp` on the wall facing `mn`, worked out as
## building.gdshader draws it: {key, centre, half, normal, mu}, or {} if the point is wall.
static func pane_at(b: Building, mp: Vector3, mn: Vector3) -> Dictionary:
	if absf(mn.y) > 0.5 or (absf(mn.x) > 0.35 and absf(mn.z) > 0.35):
		return {}
	var on_x := absf(mn.x) > 0.5
	for i in b.parts.size():
		var part: Dictionary = b.parts[i]
		if not part.has("pitch_x") or bool(part.get("parking", false)):
			continue
		var size: Vector3 = part.size
		var l := mp - (part.center as Vector3)
		var face_d := l.x * signf(mn.x) - size.x * 0.5 if on_x else l.z * signf(mn.z) - size.z * 0.5
		if absf(face_d) > 0.3 or absf(l.y) > size.y * 0.5 + 0.05:
			continue
		var width := size.z if on_x else size.x
		var u := l.z * signf(mn.x) + size.z * 0.5 if on_x else -l.x * signf(mn.z) + size.x * 0.5
		if u < -0.05 or u > width + 0.05:
			continue
		var pitch: float = part.pitch_z if on_x else part.pitch_x
		var face := (1 if mn.x > 0.0 else 2) if on_x else (3 if mn.z > 0.0 else 4)
		var v := mp.y + b.position.y
		var col := floorf(u / pitch)
		var fu := u / pitch - col
		var cell: float
		var row: float
		var fv: float
		var rect: Array
		var glass := false
		if bool(part.storefront) and v < float(part.gfh):
			cell = maxf(float(part.gfh) - float(part.base_y), 0.5)
			row = -1.0
			fv = (v - float(part.base_y)) / cell
			rect = [0.5, 0.37, 0.44, 0.37]
			glass = absf(fu - 0.5) < 0.44 and fv > 0.0 and fv < 0.74
		else:
			cell = float(part.floor_h)
			var vv := (v - float(part.gfh)) / cell
			row = floorf(vv)
			fv = vv - row
			rect = Building.WINDOW_RECTS[b.window_style]
			glass = absf(fu - float(rect[0])) < float(rect[2]) + 0.02 and absf(fv - float(rect[1])) < float(rect[3]) + 0.02
		if not glass:
			return {}
		var mu := _mu(mn)
		var centre := mp + mu * ((float(rect[0]) - fu) * pitch) + Vector3(0.0, (float(rect[1]) - fv) * cell, 0.0)
		return {"key": "%d:%d:%d:%d" % [i, face, int(col), int(row)], "centre": centre,
			"half": Vector2(float(rect[2]) * pitch, float(rect[3]) * cell), "normal": mn, "mu": mu}
	return {}


## Every glass pane of a Building whose centre is within `r` of model point `c` on a wall facing
## it, nearest first: [{centre, half, normal, mu}].
static func panes_near(b: Building, c: Vector3, r: float) -> Array:
	var out: Array = []
	for part: Dictionary in b.parts:
		if not part.has("pitch_x") or bool(part.get("parking", false)):
			continue
		var size: Vector3 = part.size
		var pc: Vector3 = part.center
		for f in 4:
			var n: Vector3 = [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD][f]
			var on_x := f < 2
			var face_c := pc + n * (size.x * 0.5 if on_x else size.z * 0.5)
			if (c - face_c).dot(n) < -0.3:
				continue # the blast is behind this wall
			var mu := _mu(n)
			var width := size.z if on_x else size.x
			var pitch: float = part.pitch_z if on_x else part.pitch_x
			var bottom := pc.y - size.y * 0.5
			var top := pc.y + size.y * 0.5
			# The face's u = 0 edge, in model space.
			var u0 := face_c - mu * width * 0.5
			var rect: Array = Building.WINDOW_RECTS[b.window_style]
			var floor_h: float = part.floor_h
			var gfh_local: float = float(part.gfh) - b.position.y
			var base_local: float = float(part.base_y) - b.position.y
			var cols := roundi(width / pitch)
			var c_u := clampi(int(floor((c - u0).dot(mu) / pitch)), 0, cols - 1)
			var span := int(ceil(r / pitch)) + 1
			var ys: Array = []
			if bool(part.storefront):
				var sf := maxf(gfh_local - base_local, 0.5)
				ys.append([base_local + 0.37 * sf, Vector2(0.44 * pitch, 0.37 * sf), 0.5])
			var rows := roundi((top - gfh_local) / floor_h)
			var c_r := int(floor((c.y - gfh_local) / floor_h))
			for row in range(maxi(0, c_r - span), mini(rows, c_r + span + 1)):
				ys.append([gfh_local + (row + float(rect[1])) * floor_h, Vector2(float(rect[2]) * pitch, float(rect[3]) * floor_h), float(rect[0])])
			for y: Array in ys:
				if float(y[0]) < bottom or float(y[0]) > top:
					continue
				for col in range(maxi(0, c_u - span), mini(cols, c_u + span + 1)):
					var centre := u0 + mu * ((col + float(y[2])) * pitch) + Vector3.UP * (float(y[0]) - u0.y)
					if centre.distance_to(c) < r and not _inside_part(b, centre + n * 0.3):
						out.append({"centre": centre, "half": y[1], "normal": n, "mu": mu})
	out.sort_custom(func(a, bb): return (a.centre as Vector3).distance_squared_to(c) < (bb.centre as Vector3).distance_squared_to(c))
	return out


static func _inside_part(b: Building, p: Vector3) -> bool:
	for part: Dictionary in b.parts:
		var l := p - (part.center as Vector3)
		var h: Vector3 = (part.size as Vector3) * 0.5
		if absf(l.x) < h.x and absf(l.y) < h.y and absf(l.z) < h.z:
			return true
	return false


# --- Records -----------------------------------------------------------------------------------

static func _entry(key: String) -> Dictionary:
	if not WorldState.building_damage.has(key):
		WorldState.building_damage[key] = {"recs": [], "keys": [], "holes": [], "litter": []}
	return WorldState.building_damage[key]


static func _kind(rec: Vector4) -> int:
	return int(floor(rec.w / 100.0 + 0.001))


## The record of the pane `pane` names (by key on a Building, by distance on a tower), or -1.
static func _find_pane(entry: Dictionary, pane: Dictionary, mp: Vector3) -> int:
	var key: String = pane.get("key", "")
	for i in entry.recs.size():
		var k := _kind(entry.recs[i])
		if k != K_CRACK and k != K_SHATTER:
			continue
		if key != "" and entry["keys"][i] == key:
			return i
		var rec: Vector4 = entry.recs[i]
		if key == "" and Vector3(rec.x, rec.y, rec.z).distance_to(mp) < 0.5:
			return i
	return -1


## Adds a record, making room by dropping the oldest scar, then the oldest crack, then the oldest.
static func _add(entry: Dictionary, rec: Vector4, key: String) -> void:
	var recs: Array = entry.recs
	var keys: Array = entry["keys"]
	if _kind(rec) == K_POCK:
		var pocks := 0
		for r: Vector4 in recs:
			pocks += 1 if _kind(r) == K_POCK else 0
		if pocks >= MAX_POCKS:
			_drop_first(entry, K_POCK)
	while recs.size() >= MAX_RECORDS:
		if not _drop_first(entry, K_POCK) and not _drop_first(entry, K_CRACK) and not _drop_first(entry, K_SHATTER):
			recs.pop_front()
			keys.pop_front()
	recs.append(rec)
	keys.append(key)


static func _drop_first(entry: Dictionary, kind: int) -> bool:
	for i in entry.recs.size():
		if _kind(entry.recs[i]) == kind:
			entry.recs.remove_at(i)
			entry["keys"].remove_at(i)
			return true
	return false


## The seed the shader gives a record (building_damage.gdshaderinc dmg_seed()).
static func record_seed(p: Vector3) -> float:
	return fposmod(p.x * 1.37 + p.y * 2.11 + p.z * 0.73, 6.2832)


## A hole's jagged outline (building_damage.gdshaderinc dmg_hole_radius(), line for line).
static func hole_radius(r: float, a: float, s: float) -> float:
	return r * (0.80 + 0.12 * sin(3.0 * a + s) + 0.07 * sin(7.0 * a + 2.3 * s) + 0.045 * sin(13.0 * a + 4.1 * s))


## Writes the records to the facade materials and rebuilds the rims and the glass on the ground.
static func _push(t: Dictionary, entry: Dictionary, geometry: bool = true) -> void:
	var arr := PackedVector4Array()
	arr.resize(MAX_RECORDS)
	var n := mini(entry.recs.size(), MAX_RECORDS)
	for i in n:
		arr[i] = entry.recs[i]
	for m: ShaderMaterial in t.mats:
		m.set_shader_parameter("damage", arr)
		m.set_shader_parameter("damage_count", n)
	if geometry:
		var node: Node3D = t.node
		_build_rims(node, entry.holes)
		_build_litter(node, entry.litter)


# --- Blasts ------------------------------------------------------------------------------------

static func _blast_target(src: Node, t: Dictionary, at: Vector3, radius: float, power: float) -> void:
	var node: Node3D = t.node
	var mc := node.to_local(at)
	var entry := _entry(t.key)
	_add(entry, Vector4(mc.x, mc.y, mc.z, K_BLAST * 100.0 + minf(radius * BLAST_SHATTER, 99.0)), "")
	var b: Building = t.building
	var shards := 0
	if b != null:
		# A curtain wall has no wall to hole: the blast takes its glass (the panes below).
		var solid := b.finish != Building.Finish.GLASS and b.window_style != Building.WindowStyle.CURTAIN
		var spot := _hole_spot(b, mc) if solid else {}
		if not spot.is_empty() and float(spot.dist) < radius * HOLE_REACH:
			var near := 1.0 - float(spot.dist) / (radius * HOLE_REACH)
			var hr := lerpf(HOLE_RADIUS.y, HOLE_RADIUS.x, near) * clampf(power, 0.6, 1.4)
			_punch(src, t, entry, spot.point, spot.normal, hr)
		for pane: Dictionary in panes_near(b, mc, radius * BLAST_SHATTER):
			if shards < BLAST_SHARD_PANES:
				_shards(node, pane)
			if shards < BLAST_LITTER_PANES:
				_lay_litter(node, entry, pane)
			shards += 1
	if shards > 0 or b == null:
		Sfx.play("glass", at, 2.0, randf_range(0.85, 1.0))
	_push(t, entry)


## Where a blast at model point `mc` meets a Building's walls: the nearest point on a part's side
## (not its roof) {point, normal, dist}, or {}.
static func _hole_spot(b: Building, mc: Vector3) -> Dictionary:
	var best := {}
	for part: Dictionary in b.parts:
		var size: Vector3 = part.size
		if size.y < 3.0:
			continue
		var c: Vector3 = part.center
		var h := size * 0.5
		var l := mc - c
		var cp := l.clamp(-h, h)
		var dist := (l - cp).length()
		# Which face the point is on: the side the blast is most outside of (inside: nearest).
		var out_x := absf(l.x) - h.x
		var out_z := absf(l.z) - h.z
		var out_y := l.y - h.y
		if out_y > maxf(out_x, out_z):
			continue # over the roof
		var n := Vector3(signf(l.x), 0.0, 0.0) if out_x > out_z else Vector3(0.0, 0.0, signf(l.z))
		if n.x != 0.0:
			cp.x = h.x * n.x
		else:
			cp.z = h.z * n.z
		cp.y = clampf(cp.y, -h.y + 0.9, h.y - 0.6)
		if best.is_empty() or dist < float(best.dist):
			best = {"point": cp + c, "normal": n, "dist": dist}
	return best


static func _punch(src: Node, t: Dictionary, entry: Dictionary, p: Vector3, n: Vector3, hr: float) -> void:
	var b: Building = t.building
	# A hole hit again grows rather than stacking a second one in it.
	for i in entry.recs.size():
		var rec: Vector4 = entry.recs[i]
		if _kind(rec) == K_HOLE and Vector3(rec.x, rec.y, rec.z).distance_to(p) < rec.w - K_HOLE * 100.0 + 0.6:
			var grown := minf(maxf(rec.w - K_HOLE * 100.0, hr) * 1.25, HOLE_MAX)
			entry.recs[i] = Vector4(rec.x, rec.y, rec.z, K_HOLE * 100.0 + grown)
			for hole: Array in entry.holes:
				if (hole[0] as Vector3).distance_to(Vector3(rec.x, rec.y, rec.z)) < 0.01:
					hole[2] = grown
			_rubble(src, t.node, p, n, hr, b)
			return
	var holes := 0
	for rec: Vector4 in entry.recs:
		holes += 1 if _kind(rec) == K_HOLE else 0
	if holes >= MAX_HOLES:
		return
	_add(entry, Vector4(p.x, p.y, p.z, K_HOLE * 100.0 + hr), "")
	entry.holes.append([p, n, hr, record_seed(p), int(b.finish), b.facade_color])
	_rubble(src, t.node, p, n, hr, b)
	# The window frames and kit pieces that stood in the hole go with the wall.
	_clear_detail(b, p, n, hr)


## Hides every facade detail and kit instance standing in the hole (the frames, sills, surrounds).
static func _clear_detail(b: Building, p: Vector3, n: Vector3, hr: float) -> void:
	var mu := _mu(n)
	for child: Node in b.find_children("*", "MultiMeshInstance3D", true, false):
		var mmi := child as MultiMeshInstance3D
		if mmi == null or mmi.multimesh == null:
			continue
		var mm := mmi.multimesh
		var xf := b.global_transform.affine_inverse() * mmi.global_transform
		var count := mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
		for i in count:
			var o := xf * mm.get_instance_transform(i).origin
			var d := o - p
			if absf(d.dot(n)) < 1.2 and Vector2(d.dot(mu), d.y).length() < hr * 1.2:
				mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), mm.get_instance_transform(i).origin))


# --- The moment: shards, rubble, dust ------------------------------------------------------------

static func _shatter_fx(t: Dictionary, pane: Dictionary, entry: Dictionary) -> void:
	var node: Node3D = t.node
	var fall := _shards(node, pane)
	Sfx.play("glass", node.to_global(pane.centre), -2.0, randf_range(0.9, 1.15))
	if _lay_litter(node, entry, pane):
		# The glass is on the ground once the shards have got there.
		node.get_tree().create_timer(fall * 0.8, false).timeout.connect(func():
			if is_instance_valid(node):
				_build_litter(node, entry.litter))


## A pane's glass falling out of its frame: one CPUParticles3D burst of glinting shards.
static func _shards(node: Node3D, pane: Dictionary) -> float:
	var parent := WeaponFX.fx_parent(node)
	if parent == null:
		return 0.0
	var half: Vector2 = pane.half
	var n: Vector3 = (node.global_basis * (pane.normal as Vector3)).normalized()
	var mu: Vector3 = (node.global_basis * (pane.mu as Vector3)).normalized()
	var at := node.to_global(pane.centre)
	var p := CPUParticles3D.new()
	p.name = "GlassShards"
	p.mesh = _shard()
	p.material_override = _shard_material()
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.amount = clampi(int(half.x * half.y * 4.0 * 26.0), 10, 48)
	p.one_shot = true
	p.explosiveness = 0.85
	p.lifetime = clampf(sqrt(2.0 * maxf(at.y - node.global_position.y, 1.0) / 9.8) + 0.5, 1.0, 4.0)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(half.x, half.y, 0.02)
	p.direction = Vector3(0.0, 0.0, 1.0)
	p.spread = 40.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 3.5
	p.gravity = Vector3(0.0, -9.8, 0.0)
	p.angular_velocity_min = -540.0
	p.angular_velocity_max = 540.0
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.6
	p.particle_flag_rotate_y = true
	p.local_coords = false
	parent.add_child(p)
	p.global_transform = Transform3D(Basis(mu, Vector3.UP, n), at)
	p.emitting = true
	p.get_tree().create_timer(p.lifetime + 0.5, false).timeout.connect(p.queue_free)
	return p.lifetime


## Chunks of wall thrown out of a hole (rigid debris, PhysicsBudget), and a cloud of its dust.
static func _rubble(src: Node, node: Node3D, p: Vector3, n: Vector3, hr: float, b: Building) -> void:
	var parent := WeaponFX.fx_parent(src)
	if parent == null:
		return
	var at := node.to_global(p)
	var gn := (node.global_basis * n).normalized()
	var col := _break_color(b)
	var count := clampi(int(3.0 + hr * 3.5), 3, RUBBLE_MAX)
	if PhysicsBudget.make_room(count):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = col
		mat.roughness = 0.95
		for i in count:
			var body := RigidBody3D.new()
			body.name = "Rubble"
			var s := Vector3(randf_range(0.12, 0.38), randf_range(0.08, 0.26), randf_range(0.10, 0.30))
			body.mass = s.x * s.y * s.z * 1900.0
			body.collision_layer = 4
			body.collision_mask = 1 | 4
			var cs := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = s
			cs.shape = box
			body.add_child(cs)
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = s
			mi.mesh = bm
			mi.material_override = mat
			body.add_child(mi)
			parent.add_child(body)
			var off := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * hr * 0.5
			body.global_position = at + gn * 0.4 + off - gn * off.dot(gn)
			body.rotation = Vector3(randf(), randf(), randf()) * TAU
			body.linear_velocity = gn * randf_range(4.0, 11.0) + Vector3.UP * randf_range(1.0, 5.0) + off * 3.0
			body.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
			PhysicsBudget.register_debris(body, RUBBLE_LIFE)
	# Dust rolling out of the hole and settling.
	var dust := CPUParticles3D.new()
	dust.name = "WallDust"
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	dust.mesh = quad
	dust.material_override = WeaponFX.smoke_material()
	dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dust.amount = 18
	dust.one_shot = true
	dust.explosiveness = 0.8
	dust.lifetime = 4.0
	dust.local_coords = false
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	dust.emission_sphere_radius = hr * 0.6
	dust.direction = Vector3(0.0, 0.0, 1.0)
	dust.spread = 55.0
	dust.initial_velocity_min = 1.0
	dust.initial_velocity_max = 4.0
	dust.damping_min = 1.5
	dust.damping_max = 2.5
	dust.gravity = Vector3(0.0, -0.4, 0.0)
	dust.scale_amount_min = 1.4 * hr
	dust.scale_amount_max = 2.6 * hr
	var ramp := Gradient.new()
	var dc := col.lerp(Color(0.62, 0.60, 0.56), 0.5)
	ramp.set_color(0, Color(dc.r, dc.g, dc.b, 0.85))
	ramp.set_color(1, Color(dc.r, dc.g, dc.b, 0.0))
	dust.color_ramp = ramp
	parent.add_child(dust)
	dust.global_transform = Transform3D(_basis_facing(gn), at + gn * 0.5)
	dust.emitting = true
	dust.get_tree().create_timer(dust.lifetime + 0.5, false).timeout.connect(dust.queue_free)


## The colour of a building's broken wall (sRGB): brick, the render's own colour, or concrete.
static func _break_color(b: Building) -> Color:
	if b == null:
		return Color(0.55, 0.54, 0.52)
	if b.finish == Building.Finish.BRICK:
		return Color(0.46, 0.22, 0.15)
	if b.finish == Building.Finish.FLAT:
		return b.facade_color.lerp(Color(0.6, 0.59, 0.56), 0.4)
	return Color(0.56, 0.55, 0.53)


static func _basis_facing(n: Vector3) -> Basis:
	var up := Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT
	var x := up.cross(n).normalized()
	return Basis(x, n.cross(x).normalized(), n)


static func _shard() -> Mesh:
	if _shard_mesh == null:
		# A sliver of glass: an irregular flat triangle a few centimetres across.
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_normal(Vector3(0, 0, 1))
		st.add_vertex(Vector3(-0.03, -0.025, 0.0))
		st.add_vertex(Vector3(0.035, -0.01, 0.0))
		st.add_vertex(Vector3(-0.005, 0.045, 0.0))
		_shard_mesh = st.commit()
	return _shard_mesh


static func _shard_material() -> StandardMaterial3D:
	if _shard_mat == null:
		_shard_mat = StandardMaterial3D.new()
		_shard_mat.albedo_color = Color(0.70, 0.80, 0.80)
		_shard_mat.metallic = 0.5
		_shard_mat.roughness = 0.06
		_shard_mat.metallic_specular = 1.0
		_shard_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _shard_mat


# --- Geometry left behind ------------------------------------------------------------------------

## Records where a pane's glass lands on the ground (a ray down from under it, out from the wall).
static func _lay_litter(node: Node3D, entry: Dictionary, pane: Dictionary) -> bool:
	if entry.litter.size() >= MAX_LITTER or not node.is_inside_tree():
		return false
	var n: Vector3 = pane.normal
	var half: Vector2 = pane.half
	var from := node.to_global((pane.centre as Vector3) + n * 0.7 - Vector3.UP * half.y)
	var space := node.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 120.0, 1)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return false
	var ground := node.to_local(hit.position)
	var fall := maxf(from.y - (hit.position as Vector3).y, 0.0)
	entry.litter.append([ground, n, half.x * 2.0, record_seed(pane.centre), fall])
	return true


## The glass on the ground: one mesh under the building, its shards lying flat.
static func _build_litter(node: Node3D, litter: Array) -> void:
	var old := node.get_node_or_null("DamageLitter")
	if old != null:
		old.free()
	if litter.is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for item: Array in litter:
		var g: Vector3 = item[0]
		var n: Vector3 = item[1]
		var w: float = item[2]
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([g.x, g.z, item[3]])
		var mu := _mu(n)
		# A higher pane throws its glass further out.
		var reach := 0.6 + minf(float(item[4]) * 0.08, 2.2)
		var count := int(w * LITTER_PER_METRE + 6)
		for i in count:
			var along := rng.randf_range(-0.6, 0.6) * w
			var out := pow(rng.randf(), 1.6) * reach - 0.55
			var c := g + mu * along + n * out + Vector3.UP * 0.012
			var s := rng.randf_range(0.015, 0.05)
			var a := rng.randf() * TAU
			for k in 3:
				var ang := a + k * TAU / 3.0 + rng.randf_range(-0.5, 0.5)
				st.add_vertex(c + Vector3(cos(ang), 0.0, sin(ang)) * s * rng.randf_range(0.5, 1.3))
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.name = "DamageLitter"
	mi.mesh = mesh
	mi.material_override = _litter_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 70.0
	node.add_child(mi)


static func _litter_material() -> StandardMaterial3D:
	if _litter_mat == null:
		_litter_mat = StandardMaterial3D.new()
		_litter_mat.albedo_color = Color(0.56, 0.64, 0.62)
		_litter_mat.metallic = 0.4
		_litter_mat.roughness = 0.05
		_litter_mat.metallic_specular = 1.0
		_litter_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _litter_mat


## The rims of the holes: broken blocks round each jagged outline, and bent rebar.
static func _build_rims(node: Node3D, holes: Array) -> void:
	var old := node.get_node_or_null("DamageRim")
	if old != null:
		old.free()
	if holes.is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	for hole: Array in holes:
		_rim(st, hole)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "DamageRim"
	mi.mesh = st.commit()
	mi.material_override = _rim_material()
	mi.visibility_range_end = 260.0
	node.add_child(mi)


static func _rim(st: SurfaceTool, hole: Array) -> void:
	var c: Vector3 = hole[0]
	var n: Vector3 = hole[1]
	var r: float = hole[2]
	var s: float = hole[3]
	var finish: int = hole[4]
	var wall: Color = hole[5]
	var mu := _mu(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([c.x, c.y, c.z])
	var brick := finish == Building.Finish.BRICK
	var core := _break_color_finish(finish, wall)
	# Broken blocks round the outline, sticking out a little, sooted toward the hole.
	var count := int(22 + r * 14)
	for i in count:
		var a := TAU * (float(i) + rng.randf_range(-0.3, 0.3)) / count
		var jr := hole_radius(r, a, s)
		var out := jr + rng.randf_range(-0.05, 0.10)
		var at := c + (mu * cos(a) + Vector3.UP * sin(a)) * out + n * rng.randf_range(-0.04, 0.05)
		var size := Vector3(rng.randf_range(0.07, 0.2), rng.randf_range(0.05, 0.14), rng.randf_range(0.06, 0.18))
		var col := core.lerp(Color(0.05, 0.045, 0.04), rng.randf_range(0.15, 0.6))
		var basis := Basis(mu, Vector3.UP, n) * Basis.from_euler(Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.5, 0.5), a + rng.randf_range(-0.4, 0.4)))
		if brick:
			# Bricks stay in their courses: broken ends left in the wall along a stepped edge.
			size = Vector3(0.21 * rng.randf_range(0.4, 1.0), 0.065, 0.10)
			at.y = c.y + snappedf(at.y - c.y, 0.075)
			at -= n * rng.randf_range(0.0, 0.06)
			basis = Basis(mu, Vector3.UP, n) * Basis.from_euler(Vector3(rng.randf_range(-0.08, 0.08), rng.randf_range(-0.25, 0.25), rng.randf_range(-0.1, 0.1)))
		_rock(st, at, basis, size, col, rng)
	if brick:
		return
	# Rebar: the bars that crossed the hole, snapped and bent out by the blast.
	var bar := Color(0.16, 0.09, 0.06)
	var pitch := 0.3
	var k: float = -floor(r / pitch)
	while k * pitch < r:
		for vertical in [false, true]:
			var off: float = k * pitch + 0.07
			for side in [-1.0, 1.0]:
				# Where the bar comes out of the edge, then a broken stub bent outward and down.
				var dir2 := Vector2(side, 0.0) if not vertical else Vector2(0.0, side)
				var base2 := Vector2(0.0, off) if not vertical else Vector2(off, 0.0)
				# March out from the centre along the bar to the hole's edge.
				var t := 0.0
				while t < r * 1.2:
					var q := base2 + dir2 * t
					if q.length() >= hole_radius(r, atan2(q.y, q.x), s):
						break
					t += 0.04
				if t >= r * 1.2 or rng.randf() < 0.3:
					continue
				var edge2 := base2 + dir2 * t
				var stub := rng.randf_range(0.15, 0.55) * minf(t, r)
				var p0 := c + mu * edge2.x + Vector3.UP * edge2.y - n * 0.12
				var bend := (-mu * dir2.x - Vector3.UP * dir2.y) * stub * 0.6 + n * stub * rng.randf_range(0.4, 0.9) + Vector3.DOWN * stub * 0.3
				var p1 := c + mu * edge2.x + Vector3.UP * edge2.y + n * 0.04
				_rod(st, p0, p1, 0.011, bar)
				_rod(st, p1, p1 + bend, 0.011, bar)
		k += 1.0


static func _break_color_finish(finish: int, wall: Color) -> Color:
	if finish == Building.Finish.BRICK:
		return Color(0.46, 0.22, 0.15)
	if finish == Building.Finish.FLAT:
		return wall.lerp(Color(0.6, 0.59, 0.56), 0.4)
	return Color(0.56, 0.55, 0.53)


## An irregular block: a box with its corners pushed about.
static func _rock(st: SurfaceTool, at: Vector3, basis: Basis, size: Vector3, col: Color, rng: RandomNumberGenerator) -> void:
	var corners: Array[Vector3] = []
	for i in 8:
		var sx := -1.0 if i & 1 == 0 else 1.0
		var sy := -1.0 if i & 2 == 0 else 1.0
		var sz := -1.0 if i & 4 == 0 else 1.0
		var p := Vector3(sx * size.x, sy * size.y, sz * size.z) * 0.5
		p *= rng.randf_range(0.7, 1.15)
		corners.append(at + basis * p)
	st.set_color(col)
	for f: Array in [[0, 2, 3, 1], [4, 5, 7, 6], [0, 1, 5, 4], [2, 6, 7, 3], [0, 4, 6, 2], [1, 3, 7, 5]]:
		st.add_vertex(corners[f[0]])
		st.add_vertex(corners[f[1]])
		st.add_vertex(corners[f[2]])
		st.add_vertex(corners[f[0]])
		st.add_vertex(corners[f[2]])
		st.add_vertex(corners[f[3]])


## A thin square rod from a to b.
static func _rod(st: SurfaceTool, a: Vector3, b: Vector3, w: float, col: Color) -> void:
	var d := (b - a)
	if d.length() < 0.01:
		return
	var z := d.normalized()
	var x := (Vector3.UP if absf(z.y) < 0.9 else Vector3.RIGHT).cross(z).normalized() * w
	var y := z.cross(x).normalized() * w
	var ring := [x + y, -x + y, -x - y, x - y]
	st.set_color(col)
	for i in 4:
		var p0: Vector3 = ring[i]
		var p1: Vector3 = ring[(i + 1) % 4]
		st.add_vertex(a + p0)
		st.add_vertex(b + p0)
		st.add_vertex(b + p1)
		st.add_vertex(a + p0)
		st.add_vertex(b + p1)
		st.add_vertex(a + p1)


static func _rim_material() -> StandardMaterial3D:
	if _rim_mat == null:
		_rim_mat = StandardMaterial3D.new()
		_rim_mat.vertex_color_use_as_albedo = true
		_rim_mat.vertex_color_is_srgb = true
		_rim_mat.roughness = 0.95
		_rim_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _rim_mat
