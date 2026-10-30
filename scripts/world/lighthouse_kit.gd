class_name LighthouseKit
extends RefCounted
## The two lights and the breakwater (Lighthouses), built in code at real size.
##
## GULL POINT LIGHT (build_lighthouse): the form of San Pedro's Point Fermin light - a two-storey
## Victorian keeper's house in white lap siding with oxblood trim, a hipped shingle roof on a
## bracketed frieze, a square tower rising out of the roof's middle to a railed gallery and an
## octagonal iron lantern with its Fresnel lens, a porch across the front on turned posts with a
## balustrade, brick chimneys, all on a stone foundation in a fenced lawn with palms on the cliff.
## HARBOR GATE LIGHT (build_gate): the form of the Angels Gate light - an octagonal tower in two
## stages of alternating black and white faces (the daymark) on a concrete pier block at the
## breakwater's head, a railed gallery and an iron lantern, fog trumpets on the pier.
## The breakwater (build_breakwater): a rubble mound under a concrete walkway cap, armoured with
## quarried blocks (STONE_SHAPES chipped boxes, one MultiMesh per shape and piece) on
## armour_stone.gdshader, white water round its foot (breakwater_foam.gdshader); far, the mound
## alone with the blocks drawn by the shader.
##
## Every building is in its own frame - origin on the pad / pier top, +Z its front, +X its right
## - on a Node3D placed in the world, and goes into ONE LandmarkGeo (a surface per material). The
## lantern's rotor is a LighthouseBeacon. Rolls are hashes of fixed keys (no rng, no seed: the
## coast does not move with the seed). `detailed` false is the far copy: the same builders less
## what is under a pixel from across the bay (balusters, brackets, casings, pickets, stones).

const WHITE := Color(0.93, 0.92, 0.88)
const OXBLOOD := Color(0.42, 0.13, 0.10)
const SHINGLE := Color(0.36, 0.16, 0.12)
const IRON := Color(0.10, 0.11, 0.11)
const LANTERN_ROOF := Color(0.45, 0.10, 0.08)
const BRASS := Color(0.62, 0.46, 0.20)
const STONE := Color(0.63, 0.58, 0.50)
const BRICK := Color(0.78, 0.56, 0.48)
const CONCRETE := Color(0.80, 0.78, 0.74)
const BLACK := Color(0.07, 0.07, 0.075)
const PORCH_CEILING := Color(0.66, 0.80, 0.82)
const BLIND := Color(0.90, 0.88, 0.82)

## The house: walls' half size, floor heights, the eave and the tower.
const HALF := 5.0
const FLOOR0 := 0.9
const FLOOR1 := 4.4
const EAVE := 7.6
const OVERHANG := 0.75
const PITCH := 0.55
const TOWER_HALF := 1.9
const TOWER_TOP := 12.5
const GALLERY := 12.72
const LANTERN_R := 1.3
const PORCH_DEPTH := 2.4
const PORCH_TOP := 3.95
## The lamp's height over the lantern's floor (the pedestal plus half the glazing).
const LAMP_OVER_BASE := 2.0

## Armour stone shapes (chipped boxes) and how many rows a flank carries.
const STONE_SHAPES := 6

static var _mats: Dictionary = {}
static var _stones: Array[Mesh] = []


# --- Materials ------------------------------------------------------------------------------------

static func mat(name: String) -> Material:
	if _mats.has(name):
		return _mats[name]
	var m: Material
	match name:
		"siding":
			m = HouseKit.material("h_siding")
		"shingle":
			m = HouseKit.material("h_shingle")
		"trim":
			m = HouseKit.material("h_trim")
		"door":
			m = HouseKit.material("h_door")
		"metal":
			m = HouseKit.material("h_metal")
		"dark":
			m = HouseKit.material("h_dark")
		"glass":
			m = HouseKit.material("glass")
		"brick":
			var bm := (PropFactory.pbr("brick_red", 2.0, Color.WHITE) as StandardMaterial3D).duplicate() as StandardMaterial3D
			bm.vertex_color_use_as_albedo = true
			bm.vertex_color_is_srgb = true
			m = bm
		"stone":
			var sm := (PropFactory.pbr("rock", 2.5, Color.WHITE) as StandardMaterial3D).duplicate() as StandardMaterial3D
			sm.vertex_color_use_as_albedo = true
			sm.vertex_color_is_srgb = true
			m = sm
		"concrete":
			var cm := (PropFactory.pbr("concrete", 3.0, Color.WHITE) as StandardMaterial3D).duplicate() as StandardMaterial3D
			cm.vertex_color_use_as_albedo = true
			cm.vertex_color_is_srgb = true
			m = cm
		"planks":
			var pm := (PropFactory.pbr("planks", 2.0, Color.WHITE) as StandardMaterial3D).duplicate() as StandardMaterial3D
			pm.vertex_color_use_as_albedo = true
			pm.vertex_color_is_srgb = true
			m = pm
		"path":
			m = PropFactory.pbr("sidewalk", 2.5, Color(1.25, 1.2, 1.1))
		"lawn":
			m = PropFactory.lawn(Color(0.40, 0.52, 0.24), 4411, 0.3, 3.0)
		"lantern_glass":
			var g := StandardMaterial3D.new()
			g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			g.albedo_color = Color(0.70, 0.80, 0.80, 0.16)
			g.roughness = 0.03
			g.metallic_specular = 0.9
			g.cull_mode = BaseMaterial3D.CULL_DISABLED
			m = g
		"armour", "armour_far":
			var sh := ShaderMaterial.new()
			sh.shader = load("res://shaders/armour_stone.gdshader")
			sh.set_shader_parameter("rock_albedo", PropFactory.texture("rock", "Color"))
			sh.set_shader_parameter("rock_normal", PropFactory.texture("rock", "NormalGL"))
			sh.set_shader_parameter("rock_rough", PropFactory.texture("rock", "Roughness"))
			sh.set_shader_parameter("blocks", 1.0 if name == "armour_far" else 0.0)
			m = sh
		"foam":
			var fm := ShaderMaterial.new()
			fm.shader = load("res://shaders/breakwater_foam.gdshader")
			m = fm
		_:
			m = PropFactory.material(Color.MAGENTA)
	_mats[name] = m
	return m


## The lens, beam and lamp materials of one light (Lighthouses.LIGHTS[id]).
static func light_mat(id: String, kind: String) -> Material:
	var key := "%s_%s" % [id, kind]
	if _mats.has(key):
		return _mats[key]
	var spec: Dictionary = Lighthouses.LIGHTS[id]
	var c: Color = spec.color
	var lin := Vector3(c.r, c.g, c.b)
	var sh := ShaderMaterial.new()
	match kind:
		"lens":
			sh.shader = load("res://shaders/lighthouse_lens.gdshader")
			sh.set_shader_parameter("beams", float(spec.beams))
		"beam":
			sh.shader = load("res://shaders/lighthouse_beam.gdshader")
		"lamp":
			sh.shader = load("res://shaders/lighthouse_lamp.gdshader")
			sh.set_shader_parameter("beams", float(spec.beams))
	# Vector3, not Color: a Color set from script is decoded on Forward+, a Vector3 is not, and the
	# shaders take these as linear on both renderers (color_space.gdshaderinc).
	sh.set_shader_parameter("lamp_color" if kind != "beam" else "beam_color", lin)
	_mats[key] = sh
	return sh


static func _h(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) / 100003.0


# --- Walls with openings ---------------------------------------------------------------------------

## A wall from p0 to p1 (frame XZ, outward to the right seen from above), y0..y1, with rectangular
## openings [u0, u1, v0, v1] (u metres from p0, v heights). The cells round the openings are the
## wall; each opening gets its reveals (`depth` deep, trim) and, if `pane` is set, a pane of house
## glass at the back (UV 0..1 across it, the blind colour and a random in COLOR) or the door.
static func _wall(g: LandmarkGeo, key: String, p0: Vector2, p1: Vector2, y0: float, y1: float, holes: Array,
		col: Color, depth: float, detailed: bool, seed_key: String) -> void:
	var d := p1 - p0
	var length := d.length()
	var dir := d / length
	var n := Vector2(-dir.y, dir.x)
	var n3 := Vector3(n.x, 0.0, n.y)
	var us: Array[float] = [0.0, length]
	var vs: Array[float] = [y0, y1]
	for h: Array in holes:
		us.append(float(h[0]))
		us.append(float(h[1]))
		vs.append(float(h[2]))
		vs.append(float(h[3]))
	us.sort()
	vs.sort()
	var at := func(u: float, v: float, inset: float) -> Vector3:
		var p := p0 + dir * u - n * inset
		return Vector3(p.x, v, p.y)
	for i in us.size() - 1:
		var ua := us[i]
		var ub := us[i + 1]
		if ub - ua < 1e-3:
			continue
		for j in vs.size() - 1:
			var va := vs[j]
			var vb := vs[j + 1]
			if vb - va < 1e-3:
				continue
			var cu := (ua + ub) * 0.5
			var cv := (va + vb) * 0.5
			var inside := false
			for h: Array in holes:
				if cu > float(h[0]) and cu < float(h[1]) and cv > float(h[2]) and cv < float(h[3]):
					inside = true
					break
			if inside:
				continue
			g.quad(key, at.call(ua, va, 0.0), at.call(ua, vb, 0.0), at.call(ub, vb, 0.0), at.call(ub, va, 0.0), n3,
				Vector2(ua, va), Vector2(ua, vb), Vector2(ub, vb), Vector2(ub, va), col)
	for k in holes.size():
		var h: Array = holes[k]
		var u0: float = h[0]
		var u1: float = h[1]
		var v0: float = h[2]
		var v1: float = h[3]
		var kind: String = h[4] if h.size() > 4 else "window"
		# Reveals: jambs, head and sill, facing into the opening.
		var dir3 := Vector3(dir.x, 0.0, dir.y)
		g.quad("trim", at.call(u0, v0, 0.0), at.call(u0, v1, 0.0), at.call(u0, v1, depth), at.call(u0, v0, depth), dir3,
			Vector2(0, v0), Vector2(0, v1), Vector2(depth, v1), Vector2(depth, v0), WHITE)
		g.quad("trim", at.call(u1, v0, 0.0), at.call(u1, v1, 0.0), at.call(u1, v1, depth), at.call(u1, v0, depth), -dir3,
			Vector2(0, v0), Vector2(0, v1), Vector2(depth, v1), Vector2(depth, v0), WHITE)
		g.quad("trim", at.call(u0, v1, 0.0), at.call(u1, v1, 0.0), at.call(u1, v1, depth), at.call(u0, v1, depth), Vector3.DOWN,
			Vector2(u0, 0), Vector2(u1, 0), Vector2(u1, depth), Vector2(u0, depth), WHITE)
		g.quad("trim", at.call(u0, v0, 0.0), at.call(u1, v0, 0.0), at.call(u1, v0, depth), at.call(u0, v0, depth), Vector3.UP,
			Vector2(u0, 0), Vector2(u1, 0), Vector2(u1, depth), Vector2(u0, depth), WHITE)
		if kind == "door":
			# A four-panel door under a glazed transom.
			var split := v1 - 0.45
			g.quad("door", at.call(u0, v0, depth), at.call(u0, split, depth), at.call(u1, split, depth), at.call(u1, v0, depth), n3,
				Vector2(u0, v0), Vector2(u0, split), Vector2(u1, split), Vector2(u1, v0), OXBLOOD)
			g.box("trim", Vector3.ZERO + at.call((u0 + u1) * 0.5, split + 0.04, depth - 0.02), Vector3(u1 - u0, 0.08, 0.06), WHITE, _yaw(dir))
			g.quad("glass", at.call(u0, split + 0.08, depth), at.call(u0, v1, depth), at.call(u1, v1, depth), at.call(u1, split + 0.08, depth), n3,
				Vector2(0, 1), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Color(BLIND.r, BLIND.g, BLIND.b, _h([seed_key, k, "d"])))
			if detailed:
				for pu in 2:
					for pv in 2:
						var cu := lerpf(u0, u1, 0.27 + 0.46 * pu)
						var cv := lerpf(v0, split, 0.27 + 0.46 * pv)
						g.box("door", at.call(cu, cv, depth - 0.02), Vector3((u1 - u0) * 0.32, (split - v0) * 0.36, 0.03), OXBLOOD, _yaw(dir), 0.012)
				g.box("metal", at.call(u1 - 0.12, FLOOR0 + 1.0, depth - 0.05), Vector3(0.05, 0.05, 0.07), BRASS, _yaw(dir))
		else:
			g.quad("glass", at.call(u0, v0, depth), at.call(u0, v1, depth), at.call(u1, v1, depth), at.call(u1, v0, depth), n3,
				Vector2(0, 1), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Color(BLIND.r, BLIND.g, BLIND.b, _h([seed_key, k])))
			if detailed:
				# Sash bars: the meeting rail and a muntin down each sash (two over two).
				var mid := (v0 + v1) * 0.5
				g.box("trim", at.call((u0 + u1) * 0.5, mid, depth - 0.03), Vector3(u1 - u0, 0.06, 0.05), WHITE, _yaw(dir))
				g.box("trim", at.call((u0 + u1) * 0.5, mid, depth - 0.02), Vector3(0.035, v1 - v0, 0.03), WHITE, _yaw(dir))
		if detailed:
			# Casing, a cap over the head and a sill under it.
			var cw := 0.12
			g.box("trim", at.call(u0 - cw * 0.5, (v0 + v1) * 0.5, -0.025), Vector3(cw, v1 - v0 + cw, 0.05), WHITE, _yaw(dir))
			g.box("trim", at.call(u1 + cw * 0.5, (v0 + v1) * 0.5, -0.025), Vector3(cw, v1 - v0 + cw, 0.05), WHITE, _yaw(dir))
			g.box("trim", at.call((u0 + u1) * 0.5, v1 + 0.11, -0.03), Vector3(u1 - u0 + cw * 2.0, 0.2, 0.06), WHITE, _yaw(dir))
			g.box("trim", at.call((u0 + u1) * 0.5, v1 + 0.24, -0.07), Vector3(u1 - u0 + cw * 2.0 + 0.16, 0.06, 0.14), OXBLOOD, _yaw(dir))
			if kind != "door":
				g.box("trim", at.call((u0 + u1) * 0.5, v0 - 0.03, -0.06), Vector3(u1 - u0 + cw * 2.0 + 0.1, 0.06, 0.14), WHITE, _yaw(dir))


## A basis turning a box so its local X runs along `dir` (frame XZ) and its local Z faces the
## wall's outside.
static func _yaw(dir: Vector2) -> Basis:
	return Basis(Vector3.UP, atan2(-dir.y, dir.x))


## The four walls of a square of half size `half` from y0 to y1, openings per side (front +Z,
## right +X, back -Z, left -X; each [u0, u1, v0, v1, kind] with u from the side's left seen from
## outside).
static func _square(g: LandmarkGeo, half: float, y0: float, y1: float, holes: Array, col: Color, depth: float,
		detailed: bool, seed_key: String) -> void:
	var sides := [
		[Vector2(-half, half), Vector2(half, half)],
		[Vector2(half, half), Vector2(half, -half)],
		[Vector2(half, -half), Vector2(-half, -half)],
		[Vector2(-half, -half), Vector2(-half, half)],
	]
	for i in 4:
		_wall(g, "siding", sides[i][0], sides[i][1], y0, y1, holes[i], col, depth, detailed, "%s_%d" % [seed_key, i])


## Openings evenly along a wall of `length`: `count` windows `w` wide between v0 and v1.
static func _row(length: float, count: int, w: float, v0: float, v1: float, skip_mid: bool = false) -> Array:
	var out: Array = []
	for i in count:
		var c := length * (float(i) + 0.5) / float(count)
		if skip_mid and count % 2 == 1 and i == count / 2:
			continue
		out.append([c - w * 0.5, c + w * 0.5, v0, v1])
	return out


# --- The lighthouse --------------------------------------------------------------------------------

## GULL POINT LIGHT on its pad: `at` is the pad's centre (world, y the pad level), `front` the
## way the porch faces (world XZ).
static func build_lighthouse(parent: Node3D, statics: StaticBody3D, at: Vector3, front: Vector2, detailed: bool) -> void:
	var root := Node3D.new()
	root.name = "GullPointLight"
	var fz := front.normalized()
	root.transform = Transform3D(Basis(Vector3.UP, atan2(fz.x, fz.y)), at)
	parent.add_child(root)
	var body: StaticBody3D = null
	if statics:
		body = StaticBody3D.new()
		body.name = "GullPointBody"
		body.collision_layer = 1
		body.collision_mask = 0
		body.transform = root.transform
		statics.add_child(body)
	_place(root, body, "light_near" if detailed else "light_far", _lighthouse_geo.bind(detailed), "LighthouseMesh")
	if body:
		_shapes_lighthouse(body)
	_rotor(root, Lighthouses.LIGHT_ID, Vector3(0.0, GALLERY, 0.0), detailed)
	_planting(root, detailed)
	if detailed:
		_porch_light(root)


## Meshes built once per key (the near lighthouse is ~120 ms of GDScript): [mesh, collision faces].
static var _geo_cache: Dictionary = {}


## Puts the cached mesh for `key` under `root` (building it with `make` the first time: a Callable
## returning a filled LandmarkGeo), and its collision faces on `body`.
static func _place(root: Node3D, body: StaticBody3D, key: String, make: Callable, node_name: String) -> MeshInstance3D:
	if not _geo_cache.has(key):
		var g: LandmarkGeo = make.call()
		var faces := g.collision.duplicate()
		var holder := Node3D.new()
		var mi0 := g.commit(holder, node_name)
		var mesh: Mesh = mi0.mesh if mi0 else null
		holder.free()
		_geo_cache[key] = [mesh, faces]
	var entry: Array = _geo_cache[key]
	var mi: MeshInstance3D = null
	if entry[0] != null:
		mi = MeshInstance3D.new()
		mi.name = node_name
		mi.mesh = entry[0]
		root.add_child(mi)
	var faces: PackedVector3Array = entry[1]
	if body and not faces.is_empty():
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
	return mi


## Builds the near and far meshes of every piece ahead of time (the loading screen, with the far
## copies), so a chunk building the near one only places it.
static func warm() -> void:
	if _geo_cache.has("light_near"):
		return
	for d: bool in [true, false]:
		var tmp := Node3D.new()
		_place(tmp, null, "light_near" if d else "light_far", _lighthouse_geo.bind(d), "LighthouseMesh")
		_place(tmp, null, "gate_near" if d else "gate_far", _gate_geo.bind(d), "GateLightMesh")
		tmp.free()


static func _lighthouse_geo(detailed: bool) -> LandmarkGeo:
	var g := LandmarkGeo.new()
	for k in ["siding", "trim", "shingle", "door", "glass", "metal", "dark", "brick", "stone", "planks", "lantern_glass", "lawn", "path"]:
		g.use(k, mat(k))
	var siding := Color(WHITE.r, WHITE.g, WHITE.b, 1.0)
	# --- Grounds: the lawn and a gravel walk round the house and out to the gate.
	_grounds(g, detailed)
	# --- Foundation: dressed stone, sunk into the pad.
	g.box("stone", Vector3(0.0, (FLOOR0 - 1.4) * 0.5, 0.0), Vector3(HALF * 2.0 + 0.3, FLOOR0 + 1.4, HALF * 2.0 + 0.3), STONE, Basis(), 0.03 if detailed else 0.0)
	# --- Walls: ground floor (door in the middle of the front), first floor.
	var gw := 1.0
	var long := HALF * 2.0
	var front0: Array = [[2.0 - gw * 0.5, 2.0 + gw * 0.5, FLOOR0 + 0.55, FLOOR0 + 2.55], [4.45, 5.55, FLOOR0, FLOOR0 + 2.55, "door"], [8.0 - gw * 0.5, 8.0 + gw * 0.5, FLOOR0 + 0.55, FLOOR0 + 2.55]]
	var side0 := _row(long, 2, gw, FLOOR0 + 0.55, FLOOR0 + 2.55)
	var holes0 := [front0, side0, _row(long, 2, gw, FLOOR0 + 0.55, FLOOR0 + 2.55), side0]
	_square(g, HALF, FLOOR0, FLOOR1, holes0, siding, 0.16, detailed, "gp0")
	var up := _row(long, 3, 0.9, FLOOR1 + 0.75, FLOOR1 + 2.35)
	var holes1 := [up, _row(long, 2, 0.9, FLOOR1 + 0.75, FLOOR1 + 2.35), up, _row(long, 2, 0.9, FLOOR1 + 0.75, FLOOR1 + 2.35)]
	_square(g, HALF, FLOOR1, EAVE, holes1, siding, 0.16, detailed, "gp1")
	# Corner boards, the water table, the belt between the floors and the frieze under the eave.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			g.box("trim", Vector3(sx * (HALF + 0.02), (FLOOR0 + EAVE) * 0.5, sz * (HALF + 0.02)), Vector3(0.2, EAVE - FLOOR0, 0.2), WHITE)
	_ring(g, "trim", HALF + 0.05, FLOOR0 - 0.02, FLOOR0 + 0.16, OXBLOOD)
	_ring(g, "trim", HALF + 0.05, FLOOR1 - 0.1, FLOOR1 + 0.12, WHITE)
	_ring(g, "trim", HALF + 0.04, EAVE - 0.42, EAVE, WHITE)
	_ring(g, "trim", HALF + 0.07, EAVE - 0.47, EAVE - 0.4, OXBLOOD)
	# --- The hipped roof round the tower, its soffit, fascia and hips.
	_hip_roof(g, HALF + OVERHANG, TOWER_HALF, EAVE, PITCH, detailed)
	if detailed:
		# Scroll brackets under the eave.
		for side in 4:
			var count := 11
			for i in count:
				var t := -HALF + 0.3 + (HALF * 2.0 - 0.6) * float(i) / float(count - 1)
				var p := Vector3(t, EAVE - 0.22, HALF + OVERHANG * 0.45)
				var b := Basis(Vector3.UP, PI * 0.5 * side)
				g.box("trim", b * p, Vector3(0.11, 0.42, OVERHANG * 0.9), WHITE, b)
	# --- Chimneys: brick, corbelled caps, through the roof at the back.
	for sx in [-1.0, 1.0]:
		var c := Vector3(sx * 3.1, 0.0, -2.9)
		g.box("brick", Vector3(c.x, (EAVE - 1.5 + 11.2) * 0.5, c.z), Vector3(0.72, 11.2 - (EAVE - 1.5), 0.72), BRICK)
		g.box("brick", Vector3(c.x, 11.25, c.z), Vector3(0.92, 0.2, 0.92), BRICK)
		g.box("dark", Vector3(c.x, 11.36, c.z), Vector3(0.5, 0.04, 0.5), IRON)
	# --- The tower: walls from inside the roof to the cornice, a window each side.
	var tw := TOWER_HALF * 2.0
	var th := _row(tw, 1, 0.72, 10.25, 11.55)
	_square(g, TOWER_HALF, EAVE - 0.4, TOWER_TOP, [th, th, th, th], siding, 0.12, detailed, "gpt")
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			g.box("trim", Vector3(sx * (TOWER_HALF + 0.02), (EAVE + TOWER_TOP) * 0.5, sz * (TOWER_HALF + 0.02)), Vector3(0.18, TOWER_TOP - EAVE, 0.18), WHITE)
	_ring(g, "trim", TOWER_HALF + 0.05, TOWER_TOP - 0.4, TOWER_TOP, WHITE)
	_ring(g, "trim", TOWER_HALF + 0.12, TOWER_TOP - 0.06, TOWER_TOP + 0.02, OXBLOOD)
	if detailed:
		for side in 4:
			for i in 5:
				var t := -TOWER_HALF + 0.2 + (TOWER_HALF * 2.0 - 0.4) * float(i) / 4.0
				var b := Basis(Vector3.UP, PI * 0.5 * side)
				g.box("trim", b * Vector3(t, TOWER_TOP - 0.2, TOWER_HALF + 0.2), Vector3(0.1, 0.36, 0.4), WHITE, b)
	# The gallery deck on the tower top, and its iron rail.
	g.box("metal", Vector3(0.0, (TOWER_TOP + GALLERY) * 0.5, 0.0), Vector3(4.7, GALLERY - TOWER_TOP, 4.7), IRON)
	_rail(g, 2.28, GALLERY, 1.0, detailed)
	# --- The lantern.
	_lantern(g, Vector3(0.0, GALLERY, 0.0), LANTERN_R, detailed)
	# --- The porch across the front.
	_porch(g, detailed)
	return g


## A square band of trim (four boxes) round a wall of half size `half` from y0 to y1.
static func _ring(g: LandmarkGeo, key: String, half: float, y0: float, y1: float, col: Color) -> void:
	var h := y1 - y0
	var c := (y0 + y1) * 0.5
	g.box(key, Vector3(0.0, c, half), Vector3(half * 2.0 + 0.1, h, 0.1), col)
	g.box(key, Vector3(0.0, c, -half), Vector3(half * 2.0 + 0.1, h, 0.1), col)
	g.box(key, Vector3(half, c, 0.0), Vector3(0.1, h, half * 2.0 + 0.1), col)
	g.box(key, Vector3(-half, c, 0.0), Vector3(0.1, h, half * 2.0 + 0.1), col)


## A hipped roof from a square eave of half size `outer` at `eave` up to a square hole of half
## size `inner` round the tower, at `pitch` (rise per run); shingle UVs in metres along the eave
## and up the slope; a soffit, a fascia and ridge caps on the hips.
static func _hip_roof(g: LandmarkGeo, outer: float, inner: float, eave: float, pitch: float, detailed: bool) -> void:
	var rise := (outer - inner) * pitch
	var top := eave + rise
	var slope_len := sqrt((outer - inner) * (outer - inner) + rise * rise)
	var col := Color(SHINGLE.r, SHINGLE.g, SHINGLE.b, 0.2)
	for side in 4:
		var b := Basis(Vector3.UP, PI * 0.5 * side)
		var a0 := b * Vector3(-outer, eave, outer)
		var a1 := b * Vector3(outer, eave, outer)
		var a2 := b * Vector3(inner, top, inner)
		var a3 := b * Vector3(-inner, top, inner)
		var n := b * Vector3(0.0, 1.0, pitch).normalized()
		var u_in := outer - inner
		g.quad("shingle", a0, a1, a2, a3, n, Vector2(0.0, 0.0), Vector2(outer * 2.0, 0.0), Vector2(outer + inner, slope_len), Vector2(u_in, slope_len), col, true)
		# Soffit (painted) and fascia.
		var s0 := b * Vector3(-outer, eave - 0.02, outer)
		var s1 := b * Vector3(outer, eave - 0.02, outer)
		var s2 := b * Vector3(HALF, eave - 0.02, HALF)
		var s3 := b * Vector3(-HALF, eave - 0.02, HALF)
		g.quad("trim", s0, s1, s2, s3, Vector3.DOWN, Vector2.ZERO, Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), WHITE)
		g.box("trim", b * Vector3(0.0, eave - 0.1, outer + 0.03), Vector3(outer * 2.0 + 0.06, 0.24, 0.06), OXBLOOD, b)
		if detailed:
			# Hip cap: from the eave corner up to the tower corner.
			var c0 := b * Vector3(outer, eave + 0.04, outer)
			var c1 := b * Vector3(inner, top + 0.04, inner)
			var mid := (c0 + c1) * 0.5
			var along := (c1 - c0)
			var basis := Basis.looking_at(along.normalized(), Vector3.UP)
			g.box("shingle", mid, Vector3(0.24, 0.08, along.length()), Color(SHINGLE.r * 0.8, SHINGLE.g * 0.8, SHINGLE.b * 0.8, 0.2), basis)


## The railed gallery round a square of half size `half` at floor `y`: posts, a top rail and a
## mid rail (far: the top rail alone).
static func _rail(g: LandmarkGeo, half: float, y: float, h: float, detailed: bool) -> void:
	for side in 4:
		var b := Basis(Vector3.UP, PI * 0.5 * side)
		g.box("metal", b * Vector3(0.0, y + h, half), Vector3(half * 2.0, 0.05, 0.05), IRON, b)
		if detailed:
			g.box("metal", b * Vector3(0.0, y + h * 0.5, half), Vector3(half * 2.0, 0.035, 0.035), IRON, b)
			var n := int(half * 2.0 / 0.16)
			for i in n + 1:
				var t := -half + half * 2.0 * float(i) / float(n)
				var thick := 0.05 if i % 6 == 0 else 0.02
				g.box("metal", b * Vector3(t, y + h * 0.5, half), Vector3(thick, h, thick), IRON, b)


## The octagonal iron lantern standing on `base` (frame), radius `r`: a pedestal with vents, the
## glazed storm panes on astragals, a domed roof in red, the ventilator ball and lightning rod.
## The rotor (LighthouseBeacon) inside it is _rotor()'s.
static func _lantern(g: LandmarkGeo, base: Vector3, r: float, detailed: bool) -> void:
	var c := Vector2(base.x, base.z)
	var segs := 8
	var y0 := base.y
	var ped := y0 + 0.85
	var glass_top := ped + 2.3
	# Pedestal (the watch room's iron wall) and a sill.
	g.band("metal", c, Vector2(r, r), Vector2(r, r), y0, ped, 0.0, TAU, segs, IRON)
	g.band("metal", c, Vector2(r + 0.08, r + 0.08), Vector2(r + 0.08, r + 0.08), ped - 0.08, ped, 0.0, TAU, segs, IRON)
	if detailed:
		for i in segs:
			var a := TAU * (float(i) + 0.5) / float(segs)
			var p := c + Vector2(cos(a), sin(a)) * (r * cos(PI / segs) + 0.01)
			g.box("dark", Vector3(p.x, y0 + 0.42, p.y), Vector3(0.22, 0.22, 0.03), BLACK, Basis(Vector3.UP, -a + PI * 0.5))
	# The glazing and its astragals.
	g.band("lantern_glass", c, Vector2(r - 0.04, r - 0.04), Vector2(r - 0.04, r - 0.04), ped, glass_top, 0.0, TAU, segs, Color.WHITE)
	for i in segs:
		var a := TAU * float(i) / float(segs)
		var p := c + Vector2(cos(a), sin(a)) * r
		g.box("metal", Vector3(p.x, (ped + glass_top) * 0.5, p.y), Vector3(0.08, glass_top - ped, 0.08), IRON, Basis(Vector3.UP, -a))
	if detailed:
		g.band("metal", c, Vector2(r, r), Vector2(r, r), (ped + glass_top) * 0.5 - 0.03, (ped + glass_top) * 0.5 + 0.03, 0.0, TAU, segs, IRON)
	# Cornice, the dome and its ball and rod.
	g.band("metal", c, Vector2(r + 0.18, r + 0.18), Vector2(r + 0.18, r + 0.18), glass_top, glass_top + 0.16, 0.0, TAU, segs, IRON)
	g.ring_flat("metal", c, Vector2(0.0, 0.0), Vector2(r + 0.18, r + 0.18), glass_top, 0.0, TAU, segs, IRON, false, true)
	g.dome("metal", c, Vector2(r + 0.18, r + 0.18), glass_top + 0.16, 1.1, 16, 4, LANTERN_ROOF)
	g.cylinder("metal", Vector3(c.x, glass_top + 1.2, c.y), 0.06, 0.25, 6, IRON)
	g.dome("metal", c, Vector2(0.24, 0.24), glass_top + 1.42, 0.24, 8, 2, IRON)
	g.cylinder("metal", Vector3(c.x, glass_top + 1.3, c.y), 0.16, 0.12, 8, IRON, 0.24, false, false)
	g.cylinder("metal", Vector3(c.x, glass_top + 1.6, c.y), 0.02, 0.9, 4, IRON)
	# The floor of the lantern room (seen through the glass) and the lens pedestal.
	g.ring_flat("dark", c, Vector2(0.0, 0.0), Vector2(r, r), ped + 0.02, 0.0, TAU, segs, Color(0.2, 0.2, 0.2))
	g.cylinder("metal", Vector3(c.x, ped, c.y), 0.32, 0.3, 8, BRASS)


## The rotor on a lantern standing on `base` (frame): the lens, the beams, the far lamp, the spots.
static func _rotor(frame: Node3D, id: String, base: Vector3, detailed: bool) -> void:
	var spec: Dictionary = Lighthouses.LIGHTS[id]
	var rotor := LighthouseBeacon.new()
	rotor.name = "Rotor"
	rotor.period = float(spec.period)
	rotor.phase = float(spec.phase)
	rotor.position = base + Vector3(0.0, LAMP_OVER_BASE, 0.0)
	frame.add_child(rotor)
	_lens(rotor, id, detailed)
	_beams(rotor, id, detailed)


## The lens barrel on the rotor (frame centred on the lamp), and its brass top and bottom.
static func _lens(rotor: LighthouseBeacon, id: String, detailed: bool) -> void:
	var r := 0.55
	var h := 1.4
	var segs := 24 if detailed else 12
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in segs:
		# Turn 0 is the rotor's +X (the first beam).
		var t0 := float(i) / float(segs)
		var t1 := float(i + 1) / float(segs)
		var a0 := t0 * TAU
		var a1 := t1 * TAU
		var p0 := Vector3(cos(a0) * r, 0.0, -sin(a0) * r)
		var p1 := Vector3(cos(a1) * r, 0.0, -sin(a1) * r)
		var n0 := p0.normalized()
		var n1 := p1.normalized()
		var lo := -h * 0.5
		var hi := h * 0.5
		var verts := [[p0 + Vector3(0, lo, 0), n0, Vector2(t0, 0)], [p1 + Vector3(0, lo, 0), n1, Vector2(t1, 0)], [p1 + Vector3(0, hi, 0), n1, Vector2(t1, 1)],
			[p0 + Vector3(0, lo, 0), n0, Vector2(t0, 0)], [p1 + Vector3(0, hi, 0), n1, Vector2(t1, 1)], [p0 + Vector3(0, hi, 0), n0, Vector2(t0, 1)]]
		# Godot's front faces wind clockwise seen from the front: outside the barrel.
		for vi in [0, 2, 1, 3, 5, 4]:
			var v: Array = verts[vi]
			st.set_normal(v[1])
			st.set_uv(v[2])
			st.add_vertex(v[0])
	var mesh := st.commit()
	mesh.surface_set_material(0, light_mat(id, "lens"))
	var mi := MeshInstance3D.new()
	mi.name = "Lens"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rotor.add_child(mi)


## The beams (drawn shafts), the far point light and the spots, all on the rotor.
static func _beams(rotor: LighthouseBeacon, id: String, detailed: bool) -> void:
	var spec: Dictionary = Lighthouses.LIGHTS[id]
	var n: int = spec.beams
	var beam := MeshInstance3D.new()
	beam.name = "Beams"
	beam.mesh = beam_mesh(n, float(spec.length))
	beam.material_override = light_mat(id, "beam")
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.extra_cull_margin = 200.0
	rotor.add_child(beam)
	rotor.beams.append(beam)
	var lamp := MeshInstance3D.new()
	lamp.name = "Lamp"
	lamp.mesh = lamp_mesh(1.6)
	lamp.material_override = light_mat(id, "lamp")
	lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lamp.extra_cull_margin = 16384.0
	rotor.add_child(lamp)
	# Real light in the volumetric fog: Forward+ desktop, where the environment has the fog on.
	if detailed and spots_wanted(rotor):
		for k in n:
			var s := SpotLight3D.new()
			s.name = "Spot%d" % k
			var c: Color = spec.color
			s.light_color = c
			s.spot_range = 700.0
			s.spot_angle = 2.2
			s.spot_attenuation = 0.6
			s.spot_angle_attenuation = 1.6
			s.shadow_enabled = false
			s.light_specular = 0.2
			# A SpotLight shines down its -Z: turn it onto the beam's axis (+X turned k / n).
			s.rotation = Vector3(0.0, PI * 0.5 + TAU * float(k) / float(n), 0.0)
			s.position = Vector3(0.3, 0.0, 0.0).rotated(Vector3.UP, TAU * float(k) / float(n))
			s.visible = false
			rotor.add_child(s)
			rotor.spots.append(s)


## True where real volumetric spots are worth having: Forward+ (a RenderingDevice), not the web.
## The fog itself is the Environment's (Quality turns it on at HIGH); without it a spot is only a
## dim cone on the water, so the far shaft carries the beam alone.
static func spots_wanted(_n: Node) -> bool:
	if OS.has_feature("web") or RenderingServer.get_rendering_device() == null:
		return false
	return OS.get_environment("LIGHTHOUSE_SPOTS") != "0"


## The drawn shafts: `n` open cones from the lens out along +X turned k / n, `length` long, UV.x 0
## at the lens and 1 at the end. Cached per (n, length).
static func beam_mesh(n: int, length: float) -> Mesh:
	var key := "beam_%d_%d" % [n, int(length)]
	if _mats.has(key):
		return _mats[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 14
	var rings := [0.0, 0.004, 0.02, 0.06, 0.15, 0.32, 0.55, 0.8, 1.0]
	var spread := tan(deg_to_rad(1.9))
	for k in n:
		var yaw := TAU * float(k) / float(n)
		var b := Basis(Vector3.UP, yaw)
		for j in rings.size() - 1:
			var t0: float = rings[j]
			var t1: float = rings[j + 1]
			var r0 := 0.45 + spread * length * t0
			var r1 := 0.45 + spread * length * t1
			for i in sides:
				var a0 := TAU * float(i) / float(sides)
				var a1 := TAU * float(i + 1) / float(sides)
				var q := [
					[Vector3(length * t0, cos(a0) * r0, sin(a0) * r0), Vector3(0, cos(a0), sin(a0)), t0],
					[Vector3(length * t1, cos(a0) * r1, sin(a0) * r1), Vector3(0, cos(a0), sin(a0)), t1],
					[Vector3(length * t1, cos(a1) * r1, sin(a1) * r1), Vector3(0, cos(a1), sin(a1)), t1],
					[Vector3(length * t0, cos(a1) * r0, sin(a1) * r0), Vector3(0, cos(a1), sin(a1)), t0],
				]
				for vi in [0, 1, 2, 0, 2, 3]:
					var v: Array = q[vi]
					st.set_normal(b * (v[1] as Vector3))
					st.set_uv(Vector2(float(v[2]), 0.0))
					st.add_vertex(b * (v[0] as Vector3))
	var mesh := st.commit()
	_mats[key] = mesh
	return mesh


## One billboard quad at the origin for lighthouse_lamp.gdshader: four corners at the centre, UV
## the corner, UV2.x the core size.
static func lamp_mesh(size: float) -> Mesh:
	var key := "lamp_%.2f" % size
	if _mats.has(key):
		return _mats[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)]
	for c: Vector2 in corners:
		st.set_uv(c)
		st.set_uv2(Vector2(size, 0.0))
		st.set_normal(Vector3.BACK)
		st.add_vertex(Vector3.ZERO)
	var mesh := st.commit()
	# All four corners at one point: the renderer's bounds would be empty.
	mesh.custom_aabb = AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4))
	_mats[key] = mesh
	return mesh


## The porch across the front: a plank deck on a stone skirt, steps, turned posts with corner
## braces, a balustrade, a shed roof in shingle with a blue ceiling and a frieze.
static func _porch(g: LandmarkGeo, detailed: bool) -> void:
	var z0 := HALF
	var z1 := HALF + PORCH_DEPTH
	var x0 := -HALF - 0.4
	var x1 := HALF + 0.4
	g.box("stone", Vector3(0.0, (FLOOR0 - 0.2 - 1.0) * 0.5, (z0 + z1) * 0.5), Vector3(x1 - x0, FLOOR0 - 0.2 + 1.0, z1 - z0), STONE)
	g.box("planks", Vector3(0.0, FLOOR0 - 0.08, (z0 + z1) * 0.5 + 0.05), Vector3(x1 - x0 + 0.1, 0.16, z1 - z0 + 0.1), Color(0.62, 0.58, 0.52), Basis(), 0.0, true)
	# Steps down the middle.
	for s in 3:
		var step_top := FLOOR0 * float(3 - s) / 4.0
		g.box("stone", Vector3(0.0, step_top * 0.5 - 0.1, z1 + 0.16 + 0.32 * float(s)), Vector3(2.2, step_top + 0.2, 0.34), STONE, Basis(), 0.0, true)
	var posts := [x0 + 0.15, -2.6, -1.25, 1.25, 2.6, x1 - 0.15]
	var top := PORCH_TOP
	for px: float in posts:
		g.box("trim", Vector3(px, (FLOOR0 + top) * 0.5, z1 - 0.15), Vector3(0.17, top - FLOOR0, 0.17), WHITE)
		if detailed:
			g.box("trim", Vector3(px, FLOOR0 + 0.1, z1 - 0.15), Vector3(0.24, 0.2, 0.24), WHITE)
			g.box("trim", Vector3(px, top - 0.35, z1 - 0.15), Vector3(0.22, 0.12, 0.22), WHITE)
			# Corner braces (the stick-style's diagonal brackets).
			for dx: float in [-1.0, 1.0]:
				if (px + dx * 0.5) < x0 or (px + dx * 0.5) > x1:
					continue
				var b := Basis(Vector3.BACK, dx * PI * 0.25)
				g.box("trim", Vector3(px + dx * 0.24, top - 0.24, z1 - 0.15), Vector3(0.06, 0.5, 0.06), WHITE, b)
	# Posts on the wall.
	for px in [x0 + 0.15, x1 - 0.15]:
		g.box("trim", Vector3(px, (FLOOR0 + top) * 0.5, z0 + 0.15), Vector3(0.17, top - FLOOR0, 0.17), WHITE)
	# Balustrade: between the posts but the steps; and down the two ends.
	var runs: Array = []
	for i in posts.size() - 1:
		var a: float = posts[i]
		var b2: float = posts[i + 1]
		if absf(a + 1.25) < 0.01 and absf(b2 - 1.25) < 0.01:
			continue
		runs.append([Vector3(a + 0.09, 0.0, z1 - 0.15), Vector3(b2 - 0.09, 0.0, z1 - 0.15)])
	runs.append([Vector3(x0 + 0.15, 0.0, z0 + 0.25), Vector3(x0 + 0.15, 0.0, z1 - 0.24)])
	runs.append([Vector3(x1 - 0.15, 0.0, z0 + 0.25), Vector3(x1 - 0.15, 0.0, z1 - 0.24)])
	for run: Array in runs:
		var a3: Vector3 = run[0]
		var b3: Vector3 = run[1]
		var along := b3 - a3
		var length := along.length()
		var basis := Basis(Vector3.UP, atan2(-along.z, along.x))
		var mid := (a3 + b3) * 0.5
		g.box("trim", mid + Vector3(0.0, FLOOR0 + 0.95, 0.0), Vector3(length, 0.07, 0.12), WHITE, basis)
		if detailed:
			g.box("trim", mid + Vector3(0.0, FLOOR0 + 0.12, 0.0), Vector3(length, 0.06, 0.08), WHITE, basis)
			var n := int(length / 0.14)
			for k in n:
				var t := (float(k) + 0.5) / float(n)
				g.box("trim", a3.lerp(b3, t) + Vector3(0.0, FLOOR0 + 0.535, 0.0), Vector3(0.045, 0.77, 0.045), WHITE, basis)
	# The roof: a shed from the wall down to the posts, its ceiling and frieze.
	var hi := FLOOR1 + 0.05
	var col := Color(SHINGLE.r, SHINGLE.g, SHINGLE.b, 0.2)
	var slope := Vector3(0.0, top - hi, z1 + 0.35 - z0)
	var nrm := Vector3(0.0, z1 + 0.35 - z0, hi - top).normalized()
	var sl := slope.length()
	g.quad("shingle", Vector3(x0 - 0.2, hi, z0), Vector3(x1 + 0.2, hi, z0), Vector3(x1 + 0.2, top, z1 + 0.35), Vector3(x0 - 0.2, top, z1 + 0.35), nrm,
		Vector2(0.0, sl), Vector2(x1 - x0 + 0.4, sl), Vector2(x1 - x0 + 0.4, 0.0), Vector2(0.0, 0.0), col, true)
	g.quad("trim", Vector3(x0, top - 0.32, z0), Vector3(x1, top - 0.32, z0), Vector3(x1, top - 0.32, z1), Vector3(x0, top - 0.32, z1), Vector3.DOWN,
		Vector2.ZERO, Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), PORCH_CEILING)
	g.box("trim", Vector3(0.0, top - 0.17, z1 - 0.15), Vector3(x1 - x0 + 0.1, 0.3, 0.14), WHITE)
	g.box("trim", Vector3(0.0, top + 0.02, z1 + 0.33), Vector3(x1 - x0 + 0.42, 0.14, 0.05), OXBLOOD)
	for sx: float in [-1.0, 1.0]:
		var xe := x0 - 0.2 if sx < 0.0 else x1 + 0.2
		g.tri("trim", Vector3(xe, hi, z0), Vector3(xe, top, z1 + 0.35), Vector3(xe, top - 0.32, z0), Vector3(sx, 0.0, 0.0),
			Vector2(0, 0), Vector2(1, 1), Vector2(0, 1), WHITE)


## The lawn round the house, a gravel walk round it and out to the gate, and the picket fence.
static func _grounds(g: LandmarkGeo, detailed: bool) -> void:
	var r := Lighthouses.PAD_RADIUS - 1.5
	var segs := 28
	var poly := PackedVector2Array()
	for i in segs:
		var a := -TAU * float(i) / float(segs)
		poly.append(Vector2(cos(a), sin(a)) * r)
	g.cap("lawn", LandmarkGeo.ccw(poly), 0.03)
	# The walk: a ring round the foundation and a straight run from the steps to the gate.
	var w0 := HALF + 0.35
	var w1 := HALF + 1.6
	for side in 4:
		var b := Basis(Vector3.UP, PI * 0.5 * side)
		var q := [b * Vector3(-w1, 0.06, w1), b * Vector3(w1, 0.06, w1), b * Vector3(w0, 0.06, w0), b * Vector3(-w0, 0.06, w0)]
		g.quad("path", q[0], q[1], q[2], q[3], Vector3.UP, Vector2(q[0].x, q[0].z), Vector2(q[1].x, q[1].z), Vector2(q[2].x, q[2].z), Vector2(q[3].x, q[3].z))
	g.quad("path", Vector3(-1.0, 0.06, HALF + PORCH_DEPTH + 1.0), Vector3(1.0, 0.06, HALF + PORCH_DEPTH + 1.0), Vector3(1.0, 0.06, r), Vector3(-1.0, 0.06, r), Vector3.UP,
		Vector2(-1, 8.4), Vector2(1, 8.4), Vector2(1, r), Vector2(-1, r))
	if not detailed:
		return
	# A white picket fence on the lawn's edge, open at the walk.
	var fr := r - 0.4
	var count := int(TAU * fr / 0.16)
	for i in count:
		var a := TAU * float(i) / float(count)
		var p := Vector2(sin(a), cos(a)) * fr
		if absf(p.x) < 1.3 and p.y > 0.0:
			continue
		var b := Basis(Vector3.UP, a)
		g.box("trim", Vector3(p.x, 0.5, p.y), Vector3(0.075, 1.0, 0.022), WHITE, b)
		if i % 14 == 0:
			g.box("trim", Vector3(p.x, 0.55, p.y), Vector3(0.1, 1.1, 0.1), WHITE, b)
	var rails := 64
	for i in rails:
		var a0 := TAU * float(i) / float(rails)
		var a1 := TAU * float(i + 1) / float(rails)
		var p0 := Vector2(sin(a0), cos(a0)) * (fr - 0.03)
		var p1 := Vector2(sin(a1), cos(a1)) * (fr - 0.03)
		var mid := (p0 + p1) * 0.5
		if absf(mid.x) < 1.3 and mid.y > 0.0:
			continue
		var along := p1 - p0
		var basis := Basis(Vector3.UP, atan2(-along.y, along.x))
		for y in [0.3, 0.8]:
			g.box("trim", Vector3(mid.x, y, mid.y), Vector3(along.length() + 0.02, 0.07, 0.03), WHITE, basis)


## Palms and a hedge of shrubs in the lawn (batches; far too, shadowless there).
static func _planting(root: Node3D, detailed: bool) -> void:
	var batch := MultiMeshBatch.new()
	var spots := [Vector3(-12.5, 0.0, 7.5), Vector3(13.0, 0.0, 4.0), Vector3(-11.0, 0.0, -10.0), Vector3(9.5, 0.0, -12.5)]
	for i in spots.size():
		var v := i % 3
		var s := 1.05 + 0.12 * float(i % 2)
		batch.add("palm_%d" % v, PropFactory.palm(v), Transform3D(Basis(Vector3.UP, float(i) * 2.1).scaled(Vector3(s, s, s)), spots[i]))
	if not detailed:
		ArenaGrounds._far_shadows(batch)
	batch.build(root)


## The porch's lantern by the door: a small light that comes on with the street lamps.
static func _porch_light(root: Node3D) -> void:
	if OS.has_feature("web"):
		return
	var l := OmniLight3D.new()
	l.name = "PorchLight"
	l.position = Vector3(0.0, PORCH_TOP - 0.55, HALF + 1.2)
	l.light_color = Color(1.0, 0.78, 0.5)
	l.omni_range = 9.0
	l.omni_attenuation = 1.4
	l.shadow_enabled = false
	l.light_energy = 0.0
	l.distance_fade_enabled = true
	l.distance_fade_begin = 60.0
	l.distance_fade_length = 20.0
	l.add_to_group("lamp_light")
	root.add_child(l)


## The house's collision: the body, the porch deck, the tower, the gallery and the lantern
## (the roofs are concave triangles already, from the quads marked collide).
static func _shapes_lighthouse(body: StaticBody3D) -> void:
	LandmarkGeo.shape_box(body, Vector3(0.0, EAVE * 0.5 - 0.3, 0.0), Vector3(HALF * 2.0, EAVE + 0.6, HALF * 2.0))
	LandmarkGeo.shape_box(body, Vector3(0.0, (TOWER_TOP + EAVE) * 0.5, 0.0), Vector3(TOWER_HALF * 2.0, TOWER_TOP - EAVE, TOWER_HALF * 2.0))
	LandmarkGeo.shape_box(body, Vector3(0.0, (TOWER_TOP + GALLERY) * 0.5, 0.0), Vector3(4.7, GALLERY - TOWER_TOP, 4.7))
	LandmarkGeo.shape_box(body, Vector3(0.0, GALLERY + 2.0, 0.0), Vector3(2.4, 4.0, 2.4))


# --- The breakwater light ------------------------------------------------------------------------

## HARBOR GATE LIGHT on its pier at the breakwater's head `at` (world XZ), the breakwater running
## in along -`dir`.
static func build_gate(parent: Node3D, statics: StaticBody3D, at: Vector2, dir: Vector2, detailed: bool) -> void:
	var root := Node3D.new()
	root.name = "HarborGateLight"
	# Front (+Z) faces out to sea along the breakwater.
	root.transform = Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.y)), Vector3(at.x, 0.0, at.y))
	parent.add_child(root)
	var body: StaticBody3D = null
	if statics:
		body = StaticBody3D.new()
		body.name = "GateLightBody"
		body.collision_mask = 0
		body.transform = root.transform
		statics.add_child(body)
		LandmarkGeo.shape_box(body, Vector3(0.0, Lighthouses.PIER_TOP + 5.6, 0.0), Vector3(5.6, 11.0, 5.6))
	_place(root, body, "gate_near" if detailed else "gate_far", _gate_geo.bind(detailed), "GateLightMesh")
	_rotor(root, Lighthouses.GATE_ID, Vector3(0.0, GATE_GALLERY, 0.0), detailed)
	# The rubble apron round the pier.
	_apron(root, detailed)


## The gate tower's gallery floor over the water.
const GATE_GALLERY := Lighthouses.PIER_TOP + 0.24 + 4.6 + 0.35 + 6.3 + 0.45


static func _gate_geo(detailed: bool) -> LandmarkGeo:
	var g := LandmarkGeo.new()
	for k in ["concrete", "trim", "dark", "metal", "glass", "lantern_glass"]:
		g.use(k, mat(k))
	var top := Lighthouses.PIER_TOP
	var ph := Lighthouses.PIER_HALF
	# The pier block, its coping and the fenders.
	g.box("concrete", Vector3(0.0, (top + Lighthouses.FOOT_Y) * 0.5, 0.0), Vector3(ph * 2.0, top - Lighthouses.FOOT_Y, ph * 2.0), CONCRETE, Basis(), 0.0, true)
	g.box("concrete", Vector3(0.0, top + 0.12, 0.0), Vector3(ph * 2.0 + 0.3, 0.24, ph * 2.0 + 0.3), Color(0.86, 0.85, 0.82))
	if detailed:
		for side in 4:
			var b := Basis(Vector3.UP, PI * 0.5 * side)
			for i in 4:
				var t := -ph + 1.6 + (ph * 2.0 - 3.2) * float(i) / 3.0
				g.box("dark", b * Vector3(t, top - 2.4, ph + 0.18), Vector3(0.35, 4.6, 0.32), Color(0.16, 0.13, 0.1), b)
		_pipe_rail(g, ph - 0.25, top + 0.24)
	# The tower: two octagonal stages of alternating black and white faces, a cornice between.
	var c := Vector2.ZERO
	var y := top + 0.24
	_oct_stage(g, c, 3.4, y, y + 4.6, detailed, 0)
	y += 4.6
	g.band("trim", c, Vector2(3.55, 3.55), Vector2(3.75, 3.75), y, y + 0.35, 0.0, TAU, 8, WHITE)
	g.ring_flat("trim", c, Vector2(2.75, 2.75), Vector2(3.75, 3.75), y + 0.35, 0.0, TAU, 8, WHITE)
	y += 0.35
	_oct_stage(g, c, 2.75, y, y + 6.3, detailed, 1)
	y += 6.3
	# Corbelled gallery and its rail.
	g.band("trim", c, Vector2(2.75, 2.75), Vector2(3.2, 3.2), y, y + 0.45, 0.0, TAU, 8, WHITE)
	g.ring_flat("metal", c, Vector2(0.0, 0.0), Vector2(3.2, 3.2), y + 0.45, 0.0, TAU, 8, IRON)
	y += 0.45
	_oct_rail(g, c, 3.1, y, detailed)
	# The lantern (green).
	_lantern(g, Vector3(0.0, y, 0.0), 1.35, detailed)
	if detailed:
		# Fog trumpets on the pier, the door and its landing, a ladder down the pier's face.
		for sx in [-1.0, 1.0]:
			var p := Vector3(sx * 4.8, top + 0.24, 4.6)
			g.cylinder("metal", p, 0.12, 0.9, 8, IRON)
			g.cylinder("metal", p + Vector3(0.0, 0.9, 0.0), 0.12, 0.55, 10, IRON, 0.42, false, false)
			g.ring_flat("dark", Vector2(p.x, p.z), Vector2(0.0, 0.0), Vector2(0.42, 0.42), p.y + 1.43, 0.0, TAU, 10, BLACK)
		g.box("dark", Vector3(0.0, top + 1.35, 3.4 * 0.924 + 0.02), Vector3(1.0, 2.1, 0.06), Color(0.15, 0.17, 0.16))
		for k in 18:
			g.box("metal", Vector3(ph - 1.2, top - 0.3 - 0.3 * float(k), ph + 0.06), Vector3(0.5, 0.03, 0.03), IRON)
		for sx in [-1.0, 1.0]:
			g.box("metal", Vector3(ph - 1.2 + sx * 0.25, top - 2.9, ph + 0.06), Vector3(0.04, 6.0, 0.04), IRON)
	return g


## One octagonal stage of the gate tower: faces alternately white and black (`flip` starts with
## black), with round-headed windows on two faces.
static func _oct_stage(g: LandmarkGeo, c: Vector2, r: float, y0: float, y1: float, detailed: bool, flip: int) -> void:
	var segs := 8
	for i in segs:
		var a0 := TAU * float(i) / float(segs) + PI / 8.0
		var a1 := TAU * float(i + 1) / float(segs) + PI / 8.0
		var p0 := c + Vector2(cos(a0), sin(a0)) * r
		var p1 := c + Vector2(cos(a1), sin(a1)) * r
		var col := BLACK if (i + flip) % 2 == 0 else WHITE
		var mid := (p0 + p1) * 0.5
		var n := Vector3(mid.x, 0.0, mid.y).normalized()
		var wkey := "concrete" if col == WHITE else "dark"
		g.quad(wkey, Vector3(p0.x, y0, p0.y), Vector3(p0.x, y1, p0.y), Vector3(p1.x, y1, p1.y), Vector3(p1.x, y0, p1.y), n,
			Vector2(0, y0), Vector2(0, y1), Vector2(p0.distance_to(p1), y1), Vector2(p0.distance_to(p1), y0), col)
		if detailed and i % 4 == 1:
			var w := Vector3(mid.x, (y0 + y1) * 0.55, mid.y) + n * 0.02
			g.box("glass", w, Vector3(0.7, 1.3, 0.04), Color(BLIND.r, BLIND.g, BLIND.b, 0.3), Basis(Vector3.UP, atan2(n.x, n.z)))
			g.box("trim", w + Vector3(0.0, 0.75, 0.0), Vector3(0.95, 0.18, 0.08), WHITE, Basis(Vector3.UP, atan2(n.x, n.z)))


## An octagonal pipe rail at radius `r` (the gate's gallery).
static func _oct_rail(g: LandmarkGeo, c: Vector2, r: float, y: float, detailed: bool) -> void:
	for i in 8:
		var a0 := TAU * float(i) / 8.0 + PI / 8.0
		var a1 := TAU * float(i + 1) / 8.0 + PI / 8.0
		var p0 := c + Vector2(cos(a0), sin(a0)) * r
		var p1 := c + Vector2(cos(a1), sin(a1)) * r
		var mid := (p0 + p1) * 0.5
		var along := p1 - p0
		var b := Basis(Vector3.UP, atan2(-along.y, along.x))
		g.box("metal", Vector3(mid.x, y + 1.0, mid.y), Vector3(along.length(), 0.05, 0.05), IRON, b)
		if detailed:
			g.box("metal", Vector3(mid.x, y + 0.5, mid.y), Vector3(along.length(), 0.035, 0.035), IRON, b)
			for k in 4:
				var p := p0.lerp(p1, float(k) / 4.0)
				g.box("metal", Vector3(p.x, y + 0.5, p.y), Vector3(0.04, 1.0, 0.04), IRON, b)


## A pipe rail round the pier's top, open on the breakwater side.
static func _pipe_rail(g: LandmarkGeo, half: float, y: float) -> void:
	for side in 4:
		if side == 2:
			continue
		var b := Basis(Vector3.UP, PI * 0.5 * side)
		for h in [0.55, 1.05]:
			g.box("metal", b * Vector3(0.0, y + h, half), Vector3(half * 2.0, 0.05, 0.05), Color(0.75, 0.62, 0.1), b)
		for i in 9:
			var t := -half + half * 2.0 * float(i) / 8.0
			g.box("metal", b * Vector3(t, y + 0.55, half), Vector3(0.05, 1.1, 0.05), Color(0.75, 0.62, 0.1), b)


## Armour stones heaped round the pier block (rotated into its frame).
static func _apron(root: Node3D, detailed: bool) -> void:
	var batch := MultiMeshBatch.new()
	var ph := Lighthouses.PIER_HALF
	var count := 140 if detailed else 0
	for i in count:
		var a := TAU * _h(["apron", i, "a"])
		var d := Vector2(cos(a), sin(a))
		# Out from the block's face along d: the square's edge distance in that direction.
		var edge := ph / maxf(absf(d.x), absf(d.y))
		var off := lerpf(0.4, 7.0, _h(["apron", i, "o"]))
		var p := d * (edge + off)
		var y := lerpf(2.8, -0.8, off / 7.0) + (_h(["apron", i, "y"]) - 0.5) * 0.6
		var s := lerpf(0.85, 1.35, _h(["apron", i, "s"]))
		var basis := Basis.from_euler(Vector3(_h(["apron", i, "x"]) * 0.6 - 0.3, _h(["apron", i, "r"]) * TAU, _h(["apron", i, "z"]) * 0.6 - 0.3)).scaled(Vector3(s, s, s))
		var k := i % STONE_SHAPES
		batch.add("bw_stone_%d" % k, stone_mesh(k), Transform3D(basis, Vector3(p.x, y, p.y)), _stone_tint(["apron", i]))
	batch.build(root)


# --- The breakwater -------------------------------------------------------------------------------

## One piece of the breakwater (Lighthouses.segments()[k]): the mound, the walkway cap and the
## foam; detailed adds the armour stones and the cap's collision.
static func build_breakwater(parent: Node3D, statics: StaticBody3D, k: int, _plan: CityPlan, detailed: bool) -> void:
	var seg: Dictionary = Lighthouses.segments()[k]
	var a: Vector2 = seg.a
	var b: Vector2 = seg.b
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x)
	# The head's last piece stops short of the pier block.
	if bool(seg.last):
		b -= d * (Lighthouses.PIER_HALF - 0.5)
	var length := a.distance_to(b)
	var root := Node3D.new()
	root.name = "Breakwater_%d" % k
	parent.add_child(root)
	var g := LandmarkGeo.new()
	g.use("core", mat("armour_far"))
	g.use("concrete", mat("concrete"))
	g.use("foam", mat("foam"))
	var crest := Lighthouses.CREST_Y
	var ch := Lighthouses.CREST_HALF
	var foot := Lighthouses.FOOT_Y
	var toe := ch + (crest - foot) * Lighthouses.FACE_SLOPE
	var step := 4.0 if detailed else 8.0
	var steps := maxi(1, int(ceil(length / step)))
	# The mound's cross-section, lumped along its length: [offset across, height].
	var prof := [[-toe, foot], [-ch, crest], [ch, crest], [toe, foot]]
	var s0: float = seg.s0
	for i in steps:
		var t0 := float(i) / float(steps)
		var t1 := float(i + 1) / float(steps)
		var c0 := a.lerp(b, t0)
		var c1 := a.lerp(b, t1)
		for j in prof.size() - 1:
			var o0: float = prof[j][0]
			var o1: float = prof[j + 1][0]
			var y0: float = prof[j][1]
			var y1: float = prof[j + 1][1]
			var l0 := _lump(s0 + length * t0, o0)
			var l1 := _lump(s0 + length * t0, o1)
			var l2 := _lump(s0 + length * t1, o1)
			var l3 := _lump(s0 + length * t1, o0)
			var p00 := c0 + n * o0
			var p01 := c0 + n * o1
			var p11 := c1 + n * o1
			var p10 := c1 + n * o0
			var want := Vector3(n.x * (y0 - y1), absf(o1 - o0), n.y * (y0 - y1)).normalized()
			if j == 1:
				want = Vector3.UP
			g.quad("core", Vector3(p00.x, y0 + l0, p00.y), Vector3(p01.x, y1 + l1, p01.y), Vector3(p11.x, y1 + l2, p11.y), Vector3(p10.x, y0 + l3, p10.y), want,
				Vector2.ZERO, Vector2.ONE, Vector2.ONE, Vector2.ZERO, Color(0.92, 0.9, 0.86), true)
	# The walkway cap: concrete slabs with joints every 6 m (a separate box each, a hair apart).
	var cap_top := Lighthouses.CAP_TOP
	var cw := Lighthouses.CAP_WIDTH
	var slabs := maxi(1, int(round(length / 6.0)))
	var yaw := Basis(Vector3.UP, atan2(-d.y, d.x))
	for i in slabs:
		var m := a.lerp(b, (float(i) + 0.5) / float(slabs))
		g.box("concrete", Vector3(m.x, cap_top - 0.7, m.y), Vector3(length / slabs - 0.03, 1.4, cw), CONCRETE, yaw, 0.04 if detailed else 0.0)
	if statics:
		var body := StaticBody3D.new()
		body.name = "BreakwaterBody_%d" % k
		body.collision_mask = 0
		statics.add_child(body)
		var mid := (a + b) * 0.5
		LandmarkGeo.shape_box(body, Vector3(mid.x, cap_top - 0.7, mid.y), Vector3(length, 1.4, cw), yaw)
		g.commit_collision(body)
	# White water along both feet.
	for side: float in [-1.0, 1.0]:
		var w_in := ch + (crest - Lighthouses.WATER_Y) * Lighthouses.FACE_SLOPE - 0.6
		var w_out := w_in + 5.5
		var fy := Lighthouses.WATER_Y + 0.22
		var fsteps := maxi(1, int(ceil(length / 8.0)))
		for i in fsteps:
			var t0 := float(i) / float(fsteps)
			var t1 := float(i + 1) / float(fsteps)
			var c0 := a.lerp(b, t0)
			var c1 := a.lerp(b, t1)
			var q0 := c0 + n * side * w_in
			var q1 := c1 + n * side * w_in
			var q2 := c1 + n * side * w_out
			var q3 := c0 + n * side * w_out
			var u0 := s0 + length * t0
			var u1 := s0 + length * t1
			g.quad("foam", Vector3(q0.x, fy, q0.y), Vector3(q1.x, fy, q1.y), Vector3(q2.x, fy, q2.y), Vector3(q3.x, fy, q3.y), Vector3.UP,
				Vector2(u0, 0.0), Vector2(u1, 0.0), Vector2(u1, 1.0), Vector2(u0, 1.0))
	var mi := g.commit(root, "BreakwaterMesh")
	if mi and not detailed:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if detailed:
		_armour(root, a, b, s0, k)


## Lumps on the mound so its faces are not planes: a few decimetres by hash of a 3 m lattice.
static func _lump(s: float, o: float) -> float:
	if absf(o) < Lighthouses.CREST_HALF + 0.01 and absf(o) > Lighthouses.CREST_HALF - 0.01:
		return 0.0
	var i := int(floor(s / 3.0))
	var f := s / 3.0 - float(i)
	var a := _h(["lump", i, int(o * 10.0)])
	var b := _h(["lump", i + 1, int(o * 10.0)])
	return (lerpf(a, b, f * f * (3.0 - 2.0 * f)) - 0.5) * 0.9


## The armour stones of one piece: rows down both faces from the cap's edge to below the water,
## each stone seated on the face, tilted with it and turned at random, a shape and a shade by
## hash. One MultiMesh per shape.
static func _armour(root: Node3D, a: Vector2, b: Vector2, s0: float, k: int) -> void:
	var batch := MultiMeshBatch.new()
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x)
	var length := a.distance_to(b)
	var crest := Lighthouses.CREST_Y
	var ch := Lighthouses.CREST_HALF
	var slope := Lighthouses.FACE_SLOPE
	# Rows by horizontal offset from the crest line; the last ones are under water.
	var rows := [2.85, 4.6, 6.4, 8.2, 10.0, 11.8]
	var face_n := Vector3(0.0, 1.0, 0.0)
	for side: float in [-1.0, 1.0]:
		var fn2 := n * side
		face_n = Vector3(fn2.x, slope, fn2.y).normalized()
		for r in rows.size():
			var off: float = rows[r]
			var spacing := 1.95 + 0.25 * float(r % 2)
			var count := int(length / spacing)
			for i in count:
				var key := [k, side, r, i]
				var u := (float(i) + 0.5 + (_h(key + ["u"]) - 0.5) * 0.6) * length / float(count)
				var o := off + (_h(key + ["o"]) - 0.5) * 0.9
				var y := crest - maxf(o - ch, 0.0) / slope
				var p := a + d * u + fn2 * o
				var s := lerpf(0.85, 1.45, _h(key + ["s"]))
				var up := face_n if o > ch + 0.2 else Vector3.UP
				# A frame with Y along the face's normal, turned about it at random, tipped a little.
				var spin := Basis(Vector3.UP, _h(key + ["r"]) * TAU)
				var tip := Basis(Vector3(1, 0, 0), (_h(key + ["x"]) - 0.5) * 0.5) * Basis(Vector3(0, 0, 1), (_h(key + ["z"]) - 0.5) * 0.5)
				var basis := _align_up(up) * spin * tip
				basis = basis.scaled(Vector3(s, s, s))
				var at := Vector3(p.x, y - 0.25 * s, p.y)
				var sh := absi(hash(key + ["k"])) % STONE_SHAPES
				batch.add("bw_stone_%d" % sh, stone_mesh(sh), Transform3D(basis, at), _stone_tint(key))
	batch.build(root)


## A basis whose Y is `up`.
static func _align_up(up: Vector3) -> Basis:
	var axis := Vector3.UP.cross(up)
	if axis.length_squared() < 1e-8:
		return Basis()
	return Basis(axis.normalized(), Vector3.UP.angle_to(up))


## A stone's shade (sRGB as written; armour_stone.gdshader decodes it): grey granite, some
## warmer, a few darker.
static func _stone_tint(key: Array) -> Color:
	var v := _h(key + ["tint"])
	var w := _h(key + ["warm"])
	var base := lerpf(0.82, 1.08, v)
	return Color(base * lerpf(1.0, 1.08, w), base * lerpf(1.0, 1.02, w), base * lerpf(1.0, 0.92, w))


## Armour stone shape `k`: a quarried block (a box with each corner chipped off by its own depth,
## faces nudged) about 2.2 x 1.4 x 1.8 m, flat-shaded, ~44 triangles. Cached.
static func stone_mesh(k: int) -> Mesh:
	while _stones.size() < STONE_SHAPES:
		_stones.append(_make_stone(_stones.size()))
	return _stones[k]


static func _make_stone(k: int) -> Mesh:
	var hx := lerpf(0.9, 1.3, _h(["stone", k, "x"]))
	var hy := lerpf(0.55, 0.85, _h(["stone", k, "y"]))
	var hz := lerpf(0.7, 1.1, _h(["stone", k, "z"]))
	var h := Vector3(hx, hy, hz)
	var m := minf(hx, minf(hy, hz))
	# Per corner: the three points where its chip plane cuts the three edges.
	var corner_pts := {}
	for sx in [-1, 1]:
		for sy in [-1, 1]:
			for sz in [-1, 1]:
				var cut := m * lerpf(0.18, 0.55, _h(["stone", k, sx, sy, sz]))
				var s := Vector3(sx, sy, sz)
				var pts: Array[Vector3] = []
				for ax in 3:
					var p := h * s
					p[ax] -= s[ax] * cut * lerpf(0.7, 1.3, _h(["stone", k, sx, sy, sz, ax]))
					pts.append(p)
				corner_pts[Vector3i(sx, sy, sz)] = pts
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var add_tri := func(p0: Vector3, p1: Vector3, p2: Vector3, want: Vector3) -> void:
		var nrm := (p2 - p0).cross(p1 - p0)
		if nrm.dot(want) < 0.0:
			var t := p1
			p1 = p2
			p2 = t
			nrm = -nrm
		nrm = nrm.normalized()
		for p: Vector3 in [p0, p1, p2]:
			st.set_normal(nrm)
			st.set_uv(Vector2(p.x + p.z, p.y))
			st.add_vertex(p)
	# Faces: the points of the four corners that lie on each face, in order round it.
	for ax in 3:
		for sgn in [-1, 1]:
			var pts: Array[Vector3] = []
			for key: Vector3i in corner_pts:
				if key[ax] != sgn:
					continue
				var cp: Array = corner_pts[key]
				for j in 3:
					if j != ax:
						pts.append(cp[j])
			var fc := Vector3.ZERO
			for p in pts:
				fc += p
			fc /= float(pts.size())
			# A face bulges a few centimetres: its centre pushed out.
			var want := Vector3.ZERO
			want[ax] = float(sgn)
			fc += want * m * 0.08 * _h(["stone", k, ax, sgn, "bulge"])
			var u_ax := (ax + 1) % 3
			var v_ax := (ax + 2) % 3
			pts.sort_custom(func(p: Vector3, q: Vector3) -> bool:
				return atan2(p[v_ax] - fc[v_ax], p[u_ax] - fc[u_ax]) < atan2(q[v_ax] - fc[v_ax], q[u_ax] - fc[u_ax]))
			for i in pts.size():
				add_tri.call(fc, pts[i], pts[(i + 1) % pts.size()], want)
	for key: Vector3i in corner_pts:
		var cp: Array = corner_pts[key]
		add_tri.call(cp[0], cp[1], cp[2], Vector3(key))
	var mesh := st.commit()
	mesh.surface_set_material(0, mat("armour"))
	return mesh
