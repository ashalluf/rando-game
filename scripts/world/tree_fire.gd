class_name TreeFire
extends Node3D
## Fire in the trees (owner's fleet task, 2026-10-05: "what a big blast leaves behind").
##
## Every FULL chunk hands its street trees and palms over as it builds (`collect()` reads the
## batch before it is built, `attach()` keeps the built nodes; two lines in CityChunk), so this
## knows where every tree near the player stands without a single physics shape. A blast
## (`Explosion.blast()` -> BlastAftermath -> `blast()`) sets the crowns within reach alight, a
## burning car sets an overhanging crown alight (polled from CarDamage's list of fires), and a
## burning tree spreads to its neighbours. A burning crown is the car fire's flames scaled up
## (CarDamage.fire_material(), shaders/fire_puff.gdshader), burning fronds dropping, embers
## falling down the wind, black smoke and a flickering light; a third of the way through, under
## the flames, the tree is swapped for its CHARRED copy (`charred_mesh()`: the same mesh with
## burnt materials - a palm's fronds burnt back to ribs by shaders/foliage.gdshader's `burnt`, a
## street tree's leaves thinned to a few scorched ones and its bark charcoal) and stays charred:
## WorldState.charred keeps it across chunk rebuilds. Caps: `max_burning`.
##
## The node itself (one, under the scene root, made by the first fire) also gathers the fires -
## burning trees and cars - into SMOKE COLUMNS (`SmokeColumn`): a big fire sends a tall dark
## column up hundreds of metres, leaning with the wind, one draw each, `max_columns` at a time.

## Off: no tree fires, charring or smoke columns (the A/B, `TREE_FIRE=0` in the environment).
static var enabled: bool = OS.get_environment("TREE_FIRE") != "0"
## Trees burning at once (half on the web). Past it nothing new catches.
static var max_burning: int = 8
## How long a crown burns (seconds, min..max): a street tree, and a palm (fronds go fast).
static var burn_seconds: Vector2 = Vector2(36.0, 54.0)
static var palm_burn_seconds: Vector2 = Vector2(24.0, 36.0)
## Share of the burn at which the tree turns to its charred copy (hidden by the flames).
static var char_share: float = 0.32
## After the flames: how long it smoulders, smoking (seconds).
static var smoulder_seconds: float = 30.0
## A burning tree tries to set each neighbour alight every `spread_interval` seconds, with these
## odds, when their crowns are within `spread_gap` metres of each other.
static var spread_interval: float = 3.5
static var spread_odds: float = 0.3
static var spread_gap: float = 3.5
## A blast sets crowns alight within this many blast radii of its centre (crown edge), with
## odds falling from `blast_odds` at the centre to nothing at the reach.
static var blast_reach: float = 1.25
static var blast_odds: float = 0.9
## A burning car sets a crown alight when its edge is within `car_reach` metres of the car and
## the crown's foot is no higher than `car_flame_height` over it; tried every `car_interval`.
static var car_reach: float = 2.5
static var car_flame_height: float = 7.0
static var car_interval: float = 2.0
static var car_odds: float = 0.22
## Flicker light (desktop only): energy and range per metre of crown.
static var light_energy: float = 4.5
## Smoke columns at once, the weight a cluster of fires needs for one (a burning car is 1, a
## wreck still burning 0.8, a burning tree 2, a palm 1.5), and how far apart two fires can be
## and still feed the same column.
static var max_columns: int = 4
static var column_weight: float = 2.0
static var column_merge: float = 45.0
## How long a column takes to come up and to clear once the fire under it is out (seconds).
static var column_rise: float = 25.0
static var column_clear: float = 70.0

static var _chunks: Dictionary = {}
static var _burns: Dictionary = {}
static var _charred_meshes: Dictionary = {}
static var _charred_mats: Dictionary = {}
static var _node: TreeFire

var _car_t: float = 0.0
var _column_t: float = 0.0
var _columns: Array = []


# --- Registry -----------------------------------------------------------------------------------

## A street tree or palm batch key ("tree_<n>" / "palm_<n>"), not "tree_grate".
static func is_tree_key(key: String) -> bool:
	if key.begins_with("palm_"):
		return key.substr(5).is_valid_int()
	return key.begins_with("tree_") and key.substr(5).is_valid_int()


## CityChunk, just before it builds its batch: every tree and palm instance it is about to draw,
## as [key, index, transform (chunk space = true world), mesh]. FULL chunks only.
static func collect(chunk: CityChunk, batch: MultiMeshBatch) -> Array:
	if not enabled or chunk.capturing or chunk.level != CityChunk.Level.FULL:
		return []
	var out: Array = []
	var data := batch.data()
	for key: String in data:
		if not is_tree_key(key):
			continue
		var b: Dictionary = data[key]
		var xforms: Array = b.xforms
		for i in xforms.size():
			out.append([key, i, xforms[i], b.mesh])
	return out


## CityChunk, just after: keeps the trees with the built nodes, and draws the ones burnt before
## (WorldState.charred) charred at once.
static func attach(chunk: CityChunk, entries: Array, nodes: Dictionary) -> void:
	if entries.is_empty():
		return
	var trees: Array = []
	for e: Array in entries:
		trees.append(_entry(e))
	var rec := {"chunk": weakref(chunk), "trees": trees, "nodes": nodes, "charred": {}}
	_chunks[chunk.key] = rec
	var burnt: Dictionary = WorldState.charred.get(chunk.key, {})
	if burnt.is_empty():
		return
	var any := false
	for t: Dictionary in trees:
		if burnt.has(t.id):
			_mark_charred(rec, t)
			any = true
	if any:
		_rebuild_charred(rec)


static func _entry(e: Array) -> Dictionary:
	var key: String = e[0]
	var xf: Transform3D = e[2]
	var mesh: Mesh = e[3]
	var palm := key.begins_with("palm_")
	var box := mesh.get_aabb() if mesh else AABB()
	if box.size.y < 0.5:
		box = AABB(Vector3(-3.0, 0.0, -3.0), Vector3(6.0, 10.0, 6.0))
	var sc := xf.basis.get_scale()
	var s := maxf(sc.x, maxf(sc.y, sc.z))
	var c := box.get_center()
	var crown_r := maxf(box.size.x, box.size.z) * (0.36 if palm else 0.42)
	# A palm's head is at the top of its leaning trunk; a broadleaf's crown is the upper part.
	var local := Vector3(c.x, box.end.y - minf(box.size.y * 0.12, 2.2), c.z) if palm \
		else Vector3(c.x, box.position.y + box.size.y * 0.64, c.z)
	return {
		"key": key, "i": int(e[1]), "id": "%s:%d" % [key, int(e[1])], "xf": xf, "mesh": mesh,
		"palm": palm, "crown": xf * local, "r": crown_r * s, "h": box.end.y * sc.y,
		"foot": xf.origin,
	}


## The chunks' records, freed chunks dropped.
static func _live() -> Array:
	var out: Array = []
	for k: String in _chunks.keys():
		var rec: Dictionary = _chunks[k]
		var ch := (rec.chunk as WeakRef).get_ref() as CityChunk
		if ch == null or not is_instance_valid(ch) or ch.is_queued_for_deletion():
			_chunks.erase(k)
			continue
		rec.key = k
		out.append(rec)
	return out


## Every tree whose crown edge is within `reach` metres of `at` (scene space, horizontally),
## nearest first: [record, tree, distance to the crown's edge].
static func trees_near(at: Vector3, reach: float) -> Array:
	var w := WorldState.to_world(at)
	var out: Array = []
	for rec: Dictionary in _live():
		for t: Dictionary in rec.trees:
			var c: Vector3 = t.crown
			var d := Vector2(c.x - w.x, c.z - w.z).length() - float(t.r)
			if d <= reach:
				out.append([rec, t, d])
	out.sort_custom(func(a, b): return a[2] < b[2])
	return out


static func is_charred(rec: Dictionary, t: Dictionary) -> bool:
	return (rec.charred as Dictionary).has(t.id)


static func burning_count() -> int:
	for k: String in _burns.keys():
		if not is_instance_valid(_burns[k]):
			_burns.erase(k)
	return _burns.size()


## How many trees are drawn charred across the loaded chunks (tests).
static func charred_count() -> int:
	var n := 0
	for rec: Dictionary in _live():
		n += (rec.charred as Dictionary).size()
	return n


# --- Setting trees alight -----------------------------------------------------------------------

## A blast at `at` (scene space) of `radius`: the crowns in reach catch, by the odds. Returns
## how many caught.
static func blast(host: Node, at: Vector3, radius: float) -> int:
	if not enabled:
		return 0
	var reach := radius * blast_reach
	var n := 0
	for hit: Array in trees_near(at, reach):
		var t: Dictionary = hit[1]
		var crown := WorldState.to_local(t.crown)
		# A blast on a roof does not light the street tree twelve metres under it.
		if absf(crown.y - at.y) > float(t.r) + radius * 1.5 + 3.0:
			continue
		var odds := blast_odds * (1.0 - clampf(float(hit[2]) / maxf(reach, 0.01), 0.0, 1.0))
		if randf() < odds and ignite(host, hit[0], t):
			n += 1
	return n


## Sets one tree alight. False if it is burning or charred already, or too many burn.
static func ignite(host: Node, rec: Dictionary, t: Dictionary, staged: float = -1.0) -> bool:
	if not enabled or host == null or not host.is_inside_tree():
		return false
	var id := "%s|%s" % [rec.key, t.id]
	if _burns.has(id) and is_instance_valid(_burns[id]):
		return false
	if is_charred(rec, t):
		return false
	var cap := max_burning if not WeaponFX._web() else maxi(1, max_burning / 2)
	if burning_count() >= cap:
		return false
	var mgr := manager(host.get_tree())
	if mgr == null:
		return false
	var b := Burn.new()
	b.rec = rec
	b.tree = t
	b.id = id
	b.staged = staged
	mgr.add_child(b)
	_burns[id] = b
	return true


## The one TreeFire node (under the scene root, so origin shifts carry it), made on demand.
static func manager(tree: SceneTree) -> TreeFire:
	if _node != null and is_instance_valid(_node) and _node.is_inside_tree():
		return _node
	if tree == null:
		return null
	var root: Node = tree.current_scene if tree.current_scene else tree.root
	var n := TreeFire.new()
	n.name = "TreeFire"
	root.add_child(n)
	_node = n
	return n


# --- Charring -----------------------------------------------------------------------------------

static func char_tree(rec: Dictionary, t: Dictionary) -> void:
	if is_charred(rec, t):
		return
	_mark_charred(rec, t)
	var key: String = rec.key
	if not WorldState.charred.has(key):
		WorldState.charred[key] = {}
	WorldState.charred[key][t.id] = true
	_rebuild_charred(rec)


static func _mark_charred(rec: Dictionary, t: Dictionary) -> void:
	rec.charred[t.id] = t
	var node := (rec.nodes as Dictionary).get(t.key) as MultiMeshInstance3D
	if node and is_instance_valid(node):
		MultiMeshBatch.hide_instance(node, int(t.i))


## The chunk's charred trees, one MultiMesh per batch key, drawn in the chunk's own space.
static func _rebuild_charred(rec: Dictionary) -> void:
	var ch := (rec.chunk as WeakRef).get_ref() as Node3D
	if ch == null or not is_instance_valid(ch):
		return
	var by_key := {}
	for id: String in rec.charred:
		var t: Dictionary = rec.charred[id]
		if not by_key.has(t.key):
			by_key[t.key] = []
		by_key[t.key].append(t)
	for key: String in by_key:
		var list: Array = by_key[key]
		var node_name := "Charred_" + key
		var mmi := ch.get_node_or_null(node_name) as MultiMeshInstance3D
		if mmi == null:
			mmi = MultiMeshInstance3D.new()
			mmi.name = node_name
			ch.add_child(mmi)
		var src: Mesh = (list[0] as Dictionary).mesh
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = charred_mesh(src)
		mm.instance_count = list.size()
		var biggest := 0.01
		for i in list.size():
			var t: Dictionary = list[i]
			var xf: Transform3D = t.xf
			mm.set_instance_transform(i, xf)
			mm.set_instance_color(i, Color.WHITE)
			# foliage_tex reads custom.x as its thinning: all the way, with the charred
			# material's thin_max, leaves only scorched scraps.
			mm.set_instance_custom_data(i, Color(1.0, 0.5, 0.5, 0.0) if not t.palm else Color(0.0, 0.0, 0.0, 1.0))
			var sc := xf.basis.get_scale()
			biggest = maxf(biggest, maxf(sc.x, maxf(sc.y, sc.z)))
		mmi.multimesh = mm
		if src and src.has_meta("foliage_ladder"):
			mmi.lod_bias = biggest
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


## The same tree, burnt: the same surfaces (and LODs) with charred materials. Cached per mesh.
static func charred_mesh(src: Mesh) -> Mesh:
	if src == null:
		return null
	var id := src.get_instance_id()
	if _charred_meshes.has(id):
		return _charred_meshes[id]
	var m := src.duplicate() as Mesh
	if m == null:
		return src
	for s in m.get_surface_count():
		m.surface_set_material(s, charred_material(src.surface_get_material(s)))
	_charred_meshes[id] = m
	return m


static func charred_material(mat: Material) -> Material:
	if mat == null:
		return null
	var id := mat.get_instance_id()
	if _charred_mats.has(id):
		return _charred_mats[id]
	var out: Material = mat
	if mat is ShaderMaterial and (mat as ShaderMaterial).shader:
		var sm := (mat as ShaderMaterial).duplicate() as ShaderMaterial
		var path := sm.shader.resource_path
		if path.ends_with("foliage.gdshader"):
			sm.set_shader_parameter("burnt", 1.0)
		elif path.ends_with("foliage_tex.gdshader"):
			# A few scorched leaves left on black twigs: dark brown, no light through them, no
			# blossom, nearly all of the canopy gone.
			sm.set_shader_parameter("base_color", Color(0.20, 0.15, 0.11))
			sm.set_shader_parameter("thin_max", 0.88)
			sm.set_shader_parameter("hue_amount", 0.0)
			sm.set_shader_parameter("blossom_mix", 0.0)
			sm.set_shader_parameter("translucency", 0.03)
			sm.set_shader_parameter("scatter_gain", 0.0)
			sm.set_shader_parameter("leaf_specular", 0.08)
		out = sm
	elif mat is StandardMaterial3D:
		var st := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
		st.albedo_color = Color(st.albedo_color.r * 0.15, st.albedo_color.g * 0.13, st.albedo_color.b * 0.12, st.albedo_color.a)
		st.roughness = 1.0
		st.metallic_specular = 0.25
		out = st
	_charred_mats[id] = out
	return out


# --- The manager: burning cars, smoke columns ---------------------------------------------------

func _process(delta: float) -> void:
	_car_t += delta
	if _car_t >= car_interval:
		_car_t = 0.0
		_cars_light_trees()
	_column_t += delta
	if _column_t >= 1.0:
		_update_columns(_column_t)
		_column_t = 0.0


## Burning cars set the crowns over them alight.
func _cars_light_trees() -> void:
	for cd in CarDamage._burning:
		if cd == null or not is_instance_valid(cd) or not cd.on_fire():
			continue
		var car: Vehicle = cd.car
		if car == null or not is_instance_valid(car):
			continue
		var p := car.global_position
		for hit: Array in trees_near(p, car_reach + 1.5):
			var t: Dictionary = hit[1]
			var crown := WorldState.to_local(t.crown)
			var foot_of_crown := crown.y - float(t.r) * 0.8
			if foot_of_crown - p.y > car_flame_height:
				continue
			if randf() < car_odds:
				ignite(self, hit[0], t)


## Every burning tree and car, as [scene point, weight].
func _fires() -> Array:
	var out: Array = []
	for b in _burns.values():
		if is_instance_valid(b) and (b as Burn).flaming():
			out.append([(b as Burn).global_position, 1.5 if (b as Burn).tree.palm else 2.0])
	for cd in CarDamage._burning:
		if cd != null and is_instance_valid(cd) and cd.on_fire() and cd.car and is_instance_valid(cd.car):
			out.append([(cd.car as Vehicle).global_position + Vector3.UP, 1.0 if cd.state == CarDamage.State.BURNING else 0.8])
	return out


func _update_columns(dt: float) -> void:
	var fires := _fires()
	# Greedy clusters: each fire joins the first cluster whose centre is within column_merge.
	var clusters: Array = []
	for f: Array in fires:
		var p: Vector3 = f[0]
		var joined := false
		for c: Dictionary in clusters:
			if (c.at as Vector3).distance_to(p) < column_merge:
				var wsum: float = c.w + float(f[1])
				c.at = (c.at as Vector3).lerp(p, float(f[1]) / wsum)
				c.top = maxf(c.top, p.y)
				c.w = wsum
				joined = true
				break
		if not joined:
			clusters.append({"at": p, "top": p.y, "w": float(f[1])})
	for col: SmokeColumn in _columns:
		col.fed = 0.0
	for c: Dictionary in clusters:
		if float(c.w) < column_weight:
			continue
		var best: SmokeColumn = null
		var best_d := column_merge * 1.5
		for col: SmokeColumn in _columns:
			var d := col.position.distance_to(c.at)
			if d < best_d:
				best = col
				best_d = d
		if best == null:
			if _columns.size() >= max_columns:
				continue
			best = SmokeColumn.new()
			add_child(best)
			best.position = c.at
			_columns.append(best)
		best.fed = float(c.w)
		best.position = best.position.lerp(Vector3(c.at.x, c.top, c.at.z), 0.2)
	for col: SmokeColumn in _columns.duplicate():
		col.step(dt, column_rise, column_clear, _wind())
		if col.gone():
			_columns.erase(col)
			col.queue_free()


func columns() -> Array:
	return _columns


## The wind the smoke leans with (m/s, xz): the weather's rain wind if there is a Weather node.
func _wind() -> Vector2:
	var root := get_tree().current_scene if get_tree() else null
	var w := root.get_node_or_null("Weather") if root else null
	var v: Vector3 = w.get("rain_wind") if w and w.get("rain_wind") != null else Vector3(6.0, 0.0, 2.0)
	var wf := 1.0
	if w and w.get("wind_factor") != null:
		wf = clampf(float(w.get("wind_factor")), 0.3, 3.0)
	return Vector2(v.x, v.z) * wf


# --- One burning tree ---------------------------------------------------------------------------

class Burn extends Node3D:
	var rec: Dictionary
	var tree: Dictionary
	var id: String
	## >= 0: a still (staged) that starts this far into the burn, its particles preprocessed.
	var staged: float = -1.0
	var t: float = 0.0
	var life: float = 40.0
	var size: float = -1.0
	var _charred: bool = false
	var _spread_t: float = 0.0
	var _flames: CPUParticles3D
	var _billows: CPUParticles3D
	var _drops: CPUParticles3D
	var _embers: CPUParticles3D
	var _smoke: CPUParticles3D
	var _light: OmniLight3D
	var _sound: AudioStreamPlayer3D
	var _flick: float = 0.5
	var _r: float = 3.0
	var _base_db: float = 0.0

	func _ready() -> void:
		name = "TreeBurn"
		var h := hash(id)
		var span: Vector2 = TreeFire.palm_burn_seconds if tree.palm else TreeFire.burn_seconds
		life = lerpf(span.x, span.y, float(h & 1023) / 1023.0)
		_r = clampf(float(tree.r), 1.2, 7.0)
		global_position = WorldState.to_local(tree.crown)
		_build()
		if staged >= 0.0:
			t = staged * life
			if t > TreeFire.char_share * life:
				_char()
		else:
			# The crown catching: one rolling whoomph of flame.
			WeaponFX._puff_layer(WeaponFX.fx_parent(self), global_position, WeaponFX._count(16), _r * 0.8, 0.9,
					1.5, 4.0, 4.0, CarDamage._flame_ramp(), false, 180.0, 1.6, Basis(), 0.0, 0.35, 1.0, false,
					CarDamage._flame_variety(), CarDamage.fire_material())
			Sfx.play("explosion", global_position, -18.0, 1.9)
		_resize(_level())

	func flaming() -> bool:
		return t < life

	func _level() -> float:
		var k := t / life
		if k < 0.1:
			return snappedf(clampf(k / 0.1, 0.25, 1.0), 0.25)
		if k < 0.62:
			return 1.0
		return snappedf(clampf(1.0 - (k - 0.62) / 0.38, 0.25, 1.0), 0.25)

	func _build() -> void:
		var r := _r
		var pre := 2.0 if staged >= 0.0 else 0.0
		# The body of the fire: tall tongues licking up out of the whole crown.
		_flames = _flame_system("Flames", 64, Vector2(1.0, 2.2), 14.0, pre)
		_flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		_flames.emission_sphere_radius = r * 0.8
		_flames.lifetime = 1.0
		_flames.lifetime_randomness = 0.4
		_flames.spread = 16.0
		_flames.damping_min = 0.3
		_flames.damping_max = 0.9
		# Big rolling billows over the crown: what reads from a block away.
		_billows = _flame_system("Billows", 18, Vector2.ONE, 180.0, pre)
		_billows.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		_billows.emission_sphere_radius = r * 0.5
		_billows.lifetime = 1.5
		_billows.lifetime_randomness = 0.3
		_billows.spread = 20.0
		_billows.position = Vector3(0.0, r * 0.35, 0.0)
		# Burning bits falling out of it: fronds and twigs, flame all the way down.
		_drops = _flame_system("Drops", 8, Vector2(0.45, 0.8), 30.0, pre)
		_drops.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		_drops.emission_sphere_radius = r * 0.7
		_drops.lifetime = 1.8
		_drops.direction = Vector3.DOWN
		_drops.spread = 40.0
		_drops.initial_velocity_min = 0.5
		_drops.initial_velocity_max = 2.0
		_drops.gravity = Vector3(0.0, -7.0, 0.0)
		_drops.scale_amount_min = 0.5
		_drops.scale_amount_max = 1.0
		# Embers: up with the heat, then drifting down the wind.
		_embers = CPUParticles3D.new()
		_embers.name = "Embers"
		_embers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_embers.amount = WeaponFX._count(40)
		_embers.lifetime = 4.5
		_embers.lifetime_randomness = 0.5
		_embers.local_coords = false
		_embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		_embers.emission_sphere_radius = r * 0.9
		_embers.direction = Vector3.UP
		_embers.spread = 60.0
		_embers.initial_velocity_min = 1.0
		_embers.initial_velocity_max = 5.0
		_embers.damping_min = 0.6
		_embers.damping_max = 1.4
		_embers.scale_amount_min = 0.035
		_embers.scale_amount_max = 0.08
		_embers.color_ramp = WeaponFX._ramp([Color(1.4, 0.76, 0.08, 1.0), Color(1.0, 0.44, 0.04, 1.0),
			Color(0.55, 0.17, 0.02, 0.7), Color(0.2, 0.05, 0.01, 0.0)])
		var eq := QuadMesh.new()
		eq.size = Vector2.ONE
		eq.material = WeaponFX._puff_material(true)
		_embers.mesh = eq
		_embers.custom_aabb = AABB(Vector3(-40.0, -30.0, -40.0), Vector3(80.0, 60.0, 80.0))
		_embers.preprocess = pre
		add_child(_embers)
		# Smoke: black, thick where it leaves the flames, rising and spreading down the wind.
		_smoke = CPUParticles3D.new()
		_smoke.name = "Smoke"
		_smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_smoke.amount = WeaponFX._count(54)
		_smoke.lifetime = 7.0
		_smoke.lifetime_randomness = 0.15
		_smoke.local_coords = false
		_smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		_smoke.emission_sphere_radius = r * 0.6
		_smoke.position = Vector3(0.0, r * 0.9, 0.0)
		_smoke.direction = Vector3.UP
		_smoke.spread = 14.0
		_smoke.initial_velocity_min = 2.5
		_smoke.initial_velocity_max = 4.5
		_smoke.damping_min = 0.15
		_smoke.damping_max = 0.4
		_smoke.scale_amount_min = r * 0.75
		_smoke.scale_amount_max = r * 1.05
		var curve := Curve.new()
		curve.max_value = 4.0
		curve.add_point(Vector2(0.0, 0.7))
		curve.add_point(Vector2(0.3, 1.5))
		curve.add_point(Vector2(1.0, 3.4))
		_smoke.scale_amount_curve = curve
		_smoke.color_ramp = WeaponFX._ramp([Color(8.0, 3.4, 1.1, 0.6), Color(1.6, 1.15, 1.0, 0.95), Color(1, 1, 1, 0.9),
			Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.22), Color(1, 1, 1, 0.0)])
		_smoke.color = Color(0.035, 0.032, 0.03, 1.0)
		_smoke.angle_min = -180.0
		_smoke.angle_max = 180.0
		var sq := QuadMesh.new()
		sq.size = Vector2.ONE
		sq.material = WeaponFX.smoke_material()
		_smoke.mesh = sq
		_smoke.custom_aabb = AABB(Vector3(-50.0, -5.0, -50.0), Vector3(100.0, 80.0, 100.0))
		_smoke.preprocess = pre * 2.0
		add_child(_smoke)
		if not WeaponFX._web():
			_light = OmniLight3D.new()
			_light.light_color = Color(1.0, 0.47, 0.15)
			_light.omni_range = r * 3.5 + 12.0
			_light.omni_attenuation = 1.3
			_light.shadow_enabled = false
			_light.distance_fade_enabled = true
			_light.distance_fade_begin = 140.0
			_light.distance_fade_length = 40.0
			_light.position = Vector3(0.0, -r * 0.3, 0.0)
			add_child(_light)
		_sound = Sfx.loop_player("fire_loop", 3.0)
		_sound.unit_size = 10.0
		_base_db = _sound.volume_db
		add_child(_sound)
		_sound.play()
		_wind_lean()

	func _flame_system(sys_name: String, amount: int, quad: Vector2, angle: float, pre: float) -> CPUParticles3D:
		var p := CPUParticles3D.new()
		p.name = sys_name
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.amount = WeaponFX._count(amount)
		p.local_coords = false
		p.direction = Vector3.UP
		p.color_ramp = CarDamage._flame_ramp()
		p.color_initial_ramp = CarDamage._flame_variety()
		p.angle_min = -angle
		p.angle_max = angle
		var curve := Curve.new()
		curve.add_point(Vector2(0.0, 0.35))
		curve.add_point(Vector2(0.22, 1.0))
		curve.add_point(Vector2(0.6, 0.8))
		curve.add_point(Vector2(1.0, 0.3))
		p.scale_amount_curve = curve
		var q := QuadMesh.new()
		q.size = quad
		q.center_offset = Vector3(0.0, (quad.y - quad.x) * 0.5, 0.0)
		q.material = CarDamage.fire_material()
		p.mesh = q
		p.custom_aabb = AABB(Vector3(-20.0, -20.0, -20.0), Vector3(40.0, 45.0, 40.0))
		p.preprocess = pre
		add_child(p)
		return p

	## The embers and the smoke go down the wind.
	func _wind_lean() -> void:
		var wind := Vector2(6.0, 2.0)
		var mgr := get_parent() as TreeFire
		if mgr:
			wind = mgr._wind()
		_embers.gravity = Vector3(wind.x * 0.25, -1.1, wind.y * 0.25)
		_smoke.gravity = Vector3(wind.x * 0.35, 1.6, wind.y * 0.35)

	## Sets the fire's size (0..1) without restarting anything (CarDamage's rule).
	func _resize(s: float) -> void:
		if absf(s - size) < 0.01:
			return
		size = s
		var r := _r
		_flames.initial_velocity_min = 1.2 * s + 0.4
		_flames.initial_velocity_max = 3.6 * s + 0.8
		_flames.gravity = Vector3(0.3, 3.0 * s + 1.0, 0.0)
		_flames.scale_amount_min = (0.7 + 0.15 * r) * s
		_flames.scale_amount_max = (1.2 + 0.3 * r) * s
		_flames.color = Color(1, 1, 1, clampf(0.4 + 0.6 * s, 0.0, 1.0))
		_billows.initial_velocity_min = 1.5 * s
		_billows.initial_velocity_max = 3.5 * s + 0.5
		_billows.gravity = Vector3(0.3, 3.5 * s, 0.0)
		_billows.scale_amount_min = (1.0 + 0.3 * r) * s
		_billows.scale_amount_max = (1.6 + 0.45 * r) * s
		_billows.color = Color(1, 1, 1, clampf(s * 1.1 - 0.2, 0.0, 1.0))
		_drops.color = Color(1, 1, 1, clampf(s, 0.0, 1.0))
		_embers.color = Color(1, 1, 1, clampf(s * 1.2, 0.2, 1.0))
		_smoke.initial_velocity_max = 2.5 + 2.5 * s
		_smoke.scale_amount_min = r * (0.5 + 0.3 * s)
		_smoke.scale_amount_max = r * (0.7 + 0.4 * s)
		if _sound:
			_sound.volume_db = _base_db + linear_to_db(maxf(s, 0.05))

	func _char() -> void:
		if _charred:
			return
		_charred = true
		TreeFire.char_tree(rec, tree)

	func _process(delta: float) -> void:
		t += delta
		if not _charred and t > TreeFire.char_share * life:
			_char()
		if t < life:
			_resize(_level())
			_spread_t += delta
			if _spread_t >= TreeFire.spread_interval and t > life * 0.15 and t < life * 0.75:
				_spread_t = 0.0
				_spread()
			if _light:
				_flick = lerpf(_flick, randf(), 1.0 - exp(-delta * 12.0))
				var ms := Time.get_ticks_msec() * 0.001
				_light.light_energy = TreeFire.light_energy * size * (0.6 + 0.55 * _flick + 0.1 * sin(ms * 23.0)) * (_r / 3.0)
		elif _flames.emitting:
			# The flames out; it smoulders a while, thinning.
			for p in [_flames, _billows, _drops, _embers]:
				(p as CPUParticles3D).emitting = false
			_smoke.color = Color(0.09, 0.085, 0.08, 0.55)
			_smoke.initial_velocity_max = 2.0
			if _light:
				_light.queue_free()
				_light = null
			if _sound:
				_sound.queue_free()
				_sound = null
		elif t > life + TreeFire.smoulder_seconds:
			_smoke.emitting = false
			if t > life + TreeFire.smoulder_seconds + 8.0:
				queue_free()

	## Tries each neighbour whose crown is close enough.
	func _spread() -> void:
		for hit: Array in TreeFire.trees_near(global_position, _r + TreeFire.spread_gap):
			var other: Dictionary = hit[1]
			if other.id == tree.id:
				continue
			if randf() < TreeFire.spread_odds:
				TreeFire.ignite(self, hit[0], other)
