class_name StadiumNight
extends RefCounted
## The ravine ballpark's night game, second pass (refcam `stadium_night`, tools/refcams/cameras_w6.json;
## docs/HANDOFF.md "The night game from the hill"). What the camera on the bank above the north lot
## gave away, fixed here so BallparkBuild keeps its one hook line:
##
## - The lot's cars were stickers: past the 3D cars' 120 m every car was a rectangle painted into
##   its stall. Every stall Ballpark.stall_car() fills now gets a 22-triangle box car (body,
##   glasshouse, a dark rocker band) out to FAR_DRAW, lit by the same lot-pole pools the ground
##   shader draws (shaders/stadium_car.gdshader); the painted car under one becomes its contact
##   shadow (ballpark_lot's `box_reach`). Tiles hand over to the detailed cars at CAR_DRAW.
## - The light banks were dots that lit nothing: each bank gets a soft bloom over its lenses and a
##   faint shaft of lit haze down toward the field (shaders/stadium_bank_glow.gdshader); the glow
##   dome over the bowl shows from the hills (ballpark_glow `away_from`).
## - The stands were flat pastel stripes: the seats shader takes a per-section crowd, the shade under
##   each deck's overhang and the riser lines at a distance (ballpark_seats `night2`).
##
## STADIUM_NIGHT=0 is the A/B (everything exactly as before).

const FAR_DRAW := 560.0
const FAR_TILE := 160.0
const FADE := 40.0

static var _enabled := -1
static var _car_mesh: ArrayMesh = null
static var _car_mat: ShaderMaterial = null
static var _banks: Dictionary = {}
static var _bank_mesh: Dictionary = {}
static var _bank_mat: ShaderMaterial = null


static func enabled() -> bool:
	if _enabled < 0:
		_enabled = 0 if OS.get_environment("STADIUM_NIGHT") == "0" else 1
	return _enabled == 1


## BallparkBuild.build()'s hook: `holder` is the park's node (world space), `detailed` the chunk's
## copy. Both copies get the box cars and the glow; the far copy also its palms.
static func dress(holder: Node3D, detailed: bool) -> void:
	if not enabled():
		return
	var glow := MeshInstance3D.new()
	glow.name = "StadiumBankGlow"
	glow.mesh = bank_mesh(detailed)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(glow)
	var players := MeshInstance3D.new()
	players.name = "StadiumPlayers"
	players.mesh = players_mesh()
	players.visibility_range_end = 1400.0
	holder.add_child(players)
	var n := far_cars(holder, detailed)
	(BallparkBuild.material("lot") as ShaderMaterial).set_shader_parameter("box_reach", FAR_DRAW - FAR_TILE * 0.75 if n > 0 else 0.0)
	if not detailed:
		# The far copy had no planting at all (CLAUDE.md, far landmarks: palms and trees stay on
		# the same meshes, shadowless): the lot's palms, as the detailed copy plants them.
		var batch := MultiMeshBatch.new()
		BallparkBuild._palms(batch)
		ArenaGrounds._far_shadows(batch)
		batch.build(holder)
	tune_materials()


## The shaders' second-pass knobs (each defaults to the old look).
static func tune_materials() -> void:
	(BallparkBuild.material("seats") as ShaderMaterial).set_shader_parameter("night2", 1.0)
	(BallparkBuild.material("glow") as ShaderMaterial).set_shader_parameter("away_from", 60.0)
	(BallparkBuild.material("glow") as ShaderMaterial).set_shader_parameter("away_gain", 1.8)


## A box car the size of ArenaGrounds' saloon: body (COLOR.a 0 flanks, 0.25 bonnet and boot; the
## shader darkens the rocker band and wheels under 0.4 m), glasshouse (0.5 glass, 0.75 roof). Front faces clockwise seen from outside (Godot's convention).
static func car_mesh() -> ArrayMesh:
	if _car_mesh:
		return _car_mesh
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var add_box := func(lo: Vector3, hi: Vector3, top_in: float, side_col: Color, top_col: Color) -> void:
		# Sides taper `top_in` at the top (a tumblehome); no bottom face.
		var b := [Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, lo.y, hi.z)]
		var t := [Vector3(lo.x + top_in, hi.y, lo.z + top_in), Vector3(hi.x - top_in, hi.y, lo.z + top_in), Vector3(hi.x - top_in, hi.y, hi.z - top_in), Vector3(lo.x + top_in, hi.y, hi.z - top_in)]
		var quad := func(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, c0: Color, c1: Color) -> void:
			var nn := (p1 - p0).cross(p2 - p0).normalized()
			var mid := (p0 + p1 + p2 + p3) * 0.25
			var out := Vector3(mid.x, 0.0, mid.z)
			if mid.y > hi.y - 0.01:
				out = Vector3.UP
			if nn.dot(out) > 0.0:
				# Godot draws clockwise front faces: wind so the normal we store is the outward one.
				for p: Vector3 in [p0, p2, p1, p0, p3, p2]:
					v.append(p)
			else:
				for p: Vector3 in [p0, p1, p2, p0, p2, p3]:
					v.append(p)
			if nn.dot(out) < 0.0:
				nn = -nn
			for i in 6:
				n.append(nn)
			c.append(c0); c.append(c0); c.append(c0); c.append(c0); c.append(c0); c.append(c0)
		for i in 4:
			var j := (i + 1) % 4
			quad.call(b[i], b[j], t[j], t[i], side_col, side_col)
		quad.call(t[0], t[1], t[2], t[3], top_col, top_col)
	# Body: 4.7 x 1.82, sill 0.32 .. shoulder 0.95; glasshouse 2.5 long, to 1.42.
	add_box.call(Vector3(-0.91, 0.12, -2.35), Vector3(0.91, 0.92, 2.35), 0.06, Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.25))
	add_box.call(Vector3(-0.8, 0.92, -0.95), Vector3(0.8, 1.42, 1.25), 0.16, Color(1, 1, 1, 0.5), Color(1, 1, 1, 0.75))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = n
	arrays[Mesh.ARRAY_COLOR] = c
	_car_mesh = ArrayMesh.new()
	_car_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if _car_mat == null:
		_car_mat = ShaderMaterial.new()
		_car_mat.shader = load("res://shaders/stadium_car.gdshader")
	_car_mesh.surface_set_material(0, _car_mat)
	return _car_mesh


## Every filled stall's box car, in tiles: FAR_TILE squares, or BallparkBuild's CAR_TILE where
## the detailed cars stand in the detailed copy (those tiles start at CAR_DRAW, where the detailed
## ones stop). Returns how many.
static func far_cars(holder: Node3D, detailed_copy: bool) -> int:
	var tiles: Dictionary = {}
	var near_tiles: Dictionary = {}
	var u0 := -Ballpark.SITE_U
	var v := Ballpark.SITE_V0
	while v < Ballpark.SITE_V1:
		for side in 2:
			var vc := v + Ballpark.LOT_STALL_D * (0.5 + side)
			var bi := 0
			while u0 + bi * Ballpark.LOT_BLOCK_U < Ballpark.SITE_U:
				for k in Ballpark.LOT_BLOCK_STALLS_N:
					var u := u0 + bi * Ballpark.LOT_BLOCK_U + (k + 0.5) * Ballpark.LOT_STALL_W
					var q := Vector2(u, vc)
					var car := Ballpark.stall_car(q)
					if car < 0:
						continue
					var detailed := detailed_copy and q.length() <= BallparkBuild.CAR_REACH
					var paint: Color = ArenaGrounds.CAR_PAINTS[(car / 7) % ArenaGrounds.CAR_PAINTS.size()]
					var nose := Ballpark.FWD if side == 0 else -Ballpark.FWD
					var yaw := atan2(-nose.x, -nose.y) + (float(car % 5) - 2.0) * 0.012
					var key: Vector3i
					if detailed:
						key = Vector3i(floori(u / BallparkBuild.CAR_TILE), floori(vc / BallparkBuild.CAR_TILE), 1)
						near_tiles[key] = true
					else:
						key = Vector3i(floori(u / FAR_TILE), floori(vc / FAR_TILE), 0)
					if not tiles.has(key):
						tiles[key] = []
					var at := BallparkBuild._w(q, Ballpark.level(q) - Ballpark.PAD_Y + 0.02)
					(tiles[key] as Array).append([Transform3D(Basis(Vector3.UP, yaw), at), paint])
				bi += 1
		v += Ballpark.LOT_MODULE
	var count := 0
	var mesh := car_mesh()
	for key: Vector3i in tiles:
		var list: Array = tiles[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i][0])
			mm.set_instance_color(i, list[i][1])
		var mi := MultiMeshInstance3D.new()
		mi.name = "StadiumCars_%d_%d_%d" % [key.x, key.y, key.z]
		mi.multimesh = mm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if key.z == 1:
			mi.visibility_range_begin = BallparkBuild.CAR_DRAW
		mi.visibility_range_end = FAR_DRAW
		mi.visibility_range_end_margin = FADE
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		holder.add_child(mi)
		count += list.size()
	BallparkBuild.stats["far_cars"] = count
	return count


## BallparkBuild._bank()'s note of each light bank it builds: its lens face's centre, the way it
## faces, what it is aimed at and its size.
static func note_bank(near: bool, centre: Vector3, face: Vector3, aim: Vector3, w: float, h: float) -> void:
	var key := "near" if near else "far"
	if not _banks.has(key):
		_banks[key] = []
	(_banks[key] as Array).append([centre, face, aim, w, h])


## The banks' blooms and shafts, one mesh (shaders/stadium_bank_glow.gdshader; the vertex stage
## turns each to the camera). UV2.x 0 a bloom (UV the corner, UV2.y its size, NORMAL the face),
## 1 a shaft (VERTEX its ends, UV.x the side, UV.y 0 at the bank and 1 at its far end, UV2.y the
## width at the far end, NORMAL the axis).
static func bank_mesh(near: bool) -> ArrayMesh:
	var key := "near" if near else "far"
	if _bank_mesh.has(key):
		return _bank_mesh[key]
	var v := PackedVector3Array()
	var nrm := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	for b: Array in _banks.get(key, []):
		var c: Vector3 = b[0]
		var face: Vector3 = b[1]
		var aim: Vector3 = b[2]
		var size := maxf(float(b[3]), float(b[4])) * 2.2
		for k: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)]:
			v.append(c)
			nrm.append(face)
			uv.append(k)
			uv2.append(Vector2(0.0, size))
		var axis := (aim - c)
		var run := axis.length() * 0.8
		axis = axis.normalized()
		var e := c + axis * run
		for k: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(1, 1), Vector2(-1, 0), Vector2(1, 1), Vector2(-1, 1)]:
			v.append(c if k.y < 0.5 else e)
			nrm.append(axis)
			uv.append(k)
			uv2.append(Vector2(1.0, run * 0.42))
	var m := ArrayMesh.new()
	if v.is_empty():
		_bank_mesh[key] = m
		return m
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = nrm
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if _bank_mat == null:
		_bank_mat = ShaderMaterial.new()
		_bank_mat.shader = load("res://shaders/stadium_bank_glow.gdshader")
	m.surface_set_material(0, _bank_mat)
	var ctr := BallparkBuild._w(Vector2(0.0, 40.0), 0.0)
	m.custom_aabb = AABB(ctr - Vector3(300.0, 60.0, 300.0), Vector3(600.0, 200.0, 600.0))
	_bank_mesh[key] = m
	return m


## Who is on the field: [u, v (Ballpark frame), uniform 0 home / 1 away / 2 umpire, stance 0 ready
## crouch / 1 upright / 2 batter], facing home (the batter faces the mound side-on, the catcher out).
const PLAYERS := [
	[0.0, 18.0, 0, 1], [0.0, -0.9, 0, 0], [19.0, 26.0, 0, 0], [8.0, 39.0, 0, 0], [-9.0, 38.5, 0, 0],
	[-18.5, 25.5, 0, 0], [-48.0, 84.0, 0, 1], [0.0, 98.0, 0, 1], [47.0, 86.0, 0, 1],
	[-0.95, 0.2, 1, 2], [0.0, -2.6, 2, 0], [24.0, 15.0, 1, 1], [-24.5, 14.5, 1, 1], [19.4, 20.0, 1, 1],
]
const UNIFORMS := [[Color(0.93, 0.93, 0.92), Color(0.07, 0.16, 0.42)], [Color(0.58, 0.59, 0.6), Color(0.45, 0.05, 0.06)], [Color(0.06, 0.07, 0.11), Color(0.05, 0.05, 0.06)]]
const SKIN := [Color(0.62, 0.44, 0.32), Color(0.38, 0.25, 0.17), Color(0.2, 0.13, 0.09), Color(0.7, 0.52, 0.4)]

static var _players_mesh: ArrayMesh = null


## The players, the batter, the umpire and the base coaches as one mesh in world space
## (shaders/stadium_player.gdshader: lit by the light banks after dark like the field). A figure is
## ~60 triangles: at the hills' distance a few pixels, and those pixels are what says "a game is on".
static func players_mesh() -> ArrayMesh:
	if _players_mesh:
		return _players_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var unit := BoxMesh.new()
	unit.size = Vector3.ONE
	var head := SphereMesh.new()
	head.radius = 0.5
	head.height = 1.0
	head.radial_segments = 8
	head.rings = 4
	for i in PLAYERS.size():
		var p: Array = PLAYERS[i]
		var q := Vector2(float(p[0]), float(p[1]))
		var uni: Array = UNIFORMS[int(p[2])]
		var stance := int(p[3])
		var to_home := -q.normalized() if q.length() > 0.5 else Vector2(0.0, 1.0)
		if stance == 2:
			to_home = Vector2(1.0, 0.0)  # side-on to the mound
		var fw := Ballpark.RIGHT * to_home.x + Ballpark.FWD * to_home.y
		var yaw := atan2(-fw.x, -fw.y)
		var base := Transform3D(Basis(Vector3.UP, yaw), BallparkBuild._w(q, 0.0))
		var crouch := 0.28 if stance == 0 else 0.0
		var skin: Color = SKIN[(i * 7 + 3) % SKIN.size()]
		var jersey: Color = uni[0]
		var cap: Color = uni[1]
		var lean := Basis(Vector3.RIGHT, -0.35 if stance == 0 else 0.0)
		var parts := [
			# legs (socks / trousers), torso, arms, head, cap
			[unit, Vector3(0.17, 0.88 - crouch, 0.2), Vector3(-0.13, (0.88 - crouch) * 0.5, 0.0), jersey, Basis()],
			[unit, Vector3(0.17, 0.88 - crouch, 0.2), Vector3(0.13, (0.88 - crouch) * 0.5, 0.0), jersey, Basis()],
			[unit, Vector3(0.17, 0.12, 0.28), Vector3(-0.13, 0.06, -0.05), Color(0.04, 0.04, 0.045), Basis()],
			[unit, Vector3(0.17, 0.12, 0.28), Vector3(0.13, 0.06, -0.05), Color(0.04, 0.04, 0.045), Basis()],
			[unit, Vector3(0.44, 0.62, 0.26), Vector3(0.0, 0.88 - crouch + 0.3, 0.0), jersey, lean],
			[unit, Vector3(0.11, 0.6, 0.12), Vector3(-0.29, 0.88 - crouch + 0.26, -0.05), jersey, lean],
			[unit, Vector3(0.11, 0.6, 0.12), Vector3(0.29, 0.88 - crouch + 0.26, -0.05), jersey, lean],
			[head, Vector3(0.22, 0.25, 0.23), Vector3(0.0, 0.88 - crouch + 0.75, -0.06), skin, Basis()],
			[unit, Vector3(0.24, 0.09, 0.32), Vector3(0.0, 0.88 - crouch + 0.86, -0.1), cap, Basis()],
		]
		if stance == 2:
			# The bat, held up over the back shoulder.
			parts.append([unit, Vector3(0.06, 0.84, 0.06), Vector3(0.22, 1.75, 0.15), Color(0.55, 0.4, 0.22), Basis(Vector3.RIGHT, 0.5)])
		for part: Array in parts:
			var size: Vector3 = part[1]
			var at: Vector3 = part[2]
			var b: Basis = part[4]
			var xf := base * Transform3D(b * Basis().scaled(size), b * at)
			st.set_color(part[3])
			var mesh: Mesh = part[0]
			var arr := mesh.surface_get_arrays(0)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			var nb := xf.basis.inverse().transposed()
			for k in idx.size():
				st.set_color(part[3])
				st.set_normal((nb * norms[idx[k]]).normalized())
				st.add_vertex(xf * verts[idx[k]])
	var m := st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/stadium_player.gdshader")
	m.surface_set_material(0, mat)
	_players_mesh = m
	return m
