class_name CityChunk
extends Node3D
## One city block plus the road on its +X side, the road on its +Z side, and the intersection at
## that corner. FULL level has everything: buildings, props, collision, physics trash cans.
## LOD level is just slabs and colored boxes for the far skyline, with plain box collision on
## buildings and full terrain collision so nothing drives into a far building or through a hill.
## Children are placed at true world coordinates; the chunk node sits at -WorldState.world_offset.

enum Level { FULL, LOD }

const BUILDING_SCENE := preload("res://scenes/props/building.tscn")
## Extra physics layer bit carried only by hill terrain, so "is terrain above me?" rays
## are not blocked by a pad, wall or roof on the way up.
const TERRAIN_LAYER := 16
const ROAD_TOP := 0.1
const SIDEWALK_TOP := 0.25
const PROP_HEALTH := {"lamp": 30.0, "hydrant": 20.0, "bench": 20.0, "stop_sign": 10.0, "signal": 60.0}

var plan: CityPlan
var ix: int = 0
var iz: int = 0
var level: Level = Level.FULL
var key: String = ""
var zone: MacroMap.Zone = MacroMap.Zone.CITY
## Colors and spacing from the streamer's exports.
var style: Dictionary = {}

var building_count: int = 0
var prop_records: Array[Dictionary] = []
## Landmark ids this chunk built in detail (the streamer hides their far versions meanwhile).
var built_landmarks: Array[String] = []

## Parked cars this chunk spawned. They live under the city root (a driven car must outlive its
## chunk), so the chunk frees the ones nobody drove when it unloads.
var _cars: Array[Node] = []
var _batch := MultiMeshBatch.new()
var _mm_nodes: Dictionary = {}
var _statics: StreetProps
var _prop_counter: int = 0


func build() -> void:
	key = "%d,%d" % [ix, iz]
	name = "Chunk_" + key
	position = -WorldState.world_offset
	if level == Level.FULL:
		_statics = StreetProps.new()
		_statics.chunk = self
		add_child(_statics)
	var block := plan.block(ix, iz)
	zone = plan.zone_at((block.rect as Rect2).get_center())
	match zone:
		MacroMap.Zone.OCEAN:
			_build_water()
		MacroMap.Zone.HILLS:
			_build_terrain()
			_build_hill_roads()
			_build_mansions()
		MacroMap.Zone.BEACH:
			_build_roads(block)
			_build_beach(block)
		MacroMap.Zone.AIRPORT:
			_build_airport()
		MacroMap.Zone.PORT:
			_build_port(block)
		_:
			_build_roads(block)
			_build_block(block)
			if level == Level.FULL:
				_build_intersection(plan.intersection(ix + 1, iz + 1))
	if level == Level.FULL and plan.macro:
		for lm in Landmarks.in_rect(owned_rect()):
			Landmarks.build(lm, self, _statics, plan, true)
			built_landmarks.append(lm.id)
	_mm_nodes = _batch.build(self)


## The whole area this chunk owns: its block plus the roads on its +X and +Z sides.
func owned_rect() -> Rect2:
	var x0 := plan.road_pos(CityPlan.AXIS_X, ix) + plan.road_width(CityPlan.AXIS_X, ix) * 0.5
	var x1 := plan.road_pos(CityPlan.AXIS_X, ix + 1) + plan.road_width(CityPlan.AXIS_X, ix + 1) * 0.5
	var z0 := plan.road_pos(CityPlan.AXIS_Z, iz) + plan.road_width(CityPlan.AXIS_Z, iz) * 0.5
	var z1 := plan.road_pos(CityPlan.AXIS_Z, iz + 1) + plan.road_width(CityPlan.AXIS_Z, iz + 1) * 0.5
	return Rect2(x0, z0, x1 - x0, z1 - z0)


# --- Airport and port ------------------------------------------------------------------

func _build_airport() -> void:
	var area := owned_rect()
	var c := area.get_center()
	_add_slab(Vector3(c.x, 0.05, c.y), Vector3(area.size.x, 0.1, area.size.y), style.tarmac, level == Level.FULL, PropFactory.pbr("asphalt", 8.0, Color(0.9, 0.9, 0.9)))
	var macro: MacroMap = plan.macro
	for rz in macro.runway_zs:
		var band := Rect2(area.position.x, rz - macro.runway_width * 0.5, area.size.x, macro.runway_width)
		var strip := band.intersection(area)
		if strip.size.y <= 0.0:
			continue
		var sc := strip.get_center()
		var runway := MeshInstance3D.new()
		runway.name = "Runway"
		var box := BoxMesh.new()
		box.size = Vector3(strip.size.x, 0.04, strip.size.y)
		runway.mesh = box
		runway.material_override = PropFactory.material(style.runway, 0.95)
		runway.position = Vector3(sc.x, 0.12, sc.y)
		add_child(runway)
		if level != Level.FULL:
			continue
		# Center line dashes and edge lines.
		var x := strip.position.x + 6.0
		while x < strip.end.x - 6.0:
			_batch.add("stripe", PropFactory.stripe(), Transform3D(Basis(Vector3.UP, PI * 0.5).scaled(Vector3(1.0, 1.0, 3.0)), Vector3(x, 0.15, rz)))
			x += 24.0
		for side: float in [-1.0, 1.0]:
			_batch.add("stripe", PropFactory.stripe(), Transform3D(Basis(Vector3.UP, PI * 0.5).scaled(Vector3(1.0, 1.0, strip.size.x / 3.0)), Vector3(sc.x, 0.15, rz + side * (macro.runway_width * 0.5 - 1.0))))
	if level == Level.FULL:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([ix, iz, 5])
		for i in 3:
			var p := Vector2(rng.randf_range(area.position.x + 5.0, area.end.x - 5.0), area.position.y + 4.0)
			if not _on_runway(p) and not _near_apron(p):
				_add_lamp(Vector3(p.x, 0.1, p.y))
		# Flyable jets on the apron, owned like parked cars (city root, freed with the chunk
		# unless someone flew them away).
		for spot in macro.apron_spots:
			var sp: Vector2 = spot[0]
			if not area.has_point(sp):
				continue
			var jet := Aircraft.new()
			jet.setup_aircraft(spot[1] as Aircraft.Kind)
			var holder: Node = get_parent() if get_parent() else self
			jet.position = WorldState.to_local(Vector3(sp.x, 1.0, sp.y)) if holder != self else Vector3(sp.x, 1.0, sp.y)
			jet.rotation.y = -PI * 0.5
			holder.add_child(jet)
			_cars.append(jet)


func _near_apron(p: Vector2) -> bool:
	for spot in plan.macro.apron_spots:
		if (spot[0] as Vector2).distance_to(p) < 45.0:
			return true
	return false


func _on_runway(p: Vector2) -> bool:
	for rz in plan.macro.runway_zs:
		if absf(p.y - rz) < plan.macro.runway_width * 0.5 + 6.0:
			return true
	return false


func _build_port(block: Dictionary) -> void:
	var area := owned_rect()
	var c := area.get_center()
	_add_slab(Vector3(c.x, 0.1, c.y), Vector3(area.size.x, 0.2, area.size.y), style.concrete, level == Level.FULL, PropFactory.pbr("concrete", 5.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = block.seed
	# Container stacks in rows, colored per box.
	var colors := [Color(0.8, 0.25, 0.2), Color(0.2, 0.45, 0.75), Color(0.85, 0.6, 0.15), Color(0.3, 0.6, 0.35), Color(0.6, 0.6, 0.62), Color(0.55, 0.3, 0.55)]
	var rows := int(area.size.y / 9.0)
	var cols := int(area.size.x / 14.0)
	var origin := Vector2(area.position.x + 8.0, area.position.y + 6.0)
	for r in rows:
		if rng.randf() < 0.3:
			continue # an empty lane for trucks
		for col in cols:
			if rng.randf() < 0.35:
				continue
			var height := rng.randi_range(1, 3)
			var p := origin + Vector2(col * 14.0, r * 9.0)
			if p.x + 6.0 > area.end.x - 4.0 or p.y + 1.2 > area.end.y - 4.0:
				continue
			for h in height:
				var col_color: Color = colors[rng.randi() % colors.size()]
				_batch.add("container", PropFactory.container(), Transform3D(Basis(), Vector3(p.x, 0.2 + 1.3 + h * 2.6, p.y)), col_color)
			if level == Level.FULL:
				_add_shape(Vector3(12.0, 2.6 * height, 2.4), Vector3(p.x, 0.2 + 1.3 * height, p.y))
	# A gantry crane on chunks that touch the harbor.
	var macro: MacroMap = plan.macro
	if area.end.y >= macro.harbor_rect.position.y - 2.0 and level == Level.FULL:
		_build_crane(Vector3(c.x, 0.2, area.end.y - 18.0))
	if level == Level.FULL:
		for i in 2:
			_add_lamp(Vector3(area.position.x + 4.0 + i * (area.size.x - 8.0), 0.2, area.position.y + 4.0))


func _build_crane(at: Vector3) -> void:
	var steel := Color(0.85, 0.45, 0.15)
	var h := 40.0
	for dx: float in [-14.0, 14.0]:
		for dz: float in [-6.0, 6.0]:
			_add_slab(at + Vector3(dx, h * 0.5, dz), Vector3(1.4, h, 1.4), steel)
	_add_slab(at + Vector3(0.0, h + 0.5, -6.0), Vector3(30.0, 1.5, 1.5), steel)
	_add_slab(at + Vector3(0.0, h + 0.5, 6.0), Vector3(30.0, 1.5, 1.5), steel)
	# Boom out over the water (+Z), and a trolley with a hanging container.
	_add_slab(at + Vector3(0.0, h + 0.5, 30.0), Vector3(3.0, 2.0, 60.0), steel)
	_add_slab(at + Vector3(0.0, h - 1.5, 26.0), Vector3(4.0, 1.5, 4.0), Color(0.3, 0.3, 0.32))
	_add_slab(at + Vector3(0.0, h - 9.0, 26.0), Vector3(0.2, 14.0, 0.2), Color(0.2, 0.2, 0.2), false)
	_batch.add("container", PropFactory.container(), Transform3D(Basis(Vector3.UP, PI * 0.5), at + Vector3(0.0, h - 17.0, 26.0)), Color(0.2, 0.45, 0.75))
	_add_slab(at + Vector3(0.0, 4.0, 0.0), Vector3(6.0, 8.0, 5.0), Color(0.3, 0.3, 0.32))


# --- Ocean, beach, hills ---------------------------------------------------------------

func _build_water() -> void:
	var area := owned_rect()
	var c := area.get_center()
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(area.size.x, 1.0, area.size.y)
	mesh.mesh = box
	mesh.material_override = PropFactory.material(style.ocean, 0.15)
	# Surface at +0.15 so it sits above the ground follower plane (y = 0), which otherwise
	# shows through as grass over the whole sea.
	mesh.position = Vector3(c.x, -0.35, c.y)
	add_child(mesh)
	if level == Level.FULL:
		_add_shape(box.size, mesh.position)


func _build_beach(block: Dictionary) -> void:
	var rect: Rect2 = block.rect
	var c := rect.get_center()
	_add_slab(Vector3(c.x, 0.0, c.y), Vector3(rect.size.x, 0.4, rect.size.y), style.sand, false, PropFactory.pbr("sand", 5.0, Color(1.0, 0.95, 0.85)))
	if level != Level.FULL:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = block.seed
	for i in rng.randi_range(6, 14):
		var p := Vector2(rng.randf_range(rect.position.x + 4.0, rect.end.x - 4.0), rng.randf_range(rect.position.y + 4.0, rect.end.y - 4.0))
		_add_palm(Vector3(p.x, 0.2, p.y), rng)
	if rng.randf() < 0.6:
		var p := Vector2(rng.randf_range(rect.position.x + 8.0, rect.end.x - 8.0), rng.randf_range(rect.position.y + 8.0, rect.end.y - 8.0))
		_add_lifeguard_tower(Vector3(p.x, 0.2, p.y), rng.randf_range(0.0, TAU))


func _add_palm(at: Vector3, rng: RandomNumberGenerator) -> void:
	var s := rng.randf_range(0.8, 1.3)
	var lean := Basis(Vector3(cos(rng.randf() * TAU), 0.0, sin(rng.randf() * TAU)).normalized(), rng.randf_range(0.0, 0.12))
	var top := at + lean * Vector3(0.0, 7.0 * s, 0.0)
	_batch.add("palm_trunk", PropFactory.palm_trunk(), Transform3D(lean.scaled(Vector3(s, s, s)), at + lean * Vector3(0.0, 3.5 * s, 0.0)))
	var fronds := rng.randi_range(6, 8)
	for i in fronds:
		var yaw := TAU * i / fronds + rng.randf_range(-0.2, 0.2)
		var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -0.5 + rng.randf_range(-0.15, 0.15))
		_batch.add("palm_frond", PropFactory.palm_frond(), Transform3D(basis.scaled(Vector3(s, s, s)), top + basis * Vector3(0.0, 0.0, -1.5 * s)), Color(0.9 + rng.randf() * 0.2, 1.0, 0.9))
	for i in 3:
		_batch.add("coconut", PropFactory.coconut(), Transform3D(Basis().scaled(Vector3.ONE * 0.35 * s), top + Vector3(rng.randf_range(-0.3, 0.3), -0.3, rng.randf_range(-0.3, 0.3))))
	_add_shape(Vector3(0.5, 7.0 * s, 0.5), at + Vector3(0.0, 3.5 * s, 0.0))


func _add_lifeguard_tower(at: Vector3, yaw: float) -> void:
	var basis := Basis(Vector3.UP, yaw)
	for dx: float in [-1.2, 1.2]:
		for dz: float in [-1.2, 1.2]:
			_batch.add("lifeguard_leg", PropFactory.lifeguard_leg(), Transform3D(basis, at + basis * Vector3(dx, 1.3, dz)))
	_batch.add("lifeguard_cabin", PropFactory.lifeguard_cabin(), Transform3D(basis, at + Vector3(0.0, 3.8, 0.0)))
	_batch.add("lifeguard_ramp", PropFactory.lifeguard_ramp(), Transform3D(basis * Basis(Vector3.RIGHT, -0.55), at + basis * Vector3(0.0, 1.3, 3.2)))
	_add_shape(Vector3(3.0, 5.0, 3.0), at + Vector3(0.0, 2.5, 0.0), yaw)


## Terrain tile over the whole owned area, colored by height, with heightmap collision.
func _build_terrain() -> void:
	var area := owned_rect()
	# Finer tile where a hill road passes, so the carved road bed reads cleanly.
	var has_road := _hill_segments().size() > 0
	var n := (28 if has_road else 14) if level == Level.FULL else 6
	var heights := PackedFloat32Array()
	heights.resize((n + 1) * (n + 1))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in n + 1:
		for i in n + 1:
			var x := area.position.x + area.size.x * i / n
			var z := area.position.y + area.size.y * j / n
			var h := plan.height_at(Vector2(x, z))
			heights[j * (n + 1) + i] = h
			var t := clampf((h - 20.0) / 160.0, 0.0, 1.0)
			st.set_color(Color(t, 0.0, 0.0, 1.0))
			st.add_vertex(Vector3(x, h, z))
	for j in n:
		for i in n:
			var a := j * (n + 1) + i
			var b := a + 1
			var c := a + (n + 1)
			var d := c + 1
			st.add_index(a)
			st.add_index(b)
			st.add_index(c)
			st.add_index(b)
			st.add_index(d)
			st.add_index(c)
	st.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.name = "Terrain"
	mesh.mesh = st.commit()
	mesh.material_override = PropFactory.terrain_material()
	add_child(mesh)
	# Collision at full resolution on every level, so a fast car never outruns the detailed
	# chunks and drops through a far hill. The body is tagged so the player can tell "under the
	# terrain" from "under a bridge".
	var cn := 28 if (has_road and level == Level.FULL) else 14
	var cheights := heights
	if n != cn:
		cheights = PackedFloat32Array()
		cheights.resize((cn + 1) * (cn + 1))
		for j in cn + 1:
			for i in cn + 1:
				cheights[j * (cn + 1) + i] = plan.height_at(Vector2(area.position.x + area.size.x * i / cn, area.position.y + area.size.y * j / cn))
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	body.collision_layer = 1 | TERRAIN_LAYER
	body.collision_mask = 0
	body.set_meta("terrain", true)
	var shape := CollisionShape3D.new()
	var hm := HeightMapShape3D.new()
	hm.map_width = cn + 1
	hm.map_depth = cn + 1
	hm.map_data = cheights
	shape.shape = hm
	var c := area.get_center()
	shape.transform = Transform3D(Basis().scaled(Vector3(area.size.x / cn, 1.0, area.size.y / cn)), Vector3(c.x, 0.0, c.y))
	body.add_child(shape)
	add_child(body)


func _hill_segments() -> Array[Dictionary]:
	if plan.macro == null or plan.macro.hill_roads == null:
		return []
	return plan.macro.hill_roads.segments_in(owned_rect())


## Asphalt strips following the carved road beds, clipped to this chunk.
func _build_hill_roads() -> void:
	var segs := _hill_segments()
	if segs.is_empty():
		return
	var area := owned_rect()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var quads := 0
	for seg in segs:
		var a: Vector2 = seg.a
		var b: Vector2 = seg.b
		var seg_len := a.distance_to(b)
		if seg_len < 0.5:
			continue
		var pieces := maxi(1, ceili(seg_len / 6.0))
		var dir := (b - a) / seg_len
		var half: float = seg.width * 0.5
		var normal := Vector2(-dir.y, dir.x) * half
		for k in pieces:
			var t0 := float(k) / pieces
			var t1 := float(k + 1) / pieces
			var c0 := a.lerp(b, t0)
			var c1 := a.lerp(b, t1)
			if not area.has_point(c0.lerp(c1, 0.5)):
				continue
			var h0 := plan.height_at(c0) + 0.12
			var h1 := plan.height_at(c1) + 0.12
			var v0 := Vector3(c0.x - normal.x, h0, c0.y - normal.y)
			var v1 := Vector3(c0.x + normal.x, h0, c0.y + normal.y)
			var v2 := Vector3(c1.x + normal.x, h1, c1.y + normal.y)
			var v3 := Vector3(c1.x - normal.x, h1, c1.y - normal.y)
			for v in [v0, v2, v1, v0, v3, v2]:
				st.add_vertex(v)
			quads += 1
	if quads == 0:
		return
	st.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.name = "HillRoad"
	mesh.mesh = st.commit()
	mesh.material_override = PropFactory.pbr("asphalt", 7.0, Color(0.7, 0.7, 0.72))
	add_child(mesh)


## Hillside estates: a flat pad cut into the slope with a house, a pool, palms and a low wall.
func _build_mansions() -> void:
	if plan.macro == null or plan.macro.hill_roads == null:
		return
	for m in plan.macro.hill_roads.mansions_in(owned_rect()):
		var pos: Vector2 = m.pos
		var h: float = m.height
		var yaw: float = m.yaw
		var rng := RandomNumberGenerator.new()
		rng.seed = m.seed
		var basis := Basis(Vector3.UP, yaw)
		var at := Vector3(pos.x, h, pos.y)
		# Pad.
		var pad := MeshInstance3D.new()
		var pad_box := BoxMesh.new()
		pad_box.size = Vector3(30.0, 0.4, 26.0)
		pad.mesh = pad_box
		pad.material_override = PropFactory.pbr("paving", 4.0, Color(0.9, 0.88, 0.84))
		pad.position = at + Vector3(0.0, 0.2, 0.0)
		pad.rotation.y = yaw
		add_child(pad)
		if level != Level.FULL:
			# Far: the pad and a house box in a warm tone.
			_batch.add("lod_box", PropFactory.unit_box(), Transform3D(basis.scaled(Vector3(18.0, 7.5, 13.0)), at + basis * Vector3(0.0, 4.15, -4.0)), Color(0.92, 0.88, 0.8))
			continue
		_add_shape(Vector3(30.0, 0.4, 26.0), at + Vector3(0.0, 0.2, 0.0), yaw)
		# House: a wide low villa on the back half of the pad.
		var house := BUILDING_SCENE.instantiate() as Building
		house.seed = m.seed
		house.lot_size = Vector2(18.0, 13.0)
		house.min_height = 6.5
		house.max_height = 9.5
		house.force_shape = Building.Shape.SLAB
		house.finish_options.assign([Building.Finish.FLAT, Building.Finish.FLAT, Building.Finish.BRICK])
		house.allow_storefront = false
		house.lit_ratio_range = Vector2(0.3, 0.6)
		house.position = at + basis * Vector3(0.0, 0.4, -4.0)
		house.rotation.y = yaw
		add_child(house)
		building_count += 1
		# Pool on the front half, with a pale rim.
		var pool_c := at + basis * Vector3(rng.randf_range(-4.0, 4.0), 0.4, 6.5)
		var rim := MeshInstance3D.new()
		var rim_box := BoxMesh.new()
		rim_box.size = Vector3(9.0, 0.12, 5.6)
		rim.mesh = rim_box
		rim.material_override = PropFactory.material(Color(0.93, 0.92, 0.88), 0.8)
		rim.position = pool_c + Vector3(0.0, 0.06, 0.0)
		rim.rotation.y = yaw
		add_child(rim)
		var water := MeshInstance3D.new()
		var water_box := BoxMesh.new()
		water_box.size = Vector3(8.0, 0.1, 4.6)
		water.mesh = water_box
		var wmat := StandardMaterial3D.new()
		wmat.albedo_color = Color(0.25, 0.65, 0.85)
		wmat.roughness = 0.05
		wmat.metallic = 0.2
		water.material_override = wmat
		water.position = pool_c + Vector3(0.0, 0.13, 0.0)
		water.rotation.y = yaw
		add_child(water)
		# Low wall around the pad and a few palms.
		for side: Vector3 in [Vector3(0.0, 0.0, 13.0), Vector3(0.0, 0.0, -13.0), Vector3(15.0, 0.0, 0.0), Vector3(-15.0, 0.0, 0.0)]:
			var along_x := side.z != 0.0
			var wsize := Vector3(30.0, 1.0, 0.4) if along_x else Vector3(0.4, 1.0, 26.0)
			var wpos := at + basis * (side + Vector3(0.0, 0.9, 0.0))
			var wall := MeshInstance3D.new()
			var wbox := BoxMesh.new()
			wbox.size = wsize
			wall.mesh = wbox
			wall.material_override = PropFactory.material(Color(0.85, 0.82, 0.76), 0.9)
			wall.position = wpos
			wall.rotation.y = yaw
			add_child(wall)
			_add_shape(wsize, wpos, yaw)
		for i in rng.randi_range(2, 4):
			var local := Vector3(rng.randf_range(-13.0, 13.0), 0.4, rng.randf_range(9.0, 12.0) * (1.0 if rng.randf() < 0.7 else -1.0))
			_add_palm(at + basis * local, rng)


func has_prop(id: String) -> bool:
	for record in prop_records:
		if record.id == id:
			return true
	return false


# --- Roads -----------------------------------------------------------------------------

func _build_roads(block: Dictionary) -> void:
	var rect: Rect2 = block.rect
	var asphalt: Color = style.asphalt
	# Vertical road on the +X side, spanning this block's Z range.
	var road_mat := PropFactory.pbr("asphalt", 7.0, Color(0.75, 0.75, 0.78))
	var rx := plan.road_pos(CityPlan.AXIS_X, ix + 1)
	var wx := plan.road_width(CityPlan.AXIS_X, ix + 1)
	_add_slab(Vector3(rx, ROAD_TOP * 0.5, rect.get_center().y), Vector3(wx, ROAD_TOP, rect.size.y), asphalt, true, road_mat)
	# Horizontal road on the +Z side, spanning this block's X range.
	var rz := plan.road_pos(CityPlan.AXIS_Z, iz + 1)
	var wz := plan.road_width(CityPlan.AXIS_Z, iz + 1)
	_add_slab(Vector3(rect.get_center().x, ROAD_TOP * 0.5, rz), Vector3(rect.size.x, ROAD_TOP, wz), asphalt, true, road_mat)
	# The intersection square at the +X +Z corner.
	_add_slab(Vector3(rx, ROAD_TOP * 0.5, rz), Vector3(wx, ROAD_TOP, wz), asphalt, true, road_mat)
	if level == Level.FULL:
		_mark_road(true, rx, wx, rect.position.y, rect.end.y)
		_mark_road(false, rz, wz, rect.position.x, rect.end.x)


## Center-line markings along one block: dashed yellow on streets, double solid on avenues.
func _mark_road(along_z: bool, center: float, width: float, a: float, b: float) -> void:
	a += 3.0
	b -= 3.0
	if b - a < 4.0:
		return
	var avenue := width >= plan.avenue_width - 0.1
	var yaw := 0.0 if along_z else PI * 0.5
	if avenue:
		for side: float in [-0.3, 0.3]:
			var mid := (a + b) * 0.5
			var pos := Vector3(center + side, ROAD_TOP + 0.01, mid) if along_z else Vector3(mid, ROAD_TOP + 0.01, center + side)
			_batch.add("dash", PropFactory.dash(), Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(1.0, 1.0, (b - a) / 3.0)), pos))
	else:
		var t := a + 1.5
		while t < b - 1.5:
			var pos := Vector3(center, ROAD_TOP + 0.01, t) if along_z else Vector3(t, ROAD_TOP + 0.01, center)
			_batch.add("dash", PropFactory.dash(), Transform3D(Basis(Vector3.UP, yaw), pos))
			t += 6.0


# --- Block -----------------------------------------------------------------------------

func _build_block(block: Dictionary) -> void:
	var rect: Rect2 = block.rect
	var district: CityPlan.District = block.district
	var params: Dictionary = CityPlan.DISTRICTS[district]
	var rng := RandomNumberGenerator.new()
	rng.seed = block.seed
	var center := rect.get_center()
	_add_slab(Vector3(center.x, SIDEWALK_TOP * 0.5, center.y), Vector3(rect.size.x, SIDEWALK_TOP, rect.size.y), style.sidewalk, true, PropFactory.pbr("paving", 3.0, Color(0.95, 0.94, 0.92)))
	match block.kind:
		CityPlan.BlockKind.PARK:
			_build_park(rect, rng)
		CityPlan.BlockKind.PLAZA:
			_build_plaza(rect, rng)
		_:
			_build_lots(rect, params, rng)
	if level == Level.FULL:
		_build_sidewalk_props(rect, params, rng)
		_park_cars(rect, rng)
		_spawn_pedestrians(rect, rng)


func _spawn_pedestrians(rect: Rect2, rng: RandomNumberGenerator) -> void:
	var count: int = style.pedestrians_per_block
	if count <= 0:
		return
	var existing := 0
	for n in get_tree().get_nodes_in_group("pedestrian"):
		# A pedestrian inside a chunk that is being freed is not flagged itself; check its chunk.
		var parent := n.get_parent()
		if n.is_queued_for_deletion() or (parent and parent.is_queued_for_deletion()):
			continue
		existing += 1
	var cap: int = style.max_pedestrians
	for i in count:
		if existing >= cap:
			return
		var ped := Pedestrian.new()
		ped.setup(rect, plan.sidewalk_width, rng.randi())
		var start := ped._random_ring_point(plan.sidewalk_width)
		ped.position = Vector3(start.x, SIDEWALK_TOP + 0.1, start.y)
		add_child(ped)
		existing += 1


## Parked cars in the lanes of this chunk's two roads, nose along the road.
func _park_cars(rect: Rect2, rng: RandomNumberGenerator) -> void:
	var max_cars: int = style.cars_per_block
	if max_cars <= 0:
		return
	var rx := plan.road_pos(CityPlan.AXIS_X, ix + 1)
	var wx := plan.road_width(CityPlan.AXIS_X, ix + 1)
	var rz := plan.road_pos(CityPlan.AXIS_Z, iz + 1)
	var wz := plan.road_width(CityPlan.AXIS_Z, iz + 1)
	var spots: Array = []
	for side: float in [-1.0, 1.0]:
		var x := rx + side * (wx * 0.5 - 2.2)
		var t := rect.position.y + 8.0
		while t < rect.end.y - 8.0:
			spots.append([Vector3(x, 0.4, t), 0.0, side])
			t += 8.0
		var z := rz + side * (wz * 0.5 - 2.2)
		t = rect.position.x + 8.0
		while t < rect.end.x - 8.0:
			spots.append([Vector3(t, 0.4, z), PI * 0.5, side])
			t += 8.0
	spots.shuffle()
	var count := 0
	for spot in spots:
		if count >= max_cars or rng.randf() > 0.35 or not PhysicsBudget.can_spawn():
			continue
		var car := Vehicle.random_car(rng)
		var holder: Node = get_parent() if get_parent() else self
		car.position = WorldState.to_local(spot[0]) if holder != self else spot[0]
		car.rotation.y = spot[1] + (PI if rng.randf() < 0.5 else 0.0)
		holder.add_child(car)
		_cars.append(car)
		count += 1


func _exit_tree() -> void:
	for car in _cars:
		if is_instance_valid(car) and not car.has_meta("driven"):
			car.queue_free()
	_cars.clear()


## Lot layout is shared by FULL and LOD so both see the same buildings.
func _lots(rect: Rect2, params: Dictionary, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var inner := rect.grow(-plan.sidewalk_width)
	var lot_range: Vector2 = params.lot
	var lot_w := rng.randf_range(lot_range.x, lot_range.y)
	var lot_d := rng.randf_range(lot_range.x, lot_range.y)
	var nx := maxi(1, floori(inner.size.x / lot_w))
	var nz := maxi(1, floori(inner.size.y / lot_d))
	var cell := Vector2(inner.size.x / nx, inner.size.y / nz)
	var gap_range: Vector2 = params.gap
	# Landmarks reserve their footprint; lots there are skipped (after using the rng, so that
	# FULL and LOD builds stay in step).
	var blocked: Array[Rect2] = []
	if plan.macro:
		for lm in Landmarks.all():
			var r: float = lm.radius
			var foot := Rect2((lm.anchor as Vector2) - Vector2(r, r), Vector2(r * 2.0, r * 2.0))
			if foot.intersects(rect):
				blocked.append(foot)
	var lots: Array[Dictionary] = []
	for lx in nx:
		for lz in nz:
			var edge := lx == 0 or lz == 0 or lx == nx - 1 or lz == nz - 1
			if not edge and rng.randf() < params.courtyard:
				continue
			var gap := rng.randf_range(gap_range.x, gap_range.y)
			var lot_size := cell - Vector2(gap, gap)
			if lot_size.x < 6.0 or lot_size.y < 6.0:
				continue
			var lot_center := inner.position + Vector2(cell.x * (lx + 0.5), cell.y * (lz + 0.5))
			var lot_seed := rng.randi()
			var lot_rect := Rect2(lot_center - lot_size * 0.5, lot_size)
			var hit := false
			for b in blocked:
				if b.intersects(lot_rect):
					hit = true
			if hit:
				continue
			lots.append({"seed": lot_seed, "size": lot_size, "center": lot_center})
	return lots


func _build_lots(rect: Rect2, params: Dictionary, rng: RandomNumberGenerator) -> void:
	var heights: Vector2 = params.height
	for lot in _lots(rect, params, rng):
		var center: Vector2 = lot.center
		var building := BUILDING_SCENE.instantiate() as Building
		building.seed = lot.seed
		building.lot_size = lot.size
		# Downtown core: the skyline climbs toward the center (supertalls in the middle).
		var boost := plan.macro.skyline_boost(center) if plan.macro else 0.0
		building.min_height = lerpf(heights.x, heights.x * 2.0, boost)
		building.max_height = lerpf(heights.y, heights.y * 2.2, boost)
		building.lit_ratio_range = params.lit
		building.shape_options.assign(params.shapes)
		building.finish_options.assign(params.finishes)
		building.position = Vector3(center.x, SIDEWALK_TOP, center.y)
		if level == Level.FULL:
			add_child(building)
			building_count += 1
		else:
			# Far away: just the boxes, in the facade color, no props. They do get plain box
			# collision so a fast car cannot drive into a footprint and get shot through the
			# floor when the detailed building appears around it.
			building.plan_only()
			for part in building.parts:
				var size: Vector3 = part.size
				var part_center: Vector3 = part.center
				var xform := Transform3D(Basis().scaled(size), building.position + part_center)
				_batch.add("lod_box", PropFactory.unit_box(), xform, building.facade_color)
				_add_lod_shape(size, building.position + part_center)
			building.free()
			building_count += 1


var _lod_body: StaticBody3D


func _add_lod_shape(size: Vector3, pos: Vector3) -> void:
	if _lod_body == null:
		_lod_body = StaticBody3D.new()
		_lod_body.name = "LodBuildings"
		_lod_body.collision_layer = 1
		_lod_body.collision_mask = 0
		add_child(_lod_body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = pos
	_lod_body.add_child(shape)


func _build_park(rect: Rect2, rng: RandomNumberGenerator) -> void:
	var inner := rect.grow(-2.0)
	var center := inner.get_center()
	_add_slab(Vector3(center.x, SIDEWALK_TOP + 0.02, center.y), Vector3(inner.size.x, 0.04, inner.size.y), style.grass, false, PropFactory.pbr("grass", 5.0, Color(0.8, 0.95, 0.75)))
	if level != Level.FULL:
		return
	var path_w := 3.0
	_add_slab(Vector3(center.x, SIDEWALK_TOP + 0.04, center.y), Vector3(inner.size.x, 0.02, path_w), style.path, false)
	_add_slab(Vector3(center.x, SIDEWALK_TOP + 0.04, center.y), Vector3(path_w, 0.02, inner.size.y), style.path, false)
	for i in rng.randi_range(10, 24):
		var p := Vector2(rng.randf_range(inner.position.x + 3.0, inner.end.x - 3.0), rng.randf_range(inner.position.y + 3.0, inner.end.y - 3.0))
		if absf(p.x - center.x) < path_w or absf(p.y - center.y) < path_w:
			continue
		_add_tree(Vector3(p.x, SIDEWALK_TOP, p.y), rng)
	for i in rng.randi_range(4, 8):
		var along_x := rng.randf() < 0.5
		var t := rng.randf_range(-0.4, 0.4)
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var p := center + (Vector2(inner.size.x * t, side * (path_w * 0.5 + 0.6)) if along_x else Vector2(side * (path_w * 0.5 + 0.6), inner.size.y * t))
		_add_bench(Vector3(p.x, SIDEWALK_TOP + 0.04, p.y), 0.0 if along_x else PI * 0.5)
	for dx: float in [-1.0, 1.0]:
		for dz: float in [-1.0, 1.0]:
			_add_lamp(Vector3(center.x + dx * (path_w * 0.5 + 1.0), SIDEWALK_TOP + 0.04, center.y + dz * (path_w * 0.5 + 1.0)))
	# Bushes and grass.
	for i in rng.randi_range(6, 14):
		var p := Vector2(rng.randf_range(inner.position.x + 2.0, inner.end.x - 2.0), rng.randf_range(inner.position.y + 2.0, inner.end.y - 2.0))
		if absf(p.x - center.x) < path_w + 1.0 or absf(p.y - center.y) < path_w + 1.0:
			continue
		_add_bush(Vector3(p.x, SIDEWALK_TOP + 0.04, p.y), rng)
	var blades: int = style.grass_per_park
	for i in blades:
		var p := Vector2(rng.randf_range(inner.position.x + 1.0, inner.end.x - 1.0), rng.randf_range(inner.position.y + 1.0, inner.end.y - 1.0))
		if absf(p.x - center.x) < path_w * 0.5 + 0.3 or absf(p.y - center.y) < path_w * 0.5 + 0.3:
			continue
		var sc := rng.randf_range(0.7, 1.5)
		var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(sc, sc, sc))
		var tint := Color(rng.randf_range(0.85, 1.1), rng.randf_range(0.9, 1.1), rng.randf_range(0.85, 1.05))
		_batch.add("grass", PropFactory.grass_blade(), Transform3D(basis, Vector3(p.x, SIDEWALK_TOP + 0.05, p.y)), tint, Color(rng.randf(), 0.0, 0.0))
	_batch.set_no_shadow("grass")


func _add_bush(at: Vector3, rng: RandomNumberGenerator) -> void:
	var sc := rng.randf_range(0.7, 1.6)
	var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(sc * rng.randf_range(0.8, 1.3), sc * rng.randf_range(0.7, 1.1), sc))
	var tint := Color(rng.randf_range(0.8, 1.15), rng.randf_range(0.85, 1.15), rng.randf_range(0.8, 1.0))
	_batch.add("bush", PropFactory.bush(), Transform3D(basis, at + Vector3(0.0, 0.5 * sc, 0.0)), tint)


func _build_plaza(rect: Rect2, rng: RandomNumberGenerator) -> void:
	var inner := rect.grow(-2.0)
	var center := inner.get_center()
	_add_slab(Vector3(center.x, SIDEWALK_TOP + 0.02, center.y), Vector3(inner.size.x, 0.04, inner.size.y), style.plaza, false, PropFactory.pbr("paving", 2.5, Color(1.0, 0.96, 0.9)))
	if level != Level.FULL:
		return
	var basin_r := minf(inner.size.x, inner.size.y) * 0.12
	var stone := Color(0.6, 0.58, 0.55)
	_add_cylinder(Vector3(center.x, SIDEWALK_TOP + 0.45, center.y), basin_r, 0.9, stone)
	_add_cylinder(Vector3(center.x, SIDEWALK_TOP + 0.8, center.y), basin_r - 0.5, 0.3, style.water, false, true)
	_add_cylinder(Vector3(center.x, SIDEWALK_TOP + 1.9, center.y), 0.6, 2.6, stone)
	_add_cylinder(Vector3(center.x, SIDEWALK_TOP + 3.3, center.y), 1.3, 0.25, stone, false)
	var ring := basin_r + 6.0
	for i in 4:
		var angle := i * PI * 0.5 + PI * 0.25
		var p := center + Vector2(cos(angle), sin(angle)) * ring
		_add_slab(Vector3(p.x, SIDEWALK_TOP + 0.35, p.y), Vector3(2.4, 0.7, 2.4), Color(0.55, 0.5, 0.45))
		_add_tree(Vector3(p.x, SIDEWALK_TOP + 0.7, p.y), rng)
	for i in 8:
		var angle := i * PI * 0.25
		var p := center + Vector2(cos(angle), sin(angle)) * (basin_r + 3.0)
		_add_bench(Vector3(p.x, SIDEWALK_TOP + 0.04, p.y), -angle + PI * 0.5)
	for dx: float in [-1.0, 1.0]:
		for dz: float in [-1.0, 1.0]:
			_add_lamp(Vector3(center.x + dx * inner.size.x * 0.3, SIDEWALK_TOP + 0.04, center.y + dz * inner.size.y * 0.3))


func _build_sidewalk_props(rect: Rect2, params: Dictionary, rng: RandomNumberGenerator) -> void:
	var tree_chance: float = params.trees
	var lamp_spacing: float = style.lamp_spacing
	var tree_spacing: float = style.tree_spacing
	var edges := [
		[Vector2(rect.position.x, rect.position.y), Vector2(rect.end.x, rect.position.y), Vector2(0.0, 1.0)],
		[Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.end.y), Vector2(0.0, -1.0)],
		[Vector2(rect.position.x, rect.position.y), Vector2(rect.position.x, rect.end.y), Vector2(1.0, 0.0)],
		[Vector2(rect.end.x, rect.position.y), Vector2(rect.end.x, rect.end.y), Vector2(-1.0, 0.0)],
	]
	var hydrant_edge := rng.randi() % 4
	var cans_left: int = style.trash_cans_per_block
	for e in edges.size():
		var a: Vector2 = edges[e][0]
		var b: Vector2 = edges[e][1]
		var inward: Vector2 = edges[e][2]
		var length := a.distance_to(b)
		var dir := (b - a) / length
		var t := lamp_spacing * (0.5 if e % 2 == 0 else 0.25)
		while t < length - 4.0:
			var p := a + dir * t + inward
			_add_lamp(Vector3(p.x, SIDEWALK_TOP, p.y))
			t += lamp_spacing
		t = tree_spacing * 0.75
		while t < length - 4.0:
			if rng.randf() < tree_chance and fmod(t, lamp_spacing) > 3.0:
				var p := a + dir * t + inward * 1.6
				_add_tree(Vector3(p.x, SIDEWALK_TOP, p.y), rng)
			elif rng.randf() < tree_chance * 0.5:
				var p := a + dir * (t + tree_spacing * 0.4) + inward * 2.2
				_add_bush(Vector3(p.x, SIDEWALK_TOP, p.y), rng)
			t += tree_spacing
		if e == hydrant_edge:
			var p := a + dir * rng.randf_range(6.0, length - 6.0) + inward
			_add_prop("hydrant", Vector3(p.x, SIDEWALK_TOP, p.y), Color(0.85, 0.15, 0.12), [
				["hydrant", PropFactory.hydrant(), Transform3D(Basis(), Vector3(p.x, SIDEWALK_TOP + 0.4, p.y))],
			], [[Vector3(0.4, 0.8, 0.4), Vector3(p.x, SIDEWALK_TOP + 0.4, p.y), 0.0]])
		if cans_left > 0 and rng.randf() < 0.6 and PhysicsBudget.can_spawn():
			cans_left -= 1
			var p := a + dir * rng.randf_range(4.0, length - 4.0) + inward * 1.3
			var can := TrashCan.new()
			can.position = Vector3(p.x, SIDEWALK_TOP + 0.02, p.y)
			add_child(can)


# --- Intersections ---------------------------------------------------------------------

func _build_intersection(inter: Dictionary) -> void:
	var pos: Vector2 = inter.pos
	var size: Vector2 = inter.size
	var kind: CityPlan.Intersection = inter.kind
	var rng := RandomNumberGenerator.new()
	rng.seed = inter.seed
	if kind == CityPlan.Intersection.ROUNDABOUT:
		var r := minf(size.x, size.y) * 0.3
		_add_cylinder(Vector3(pos.x, ROAD_TOP + 0.15, pos.y), r, 0.3, style.sidewalk)
		_add_cylinder(Vector3(pos.x, ROAD_TOP + 0.31, pos.y), r - 0.8, 0.04, style.grass, false)
		_add_tree(Vector3(pos.x, ROAD_TOP + 0.3, pos.y), rng)
		return
	if kind == CityPlan.Intersection.PLAIN:
		return
	_add_crosswalks(pos, size)
	var corners := [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]
	for c: Vector2 in corners:
		var corner := pos + Vector2(c.x * (size.x * 0.5 + 1.2), c.y * (size.y * 0.5 + 1.2))
		var at := Vector3(corner.x, SIDEWALK_TOP, corner.y)
		if kind == CityPlan.Intersection.STOP_SIGNS:
			var face := Basis(Vector3.RIGHT, PI * 0.5).rotated(Vector3.UP, atan2(-c.x, -c.y))
			_add_prop("stop_sign", at, Color(0.8, 0.12, 0.1), [
				["sign_pole", PropFactory.sign_pole(), Transform3D(Basis(), at + Vector3(0.0, 1.3, 0.0))],
				["stop_sign", PropFactory.stop_sign(), Transform3D(face, at + Vector3(0.0, 2.4, 0.0))],
			], [[Vector3(0.3, 2.8, 0.3), at + Vector3(0.0, 1.4, 0.0), 0.0]])
		else:
			_add_signal(at, c, size)


func _add_crosswalks(pos: Vector2, size: Vector2) -> void:
	for side: float in [-1.0, 1.0]:
		var z := pos.y + side * (size.y * 0.5 + 1.8)
		var x := pos.x - size.x * 0.5 + 1.2
		while x < pos.x + size.x * 0.5 - 0.6:
			_batch.add("stripe", PropFactory.stripe(), Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(x, ROAD_TOP + 0.015, z)))
			x += 1.4
		var xx := pos.x + side * (size.x * 0.5 + 1.8)
		var zz := pos.y - size.y * 0.5 + 1.2
		while zz < pos.y + size.y * 0.5 - 0.6:
			_batch.add("stripe", PropFactory.stripe(), Transform3D(Basis(), Vector3(xx, ROAD_TOP + 0.015, zz)))
			zz += 1.4


func _add_signal(at: Vector3, corner: Vector2, size: Vector2) -> void:
	var along_x := size.x >= size.y
	var dir := Vector3(-corner.x, 0.0, 0.0) if along_x else Vector3(0.0, 0.0, -corner.y)
	var yaw := 0.0 if along_x else PI * 0.5
	var arm_center := at + Vector3(0.0, 6.2, 0.0) + dir * 2.5
	var box_pos := at + Vector3(0.0, 5.5, 0.0) + dir * 4.6
	var instances := [
		["signal_pole", PropFactory.signal_pole(), Transform3D(Basis(), at + Vector3(0.0, 3.25, 0.0))],
		["signal_arm", PropFactory.signal_arm(), Transform3D(Basis(Vector3.UP, yaw), arm_center)],
		["signal_box", PropFactory.signal_box(), Transform3D(Basis(), box_pos)],
	]
	var colors := [Color(1.0, 0.2, 0.15), Color(1.0, 0.8, 0.2), Color(0.2, 1.0, 0.3)]
	var facing := (Vector3(0.0, 0.0, 0.2) if along_x else Vector3(0.2, 0.0, 0.0)) * (corner.y if along_x else corner.x)
	for i in 3:
		instances.append(["signal_light_%d" % i, PropFactory.signal_light(colors[i]), Transform3D(Basis(), box_pos + Vector3(0.0, 0.32 - i * 0.32, 0.0) + facing)])
	_add_prop("signal", at, Color(0.2, 0.2, 0.22), instances, [[Vector3(0.3, 6.5, 0.3), at + Vector3(0.0, 3.25, 0.0), 0.0]])


# --- Props (destructible) --------------------------------------------------------------

## Registers a breakable prop: MultiMesh instances plus collision shapes tagged with its record.
## Skipped entirely if WorldState says this prop was already destroyed.
func _add_prop(kind: String, at: Vector3, color: Color, instances: Array, shapes: Array) -> void:
	var id := "%s_%d" % [kind, _prop_counter]
	_prop_counter += 1
	if WorldState.is_destroyed(key, id):
		return
	var record := {"id": id, "kind": kind, "position": at, "color": color, "health": PROP_HEALTH.get(kind, 20.0), "instances": [], "shapes": [], "dead": false}
	for inst in instances:
		var index := _batch.add(inst[0], inst[1], inst[2])
		record.instances.append([inst[0], index])
	for s in shapes:
		var shape := _add_shape(s[0], s[1], s[2])
		if shape:
			shape.set_meta("prop", record)
			record.shapes.append(shape)
	prop_records.append(record)


func damage_prop(record: Dictionary, damage: float, hit_dir: Vector3) -> void:
	if record.dead:
		return
	record.health -= damage
	if record.health <= 0.0:
		break_prop(record, hit_dir)


func break_prop(record: Dictionary, hit_dir: Vector3 = Vector3.UP) -> void:
	if record.dead:
		return
	record.dead = true
	for inst in record.instances:
		MultiMeshBatch.hide_instance(_mm_nodes.get(inst[0]), inst[1])
	for shape in record.shapes:
		if is_instance_valid(shape):
			shape.queue_free()
	WorldState.mark_destroyed(key, record.id)
	Sfx.play("break", record.position)
	_spawn_debris(record.position, record.color, hit_dir)


func _spawn_debris(at: Vector3, color: Color, hit_dir: Vector3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([at.x, at.z, Time.get_ticks_msec()])
	var pieces := 4
	if not PhysicsBudget.make_room(pieces):
		return
	for i in pieces:
		var body := RigidBody3D.new()
		body.collision_layer = 4
		body.collision_mask = 7
		body.mass = 1.5
		var size := Vector3(rng.randf_range(0.2, 0.5), rng.randf_range(0.3, 1.2), rng.randf_range(0.2, 0.5))
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = size
		mesh.mesh = box
		mesh.material_override = PropFactory.material(color)
		body.add_child(mesh)
		var shape := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		shape.shape = bs
		body.add_child(shape)
		body.position = at + Vector3(rng.randf_range(-0.4, 0.4), 0.6 + i * 0.7, rng.randf_range(-0.4, 0.4))
		add_child(body)
		PhysicsBudget.register_debris(body)
		body.linear_velocity = (hit_dir.normalized() * 6.0 + Vector3(rng.randf_range(-3, 3), rng.randf_range(4, 9), rng.randf_range(-3, 3)))
		body.angular_velocity = Vector3(rng.randf_range(-6, 6), rng.randf_range(-6, 6), rng.randf_range(-6, 6))


func _add_lamp(at: Vector3) -> void:
	_add_prop("lamp", at, Color(0.28, 0.29, 0.32), [
		["lamp_pole", PropFactory.lamp_pole(), Transform3D(Basis(), at + Vector3(0.0, 3.0, 0.0))],
		["lamp_head", PropFactory.lamp_head(), Transform3D(Basis(), at + Vector3(0.0, 6.05, 0.0))],
	], [[Vector3(0.25, 6.0, 0.25), at + Vector3(0.0, 3.0, 0.0), 0.0]])


func _add_bench(at: Vector3, yaw: float) -> void:
	var basis := Basis(Vector3.UP, yaw)
	_add_prop("bench", at, Color(0.5, 0.36, 0.22), [
		["bench_legs", PropFactory.bench_legs(), Transform3D(basis, at + Vector3(0.0, 0.22, 0.0))],
		["bench", PropFactory.bench(), Transform3D(basis, at + Vector3(0.0, 0.5, 0.0))],
	], [[Vector3(1.8, 0.55, 0.5), at + Vector3(0.0, 0.28, 0.0), yaw]])


func _add_tree(at: Vector3, rng: RandomNumberGenerator) -> void:
	var s := rng.randf_range(0.8, 1.4)
	var yaw := rng.randf_range(0.0, TAU)
	_batch.add("trunk", PropFactory.trunk(), Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s)), at + Vector3(0.0, 1.1 * s, 0.0)))
	var tint := Color(rng.randf_range(0.8, 1.1), rng.randf_range(0.85, 1.15), rng.randf_range(0.8, 1.05))
	if rng.randf() < 0.7:
		_batch.add("canopy_round", PropFactory.canopy_round(), Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s * rng.randf_range(0.9, 1.3), s)), at + Vector3(0.0, 3.4 * s, 0.0)), tint)
	else:
		_batch.add("canopy_cone", PropFactory.canopy_cone(), Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s)), at + Vector3(0.0, 3.8 * s, 0.0)), tint)


# --- Helpers ---------------------------------------------------------------------------

func _add_slab(pos: Vector3, size: Vector3, color: Color, collide: bool = true, material: Material = null) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material if material else PropFactory.material(color, 0.95)
	mesh.position = pos
	add_child(mesh)
	if collide:
		_add_shape(size, pos)


func _add_cylinder(pos: Vector3, radius: float, height: float, color: Color, collide: bool = true, unshaded: bool = false) -> void:
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.radial_segments = 16
	mesh.mesh = cyl
	mesh.material_override = PropFactory.material(color, 0.9, unshaded)
	mesh.position = pos
	add_child(mesh)
	if collide and _statics:
		var shape := CollisionShape3D.new()
		var s := CylinderShape3D.new()
		s.radius = radius
		s.height = height
		shape.shape = s
		shape.position = pos
		_statics.add_child(shape)


func _add_shape(size: Vector3, pos: Vector3, yaw: float = 0.0) -> CollisionShape3D:
	if _statics == null:
		return null
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = pos
	shape.rotation.y = yaw
	_statics.add_child(shape)
	return shape
