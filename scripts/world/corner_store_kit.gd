class_name CornerStoreKit
extends RefCounted
## The corner store's geometry (CornerStore): everything built in code at real size in the store's
## own frame (x across the front, y up from the floor, z out of the front face; the room is z < 0;
## CornerStore.layout() has the numbers). LandmarkGeo meshes on ONE material
## (shaders/corner_store.gdshader, the kind in the vertex alpha: K_*), the glass on
## corner_store_glass.gdshader (the traced room) or corner_store_clear.gdshader (the real one
## behind it), the products as one MultiMesh per kind on corner_store_goods.gdshader.
##
## FULL chunks only. The shell, the glass, the door and the collision are built in the lot's
## step; the interior (walls inside, floor, ceiling, shelving, coolers, counter: ~6-9k triangles),
## the products (~2,000 instances, ~110k triangles, no shadows) and the people are three deferred
## build steps (CityChunk._run_or_defer), hidden until CornerStoreSite shows them.

# Kinds in corner_store.gdshader (the vertex alpha x 32).
const K_STUCCO := 0
const K_PAINT := 1
const K_FLOOR := 2
const K_CEILING := 3
const K_TROFFER := 4
const K_ALUMINIUM := 5
const K_STEEL := 6
const K_SHELF := 7
const K_LAMINATE := 8
const K_SIGN := 9
const K_LETTERS := 10
const K_GLOW := 11
const K_RUBBER := 12
const K_TILE := 13
const K_CONCRETE := 14
const K_PEGBOARD := 15
const K_SCREEN := 16
const K_POSTER := 17
const K_NEON := 18
const K_CHROME := 19
const K_ROOF := 20
const K_WIRE := 21
const K_PRICE := 22

# Product parts in corner_store_goods.gdshader (the vertex alpha x 8).
const P_BODY := 0
const P_LABEL := 1
const P_CAP := 2
const P_CLEAR := 3
const P_SIDE := 4

## The product meshes: unit size (x, z -0.5..0.5, y 0..1), scaled per instance.
enum Goods { BOX, CAN, BOTTLE, BAG }

## Shelf heights (from the floor) on the back wall, the gondolas and in the coolers.
const BACK_SHELVES := [0.14, 0.52, 0.90, 1.28, 1.66]
const GONDOLA_SHELVES := [0.14, 0.52, 0.90, 1.28]
const COOLER_SHELVES := [0.16, 0.54, 0.92, 1.30, 1.66]
const WALL_PAINT := Color(0.93, 0.92, 0.88)
const FLOOR_TONE := Color(0.88, 0.86, 0.80)
const SHELF_TONE := Color(0.88, 0.88, 0.86)
const COUNTER_TONE := Color(0.46, 0.30, 0.20)
const STEEL_TONE := Color(0.16, 0.16, 0.17)
const ALU_TONE := Color(0.70, 0.71, 0.72)
## Product families: [goods kind, width, height, depth (m) ranges as Vector2s].
const FAMILIES := {
	"bag": [Goods.BAG, Vector2(0.15, 0.24), Vector2(0.22, 0.31), Vector2(0.06, 0.08)],
	"box": [Goods.BOX, Vector2(0.12, 0.20), Vector2(0.17, 0.30), Vector2(0.05, 0.08)],
	"small": [Goods.BOX, Vector2(0.05, 0.09), Vector2(0.08, 0.14), Vector2(0.03, 0.05)],
	"can": [Goods.CAN, Vector2(0.066, 0.068), Vector2(0.11, 0.123), Vector2(0.066, 0.068)],
	"tall_can": [Goods.CAN, Vector2(0.058, 0.06), Vector2(0.15, 0.16), Vector2(0.058, 0.06)],
	"bottle": [Goods.BOTTLE, Vector2(0.066, 0.07), Vector2(0.21, 0.245), Vector2(0.066, 0.07)],
	"big_bottle": [Goods.BOTTLE, Vector2(0.10, 0.11), Vector2(0.30, 0.33), Vector2(0.10, 0.11)],
	"jug": [Goods.BOTTLE, Vector2(0.15, 0.16), Vector2(0.25, 0.27), Vector2(0.15, 0.16)],
	"case": [Goods.BOX, Vector2(0.26, 0.28), Vector2(0.12, 0.13), Vector2(0.38, 0.40)],
	"jar": [Goods.CAN, Vector2(0.08, 0.10), Vector2(0.12, 0.17), Vector2(0.08, 0.10)],
	"pack": [Goods.BOX, Vector2(0.055, 0.056), Vector2(0.086, 0.088), Vector2(0.022, 0.023)],
	"candy": [Goods.BOX, Vector2(0.03, 0.05), Vector2(0.12, 0.16), Vector2(0.015, 0.02)],
	"cereal": [Goods.BOX, Vector2(0.19, 0.21), Vector2(0.28, 0.31), Vector2(0.06, 0.07)],
	"detergent": [Goods.BOTTLE, Vector2(0.15, 0.17), Vector2(0.27, 0.31), Vector2(0.10, 0.12)],
	"tub": [Goods.CAN, Vector2(0.11, 0.13), Vector2(0.07, 0.10), Vector2(0.11, 0.13)],
}
const BACK_MIX := [["bag", "bag", "small"], ["cereal", "box", "bag"], ["box", "jar", "tub"], ["can", "jar", "tub"], ["detergent", "big_bottle", "box"]]
const GONDOLA_MIX := [["can", "jar", "box", "tub"], ["box", "small", "can"], ["bag", "cereal", "box"], ["bag", "small", "jar"]]
## The signs hung over the aisles (generic words, no brands).
const AISLE_SIGNS := ["SNACKS", "CANDY", "GROCERY", "HOUSEHOLD", "CHIPS & DIPS", "CEREAL", "CANNED FOOD", "PET FOOD", "BAKERY"]
const COOLER_MIX := [["case", "jug"], ["big_bottle", "jug"], ["bottle", "tall_can"], ["bottle", "can"], ["tall_can", "bottle"]]

static var _materials: Dictionary = {}
static var _goods_meshes: Dictionary = {}
## Triangles of the last interior and product build (the probe and the checks read these).
static var last_interior_tris: int = 0
static var last_goods: int = 0
## Microseconds the last store spent in each build step: the lot's, shell, glass and door,
## interior, goods, people.
static var last_step_us: Array = [0, 0, 0, 0, 0, 0]


# --- Materials -----------------------------------------------------------------------------------

static func kit_material() -> ShaderMaterial:
	if _materials.has("kit"):
		return _materials.kit
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/corner_store.gdshader")
	m.set_shader_parameter("plaster_tex", PropFactory.texture("plaster_painted", "Color"))
	m.set_shader_parameter("plaster_nrm", PropFactory.texture("plaster_painted", "NormalGL"))
	_materials.kit = m
	return m


static func goods_material() -> ShaderMaterial:
	if _materials.has("goods"):
		return _materials.goods
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/corner_store_goods.gdshader")
	m.set_shader_parameter("labels", load("res://assets/textures/corner_store/goods_labels.jpg"))
	_materials.goods = m
	return m


static func clear_material() -> ShaderMaterial:
	if _materials.has("clear"):
		return _materials.clear
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/corner_store_clear.gdshader")
	_materials.clear = m
	return m


## The traced room for one store's glass (its own copy: the layout is in its uniforms). Colours go
## in as Vector3 (sRGB numbers, decoded in the shader): a Color set from script would be decoded
## again on Forward+.
static func traced_material(s: Dictionary, lay: Dictionary, to_store: Transform3D) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/corner_store_glass.gdshader")
	var cs: float = lay.cs
	m.set_shader_parameter("to_store", Projection(to_store))
	m.set_shader_parameter("room", Vector4(lay.ix0, lay.ix1, lay.iz0, lay.iz1))
	m.set_shader_parameter("ceiling", CornerStore.CEILING)
	m.set_shader_parameter("back_depth", CornerStore.BACK_SHELF)
	m.set_shader_parameter("back_height", 2.1)
	var wall_x: float = -cs * float(lay.ix1)
	var cz: Vector2 = lay.cooler_z
	m.set_shader_parameter("cooler", Vector4(wall_x, lay.cooler_face, cz.x, cz.y) if int(lay.n_doors) > 0 else Vector4(wall_x, wall_x, -1.0, -1.0))
	m.set_shader_parameter("cooler_height", 2.3)
	m.set_shader_parameter("cooler_door", CornerStore.COOLER_DOOR)
	var kz: Vector2 = lay.counter_z
	m.set_shader_parameter("counter", Vector3(lay.counter_x, kz.x, kz.y))
	m.set_shader_parameter("rack", Vector2(cs * float(lay.ix1), -cs))
	var gx := Vector4.ZERO
	var gs: Array = lay.gondolas
	for i in mini(gs.size(), 4):
		gx[i] = gs[i]
	m.set_shader_parameter("gondola_x", gx)
	m.set_shader_parameter("gondola_count", mini(gs.size(), 4))
	var gz: Vector2 = lay.g_z
	m.set_shader_parameter("gondola_zh", Vector3(gz.x, gz.y, lay.g_h))
	m.set_shader_parameter("wall_color", _v3(WALL_PAINT))
	m.set_shader_parameter("floor_color", _v3(FLOOR_TONE))
	m.set_shader_parameter("shelf_color", _v3(SHELF_TONE))
	m.set_shader_parameter("seed", float(int(s.seed) % 977) * 0.731)
	return m


static func _v3(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)


static func _k(c: Color, kind: int) -> Color:
	return Color(c.r, c.g, c.b, float(kind) / 32.0)


## LandmarkGeo's surfaces as one MeshInstance3D, unindexed and without tangents (nothing here
## is normal-mapped): LandmarkGeo.commit()'s index and tangent passes were most of a step.
static func _commit(g: LandmarkGeo, parent: Node3D, node_name: String, shadow: bool) -> MeshInstance3D:
	var mesh := ArrayMesh.new()
	for key: String in g._order:
		var sf: Dictionary = g._surfaces[key]
		if int(sf.n) == 0:
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = sf.v
		arrays[Mesh.ARRAY_NORMAL] = sf.nrm
		arrays[Mesh.ARRAY_TEX_UV] = sf.uv
		arrays[Mesh.ARRAY_COLOR] = sf.col
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, sf.mat)
	g._surfaces.clear()
	g._order.clear()
	if mesh.get_surface_count() == 0:
		return null
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


# --- The store -----------------------------------------------------------------------------------

## Builds store `s` into chunk `ch` at `xf` (the store's frame in the chunk).
static func build(ch: CityChunk, s: Dictionary, lay: Dictionary, xf: Transform3D) -> void:
	var t0 := Time.get_ticks_usec()
	var site := CornerStoreSite.new()
	site.name = "CornerStore_%d" % (int(s.seed) % 100000)
	site.transform = xf
	site.add_to_group("corner_store")
	site.set_meta("seed", int(s.seed))
	site.set_meta("name", String(s.name))
	site.store = s
	site.lay = lay
	ch.add_child(site)
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = 1
	body.collision_mask = 0
	site.add_child(body)
	var interior := Node3D.new()
	interior.name = "Interior"
	interior.visible = false
	site.add_child(interior)
	site.interior = interior
	_collision(body, lay)
	last_step_us[0] = Time.get_ticks_usec() - t0
	# The outside, the glass and door, the interior, the goods and the people: deferred build
	# steps, in order (the chunk is swapped in only once they are all done).
	var state := {"phase": 0}
	ch._run_or_defer(func() -> bool:
		if not is_instance_valid(site):
			return true
		var ts := Time.get_ticks_usec()
		var phase := int(state.phase)
		match phase:
			0:
				_shell(site, body, s, lay, ch, xf)
			1:
				_glass(site, s, lay)
				_door(site, s, lay)
			2:
				_interior(site, s, lay)
			3:
				_goods(site, s, lay)
			_:
				_people(ch, site, s, lay, xf)
				site.interior_ready = true
		last_step_us[mini(phase + 1, 5)] = Time.get_ticks_usec() - ts
		if phase >= 4:
			return true
		state.phase = phase + 1
		return false)


## The outside: walls with the storefront cut into the front, the parapet and roof, the sign band
## round the corner, the grille box and the bars over the windows, the bulkhead, the posters and
## the neon OPEN, the painted words down the side, the ice chest, the ramp at the door.
static func _shell(site: CornerStoreSite, body: StaticBody3D, s: Dictionary, lay: Dictionary, ch: CityChunk, xf: Transform3D) -> void:
	var g := LandmarkGeo.new()
	g.use("kit", kit_material())
	var W: float = s.W
	var D: float = s.D
	var cs: float = lay.cs
	var T := CornerStore.WALL
	var stucco: Color = s.stucco
	var sign_face: Color = (s.sign as Array)[0]
	var sign_ink: Color = (s.sign as Array)[1]
	var low := -0.5 - float(s.get("relief", 0.0))
	var top := CornerStore.PARAPET
	var openings := _openings(lay, W)
	# The front wall, round its openings; the inside face is the interior's.
	_front_wall(g, "kit", -W * 0.5, W * 0.5, low, top, T, openings, stucco, false)
	# The side, back and other side: outer faces.
	g.quad("kit", Vector3(W * 0.5, low, 0.0), Vector3(W * 0.5, top, 0.0), Vector3(W * 0.5, top, -D), Vector3(W * 0.5, low, -D), Vector3.RIGHT,
			Vector2(0.0, low), Vector2(0.0, top), Vector2(D, top), Vector2(D, low), _k(stucco, K_STUCCO))
	g.quad("kit", Vector3(-W * 0.5, low, 0.0), Vector3(-W * 0.5, top, 0.0), Vector3(-W * 0.5, top, -D), Vector3(-W * 0.5, low, -D), Vector3.LEFT,
			Vector2(0.0, low), Vector2(0.0, top), Vector2(D, top), Vector2(D, low), _k(stucco, K_STUCCO))
	g.quad("kit", Vector3(-W * 0.5, low, -D), Vector3(-W * 0.5, top, -D), Vector3(W * 0.5, top, -D), Vector3(W * 0.5, low, -D), Vector3.FORWARD,
			Vector2(0.0, low), Vector2(0.0, top), Vector2(W, top), Vector2(W, low), _k(stucco, K_STUCCO))
	# Parapet: its inner faces over the roof, the roof, the coping.
	var R := CornerStore.ROOF
	for f: Array in [[Vector3(W * 0.5 - T, 0, 0), Vector3.LEFT, D], [Vector3(-W * 0.5 + T, 0, 0), Vector3.RIGHT, D]]:
		var x: float = (f[0] as Vector3).x
		g.quad("kit", Vector3(x, R, -T), Vector3(x, top, -T), Vector3(x, top, -D + T), Vector3(x, R, -D + T), f[1],
				Vector2(0, R), Vector2(0, top), Vector2(D, top), Vector2(D, R), _k(stucco * 0.9, K_STUCCO))
	for zf: Array in [[-T, Vector3.FORWARD], [-D + T, Vector3.BACK]]:
		var z: float = zf[0]
		g.quad("kit", Vector3(-W * 0.5 + T, R, z), Vector3(-W * 0.5 + T, top, z), Vector3(W * 0.5 - T, top, z), Vector3(W * 0.5 - T, R, z), zf[1],
				Vector2(0, R), Vector2(0, top), Vector2(W, top), Vector2(W, R), _k(stucco * 0.9, K_STUCCO))
	g.quad("kit", Vector3(-W * 0.5 + T, R, -T), Vector3(W * 0.5 - T, R, -T), Vector3(W * 0.5 - T, R, -D + T), Vector3(-W * 0.5 + T, R, -D + T), Vector3.UP,
			Vector2(-W * 0.5, -T), Vector2(W * 0.5, -T), Vector2(W * 0.5, -D), Vector2(-W * 0.5, -D), _k(Color(0.62, 0.62, 0.60), K_ROOF))
	var cap := _k(Color(0.78, 0.77, 0.74), K_CONCRETE)
	g.box("kit", Vector3(0.0, top + 0.04, -T * 0.5), Vector3(W + 0.06, 0.08, T + 0.06), cap)
	g.box("kit", Vector3(0.0, top + 0.04, -D + T * 0.5), Vector3(W + 0.06, 0.08, T + 0.06), cap)
	g.box("kit", Vector3(W * 0.5 - T * 0.5, top + 0.04, -D * 0.5), Vector3(T + 0.06, 0.08, D - T * 2.0), cap)
	g.box("kit", Vector3(-W * 0.5 + T * 0.5, top + 0.04, -D * 0.5), Vector3(T + 0.06, 0.08, D - T * 2.0), cap)
	# A rooftop unit and its duct.
	g.box("kit", Vector3(-cs * W * 0.18, R + 0.45, -D * 0.6), Vector3(1.3, 0.9, 1.0), _k(Color(0.72, 0.72, 0.70), K_STEEL), Basis(), 0.03)
	g.box("kit", Vector3(-cs * W * 0.18, R + 0.12, -D * 0.6 + 0.9), Vector3(0.4, 0.24, 0.8), _k(Color(0.66, 0.66, 0.64), K_ALUMINIUM))
	# The sign band across the front and down the corner side, and its letters.
	var sy: Vector2 = CornerStore.SIGN_Y
	var sh := sy.y - sy.x
	g.box("kit", Vector3(0.0, (sy.x + sy.y) * 0.5, 0.11), Vector3(W + 0.04, sh, 0.22), _k(sign_face, K_SIGN))
	var side_len := minf(D * 0.62, 7.5)
	g.box("kit", Vector3(cs * (W * 0.5 + 0.11), (sy.x + sy.y) * 0.5, -side_len * 0.5 + 0.11), Vector3(0.22, sh, side_len), _k(sign_face, K_SIGN))
	g.box("kit", Vector3(0.0, sy.y + 0.03, 0.12), Vector3(W + 0.08, 0.06, 0.26), _k(ALU_TONE, K_ALUMINIUM))
	g.box("kit", Vector3(cs * (W * 0.5 + 0.12), sy.y + 0.03, -side_len * 0.5 + 0.12), Vector3(0.26, 0.06, side_len + 0.02), _k(ALU_TONE, K_ALUMINIUM))
	var name: String = s.name
	_letters(g, "kit", name, Vector3(0.0, (sy.x + sy.y) * 0.5, 0.226), Vector3.RIGHT, Vector3.UP, 0.52, W - 0.7, _k(sign_ink, K_LETTERS))
	_letters(g, "kit", name, Vector3(cs * (W * 0.5 + 0.226), (sy.x + sy.y) * 0.5, -side_len * 0.5 + 0.11), Vector3(0, 0, -cs), Vector3.UP, 0.48, side_len - 0.6, _k(sign_ink, K_LETTERS))
	# Painted words down the side street wall.
	var words := "ICE  -  COLD DRINKS  -  LOTTO  -  SNACKS"
	_letters(g, "kit", words, Vector3(cs * (W * 0.5 + 0.012), 2.2, -D * 0.55), Vector3(0, 0, -cs), Vector3.UP, 0.34, D * 0.8, _k(sign_face * 0.85, K_STUCCO))
	g.box("kit", Vector3(cs * (W * 0.5 + 0.004), 2.2, -D * 0.55), Vector3(0.006, 0.56, minf(D * 0.84, (D - 1.0))), _k(Color(0.96, 0.95, 0.90), K_STUCCO))
	# The storefront: a grille box over each opening, bars over the windows, the bulkhead's kick.
	for o: Array in openings:
		var u0: float = o[0]
		var u1: float = o[1]
		var v1: float = o[3]
		var door: bool = o[4]
		g.box("kit", Vector3((u0 + u1) * 0.5, v1 + 0.15, 0.11), Vector3(u1 - u0 + 0.12, 0.28, 0.22), _k(Color(0.30, 0.31, 0.32), K_STEEL), Basis(), 0.02)
		if door:
			continue
		var v0: float = o[2]
		var n := maxi(int((u1 - u0) / 0.13), 2)
		for i in n + 1:
			var x := lerpf(u0 + 0.05, u1 - 0.05, float(i) / float(n))
			g.box("kit", Vector3(x, (v0 + v1) * 0.5, -0.03), Vector3(0.018, v1 - v0, 0.018), _k(STEEL_TONE, K_STEEL))
		for y: float in [v0 + 0.06, (v0 + v1) * 0.5, v1 - 0.06]:
			g.box("kit", Vector3((u0 + u1) * 0.5, y, -0.03), Vector3(u1 - u0, 0.035, 0.012), _k(STEEL_TONE, K_STEEL))
	# Posters and the OPEN sign inside the first window (geometry in front of the glass: both the
	# traced and the clear glass see them).
	_posters(g, s, lay, openings)
	# The ice chest by the door, outside.
	var far_win: Array = openings[0]
	var ice_x := lerpf(float(far_win[0]), float(far_win[1]), 0.7)
	g.box("kit", Vector3(ice_x, 0.5 - 0.2, 0.75), Vector3(1.3, 1.0, 0.72), _k(Color(0.95, 0.96, 0.97), K_PAINT), Basis(), 0.03)
	g.box("kit", Vector3(ice_x, 0.82, 1.11), Vector3(1.32, 0.05, 0.02), _k(ALU_TONE, K_ALUMINIUM))
	_letters(g, "kit", "ICE", Vector3(ice_x, 0.48, 1.115), Vector3.RIGHT, Vector3.UP, 0.3, 1.0, _k(Color(0.10, 0.35, 0.75), K_PAINT))
	LandmarkGeo.shape_box(body, Vector3(ice_x, 0.3, 0.75), Vector3(1.3, 1.0, 0.72))
	# A ramp down to the pavement at the door when the floor stands over it.
	var door_x: float = lay.door_x
	var outside := xf * Vector3(door_x, 0.0, 0.8)
	var drop := xf.origin.y - ch.ground_y(outside.x, outside.z)
	if drop > 0.03:
		var L := clampf(drop * 6.0, 0.5, 2.6)
		var hw := CornerStore.DOOR_W * 0.5 + 0.3
		var a := Vector3(door_x - hw, 0.0, 0.0)
		var b := Vector3(door_x + hw, 0.0, 0.0)
		var c := Vector3(door_x + hw, -drop, L)
		var d := Vector3(door_x - hw, -drop, L)
		var conc := _k(Color(0.72, 0.71, 0.68), K_CONCRETE)
		g.quad("kit", a, b, c, d, Vector3(0, L, drop).normalized(), Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z), Vector2(d.x, d.z), conc)
		for sx: float in [-1.0, 1.0]:
			var e := Vector3(door_x + sx * hw, 0.0, 0.0)
			var f := Vector3(door_x + sx * hw, -drop - 0.05, L)
			var h := Vector3(door_x + sx * hw, -drop - 0.05, 0.0)
			g.tri("kit", e, f, h, Vector3(sx, 0, 0), Vector2(0, 0), Vector2(L, -drop), Vector2(0, -drop), conc)
		var shape := ConvexPolygonShape3D.new()
		shape.points = PackedVector3Array([a, b, c, d, Vector3(a.x, -drop - 0.1, 0.0), Vector3(b.x, -drop - 0.1, 0.0)])
		var csh := CollisionShape3D.new()
		csh.shape = shape
		body.add_child(csh)
	_commit(g, site, "Shell", true)


## The storefront's openings, far end first: [u0, u1, v0, v1, is_door]. The far window runs from
## half a metre in from the far end to a pier before the door; past the door a narrow window to
## the corner pier if there is room for one.
static func _openings(lay: Dictionary, W: float) -> Array:
	var cs: float = lay.cs
	var door_x: float = lay.door_x
	var hd := CornerStore.DOOR_W * 0.5 + 0.06
	var out: Array = []
	var far_end := -cs * (W * 0.5 - 0.55)
	var near_door := door_x - cs * (hd + 0.4)
	out.append([minf(far_end, near_door), maxf(far_end, near_door), CornerStore.BULKHEAD, CornerStore.GLASS_TOP, false])
	out.append([door_x - hd, door_x + hd, 0.0, CornerStore.GLASS_TOP, true])
	var b0 := door_x + cs * (hd + 0.4)
	var b1 := cs * (W * 0.5 - 0.6)
	if absf(b1 - b0) >= 0.8:
		out.append([minf(b0, b1), maxf(b0, b1), CornerStore.BULKHEAD, CornerStore.GLASS_TOP, false])
	return out


## A wall along x with its outer face at z = 0, `t` thick, from y0 to y1, cut round `holes`
## ([u0, u1, v0, v1, door]). `inner` builds the inside face (paint, floor to ceiling) instead of
## the outer one and its reveals. Under a window the face is the tiled bulkhead.
static func _front_wall(g: LandmarkGeo, key: String, x0: float, x1: float, y0: float, y1: float, t: float, holes: Array, col: Color, inner: bool) -> void:
	var xs: Array[float] = [x0, x1]
	var ys: Array[float] = [y0, y1]
	if inner:
		ys = [0.0, CornerStore.CEILING]
	for h: Array in holes:
		xs.append(h[0])
		xs.append(h[1])
		for v: float in [h[2], h[3]]:
			if v > ys[0] and v < ys[ys.size() - 1]:
				ys.append(v)
	xs.sort()
	ys.sort()
	for i in xs.size() - 1:
		var xa := xs[i]
		var xb := xs[i + 1]
		if xb - xa < 1e-3:
			continue
		for j in ys.size() - 1:
			var ya := ys[j]
			var yb := ys[j + 1]
			if yb - ya < 1e-3:
				continue
			var xm := (xa + xb) * 0.5
			var ym := (ya + yb) * 0.5
			var in_hole := false
			var under := false
			for h: Array in holes:
				if xm > float(h[0]) and xm < float(h[1]):
					if ym > float(h[2]) and ym < float(h[3]):
						in_hole = true
					elif ym < float(h[2]) and not bool(h[4]):
						under = true
			if in_hole:
				continue
			if inner:
				g.quad(key, Vector3(xa, ya, -t), Vector3(xa, yb, -t), Vector3(xb, yb, -t), Vector3(xb, ya, -t), Vector3.FORWARD,
						Vector2(xa, ya), Vector2(xa, yb), Vector2(xb, yb), Vector2(xb, ya), _k(WALL_PAINT, K_PAINT))
			else:
				var c := _k(Color(0.10, 0.20, 0.17), K_TILE) if under else _k(col, K_STUCCO)
				g.quad(key, Vector3(xa, ya, 0.0), Vector3(xa, yb, 0.0), Vector3(xb, yb, 0.0), Vector3(xb, ya, 0.0), Vector3.BACK,
						Vector2(xa, ya), Vector2(xa, yb), Vector2(xb, yb), Vector2(xb, ya), c)
	if inner:
		return
	# Reveals: jambs, sill, head (the depth of the wall).
	for h: Array in holes:
		var u0: float = h[0]
		var u1: float = h[1]
		var v0: float = h[2]
		var v1: float = h[3]
		var rc := _k(col * 0.95, K_STUCCO)
		g.quad(key, Vector3(u0, v0, 0), Vector3(u0, v1, 0), Vector3(u0, v1, -t), Vector3(u0, v0, -t), Vector3.RIGHT, Vector2(0, v0), Vector2(0, v1), Vector2(t, v1), Vector2(t, v0), rc)
		g.quad(key, Vector3(u1, v0, 0), Vector3(u1, v1, 0), Vector3(u1, v1, -t), Vector3(u1, v0, -t), Vector3.LEFT, Vector2(0, v0), Vector2(0, v1), Vector2(t, v1), Vector2(t, v0), rc)
		g.quad(key, Vector3(u0, v1, 0), Vector3(u1, v1, 0), Vector3(u1, v1, -t), Vector3(u0, v1, -t), Vector3.DOWN, Vector2(u0, 0), Vector2(u1, 0), Vector2(u1, t), Vector2(u0, t), rc)
		if v0 > 0.01:
			g.quad(key, Vector3(u0, v0, 0.04), Vector3(u1, v0, 0.04), Vector3(u1, v0, -t), Vector3(u0, v0, -t), Vector3.UP, Vector2(u0, 0), Vector2(u1, 0), Vector2(u1, t), Vector2(u0, t), _k(Color(0.70, 0.69, 0.66), K_CONCRETE))


## Flat lettering (FreewayKit.text_geo) centred at `at`, along `right`, `up`, facing right x up,
## at most `max_w` wide.
static func _letters(g: LandmarkGeo, key: String, text: String, at: Vector3, right: Vector3, up: Vector3, height: float, max_w: float, col: Color) -> void:
	var geo := FreewayKit.text_geo(text, height)
	var verts: PackedVector3Array = geo[0]
	var idx: PackedInt32Array = geo[1]
	var width: float = geo[2]
	if verts.is_empty():
		return
	var squeeze := minf(1.0, max_w / maxf(width, 0.001))
	# TextMesh faces +Z: out = right x up.
	var out := right.cross(up).normalized()
	for k in range(0, idx.size() - 2, 3):
		var p: Array[Vector3] = []
		var uv: Array[Vector2] = []
		for j in 3:
			var v := verts[idx[k + j]]
			p.append(at + right * (v.x * squeeze) + up * v.y)
			uv.append(Vector2(v.x * squeeze, v.y))
		g.tri(key, p[0], p[1], p[2], out, uv[0], uv[1], uv[2], col)


## Window posters (printed, with their words) and a neon OPEN, just inside the far window.
static func _posters(g: LandmarkGeo, s: Dictionary, lay: Dictionary, openings: Array) -> void:
	var win: Array = openings[0]
	var u0: float = win[0]
	var u1: float = win[1]
	var z := -CornerStore.WALL * 0.5 - 0.035
	var sd: int = s.seed
	var posters := [["COLD BEER", Color(0.12, 0.30, 0.70), Color(1.0, 1.0, 1.0)], ["ICE", Color(0.92, 0.95, 0.98), Color(0.10, 0.35, 0.75)],
		["LOTTO", Color(0.96, 0.80, 0.12), Color(0.70, 0.08, 0.06)], ["ATM INSIDE", Color(0.10, 0.45, 0.25), Color(1.0, 1.0, 1.0)],
		["SNACKS", Color(0.85, 0.15, 0.12), Color(1.0, 0.95, 0.75)], ["HOT COFFEE", Color(0.35, 0.18, 0.10), Color(1.0, 0.92, 0.75)]]
	var n := clampi(int((u1 - u0) / 0.95), 1, 3)
	for i in n:
		var p: Array = posters[(sd + i * 7) % posters.size()]
		var cx := lerpf(u0, u1, (float(i) + 0.5) / float(n))
		var w := 0.62
		var h := 0.82
		var cy := CornerStore.BULKHEAD + 0.12 + h * 0.5 + float((sd >> (i * 3)) % 3) * 0.08
		g.quad("kit", Vector3(cx - w * 0.5, cy - h * 0.5, z), Vector3(cx - w * 0.5, cy + h * 0.5, z), Vector3(cx + w * 0.5, cy + h * 0.5, z), Vector3(cx + w * 0.5, cy - h * 0.5, z), Vector3.BACK,
				Vector2(0, 0), Vector2(0, h), Vector2(w, h), Vector2(w, 0), _k(p[1], K_POSTER))
		g.quad("kit", Vector3(cx - w * 0.5, cy - h * 0.5, z - 0.002), Vector3(cx - w * 0.5, cy + h * 0.5, z - 0.002), Vector3(cx + w * 0.5, cy + h * 0.5, z - 0.002), Vector3(cx + w * 0.5, cy - h * 0.5, z - 0.002), Vector3.FORWARD,
				Vector2(0, 0), Vector2(0, h), Vector2(w, h), Vector2(w, 0), _k(Color(0.9, 0.9, 0.88), K_POSTER))
		_letters(g, "kit", String(p[0]), Vector3(cx, cy + 0.08, z + 0.003), Vector3.RIGHT, Vector3.UP, 0.13, w - 0.08, _k(p[2], K_POSTER))
		g.box("kit", Vector3(cx, cy - h * 0.28, z + 0.002), Vector3(w * 0.7, 0.05, 0.002), _k(p[2], K_POSTER))
	# The neon OPEN: red letters in a blue border, hung near the top of the window.
	var ox := lerpf(u0, u1, 0.5 if n == 1 else 0.82)
	var oy := CornerStore.GLASS_TOP - 0.42
	var oz := z - 0.06
	_letters(g, "kit", "OPEN", Vector3(ox, oy, oz), Vector3.RIGHT, Vector3.UP, 0.2, 0.7, _k(Color(1.0, 0.16, 0.12), K_NEON))
	for e: Array in [[Vector3(ox, oy + 0.17, oz), Vector3(0.76, 0.02, 0.02)], [Vector3(ox, oy - 0.17, oz), Vector3(0.76, 0.02, 0.02)],
			[Vector3(ox - 0.38, oy, oz), Vector3(0.02, 0.34, 0.02)], [Vector3(ox + 0.38, oy, oz), Vector3(0.02, 0.34, 0.02)]]:
		g.box("kit", e[0], e[1], _k(Color(0.2, 0.45, 1.0), K_NEON))


## The glass: one pane per window, the transom over the door, framed in aluminium. Traced until the
## site shows the interior.
static func _glass(site: CornerStoreSite, s: Dictionary, lay: Dictionary) -> void:
	var W: float = s.W
	var openings := _openings(lay, W)
	var g := LandmarkGeo.new()
	var traced := traced_material(s, lay, Transform3D())
	g.use("glass", traced)
	var f := LandmarkGeo.new()
	f.use("kit", kit_material())
	var z := -CornerStore.WALL * 0.5
	var alu := _k(ALU_TONE, K_ALUMINIUM)
	for o: Array in openings:
		var u0: float = o[0]
		var u1: float = o[1]
		var v0: float = o[2]
		var v1: float = o[3]
		var door: bool = o[4]
		var g0 := CornerStore.DOOR_H + 0.06 if door else v0
		g.quad("glass", Vector3(u0, g0, z), Vector3(u0, v1, z), Vector3(u1, v1, z), Vector3(u1, g0, z), Vector3.BACK,
				Vector2(u0, g0), Vector2(u0, v1), Vector2(u1, v1), Vector2(u1, g0), Color.WHITE)
		# Frame: jambs, head, sill, a mullion every metre and a half, the door's transom bar.
		for e: Array in [[Vector3(u0 + 0.03, (v0 + v1) * 0.5, z), Vector3(0.06, v1 - v0, 0.1)], [Vector3(u1 - 0.03, (v0 + v1) * 0.5, z), Vector3(0.06, v1 - v0, 0.1)],
				[Vector3((u0 + u1) * 0.5, v1 - 0.03, z), Vector3(u1 - u0, 0.06, 0.1)]]:
			f.box("kit", e[0], e[1], alu)
		if door:
			f.box("kit", Vector3((u0 + u1) * 0.5, CornerStore.DOOR_H + 0.03, z), Vector3(u1 - u0, 0.06, 0.1), alu)
		else:
			f.box("kit", Vector3((u0 + u1) * 0.5, v0 + 0.03, z), Vector3(u1 - u0, 0.06, 0.1), alu)
			var n := int((u1 - u0) / 1.5)
			for i in range(1, n + 1):
				f.box("kit", Vector3(lerpf(u0, u1, float(i) / float(n + 1)), (v0 + v1) * 0.5, z), Vector3(0.05, v1 - v0, 0.1), alu)
	var mi := _commit(g, site, "Glass", false)
	if mi:
		site.add_glass(mi, traced, clear_material())
	_commit(f, site, "Frames", true)


## The door: a glazed aluminium leaf on a hinge (a pivot node at the hinge), its own collision on
## an AnimatableBody3D that swings with it; push bar, kick plate, hours and OPEN on the glass.
static func _door(site: CornerStoreSite, s: Dictionary, lay: Dictionary) -> void:
	var cs: float = lay.cs
	var door_x: float = lay.door_x
	var DW := CornerStore.DOOR_W
	var DH := CornerStore.DOOR_H
	var z := -CornerStore.WALL * 0.5
	var pivot := Node3D.new()
	pivot.name = "Door"
	# The hinge on the far side of the door: the leaf runs toward the corner (+cs).
	pivot.position = Vector3(door_x - cs * DW * 0.5, 0.0, z)
	site.add_child(pivot)
	site.door = pivot
	var to_store := Transform3D(Basis(), pivot.position)
	var traced := traced_material(s, lay, to_store)
	var g := LandmarkGeo.new()
	g.use("glass", traced)
	var f := LandmarkGeo.new()
	f.use("kit", kit_material())
	var alu := _k(ALU_TONE, K_ALUMINIUM)
	var x0 := 0.0
	var x1 := cs * DW
	var lo := minf(x0, x1)
	var hi := maxf(x0, x1)
	var st := 0.09
	g.quad("glass", Vector3(lo + st, 0.28, 0.0), Vector3(lo + st, DH - st, 0.0), Vector3(hi - st, DH - st, 0.0), Vector3(hi - st, 0.28, 0.0), Vector3.BACK,
			Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Color.WHITE)
	g.quad("glass", Vector3(lo + st, 0.28, 0.0), Vector3(lo + st, DH - st, 0.0), Vector3(hi - st, DH - st, 0.0), Vector3(hi - st, 0.28, 0.0), Vector3.FORWARD,
			Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Color.WHITE)
	f.box("kit", Vector3(lo + st * 0.5, DH * 0.5, 0.0), Vector3(st, DH, 0.05), alu)
	f.box("kit", Vector3(hi - st * 0.5, DH * 0.5, 0.0), Vector3(st, DH, 0.05), alu)
	f.box("kit", Vector3((lo + hi) * 0.5, DH - st * 0.5, 0.0), Vector3(DW, st, 0.05), alu)
	f.box("kit", Vector3((lo + hi) * 0.5, 0.14, 0.0), Vector3(DW, 0.28, 0.05), alu)
	# Pull handle outside, push bar inside, on the free edge.
	var hx := x1 - cs * 0.16
	f.box("kit", Vector3(hx, 1.05, 0.07), Vector3(0.025, 0.6, 0.025), _k(Color(0.85, 0.85, 0.86), K_CHROME))
	f.box("kit", Vector3(hx, 1.05, 0.04), Vector3(0.05, 0.03, 0.06), alu)
	f.box("kit", Vector3((lo + hi) * 0.5, 1.0, -0.06), Vector3(DW - 0.25, 0.05, 0.05), alu)
	_letters(f, "kit", "OPEN 6AM - 2AM", Vector3((lo + hi) * 0.5, 1.55, 0.004), Vector3.RIGHT, Vector3.UP, 0.05, DW * 0.6, _k(Color(0.95, 0.95, 0.95), K_POSTER))
	var mi := _commit(g, pivot, "Leaf", false)
	if mi:
		site.add_glass(mi, traced, clear_material())
	_commit(f, pivot, "LeafFrame", true)
	var ab := AnimatableBody3D.new()
	ab.name = "DoorBody"
	ab.collision_layer = 1
	ab.collision_mask = 0
	pivot.add_child(ab)
	LandmarkGeo.shape_box(ab, Vector3((lo + hi) * 0.5, DH * 0.5, 0.0), Vector3(DW - 0.04, DH, 0.06))


## The collision: walls round the door opening, the roof, the floor, the fittings inside.
static func _collision(body: StaticBody3D, lay: Dictionary) -> void:
	var W: float = lay.W
	var D: float = lay.D
	var T := CornerStore.WALL
	var H := CornerStore.PARAPET
	var low := -0.5 - float(lay.get("relief", 0.0))
	var door_x: float = lay.door_x
	var hd := CornerStore.DOOR_W * 0.5 + 0.06
	var yc := (low + H) * 0.5
	var hh := H - low
	# Front wall either side of the door, and the lintel over it.
	var a0 := -W * 0.5
	var a1 := door_x - hd
	var b0 := door_x + hd
	var b1 := W * 0.5
	LandmarkGeo.shape_box(body, Vector3((a0 + a1) * 0.5, yc, -T * 0.5), Vector3(a1 - a0, hh, T))
	LandmarkGeo.shape_box(body, Vector3((b0 + b1) * 0.5, yc, -T * 0.5), Vector3(b1 - b0, hh, T))
	LandmarkGeo.shape_box(body, Vector3(door_x, (CornerStore.GLASS_TOP + H) * 0.5, -T * 0.5), Vector3(hd * 2.0, H - CornerStore.GLASS_TOP, T))
	LandmarkGeo.shape_box(body, Vector3(door_x, (CornerStore.DOOR_H + 0.06 + CornerStore.GLASS_TOP) * 0.5, -T * 0.5), Vector3(hd * 2.0, CornerStore.GLASS_TOP - CornerStore.DOOR_H - 0.06, T))
	LandmarkGeo.shape_box(body, Vector3(W * 0.5 - T * 0.5, yc, -D * 0.5), Vector3(T, hh, D))
	LandmarkGeo.shape_box(body, Vector3(-W * 0.5 + T * 0.5, yc, -D * 0.5), Vector3(T, hh, D))
	LandmarkGeo.shape_box(body, Vector3(0.0, yc, -D + T * 0.5), Vector3(W, hh, T))
	LandmarkGeo.shape_box(body, Vector3(0.0, CornerStore.ROOF - 0.15, -D * 0.5), Vector3(W, 0.3, D))
	LandmarkGeo.shape_box(body, Vector3(0.0, -0.3, -D * 0.5), Vector3(W, 0.6, D))
	# Fittings.
	var cs: float = lay.cs
	var ix1: float = lay.ix1
	var iz0: float = lay.iz0
	LandmarkGeo.shape_box(body, Vector3(0.0, 1.1, iz0 + CornerStore.BACK_SHELF * 0.5), Vector3(W - T * 2.0, 2.2, CornerStore.BACK_SHELF))
	var cz: Vector2 = lay.cooler_z
	if int(lay.n_doors) > 0:
		var cx := -cs * (ix1 - CornerStore.COOLER_DEEP * 0.5)
		LandmarkGeo.shape_box(body, Vector3(cx, 1.15, (cz.x + cz.y) * 0.5), Vector3(CornerStore.COOLER_DEEP, 2.3, cz.x - cz.y))
	var kz: Vector2 = lay.counter_z
	LandmarkGeo.shape_box(body, Vector3(lay.counter_x, 0.5, (kz.x + kz.y) * 0.5), Vector3(CornerStore.COUNTER_DEEP, 1.0, kz.x - kz.y))
	var gz: Vector2 = lay.g_z
	for gx: float in lay.gondolas:
		LandmarkGeo.shape_box(body, Vector3(gx, float(lay.g_h) * 0.5, (gz.x + gz.y) * 0.5), Vector3(CornerStore.GONDOLA_W, lay.g_h, gz.x - gz.y))


# --- Inside --------------------------------------------------------------------------------------

## The room: walls inside, floor, the drop ceiling and its light panels, the back shelving, the
## gondolas, the coolers, the counter and what stands on it, the cigarette rack, the mirror, signs.
static func _interior(site: CornerStoreSite, s: Dictionary, lay: Dictionary) -> void:
	var g := LandmarkGeo.new()
	g.use("kit", kit_material())
	g.use("clear", clear_material())
	var W: float = s.W
	var cs: float = lay.cs
	var ix0: float = lay.ix0
	var ix1: float = lay.ix1
	var iz0: float = lay.iz0
	var iz1: float = lay.iz1
	var C := CornerStore.CEILING
	var paint := _k(WALL_PAINT, K_PAINT)
	_front_wall(g, "kit", -W * 0.5, W * 0.5, 0.0, C, CornerStore.WALL, _openings(lay, W), WALL_PAINT, true)
	g.quad("kit", Vector3(ix1, 0, iz1), Vector3(ix1, C, iz1), Vector3(ix1, C, iz0), Vector3(ix1, 0, iz0), Vector3.LEFT, Vector2(iz1, 0), Vector2(iz1, C), Vector2(iz0, C), Vector2(iz0, 0), paint)
	g.quad("kit", Vector3(ix0, 0, iz1), Vector3(ix0, C, iz1), Vector3(ix0, C, iz0), Vector3(ix0, 0, iz0), Vector3.RIGHT, Vector2(iz1, 0), Vector2(iz1, C), Vector2(iz0, C), Vector2(iz0, 0), paint)
	g.quad("kit", Vector3(ix0, 0, iz0), Vector3(ix0, C, iz0), Vector3(ix1, C, iz0), Vector3(ix1, 0, iz0), Vector3.BACK, Vector2(ix0, 0), Vector2(ix0, C), Vector2(ix1, C), Vector2(ix1, 0), paint)
	# Floor and ceiling (UV = the store's x, z: the trace lays the same tiles).
	g.quad("kit", Vector3(ix0, 0, iz1), Vector3(ix1, 0, iz1), Vector3(ix1, 0, iz0), Vector3(ix0, 0, iz0), Vector3.UP, Vector2(ix0, iz1), Vector2(ix1, iz1), Vector2(ix1, iz0), Vector2(ix0, iz0), _k(FLOOR_TONE, K_FLOOR))
	g.quad("kit", Vector3(ix0, C, iz1), Vector3(ix1, C, iz1), Vector3(ix1, C, iz0), Vector3(ix0, C, iz0), Vector3.DOWN, Vector2(ix0, iz1), Vector2(ix1, iz1), Vector2(ix1, iz0), Vector2(ix0, iz0), _k(Color(0.9, 0.9, 0.88), K_CEILING))
	# Light panels where the trace puts them: 1.2 x 0.58 m in a 2.4 m grid from the room's corner.
	var nx := int(floor((ix1 - ix0) / 2.4))
	var nz := int(floor((iz1 - iz0) / 2.4))
	for i in nx:
		for j in nz:
			var px := ix0 + 2.4 * (float(i) + 0.5)
			var pz := iz0 + 2.4 * (float(j) + 0.5)
			var a := Vector3(px - 0.6, C - 0.005, pz - 0.29)
			var b := Vector3(px + 0.6, C - 0.005, pz - 0.29)
			var c := Vector3(px + 0.6, C - 0.005, pz + 0.29)
			var d := Vector3(px - 0.6, C - 0.005, pz + 0.29)
			g.quad("kit", a, b, c, d, Vector3.DOWN, Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z), Vector2(d.x, d.z), _k(Color.WHITE, K_TROFFER))
	# Base moulding.
	var cove := _k(Color(0.18, 0.18, 0.19), K_RUBBER)
	g.box("kit", Vector3(0.0, 0.05, iz0 + 0.006), Vector3(ix1 - ix0, 0.1, 0.012), cove)
	_back_shelving(g, lay)
	var gz: Vector2 = lay.g_z
	for gx: float in lay.gondolas:
		_gondola(g, gx, gz, float(lay.g_h))
	if int(lay.n_doors) > 0:
		_coolers(g, lay)
	_counter(g, s, lay)
	# A convex security mirror in the back corner on the counter side.
	_mirror(g, Vector3(cs * (ix1 - 0.25), C - 0.35, iz0 + 0.25), Vector3(-cs, -0.6, 1.0).normalized(), 0.28)
	# A lit LOTTO sign hung over the counter.
	var kz: Vector2 = lay.counter_z
	var lx: float = lay.counter_x
	var lzc := (kz.x + kz.y) * 0.5
	g.box("kit", Vector3(lx, 2.45, lzc), Vector3(0.08, 0.32, 1.1), _k(Color(0.96, 0.80, 0.10), K_SIGN))
	_letters(g, "kit", "LOTTO", Vector3(lx - cs * 0.045, 2.45, lzc), Vector3(0, 0, cs), Vector3.UP, 0.2, 1.0, _k(Color(0.75, 0.06, 0.05), K_LETTERS))
	for zz: float in [lzc - 0.45, lzc + 0.45]:
		g.box("kit", Vector3(lx, 2.78, zz), Vector3(0.01, 0.45, 0.01), _k(Color(0.4, 0.4, 0.4), K_STEEL))
	# Signs hung from the ceiling over each aisle's front end, and a header over the back wall.
	var sd: int = s.seed
	var gz2: Vector2 = lay.g_z
	var gi := 0
	for gx: float in lay.gondolas:
		var word: String = AISLE_SIGNS[(sd + gi * 3) % AISLE_SIGNS.size()]
		var sc := Vector3(gx, 2.42, gz2.x - 0.4)
		g.box("kit", sc, Vector3(1.0, 0.3, 0.02), _k(Color(0.95, 0.95, 0.92), K_POSTER))
		g.box("kit", sc + Vector3(0, 0.13, 0), Vector3(1.0, 0.04, 0.025), _k(Color(0.8, 0.1, 0.1), K_POSTER))
		_letters(g, "kit", word, sc + Vector3(0, -0.02, 0.012), Vector3.RIGHT, Vector3.UP, 0.12, 0.9, _k(Color(0.12, 0.12, 0.14), K_POSTER))
		_letters(g, "kit", word, sc + Vector3(0, -0.02, -0.012), Vector3.LEFT, Vector3.UP, 0.12, 0.9, _k(Color(0.12, 0.12, 0.14), K_POSTER))
		for dx: float in [-0.4, 0.4]:
			g.box("kit", sc + Vector3(dx, 0.37, 0), Vector3(0.006, 0.45, 0.006), _k(Color(0.5, 0.5, 0.5), K_STEEL))
		gi += 1
	var hb := Vector3((ix0 + ix1) * 0.5, 2.38, iz0 + 0.03)
	g.box("kit", hb, Vector3(minf(3.0, ix1 - ix0 - 1.0), 0.32, 0.03), _k(Color(0.1, 0.32, 0.6), K_SIGN))
	_letters(g, "kit", "GROCERY", hb + Vector3(0, 0, 0.018), Vector3.RIGHT, Vector3.UP, 0.18, 2.6, _k(Color.WHITE, K_LETTERS))
	last_interior_tris = g.triangles
	_commit(g, site.interior, "Room", false)


static func _back_shelving(g: LandmarkGeo, lay: Dictionary) -> void:
	var ix0: float = lay.ix0
	var ix1: float = lay.ix1
	var iz0: float = lay.iz0
	var d := CornerStore.BACK_SHELF
	var shelf := _k(SHELF_TONE, K_SHELF)
	var w := ix1 - ix0
	g.box("kit", Vector3((ix0 + ix1) * 0.5, 1.05, iz0 + 0.02), Vector3(w, 2.1, 0.04), _k(SHELF_TONE * 0.95, K_PEGBOARD))
	g.box("kit", Vector3((ix0 + ix1) * 0.5, 0.06, iz0 + d * 0.5), Vector3(w, 0.12, d), _k(SHELF_TONE * 0.6, K_SHELF))
	for y: float in BACK_SHELVES:
		g.box("kit", Vector3((ix0 + ix1) * 0.5, y - 0.012, iz0 + d * 0.5), Vector3(w, 0.024, d), shelf)
		g.box("kit", Vector3((ix0 + ix1) * 0.5, y + 0.005, iz0 + d - 0.005), Vector3(w, 0.04, 0.012), _k(Color(0.96, 0.96, 0.94), K_PRICE))
	var n := maxi(int(w / 1.22), 1)
	for i in n + 1:
		g.box("kit", Vector3(lerpf(ix0 + 0.02, ix1 - 0.02, float(i) / float(n)), 1.05, iz0 + d * 0.5), Vector3(0.03, 2.1, d), shelf)
	g.box("kit", Vector3((ix0 + ix1) * 0.5, 2.1 + 0.015, iz0 + d * 0.5), Vector3(w, 0.03, d), shelf)


static func _gondola(g: LandmarkGeo, gx: float, gz: Vector2, gh: float) -> void:
	var L := gz.x - gz.y
	var zc := (gz.x + gz.y) * 0.5
	var shelf := _k(SHELF_TONE, K_SHELF)
	var half := CornerStore.GONDOLA_W * 0.5
	g.box("kit", Vector3(gx, 0.06, zc), Vector3(CornerStore.GONDOLA_W, 0.12, L), _k(SHELF_TONE * 0.6, K_SHELF))
	g.box("kit", Vector3(gx, gh * 0.5, zc), Vector3(0.04, gh, L - 0.02), _k(SHELF_TONE * 0.95, K_PEGBOARD))
	for y: float in GONDOLA_SHELVES:
		g.box("kit", Vector3(gx, y - 0.012, zc), Vector3(CornerStore.GONDOLA_W, 0.024, L), shelf)
		for sx: float in [-1.0, 1.0]:
			g.box("kit", Vector3(gx + sx * (half - 0.006), y + 0.005, zc), Vector3(0.012, 0.04, L), _k(Color(0.96, 0.96, 0.94), K_PRICE))
	for zz: float in [gz.x - 0.015, gz.y + 0.015]:
		g.box("kit", Vector3(gx, gh * 0.5, zz), Vector3(CornerStore.GONDOLA_W, gh, 0.03), shelf)
	g.box("kit", Vector3(gx, gh + 0.015, zc), Vector3(CornerStore.GONDOLA_W + 0.02, 0.03, L + 0.02), shelf)
	# The endcap facing the window: three shelves across the end.
	for y: float in [0.3, 0.75, 1.2]:
		g.box("kit", Vector3(gx, y - 0.012, gz.x + 0.17), Vector3(CornerStore.GONDOLA_W, 0.024, 0.34), shelf)
	g.box("kit", Vector3(gx, 0.06, gz.x + 0.17), Vector3(CornerStore.GONDOLA_W, 0.12, 0.34), _k(SHELF_TONE * 0.6, K_SHELF))


static func _coolers(g: LandmarkGeo, lay: Dictionary) -> void:
	var cs: float = lay.cs
	var ix1: float = lay.ix1
	var wall := -cs * ix1
	var face: float = lay.cooler_face
	var cz: Vector2 = lay.cooler_z
	var n: int = lay.n_doors
	var dw := CornerStore.COOLER_DOOR
	var into := Vector3(cs, 0, 0)
	var xc := (wall + face) * 0.5
	var deep := absf(face - wall)
	var body := _k(Color(0.22, 0.22, 0.24), K_SHELF)
	# Cabinet: top, the header with its lit band, the base, the ends.
	g.box("kit", Vector3(xc, 2.2, (cz.x + cz.y) * 0.5), Vector3(deep, 0.2, cz.x - cz.y), body)
	g.box("kit", Vector3(face + cs * 0.01, 2.08, (cz.x + cz.y) * 0.5), Vector3(0.02, 0.12, cz.x - cz.y), _k(Color(0.85, 0.10, 0.10), K_SIGN))
	_letters(g, "kit", "COLD DRINKS", Vector3(face + cs * 0.022, 2.08, (cz.x + cz.y) * 0.5), Vector3(0, 0, -cs), Vector3.UP, 0.08, cz.x - cz.y - 0.4, _k(Color.WHITE, K_LETTERS))
	g.box("kit", Vector3(xc, 0.06, (cz.x + cz.y) * 0.5), Vector3(deep, 0.12, cz.x - cz.y), _k(Color(0.12, 0.12, 0.13), K_RUBBER))
	for zz: float in [cz.x - 0.02, cz.y + 0.02]:
		g.box("kit", Vector3(xc, 1.1, zz), Vector3(deep, 2.2, 0.04), body)
	# The lit back, the wire shelves, the doors' frames, glass and handles.
	g.quad("kit", Vector3(wall + cs * 0.06, 0.12, cz.x), Vector3(wall + cs * 0.06, 2.0, cz.x), Vector3(wall + cs * 0.06, 2.0, cz.y), Vector3(wall + cs * 0.06, 0.12, cz.y), into,
			Vector2(cz.x, 0.12), Vector2(cz.x, 2.0), Vector2(cz.y, 2.0), Vector2(cz.y, 0.12), _k(Color.WHITE, K_GLOW))
	for y: float in COOLER_SHELVES:
		g.box("kit", Vector3(xc - cs * 0.05, y - 0.01, (cz.x + cz.y) * 0.5), Vector3(deep - 0.16, 0.02, cz.x - cz.y - 0.08), _k(Color(0.75, 0.76, 0.78), K_WIRE))
	var alu := _k(ALU_TONE, K_ALUMINIUM)
	for i in n + 1:
		var z := cz.x - float(i) * dw
		g.box("kit", Vector3(face, 1.06, z), Vector3(0.06, 1.88, 0.06), alu)
		# An LED strip down the inside of each mullion.
		g.box("kit", Vector3(face - cs * 0.04, 1.06, z), Vector3(0.01, 1.8, 0.02), _k(Color.WHITE, K_GLOW))
	g.box("kit", Vector3(face, 2.0, (cz.x + cz.y) * 0.5), Vector3(0.06, 0.06, cz.x - cz.y), alu)
	g.box("kit", Vector3(face, 0.12, (cz.x + cz.y) * 0.5), Vector3(0.06, 0.06, cz.x - cz.y), alu)
	for i in n:
		var z0 := cz.x - float(i) * dw - 0.03
		var z1 := cz.x - float(i + 1) * dw + 0.03
		var gxp := face + cs * 0.02
		g.quad("clear", Vector3(gxp, 0.15, z0), Vector3(gxp, 1.97, z0), Vector3(gxp, 1.97, z1), Vector3(gxp, 0.15, z1), into,
				Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Color.WHITE)
		var hz := z1 + 0.08 if i % 2 == 0 else z0 - 0.08
		g.box("kit", Vector3(face + cs * 0.06, 1.1, hz), Vector3(0.025, 0.7, 0.025), _k(Color(0.85, 0.85, 0.86), K_CHROME))


static func _counter(g: LandmarkGeo, s: Dictionary, lay: Dictionary) -> void:
	var cs: float = lay.cs
	var cx: float = lay.counter_x
	var kz: Vector2 = lay.counter_z
	var L := kz.x - kz.y
	var zc := (kz.x + kz.y) * 0.5
	var CD := CornerStore.COUNTER_DEEP
	var ix1: float = lay.ix1
	g.box("kit", Vector3(cx, 0.48, zc), Vector3(CD, 0.88, L), _k(COUNTER_TONE, K_LAMINATE))
	g.box("kit", Vector3(cx, 0.06, zc), Vector3(CD - 0.06, 0.12, L - 0.06), _k(Color(0.1, 0.1, 0.1), K_RUBBER))
	g.box("kit", Vector3(cx - cs * 0.04, 0.95, zc), Vector3(CD + 0.12, 0.05, L + 0.06), _k(Color(0.55, 0.53, 0.50), K_LAMINATE), Basis(), 0.01)
	# The till (facing the cashier), the card reader (facing the customer), the lotto terminal.
	var cust := -cs
	var ty := 0.975
	var till_z := zc + L * 0.2
	g.box("kit", Vector3(cx + cs * 0.08, ty + 0.06, till_z), Vector3(0.38, 0.12, 0.42), _k(Color(0.12, 0.12, 0.13), K_RUBBER), Basis(), 0.01)
	var scr := Basis(Vector3.FORWARD, cs * -0.35)
	g.box("kit", Vector3(cx + cs * 0.12, ty + 0.3, till_z), Vector3(0.03, 0.26, 0.34), _k(Color(0.08, 0.08, 0.09), K_RUBBER), scr)
	g.box("kit", Vector3(cx + cs * 0.105, ty + 0.3, till_z), Vector3(0.006, 0.22, 0.3), _k(Color(0.45, 0.75, 1.0), K_SCREEN), scr)
	g.box("kit", Vector3(cx + cust * 0.18, ty + 0.06, till_z - 0.25), Vector3(0.1, 0.1, 0.07), _k(Color(0.15, 0.15, 0.16), K_RUBBER))
	var lot_z := zc - L * 0.15
	g.box("kit", Vector3(cx, ty + 0.12, lot_z), Vector3(0.32, 0.24, 0.3), _k(Color(0.92, 0.92, 0.9), K_SHELF), Basis(), 0.02)
	g.box("kit", Vector3(cx + cs * 0.15, ty + 0.18, lot_z), Vector3(0.006, 0.12, 0.22), _k(Color(0.95, 0.75, 0.3), K_SCREEN))
	# The scratch-ticket case at the customer's end of the counter: a glass-fronted box of rolls.
	var sc_z := kz.x - 0.4
	g.box("kit", Vector3(cx, ty + 0.2, sc_z), Vector3(0.28, 0.4, 0.62), _k(Color(0.10, 0.10, 0.12), K_SHELF))
	g.quad("clear", Vector3(cx + cust * 0.141, ty + 0.02, sc_z - 0.3), Vector3(cx + cust * 0.141, ty + 0.38, sc_z - 0.3), Vector3(cx + cust * 0.141, ty + 0.38, sc_z + 0.3), Vector3(cx + cust * 0.141, ty + 0.02, sc_z + 0.3),
			Vector3(cust, 0, 0), Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Color.WHITE)
	# Clutter on the counter: an energy-shot display, a lighter tray, a gum stand, a tip jar,
	# the receipt printer, a stack of flyers (their goods are in _goods()).
	var cl := _k(Color(0.9, 0.9, 0.88), K_SHELF)
	g.box("kit", Vector3(cx + cust * 0.12, ty + 0.06, zc - 0.05), Vector3(0.18, 0.12, 0.22), _k(Color(0.12, 0.12, 0.12), K_SHELF))
	g.box("kit", Vector3(cx + cust * 0.12, ty + 0.18, zc - 0.05 - 0.1), Vector3(0.18, 0.12, 0.02), _k(Color(0.95, 0.75, 0.1), K_POSTER))
	g.box("kit", Vector3(cx + cust * 0.15, ty + 0.025, zc + L * 0.36), Vector3(0.12, 0.05, 0.2), cl)
	g.box("kit", Vector3(cx + cs * 0.05, ty + 0.06, till_z + 0.3), Vector3(0.12, 0.12, 0.14), _k(Color(0.16, 0.16, 0.17), K_RUBBER), Basis(), 0.01)
	g.box("kit", Vector3(cx + cust * 0.05, ty + 0.012, zc + L * 0.05), Vector3(0.22, 0.024, 0.3), _k(Color(0.9, 0.88, 0.8), K_POSTER))
	var jar := Vector3(cx + cust * 0.18, ty, till_z - 0.45)
	g.cylinder("clear", jar, 0.055, 0.13, 12, Color.WHITE)
	g.cylinder("kit", jar + Vector3(0, 0.002, 0), 0.05, 0.035, 10, _k(Color(0.55, 0.45, 0.25), K_CHROME))
	g.cylinder("kit", jar + Vector3(0, 0.13, 0), 0.058, 0.012, 12, _k(Color(0.2, 0.2, 0.2), K_RUBBER))
	# The cigarette rack on the wall behind the cashier, its lit header.
	var wall := cs * ix1
	var rx := wall - cs * 0.15
	g.box("kit", Vector3(rx, 1.8, zc), Vector3(0.3, 1.1, L), _k(Color(0.10, 0.10, 0.11), K_SHELF))
	g.box("kit", Vector3(rx - cs * 0.15, 2.3, zc), Vector3(0.02, 0.1, L), _k(Color(1.0, 0.95, 0.85), K_GLOW))
	for i in 9:
		g.box("kit", Vector3(rx - cs * 0.14, 1.27 + float(i) * 0.11, zc), Vector3(0.04, 0.008, L), _k(Color(0.35, 0.35, 0.37), K_ALUMINIUM))
	# A stool for the cashier and a small cabinet under the rack.
	var stool := Vector3(wall - cs * 0.62, 0.0, kz.y + 0.5)
	g.cylinder("kit", stool, 0.025, 0.65, 8, _k(Color(0.3, 0.3, 0.32), K_STEEL))
	g.cylinder("kit", stool + Vector3(0, 0.65, 0), 0.18, 0.06, 12, _k(Color(0.1, 0.1, 0.1), K_RUBBER))
	g.box("kit", Vector3(wall - cs * 0.22, 0.45, zc), Vector3(0.44, 0.9, L - 0.4), _k(COUNTER_TONE * 0.9, K_LAMINATE))
	# The impulse rack on the customer's face of the counter.
	var face := cx + cust * (CD * 0.5)
	for y: float in [0.32, 0.56]:
		g.box("kit", Vector3(face + cust * 0.07, y - 0.01, zc), Vector3(0.14, 0.02, L - 0.3), _k(Color(0.3, 0.3, 0.32), K_WIRE))


## A convex mirror: a spherical cap of radius r facing `n`, chrome.
static func _mirror(g: LandmarkGeo, c: Vector3, n: Vector3, r: float) -> void:
	var u := n.cross(Vector3.UP).normalized()
	var v := u.cross(n).normalized()
	var rings := 4
	var segs := 14
	var bulge := r * 0.35
	var pt := func(rho: float, t: float) -> Vector3:
		return c + (u * cos(t) + v * sin(t)) * (r * rho) + n * (bulge * (1.0 - rho * rho))
	for j in rings:
		for i in segs:
			var r0 := float(j) / rings
			var r1 := float(j + 1) / rings
			var t0 := TAU * float(i) / segs
			var t1 := TAU * float(i + 1) / segs
			var a: Vector3 = pt.call(r0, t0)
			var b: Vector3 = pt.call(r1, t0)
			var cc: Vector3 = pt.call(r1, t1)
			var d: Vector3 = pt.call(r0, t1)
			var nn := ((a + cc) * 0.5 - (c - n * r * 1.5)).normalized()
			g.quad("kit", a, b, cc, d, nn, Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), _k(Color(0.9, 0.9, 0.9), K_CHROME))
	g.cylinder("kit", c - n * 0.02 + Vector3(0, 0, 0), r + 0.02, 0.02, 14, _k(Color(0.1, 0.1, 0.1), K_RUBBER))


# --- Goods ---------------------------------------------------------------------------------------

## product_color() of the traced room (corner_store_glass.gdshader), as an sRGB Color.
static func product_color(h: float) -> Color:
	var c := Vector3(0.5 + 0.5 * cos(TAU * h), 0.5 + 0.5 * cos(TAU * (h + 0.33)), 0.5 + 0.5 * cos(TAU * (h + 0.67)))
	var grey := (c.x + c.y + c.z) / 3.0
	c = Vector3(grey, grey, grey).lerp(c, 0.75)
	var light := _hash21(Vector2(h * 91.0, 3.3))
	c = c * lerpf(0.35, 0.95, light) + (Vector3(0.25, 0.25, 0.25) if light > 0.85 else Vector3.ZERO)
	return Color(c.x, c.y, c.z).linear_to_srgb()


static func _hash21(p: Vector2) -> float:
	p = Vector2(fposmod(p.x * 123.34, 1.0), fposmod(p.y * 456.21, 1.0))
	var d := p.dot(p + Vector2(45.32, 45.32))
	p += Vector2(d, d)
	return fposmod(p.x * p.y, 1.0)


## One mesh per kind of goods, unit size, white with the part code in the alpha.
static func goods_mesh(kind: int) -> ArrayMesh:
	if _goods_meshes.has(kind):
		return _goods_meshes[kind]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var add := func(p: Vector3, nrm: Vector3, uv: Vector2, part: int) -> void:
		st.set_color(Color(1, 1, 1, float(part) / 8.0))
		st.set_normal(nrm)
		st.set_uv(uv)
		st.add_vertex(p)
	match kind:
		Goods.BOX:
			_box_faces(add, Vector3(-0.5, 0.0, -0.5), Vector3(0.5, 1.0, 0.5), P_BODY, P_SIDE)
		Goods.BAG:
			# A pillow: the front and back puffed out in the middle, crimped flat and serrated at the
			# top and bottom, the film crinkled (a fixed hash per grid node, so shared corners agree).
			var cols := 5
			var rows := 7
			var node := func(i: int, j: int, side: float) -> Array:
				var u := float(i) / cols
				var v := float(j) / rows
				var puff := sin(PI * u) * sin(PI * clampf((v - 0.07) / 0.86, 0.0, 1.0))
				var h1 := float(absi(hash([i, j, side, "crinkle"])) % 1000) / 1000.0 - 0.5
				var h2 := float(absi(hash([j, i, side, "crinkle2"])) % 1000) / 1000.0 - 0.5
				var edge := j == 0 or j == rows
				var y := v + (0.012 * (1.0 if i % 2 == 0 else -1.0) if edge else 0.0)
				var p := Vector3(u - 0.5 + h2 * 0.03 * puff, y, side * 0.5 * maxf(puff * (1.0 + h1 * 0.35), 0.02))
				var n := Vector3(-cos(PI * u) * 0.6 + h2 * 0.6, h1 * 0.5, side).normalized()
				return [p, n, Vector2(u if side > 0.0 else 1.0 - u, v)]
			for side: float in [1.0, -1.0]:
				for i in cols:
					for j in rows:
						var q := [node.call(i, j, side), node.call(i + 1, j, side), node.call(i + 1, j + 1, side), node.call(i, j + 1, side)]
						var order := [0, 2, 1, 0, 3, 2] if side > 0.0 else [0, 1, 2, 0, 2, 3]
						for k: int in order:
							var e: Array = q[k]
							add.call(e[0], e[1], e[2], P_BODY if side > 0.0 else P_SIDE)
		Goods.CAN:
			_lathe(add, [[0.0, 0.0], [0.5, 0.04], [0.5, 0.92], [0.43, 1.0], [0.0, 1.0]], [P_CAP, P_LABEL, P_CAP, P_CAP], 8)
		Goods.BOTTLE:
			_lathe(add, [[0.0, 0.0], [0.5, 0.05], [0.5, 0.25], [0.5, 0.6], [0.46, 0.7], [0.17, 0.88], [0.17, 1.0], [0.0, 1.0]],
					[P_CLEAR, P_CLEAR, P_LABEL, P_CLEAR, P_CLEAR, P_CAP, P_CAP], 8)
	st.index()
	var m := st.commit()
	m.surface_set_material(0, goods_material())
	_goods_meshes[kind] = m
	return m


static func _box_faces(add: Callable, lo: Vector3, hi: Vector3, front: int, rest: int) -> void:
	var c := [Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(lo.x, hi.y, lo.z),
		Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z)]
	# Each face as four corners, clockwise seen from outside (Godot's front faces), its normal, its part.
	var faces := [[[4, 7, 6, 5], Vector3.BACK, front], [[1, 2, 3, 0], Vector3.FORWARD, rest], [[5, 6, 2, 1], Vector3.RIGHT, rest],
		[[0, 3, 7, 4], Vector3.LEFT, rest], [[3, 2, 6, 7], Vector3.UP, rest], [[0, 4, 5, 1], Vector3.DOWN, rest]]
	var uvs := [Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0)]
	for f: Array in faces:
		var idx: Array = f[0]
		for k: int in [0, 1, 2, 0, 2, 3]:
			add.call(c[idx[k]], f[1], uvs[k], f[2])


## A surface of revolution round y from profile points [radius, height] (radius 0.5 = the unit's
## edge); `parts` per band.
static func _lathe(add: Callable, profile: Array, parts: Array, segs: int) -> void:
	for b in profile.size() - 1:
		var p0: Array = profile[b]
		var p1: Array = profile[b + 1]
		var r0: float = p0[0]
		var y0: float = p0[1]
		var r1: float = p1[0]
		var y1: float = p1[1]
		var slope := Vector2(y1 - y0, -(r1 - r0)).normalized()
		for i in segs:
			var t0 := TAU * float(i) / segs
			var t1 := TAU * float(i + 1) / segs
			var a := Vector3(cos(t0) * r0, y0, sin(t0) * r0)
			var bb := Vector3(cos(t1) * r0, y0, sin(t1) * r0)
			var c := Vector3(cos(t1) * r1, y1, sin(t1) * r1)
			var d := Vector3(cos(t0) * r1, y1, sin(t0) * r1)
			var n0 := Vector3(cos(t0) * slope.x, slope.y, sin(t0) * slope.x).normalized()
			var n1 := Vector3(cos(t1) * slope.x, slope.y, sin(t1) * slope.x).normalized()
			# u runs round from the front (+z), so the label's design faces the shelf edge.
			var u0 := fposmod(0.25 - t0 / TAU, 1.0) * 2.0
			var u1 := u0 - 2.0 / segs
			var vv0 := y0
			var vv1 := y1
			var part: int = parts[b]
			# Front faces wind clockwise seen from outside: a, b, c then a, c, d (t runs leftward seen from out).
			add.call(a, n0, Vector2(u0, vv0), part)
			add.call(bb, n1, Vector2(u1, vv0), part)
			add.call(c, n1, Vector2(u1, vv1), part)
			add.call(a, n0, Vector2(u0, vv0), part)
			add.call(c, n1, Vector2(u1, vv1), part)
			add.call(d, n0, Vector2(u0, vv1), part)


## The products: the back wall, both faces and the endcap of every gondola, the coolers, the
## cigarette rack, the impulse rack and the scratch-ticket case. One MultiMesh per goods kind.
static func _goods(site: CornerStoreSite, s: Dictionary, lay: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(s.seed), "cstore_goods"])
	var acc := {}
	var cs: float = lay.cs
	var ix0: float = lay.ix0
	var ix1: float = lay.ix1
	var iz0: float = lay.iz0
	var d := CornerStore.BACK_SHELF
	# The back wall.
	for k in BACK_SHELVES.size():
		var y: float = BACK_SHELVES[k]
		var room: float = (BACK_SHELVES[k + 1] if k + 1 < BACK_SHELVES.size() else 2.1) - y - 0.04
		_fill(acc, rng, Vector3(ix0 + 0.04, y, iz0 + d - 0.02), Vector3.RIGHT, Vector3.BACK, (ix1 - ix0) - 0.08, room, d - 0.06, BACK_MIX[k % BACK_MIX.size()])
	# The gondolas: both long faces and the endcap.
	var gz: Vector2 = lay.g_z
	var half := CornerStore.GONDOLA_W * 0.5
	for gi in (lay.gondolas as Array).size():
		var gx: float = lay.gondolas[gi]
		for k in GONDOLA_SHELVES.size():
			var y: float = GONDOLA_SHELVES[k]
			var room: float = (GONDOLA_SHELVES[k + 1] if k + 1 < GONDOLA_SHELVES.size() else float(lay.g_h)) - y - 0.04
			if k == GONDOLA_SHELVES.size() - 1:
				room = minf(room + 0.3, 0.42)
			var mix: Array = GONDOLA_MIX[(gi + k) % GONDOLA_MIX.size()]
			_fill(acc, rng, Vector3(gx + half - 0.01, y, gz.x - 0.04), Vector3.FORWARD, Vector3.RIGHT, gz.x - gz.y - 0.08, room, half - 0.04, mix)
			_fill(acc, rng, Vector3(gx - half + 0.01, y, gz.y + 0.04), Vector3.BACK, Vector3.LEFT, gz.x - gz.y - 0.08, room, half - 0.04, GONDOLA_MIX[(gi + k + 2) % GONDOLA_MIX.size()])
		for y: float in [0.3, 0.75, 1.2]:
			_fill(acc, rng, Vector3(gx - half + 0.03, y, gz.x + 0.33), Vector3.RIGHT, Vector3.BACK, CornerStore.GONDOLA_W - 0.06, 0.4, 0.3, ["case", "big_bottle", "bag"])
	# The coolers: drinks facing the doors.
	if int(lay.n_doors) > 0:
		var cz: Vector2 = lay.cooler_z
		var face: float = lay.cooler_face
		var into := Vector3(cs, 0, 0)
		var along := Vector3(0, 0, -1)
		for k in COOLER_SHELVES.size():
			var y: float = COOLER_SHELVES[k]
			var room: float = (COOLER_SHELVES[k + 1] if k + 1 < COOLER_SHELVES.size() else 1.98) - y - 0.03
			_fill(acc, rng, Vector3(face - cs * 0.06, y, cz.x - 0.05), along, into, cz.x - cz.y - 0.1, room, CornerStore.COOLER_DEEP - 0.18, COOLER_MIX[k % COOLER_MIX.size()], true)
	# The cigarette rack: rows of packs facing the counter.
	var kz: Vector2 = lay.counter_z
	var rfront := cs * ix1 - cs * 0.335
	var toward := Vector3(-cs, 0, 0)
	var along_r := Vector3(0, 0, -1)
	for r in 9:
		_fill(acc, rng, Vector3(rfront, 1.275 + float(r) * 0.11, kz.x - 0.02), along_r, toward, kz.x - kz.y - 0.04, 0.095, 0.1, ["pack"], true, 0.004, true)
	# Candy on the impulse rack, facing the customer.
	var cust := -cs
	var cface: float = float(lay.counter_x) + cust * CornerStore.COUNTER_DEEP * 0.5
	for y: float in [0.32, 0.56]:
		_fill(acc, rng, Vector3(cface + cust * 0.13, y, kz.y + 0.15), Vector3(0, 0, 1), Vector3(cust, 0, 0), kz.x - kz.y - 0.3, 0.2, 0.12, ["candy", "small"])
	# Scratch tickets: two rows of bright rolls behind the case's glass.
	var sc_z := kz.x - 0.4
	for row in 2:
		_fill(acc, rng, Vector3(float(lay.counter_x) + cust * 0.12, 0.995 + float(row) * 0.18, sc_z + 0.28), Vector3(0, 0, -1), Vector3(cust, 0, 0), 0.56, 0.15, 0.2, ["candy"], true, 0.01, true)
	# Energy shots, lighters and gum on the counter.
	var es := Vector3(float(lay.counter_x) + cust * 0.12, 1.035, kz.y * 0.0 + (kz.x + kz.y) * 0.5 + 0.05)
	_fill(acc, rng, es + Vector3(0, 0, 0.1), Vector3(0, 0, -1), Vector3(cust, 0, 0), 0.2, 0.1, 0.16, ["tall_can"], true, 0.004, true)
	var lt := Vector3(float(lay.counter_x) + cust * 0.15, 1.025, (kz.x + kz.y) * 0.5 + (kz.x - kz.y) * 0.36)
	_fill(acc, rng, lt + Vector3(0.05 * cust, 0, 0.09), Vector3(0, 0, -1), Vector3(cust, 0, 0), 0.18, 0.07, 0.1, ["candy"], true, 0.003, true)
	last_goods = 0
	for kind: int in acc:
		var a: Dictionary = acc[kind]
		var xs: Array = a.xf
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = goods_mesh(kind)
		mm.instance_count = xs.size()
		for i in xs.size():
			mm.set_instance_transform(i, xs[i])
			mm.set_instance_color(i, a.col[i])
			mm.set_instance_custom_data(i, a.custom[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Goods_%d" % kind
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		site.interior.add_child(mmi)
		last_goods += xs.size()


## Fills a shelf run with facings: from `start` along `along` for `length` metres, the packs'
## fronts at `start` facing `out`, standing on the shelf, at most `room` tall and `depth` deep.
## Families from `mix` in runs of 2-6 identical packs. `deep` adds a second row behind (coolers).
static func _fill(acc: Dictionary, rng: RandomNumberGenerator, start: Vector3, along: Vector3, out: Vector3, length: float,
		room: float, depth: float, mix: Array, deep: bool = false, gap: float = 0.012, tidy: bool = false) -> void:
	# A right-handed frame facing `out` (a mirrored one would turn the packs inside out).
	var basis := Basis(Vector3.UP.cross(out), Vector3.UP, out)
	var cur := 0.0
	while cur < length:
		var fam: Array = FAMILIES[mix[rng.randi() % mix.size()]]
		var kind: int = fam[0]
		var w := rng.randf_range((fam[1] as Vector2).x, (fam[1] as Vector2).y)
		var h := minf(rng.randf_range((fam[2] as Vector2).x, (fam[2] as Vector2).y), room)
		var dd := minf(rng.randf_range((fam[3] as Vector2).x, (fam[3] as Vector2).y), depth)
		if h < 0.05:
			return
		# The print is a cell of the atlas; the colour only tints what is behind clear plastic and
		# the caps, mostly near white.
		var main := product_color(rng.randf()).lerp(Color(0.95, 0.94, 0.9), 0.35)
		if kind == Goods.BOTTLE and w > 0.14:
			main = Color(0.95, 0.95, 0.93)
		var custom := Color(float(rng.randi() % 64) / 64.0, rng.randf(), rng.randf_range(0.0, 0.5) if rng.randf() < 0.3 else 0.0, 0.0)
		var n := rng.randi_range(2, 6)
		for i in n:
			if cur + w > length:
				return
			# Sold out: a gap the width of a facing now and then.
			if not tidy and rng.randf() < 0.07:
				cur += w + gap
				continue
			var rows := 1
			if deep:
				rows = maxi(1, mini(2, int(depth / maxf(dd, 0.05))))
			# Facings pulled forward unevenly (the back ones bought first).
			var pull := rng.randf_range(0.0, 0.05) if rng.randf() < 0.6 else rng.randf_range(0.05, maxf(0.06, depth - dd))
			pull = minf(pull, maxf(0.0, depth - float(rows) * (dd + 0.005)))
			var skew := rng.randf_range(-0.06, 0.06)
			if tidy:
				pull = 0.0
				skew = 0.0
			for r in rows:
				var c := start + along * (cur + w * 0.5) - out * (dd * 0.5 + pull + float(r) * (dd + 0.005))
				var xf := Transform3D(basis.rotated(Vector3.UP, skew).scaled_local(Vector3(w, h, dd)), c)
				if not acc.has(kind):
					acc[kind] = {"xf": [], "col": [], "custom": []}
				(acc[kind].xf as Array).append(xf)
				(acc[kind].col as Array).append(main)
				(acc[kind].custom as Array).append(custom)
			cur += w + gap
		cur += rng.randf_range(0.0, 0.03)


# --- People and lights ---------------------------------------------------------------------------

static func _people(ch: CityChunk, site: CornerStoreSite, s: Dictionary, lay: Dictionary, xf: Transform3D) -> void:
	# The interior's lights (always on: the store is open), hidden with it.
	var W: float = s.W
	var D: float = s.D
	var spots_l: Array = [[Vector3(0.0, CornerStore.CEILING - 0.25, -D * 0.25), 1.15], [Vector3(-W * 0.2, CornerStore.CEILING - 0.25, -D * 0.62), 0.8],
		[Vector3(W * 0.22, CornerStore.CEILING - 0.25, -D * 0.7), 1.0]]
	if OS.has_feature("web"):
		spots_l = [[Vector3(0.0, CornerStore.CEILING - 0.3, -D * 0.5), 1.1]]
	for i in spots_l.size():
		var l := OmniLight3D.new()
		l.name = "Light%d" % i
		l.position = spots_l[i][0]
		l.omni_range = maxf(W, D) * 0.6
		l.omni_attenuation = 1.4
		l.light_energy = float(spots_l[i][1])
		l.light_color = Color(1.0, 0.95, 0.88)
		l.shadow_enabled = false
		l.light_specular = 0.4
		site.interior.add_child(l)
	# The coolers throw a cold glow on the aisle in front of them.
	if int(lay.n_doors) > 0 and not OS.has_feature("web"):
		var cz: Vector2 = lay.cooler_z
		var cg := OmniLight3D.new()
		cg.name = "CoolerGlow"
		cg.position = Vector3(float(lay.cooler_face) + float(lay.cs) * 0.5, 1.2, (cz.x + cz.y) * 0.5)
		cg.omni_range = absf(cz.x - cz.y) * 0.6 + 1.0
		cg.light_energy = 0.6
		cg.light_color = Color(0.85, 0.93, 1.0)
		cg.shadow_enabled = false
		site.interior.add_child(cg)
	# At night the shop spills its light out over the pavement (the chunk's shop_spill batch, the
	# pools the open shops of the city's buildings throw, in a batch of its own: the city's spill
	# is counted against the buildings' pools).
	var spill := PropFactory.shop_spill()
	for o: Array in _openings(lay, W):
		var u0: float = o[0]
		var u1: float = o[1]
		var wide := (u1 - u0) * 1.6 + 1.0
		var pxf := Transform3D(Basis(xf.basis.x * wide, xf.basis.z * 7.0, xf.basis.x.cross(xf.basis.z)), xf * Vector3((u0 + u1) * 0.5, 0.0, 0.2))
		pxf.origin.y = CityChunk.SIDEWALK_TOP + 0.06
		ch._batch.add("cstore_spill", spill, pxf, Color(1.0, 0.93, 0.82, 0.85))
	ch._batch.set_no_shadow("cstore_spill")
	ch._batch.set_draw_distance("cstore_spill", CityChunk.SHOP_SPILL_DISTANCE)
	# The cashier behind the counter and a customer in front of it: placed, kinematic, ducking
	# at gunfire (StreetVendor's truck cook), in the crowd cap.
	var cs: float = lay.cs
	var kz: Vector2 = lay.counter_z
	var zc := (kz.x + kz.y) * 0.5
	var spots := [[Vector3(cs * (float(lay.ix1) - 0.78), 0.0, zc), Vector3(-cs, 0, 0)],
		[Vector3(float(lay.counter_x) - cs * (CornerStore.COUNTER_DEEP * 0.5 + 0.5), 0.0, zc + 0.35), Vector3(cs, 0, 0)]]
	var rect: Rect2 = s.rect
	for i in spots.size():
		if i == 1 and absi(hash([int(s.seed), "cstore_customer"])) % 3 == 0:
			continue
		if not ch._take_crowd_room():
			return
		var p: Vector3 = xf * (spots[i][0] as Vector3)
		var dir: Vector3 = xf.basis * (spots[i][1] as Vector3)
		var at := Vector2(p.x, p.z)
		var lift := xf.origin.y - ch.ground_y(at.x, at.y)
		var ped := StreetVendor.new()
		ped.setup_vendor(rect, absi(hash([int(s.seed), "cstore_ped", i])), at, atan2(-dir.x, -dir.z), true, lift)
		ped.position = Vector3(at.x, xf.origin.y + 0.05, at.y)
		ped.add_to_group("corner_store_people")
		ch.add_child(ped)
		site.people.append(ped)
